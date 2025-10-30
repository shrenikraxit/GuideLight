//
//  PathfindingEngine.swift - FIXED: Direct door connection for cross-room navigation
//  GuideLight v3
//

import Foundation
import simd

// MARK: - Pathfinding Engine (A* Algorithm)
class PathfindingEngine {
    
    private let map: IndoorMap
    
    init(map: IndoorMap) {
        self.map = map
        print("🗺️ PathfindingEngine initialized")
        print("   Rooms: \(map.rooms.count)")
        print("   Beacons: \(map.beacons.count)")
        print("   Doorways: \(map.doorways.count)")
        print("   Waypoints: \(map.waypoints.count)")
    }
    
    // MARK: - Main Pathfinding Method
    
    func findPath(
        from startPosition: simd_float3,
        to destinationBeacon: Beacon
    ) -> NavigationPath? {
        
        print("\n🎯 === PATHFINDING START ===")
        print("   From: \(formatPosition(startPosition))")
        print("   To: \(destinationBeacon.name) at \(formatPosition(destinationBeacon.position))")
        
        // Determine rooms
        let startRoom = determineRoom(for: startPosition)
        let destRoom = destinationBeacon.roomId
        
        print("   Start room: \(startRoom != nil ? (map.room(withId: startRoom!)?.name ?? startRoom!) : "UNKNOWN")")
        print("   Dest room: \(map.room(withId: destRoom)?.name ?? destRoom)")
        
        // If in same room, create direct path (enhanced with waypoint checking)
        if let startRoom = startRoom, startRoom == destRoom {
            print("✅ Same room - creating direct path with waypoint checking")
            return createDirectPathWithWaypoints(from: startPosition, to: destinationBeacon)
        }
        
        // Different rooms - need to go through doorways
        guard let startRoom = startRoom else {
            print("❌ Cannot determine starting room")
            print("   Available rooms: \(map.rooms.map { $0.name }.joined(separator: ", "))")
            return nil
        }
        
        print("🚪 Searching for doorway path...")
        
        // Find doorway path between rooms
        guard let doorwayPath = findDoorwayPath(from: startRoom, to: destRoom) else {
            print("❌ No doorway path found between rooms")
            print("   Available doorways:")
            for doorway in map.doorways {
                let roomAName = map.room(withId: doorway.connectsRooms.roomA)?.name ?? doorway.connectsRooms.roomA
                let roomBName = map.room(withId: doorway.connectsRooms.roomB)?.name ?? doorway.connectsRooms.roomB
                print("     - \(doorway.name): \(roomAName) ↔ \(roomBName)")
            }
            return nil
        }
        
        print("✅ Found doorway path with \(doorwayPath.count) doorways")
        
        // Build complete path with direct door connections (FIXED)
        return buildCompletePathWithDirectDoorConnections(
            from: startPosition,
            to: destinationBeacon,
            via: doorwayPath
        )
    }
    
    // MARK: - Room-Based A* Search
    
    private func findDoorwayPath(from startRoom: String, to destRoom: String) -> [Doorway]? {
        print("   Building room connectivity graph...")
        
        // Build room connectivity graph
        var roomGraph: [String: [(doorway: Doorway, toRoom: String)]] = [:]
        
        for doorway in map.doorways {
            // Only use accessible doorways
            guard doorway.isAccessible else { continue }
            
            // Add edge from roomA to roomB
            if roomGraph[doorway.connectsRooms.roomA] == nil {
                roomGraph[doorway.connectsRooms.roomA] = []
            }
            roomGraph[doorway.connectsRooms.roomA]?.append((doorway, doorway.connectsRooms.roomB))
            
            // Add edge from roomB to roomA
            if roomGraph[doorway.connectsRooms.roomB] == nil {
                roomGraph[doorway.connectsRooms.roomB] = []
            }
            roomGraph[doorway.connectsRooms.roomB]?.append((doorway, doorway.connectsRooms.roomA))
            
            let roomAName = map.room(withId: doorway.connectsRooms.roomA)?.name ?? doorway.connectsRooms.roomA
            let roomBName = map.room(withId: doorway.connectsRooms.roomB)?.name ?? doorway.connectsRooms.roomB
            print("     Added: \(roomAName) ↔ \(roomBName) via \(doorway.name)")
        }
        
        // Check if start and destination are in the graph
        guard roomGraph[startRoom] != nil else {
            print("❌ Start room not in graph")
            return nil
        }
        
        guard roomGraph[destRoom] != nil || destRoom == startRoom else {
            print("❌ Destination room not in graph")
            return nil
        }
        
        print("   Starting A* search from \(map.room(withId: startRoom)?.name ?? startRoom)...")
        
        // A* search through room graph
        var openSet: Set<String> = [startRoom]
        var cameFrom: [String: (doorway: Doorway, fromRoom: String)] = [:]
        var gScore: [String: Float] = [startRoom: 0]
        var fScore: [String: Float] = [startRoom: estimateDistance(from: startRoom, to: destRoom)]
        
        var iterations = 0
        let maxIterations = 100
        
        while !openSet.isEmpty && iterations < maxIterations {
            iterations += 1
            
            // Get room with lowest fScore
            guard let current = openSet.min(by: { fScore[$0] ?? Float.infinity < fScore[$1] ?? Float.infinity }) else {
                break
            }
            
            let currentName = map.room(withId: current)?.name ?? current
            print("     Checking \(currentName) (iteration \(iterations))")
            
            if current == destRoom {
                print("✅ Found path to destination!")
                return reconstructDoorwayPath(from: cameFrom, startRoom: startRoom, destRoom: destRoom)
            }
            
            openSet.remove(current)
            
            guard let neighbors = roomGraph[current] else { continue }
            
            for (doorway, neighbor) in neighbors {
                let tentativeGScore = (gScore[current] ?? Float.infinity) + doorway.width
                
                if tentativeGScore < (gScore[neighbor] ?? Float.infinity) {
                    let neighborName = map.room(withId: neighbor)?.name ?? neighbor
                    print("         Better path to \(neighborName) via \(doorway.name)")
                    
                    cameFrom[neighbor] = (doorway, current)
                    gScore[neighbor] = tentativeGScore
                    fScore[neighbor] = tentativeGScore + estimateDistance(from: neighbor, to: destRoom)
                    openSet.insert(neighbor)
                }
            }
        }
        
        if iterations >= maxIterations {
            print("❌ A* search exceeded max iterations")
        } else {
            print("❌ A* search exhausted without finding path")
        }
        
        return nil
    }
    
    private func reconstructDoorwayPath(
        from cameFrom: [String: (doorway: Doorway, fromRoom: String)],
        startRoom: String,
        destRoom: String
    ) -> [Doorway] {
        var path: [Doorway] = []
        var current = destRoom
        
        print("   Reconstructing path...")
        
        while current != startRoom {
            guard let prev = cameFrom[current] else {
                print("❌ Path reconstruction failed at \(current)")
                break
            }
            path.insert(prev.doorway, at: 0)
            print("     <- \(prev.doorway.name)")
            current = prev.fromRoom
        }
        
        let path_string = path.map { "\($0.name)" }.joined(separator: " → ")
        print("   Final path: \(path_string)")
        return path
    }
    
    // MARK: - FIXED: Direct Door Connection Path Building
    
    private func createDirectPathWithWaypoints(from start: simd_float3, to beacon: Beacon) -> NavigationPath {
        print("🎯 Creating direct path with waypoint checking...")
        
        var waypoints: [NavigationWaypoint] = []
        var totalDistance: Float = 0
        let roomsTraversed: [String] = []
        
        // Start waypoint
        waypoints.append(NavigationWaypoint(
            position: start,
            type: .start,
            name: "Start",
            roomId: beacon.roomId
        ))
        
        // Check for waypoints that should be included based on beacon connections
        let intermediateWaypoints = findWaypointsForBeacons(
            from: start,
            to: beacon.position,
            beaconA: nil, // Start position doesn't have a beacon ID
            beaconB: beacon.id.uuidString
        )
        
        // Add intermediate waypoints
        var currentPos = start
        for waypoint in intermediateWaypoints {
            let waypointNavWaypoint = NavigationWaypoint(
                position: waypoint.coordinates,
                type: .intermediate,
                name: waypoint.name,
                roomId: waypoint.roomId,
                audioInstruction: waypoint.audioLandmark
            )
            waypoints.append(waypointNavWaypoint)
            
            let segmentDistance = simd_distance(currentPos, waypoint.coordinates)
            totalDistance += segmentDistance
            currentPos = waypoint.coordinates
            
            print("     Added waypoint: \(waypoint.name) - \(String(format: "%.1fm", segmentDistance))")
        }
        
        // Destination waypoint
        waypoints.append(NavigationWaypoint(
            position: beacon.position,
            type: .destination,
            name: beacon.name,
            roomId: beacon.roomId,
            audioInstruction: "You have arrived at \(beacon.name)"
        ))
        
        // Add final segment distance
        let finalDistance = simd_distance(currentPos, beacon.position)
        totalDistance += finalDistance
        
        let time = TimeInterval(totalDistance / 1.2)
        
        print("✅ Direct path with waypoints created: \(String(format: "%.1fm", totalDistance))")
        return NavigationPath(
            waypoints: waypoints,
            totalDistance: totalDistance,
            estimatedTime: time,
            roomsTraversed: roomsTraversed
        )
    }
    
    // MARK: - FIXED: Direct Door Connection Method
    private func buildCompletePathWithDirectDoorConnections(
        from start: simd_float3,
        to destination: Beacon,
        via doorways: [Doorway]
    ) -> NavigationPath? {
        
        print("   Building complete path with DIRECT door connections...")
        
        var waypoints: [NavigationWaypoint] = []
        var totalDistance: Float = 0
        var roomsTraversed: [String] = []
        
        // Start waypoint
        let startRoom = determineRoom(for: start) ?? doorways.first?.connectsRooms.roomA ?? ""
        waypoints.append(NavigationWaypoint(
            position: start,
            type: .start,
            name: "Start Position",
            roomId: startRoom
        ))
        roomsTraversed.append(startRoom)
        
        print("     1. Start at \(formatPosition(start))")
        
        // Process each segment of the path
        var currentPos = start
        var currentRoom = startRoom
        var step = 2
        
        // FIXED: Go directly to each doorway without intermediate beacons
        for doorway in doorways {
            let nextRoom = doorway.connectsRooms.otherRoom(from: currentRoom) ?? currentRoom
            
            // FIXED: Only add relevant waypoints that are truly on the direct path to the door
            // But avoid adding waypoints that would cause detours to nearby beacons
            let segmentWaypoints = findDirectPathWaypoints(
                from: currentPos,
                to: doorway.position,
                currentRoom: currentRoom
            )
            
            // Add intermediate waypoints for this segment (if any)
            for waypoint in segmentWaypoints {
                let waypointNavWaypoint = NavigationWaypoint(
                    position: waypoint.coordinates,
                    type: .intermediate,
                    name: waypoint.name,
                    roomId: waypoint.roomId,
                    audioInstruction: waypoint.audioLandmark
                )
                waypoints.append(waypointNavWaypoint)
                
                let segmentDistance = simd_distance(currentPos, waypoint.coordinates)
                totalDistance += segmentDistance
                currentPos = waypoint.coordinates
                
                print("     \(step). Waypoint: \(waypoint.name) - \(String(format: "%.1fm", segmentDistance))")
                step += 1
            }
            
            // Add doorway waypoint
            let doorwayWaypoint = NavigationWaypoint(
                position: doorway.position,
                type: .doorway,
                name: doorway.name,
                roomId: currentRoom,
                doorwayId: doorway.id.uuidString,
                audioInstruction: getNavigationGuidance(for: doorway, from: currentRoom, to: nextRoom)
            )
            waypoints.append(doorwayWaypoint)
            
            // Update distance to doorway (DIRECT distance)
            let segmentDistance = simd_distance(currentPos, doorway.position)
            totalDistance += segmentDistance
            print("     \(step). \(doorway.name) - \(String(format: "%.1fm", segmentDistance))")
            step += 1
            
            currentPos = doorway.position
            currentRoom = nextRoom
            
            if !roomsTraversed.contains(currentRoom) {
                roomsTraversed.append(currentRoom)
            }
        }
        
        // FIXED: For the final segment, only add waypoints that truly improve navigation to destination
        let finalSegmentWaypoints = findDirectPathWaypoints(
            from: currentPos,
            to: destination.position,
            currentRoom: currentRoom
        )
        
        // Add final segment waypoints
        for waypoint in finalSegmentWaypoints {
            let waypointNavWaypoint = NavigationWaypoint(
                position: waypoint.coordinates,
                type: .intermediate,
                name: waypoint.name,
                roomId: waypoint.roomId,
                audioInstruction: waypoint.audioLandmark
            )
            waypoints.append(waypointNavWaypoint)
            
            let segmentDistance = simd_distance(currentPos, waypoint.coordinates)
            totalDistance += segmentDistance
            currentPos = waypoint.coordinates
            
            print("     \(step). Waypoint: \(waypoint.name) - \(String(format: "%.1fm", segmentDistance))")
            step += 1
        }
        
        // Destination waypoint
        let finalDistance = simd_distance(currentPos, destination.position)
        waypoints.append(NavigationWaypoint(
            position: destination.position,
            type: .destination,
            name: destination.name,
            roomId: destination.roomId,
            audioInstruction: "You have arrived at \(destination.name)"
        ))
        totalDistance += finalDistance
        print("     \(step). \(destination.name) - \(String(format: "%.1fm", finalDistance))")
        
        let estimatedTime = TimeInterval(totalDistance / 1.2)
        
        print("\n✅ === PATH COMPLETE ===")
        print("   Waypoints: \(waypoints.count)")
        print("   Total distance: \(String(format: "%.1fm", totalDistance))")
        print("   Estimated time: \(Int(estimatedTime))s")
        print("   Rooms: \(roomsTraversed.compactMap { map.room(withId: $0)?.name }.joined(separator: " → "))")
        
        return NavigationPath(
            waypoints: waypoints,
            totalDistance: totalDistance,
            estimatedTime: estimatedTime,
            roomsTraversed: roomsTraversed
        )
    }
    
    // MARK: - FIXED: New Direct Path Waypoint Detection Method
    
    /// Find waypoints that are actually on the direct path (not detours to nearby beacons)
    private func findDirectPathWaypoints(
        from startPos: simd_float3,
        to endPos: simd_float3,
        currentRoom: String
    ) -> [Waypoint] {
        var relevantWaypoints: [Waypoint] = []
        
        // Only include waypoints that are:
        // 1. Close to the direct line between start and end
        // 2. Not causing a detour to an unrelated beacon
        for waypoint in map.waypoints {
            guard waypoint.isAccessible else { continue }
            
            // Check if waypoint is close to the direct path line
            let distanceFromPath = distanceFromPointToLineSegment(
                point: waypoint.coordinates,
                lineStart: startPos,
                lineEnd: endPos
            )
            
            // Only include waypoints that are very close to the direct path (within 2 meters)
            // This prevents detours to nearby beacons
            guard distanceFromPath < 2.0 else { continue }
            
            // Additional check: waypoint should be between start and end (not behind or beyond)
            let totalDistance = simd_distance(startPos, endPos)
            let distanceToWaypoint = simd_distance(startPos, waypoint.coordinates)
            let waypointToEndDistance = simd_distance(waypoint.coordinates, endPos)
            
            // If going through waypoint is not significantly longer than direct path, include it
            let pathThroughWaypoint = distanceToWaypoint + waypointToEndDistance
            let detourRatio = pathThroughWaypoint / totalDistance
            
            // Only include if detour is minimal (less than 10% longer)
            if detourRatio < 1.1 {
                relevantWaypoints.append(waypoint)
                print("     Found direct path waypoint: \(waypoint.name) (detour ratio: \(String(format: "%.2f", detourRatio)))")
            }
        }
        
        // Sort waypoints by distance from start position for logical ordering
        relevantWaypoints.sort { waypoint1, waypoint2 in
            let dist1 = simd_distance(startPos, waypoint1.coordinates)
            let dist2 = simd_distance(startPos, waypoint2.coordinates)
            return dist1 < dist2
        }
        
        return relevantWaypoints
    }
    
    // MARK: - Original Waypoint Detection Methods (kept for same-room navigation)
    
    /// Find waypoints that should be included when traveling between two beacons
    private func findWaypointsForBeacons(
        from startPos: simd_float3,
        to endPos: simd_float3,
        beaconA: String?,
        beaconB: String
    ) -> [Waypoint] {
        var relevantWaypoints: [Waypoint] = []
        
        // Find waypoints that connect these beacons
        for waypoint in map.waypoints {
            guard waypoint.isAccessible && waypoint.connectedBeacons.count >= 2 else { continue }
            
            // Check if this waypoint connects the two beacons (if we have both beacon IDs)
            if let beaconA = beaconA {
                if waypoint.connectedBeacons.contains(beaconA) && waypoint.connectedBeacons.contains(beaconB) {
                    relevantWaypoints.append(waypoint)
                    print("     Found connecting waypoint: \(waypoint.name) (connects \(beaconA) → \(beaconB))")
                }
            } else {
                // For start position, check if waypoint connects to destination beacon
                if waypoint.connectedBeacons.contains(beaconB) {
                    relevantWaypoints.append(waypoint)
                    print("     Found connecting waypoint: \(waypoint.name) (connects to \(beaconB))")
                }
            }
        }
        
        // Sort waypoints by distance from start position for logical ordering
        relevantWaypoints.sort { waypoint1, waypoint2 in
            let dist1 = simd_distance(startPos, waypoint1.coordinates)
            let dist2 = simd_distance(startPos, waypoint2.coordinates)
            return dist1 < dist2
        }
        
        return relevantWaypoints
    }
    
    // MARK: - Helper Methods
    
    private func findNearestBeacon(to position: simd_float3, inRoom roomId: String) -> Beacon? {
        let roomBeacons = map.beacons.filter { $0.roomId == roomId }
        
        var nearestBeacon: Beacon?
        var minDistance: Float = Float.infinity
        
        for beacon in roomBeacons {
            let distance = simd_distance(position, beacon.position)
            if distance < minDistance {
                minDistance = distance
                nearestBeacon = beacon
            }
        }
        
        return nearestBeacon
    }
    
    private func findNearestBeaconGlobally(to position: simd_float3) -> Beacon? {
        var nearestBeacon: Beacon?
        var minDistance: Float = Float.infinity
        
        for beacon in map.beacons {
            let distance = simd_distance(position, beacon.position)
            if distance < minDistance {
                minDistance = distance
                nearestBeacon = beacon
            }
        }
        
        return nearestBeacon
    }
    
    private func isBeaconRelevantToPath(_ beacon: Beacon, startPos: simd_float3, endPos: simd_float3) -> Bool {
        // A beacon is relevant if it's reasonably close to either the start or end of the path segment
        let distToStart = simd_distance(beacon.position, startPos)
        let distToEnd = simd_distance(beacon.position, endPos)
        
        // Consider beacon relevant if it's within 10 meters of either endpoint
        // This is more generous for cross-room connections
        return distToStart < 10.0 || distToEnd < 10.0
    }
    
    private func distanceFromPointToLineSegment(
        point: simd_float3,
        lineStart: simd_float3,
        lineEnd: simd_float3
    ) -> Float {
        let lineVec = lineEnd - lineStart
        let pointVec = point - lineStart
        let lineLength = simd_length(lineVec)
        
        guard lineLength > 0 else {
            return simd_distance(point, lineStart)
        }
        
        let lineUnit = lineVec / lineLength
        let projectionLength = simd_dot(pointVec, lineUnit)
        
        // Clamp to line segment
        let clampedProjection = max(0, min(lineLength, projectionLength))
        let closestPointOnLine = lineStart + lineUnit * clampedProjection
        
        return simd_distance(point, closestPointOnLine)
    }
    
    private func determineRoom(for position: simd_float3) -> String? {
        var closestBeacon: Beacon?
        var minDistance: Float = Float.infinity
        
        for beacon in map.beacons {
            let distance = simd_distance(
                simd_float2(position.x, position.z),
                simd_float2(beacon.position.x, beacon.position.z)
            )
            if distance < minDistance {
                minDistance = distance
                closestBeacon = beacon
            }
        }
        
        return closestBeacon?.roomId
    }
    
    private func estimateDistance(from roomA: String, to roomB: String) -> Float {
        let beaconsA = map.beacons.filter { $0.roomId == roomA }
        let beaconsB = map.beacons.filter { $0.roomId == roomB }
        
        guard !beaconsA.isEmpty && !beaconsB.isEmpty else { return 10.0 }
        
        let avgPosA = beaconsA.reduce(simd_float2(0, 0)) { result, beacon in
            result + simd_float2(beacon.position.x, beacon.position.z)
        } / Float(beaconsA.count)
        
        let avgPosB = beaconsB.reduce(simd_float2(0, 0)) { result, beacon in
            result + simd_float2(beacon.position.x, beacon.position.z)
        } / Float(beaconsB.count)
        
        return simd_distance(avgPosA, avgPosB)
    }
    
    private func formatPosition(_ pos: simd_float3) -> String {
        return "(\(String(format: "%.1f", pos.x)), \(String(format: "%.1f", pos.z)))"
    }
    
    /// Get audio guidance for navigation with room names + hinge/action detail
    private func getNavigationGuidance(for doorway: Doorway, from fromRoomId: String, to toRoomId: String) -> String {
        // Resolve a friendly room name; fall back to ID last
        let targetRoomName = map.room(withId: toRoomId)?.name
            ?? map.rooms.first(where: { $0.id.uuidString == toRoomId })?.name
            ?? toRoomId

        // Action depends on approach direction
        let action = doorway.action(from: fromRoomId, to: toRoomId)

        // Hinge description only for hinged doors
        let hingeText: String = {
            switch doorway.doorType {
            case .hinged_left:  return "Left-hinged"
            case .hinged_right: return "Right-hinged"
            default:            return "" // sliding/automatic/no door
            }
        }()

        // Build concise instruction
        switch action {
        case .push, .pull:
            if hingeText.isEmpty {
                // Non-hinged door types that still require an action
                let verb = (action == .push) ? "Push" : "Pull"
                return "\(verb) to enter \(targetRoomName)"
            } else {
                // Hinged + action
                let verb = (action == .push) ? "push" : "pull"
                return "\(hingeText) door, \(verb) to enter \(targetRoomName)"
            }
        case .slide:
            return "Slide door to enter \(targetRoomName)"
        case .automatic:
            return "Automatic door, walk through to \(targetRoomName)"
        case .walkThrough:
            return "Walk through to \(targetRoomName)"
        }
    }

}
