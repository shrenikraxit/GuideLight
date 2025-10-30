//
//  LocationDescriptionService.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/21/25.
//

import Foundation
import simd

// MARK: - Doorway helpers (renamed to avoid clashes)
extension ConnectedRooms {
    /// If this doorway connects `roomId`, return the opposite room id; otherwise nil.
    func counterpart(of roomId: String) -> String? {
        if roomA == roomId { return roomB }
        if roomB == roomId { return roomA }
        return nil
    }
}

/// Service that generates natural language descriptions of the user's current location
@MainActor
final class LocationDescriptionService {
    
    static let shared = LocationDescriptionService()
    private init() {}
    
    // MARK: - Public Methods
    
    /// Generate a comprehensive location description for the user's current position
    func describeCurrentLocation(
        position: simd_float3,
        map: IndoorMap,
        includeNavigationHints: Bool = true
    ) -> String? {
        
        guard let currentRoomId = determineCurrentRoom(position: position, map: map),
              let room = map.room(withId: currentRoomId) else {
            return "I cannot determine your current location. Please ensure you are in a mapped area."
            
        }
        
        print("[LocationDescription] Describing location in room: \(room.name)")
        
        // Build comprehensive description
        var components: [String] = []
        
        // 1. Primary location statement
        components.append(buildPrimaryLocationStatement(room: room, map: map))
        
        // 2. Contextual information (if available)
        if let contextInfo = buildContextualInformation(room: room, map: map) {
            components.append(contextInfo)
        }
        
        // 3. Floor surface information
        components.append(buildFloorSurfaceDescription(room: room))
        
        // 4. Navigation hints (if requested)
        if includeNavigationHints {
            if let navHints = buildNavigationHints(room: room, map: map) {
                components.append(navHints)
            }
        }
        
        let fullDescription = components.joined(separator: " ")
        print("[LocationDescription] Generated description: \(fullDescription)")
        
        return fullDescription
    }
    
    /// Quick room identification without full description
    func identifyCurrentRoom(position: simd_float3, map: IndoorMap) -> Room? {
        guard let roomId = determineCurrentRoom(position: position, map: map) else {
            return nil
        }
        return map.room(withId: roomId)
    }
    
    // MARK: - Private Methods
    
    /// Determine which room the user is currently in based on their position
    private func determineCurrentRoom(position: simd_float3, map: IndoorMap) -> String? {
        // Find the closest beacon to determine room
        var closestBeacon: Beacon?
        var minDistance: Float = .infinity
        
        for beacon in map.beacons {
            let distance = simd_distance(position, beacon.position)
            if distance < minDistance {
                minDistance = distance
                closestBeacon = beacon
            }
        }
        
        return closestBeacon?.roomId
    }
    
    /// Build the primary location statement
    private func buildPrimaryLocationStatement(room: Room, map: IndoorMap) -> String {
        // Priority 1: Use description if available (most specific)
        if let description = room.description, !description.isEmpty {
            return "You are in the \(room.name), \(description)."
        }
        
        // Priority 2: Fallback to room type-based description
        switch room.type {
        case .entrance:
            return "You are in the \(room.name), the entrance to the building."
        case .auditorium:
            return "You are in the \(room.name), an auditorium or lecture hall."
        case .cafeteria:
            return "You are in the \(room.name), a cafeteria or dining area."
        case .lab:
            return "You are in the \(room.name), a laboratory or research area."
        case .classroom:
            return "You are in the \(room.name), classroom area."
        case .elevator:
            return "You are in the \(room.name), the elevator lobby."
        case .stairwell:
            return "You are in the \(room.name), a stairwell or escalator."
        case .lobby:
            return "You are in the \(room.name), the lobby or main entrance."
        case .hallway:
            return "You are in the \(room.name), a hallway connecting different areas."
        case .bathroom:
            return "You are in the \(room.name), a bathroom facility."
        case .kitchen:
            return "You are in the \(room.name), the kitchen area."
        case .bedroom:
            return "You are in the \(room.name), a bedroom."
        case .office:
            return "You are in the \(room.name), an office or workspace."
        case .storage:
            return "You are in the \(room.name), a storage area."
        case .garage:
            return "You are in the \(room.name), the garage."
        case .laundry:
            return "You are in the \(room.name), the laundry room."
        case .general:
            return "You are in the \(room.name)."
        case .living:
            return "You are in the \(room.name), a family living room"
        }
    }
    
    /// Build contextual information about the location
    private func buildContextualInformation(room: Room, map: IndoorMap) -> String? {
        var contextParts: [String] = []
        let roomId = room.id.uuidString
        
        // Check for entry capabilities for entrance rooms
        if room.type == .entrance {
            let doorways = map.doorways.filter { $0.connectsRooms.roomA == roomId || $0.connectsRooms.roomB == roomId }
            if !doorways.isEmpty {
                if room.name.lowercased().contains("outside") {
                    contextParts.append("You can enter the building from here")
                } else {
                    contextParts.append("This is an entrance area")
                }
            }
        }
        
        // Beacons available from here
        let roomBeacons = map.beacons.filter { $0.roomId == roomId }
        let accessibleBeacons = roomBeacons.filter { $0.isAccessible && !$0.isObstacle }
        
        if accessibleBeacons.count > 1 {
            let destinations = accessibleBeacons.prefix(3).map { $0.name }
            if destinations.count == 2 {
                contextParts.append("You can navigate to \(destinations[0]) or \(destinations[1]) from here")
            } else if destinations.count >= 3 {
                contextParts.append("You can navigate to \(destinations[0]), \(destinations[1]), or \(destinations[2]) from here")
            }
        }
        
        return contextParts.isEmpty ? nil : contextParts.joined(separator: ". ")
    }
    
    /// Build floor surface description
    private func buildFloorSurfaceDescription(room: Room) -> String {
        return "The floor surface is \(room.floorSurface.displayName.lowercased()) with \(room.floorSurface.echoLevel)."
    }
    
    /// Build navigation hints
    private func buildNavigationHints(room: Room, map: IndoorMap) -> String? {
        let roomId = room.id.uuidString
        let doorways = map.doorways.filter { $0.connectsRooms.roomA == roomId || $0.connectsRooms.roomB == roomId }
        guard !doorways.isEmpty else { return nil }
        
        var hints: [String] = []
        
        if doorways.count == 1 {
            let connectedRoomId = doorways[0].connectsRooms.counterpart(of: roomId)
            if let connectedRoom = map.room(withId: connectedRoomId ?? "") {
                hints.append("There is an exit leading to \(connectedRoom.name)")
            }
        } else {
            let connectedRooms = doorways.compactMap { doorway in
                let otherRoomId = doorway.connectsRooms.counterpart(of: roomId)
                return map.room(withId: otherRoomId ?? "")?.name
            }.prefix(3)
            
            if connectedRooms.count >= 2 {
                let roomsList = Array(connectedRooms)
                if roomsList.count == 2 {
                    hints.append("There are exits leading to \(roomsList[0]) and \(roomsList[1])")
                } else {
                    hints.append("There are exits leading to \(roomsList[0]), \(roomsList[1]), and other areas")
                }
            }
        }
        
        return hints.isEmpty ? nil : hints.joined(separator: ". ")
    }
}


