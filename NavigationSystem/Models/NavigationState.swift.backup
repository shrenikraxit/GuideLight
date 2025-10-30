//
//  NavigationState.swift
//  GuideLight v3
//
//  Complete file with Path JSON export
//

import Foundation
import simd

// MARK: - Navigation State
enum NavigationState: Equatable {
    case notStarted
    case calibrating
    case selectingDestination
    case computingPath
    case navigating(currentWaypoint: Int, totalWaypoints: Int)
    case arrived
    case paused
    case failed(String)
    
    var isActive: Bool {
        switch self {
        case .navigating:
            return true
        default:
            return false
        }
    }
}

// MARK: - Navigation Waypoint
struct NavigationWaypoint: Identifiable, Equatable {
    let id: UUID
    let position: simd_float3
    let type: WaypointType
    let name: String
    let roomId: String?
    let doorwayId: String?
    let audioInstruction: String?
    
    init(position: simd_float3, type: WaypointType, name: String,
         roomId: String? = nil, doorwayId: String? = nil, audioInstruction: String? = nil) {
        self.id = UUID()
        self.position = position
        self.type = type
        self.name = name
        self.roomId = roomId
        self.doorwayId = doorwayId
        self.audioInstruction = audioInstruction
    }
    
    enum WaypointType: String {
        case start = "start"
        case intermediate = "intermediate"
        case doorway = "doorway"
        case destination = "destination"
    }
}

// MARK: - Navigation Path
struct NavigationPath: Equatable {
    let waypoints: [NavigationWaypoint]
    let totalDistance: Float
    let estimatedTime: TimeInterval
    let roomsTraversed: [String]
    
    var waypointCount: Int {
        return waypoints.count
    }
    
    func distance(from index: Int) -> Float {
        guard index < waypoints.count - 1 else { return 0 }
        
        var total: Float = 0
        for i in index..<(waypoints.count - 1) {
            let current = waypoints[i].position
            let next = waypoints[i + 1].position
            total += simd_distance(current, next)
        }
        return total
    }
    
    // MARK: - Path JSON Export
    
    /// Export path as JSON dictionary for visualization
    func toJSON() -> [String: Any] {
        var pathNodes: [[String: Any]] = []
        
        for (index, waypoint) in waypoints.enumerated() {
            var node: [String: Any] = [
                "step": index + 1,
                "nodeId": waypoint.id.uuidString,
                "nodeName": waypoint.name,
                "nodeType": nodeTypeString(for: waypoint.type),
                "position": [
                    "x": Double(waypoint.position.x),
                    "y": Double(waypoint.position.y),
                    "z": Double(waypoint.position.z)
                ]
            ]
            
            if let roomId = waypoint.roomId {
                node["roomId"] = roomId
            }
            
            // Calculate distance to next waypoint
            if index < waypoints.count - 1 {
                let distanceToNext = simd_distance(waypoint.position, waypoints[index + 1].position)
                node["distanceToNext"] = Double(distanceToNext)
            }
            
            pathNodes.append(node)
        }
        
        return [
            "totalSteps": waypoints.count,
            "totalDistance": Double(totalDistance),
            "startNode": waypoints.first?.name ?? "Unknown",
            "endNode": waypoints.last?.name ?? "Unknown",
            "pathCalculated": Date().timeIntervalSince1970,
            "path": pathNodes
        ]
    }
    
    private func nodeTypeString(for type: NavigationWaypoint.WaypointType) -> String {
        switch type {
        case .start: return "waypoint"
        case .intermediate: return "waypoint"
        case .doorway: return "doorway"
        case .destination: return "beacon_landmark"
        }
    }
    
    /// Export as pretty-printed JSON string
    func toJSONString() -> String {
        let jsonDict = toJSON()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: jsonDict, options: .prettyPrinted),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }
}

// MARK: - Navigation Progress
struct NavigationProgress: Equatable {
    let currentWaypointIndex: Int
    let distanceToNextWaypoint: Float
    let totalDistanceRemaining: Float
    let estimatedTimeRemaining: TimeInterval
    let currentHeading: Float
    let targetHeading: Float
    let headingError: Float
    
    var percentComplete: Float {
        guard totalDistanceRemaining > 0 else { return 1.0 }
        return 0.0
    }
    
    var isAligned: Bool {
        return abs(headingError) < 0.2617994  // 15 degrees in radians
    }
    
    var alignmentQuality: AlignmentQuality {
        let absError = abs(headingError)
        let degrees = absError * 180 / .pi
        
        if degrees < 15.0 {
            return .excellent
        } else if degrees < 30.0 {
            return .good
        } else if degrees < 60.0 {
            return .fair
        } else if degrees < 120.0 {
            return .poor
        } else {
            return .veryPoor
        }
    }
    
    enum AlignmentQuality {
        case excellent, good, fair, poor, veryPoor
        
        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "lightgreen"
            case .fair: return "yellow"
            case .poor: return "orange"
            case .veryPoor: return "red"
            }
        }
        
        var compassScale: Float {
            switch self {
            case .excellent: return 1.0
            case .good: return 1.1
            case .fair: return 1.2
            case .poor: return 1.3
            case .veryPoor: return 1.4
            }
        }
    }
}

// MARK: - User Position Update
struct UserPositionUpdate {
    let position: simd_float3
    let heading: Float
    let timestamp: Date
    let trackingQuality: TrackingQuality
    
    enum TrackingQuality {
        case excellent
        case good
        case limited
        case poor
        
        var description: String {
            switch self {
            case .excellent: return "Excellent"
            case .good: return "Good"
            case .limited: return "Limited"
            case .poor: return "Poor"
            }
        }
    }
}
