//
//  Doorway.swift - REFACTORED
//  Door exists BETWEEN two rooms with clear directional actions
//

import Foundation
import simd

// MARK: - Doorway Model (Direction-Aware)
struct Doorway: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let position: simd_float3  // Door position in 3D space
    let width: Float
    let height: Float
    let connectsRooms: ConnectedRooms  // Which two rooms it connects
    let doorType: DoorwayType
    let doorActions: DoorActions  // What action from each side
    let isAccessible: Bool
    let timestamp: Date
    
    // Optional - editable later
    var description: String?
    var audioLandmark: String?
    
    init(name: String, position: simd_float3, width: Float, height: Float = 2.1,
         connectsRooms: ConnectedRooms, doorType: DoorwayType = .hinged_right,
         doorActions: DoorActions, isAccessible: Bool = true,
         description: String? = nil, audioLandmark: String? = nil) {
        self.id = UUID()
        self.name = name
        self.position = position
        self.width = width
        self.height = height
        self.connectsRooms = connectsRooms
        self.doorType = doorType
        self.doorActions = doorActions
        self.isAccessible = isAccessible
        self.timestamp = Date()
        self.description = description
        self.audioLandmark = audioLandmark
    }
    
    // Get the action needed when traveling from one room to another
    func action(from fromRoomId: String, to toRoomId: String) -> DoorAction {
        if fromRoomId == connectsRooms.roomA {
            return doorActions.fromRoomA
        } else if fromRoomId == connectsRooms.roomB {
            return doorActions.fromRoomB
        }
        return .walkThrough  // Fallback
    }
    
    // Get audio guidance for navigation
    func navigationGuidance(from fromRoomId: String, to toRoomId: String) -> String {
        let action = action(from: fromRoomId, to: toRoomId)
        let targetRoom = toRoomId == connectsRooms.roomA ? connectsRooms.roomA : connectsRooms.roomB
        
        switch action {
        case .push:
            return "Push door to enter \(targetRoom)"
        case .pull:
            return "Pull door to enter \(targetRoom)"
        case .slide:
            return "Slide door to enter \(targetRoom)"
        case .automatic:
            return "Door opens automatically, walk through to \(targetRoom)"
        case .walkThrough:
            return "Walk through to \(targetRoom)"
        }
    }
    
    var floorPosition: simd_float2 {
        return simd_float2(position.x, position.z)
    }
}

// MARK: - Connected Rooms
struct ConnectedRooms: Codable, Equatable {
    let roomA: String  // First room ID
    let roomB: String  // Second room ID
    
    // Check if a room is connected
    func contains(roomId: String) -> Bool {
        return roomId == roomA || roomId == roomB
    }
    
    // Get the other room
    func otherRoom(from roomId: String) -> String? {
        if roomId == roomA {
            return roomB
        } else if roomId == roomB {
            return roomA
        }
        return nil
    }
}

// MARK: - Door Actions (What to do from each side)
struct DoorActions: Codable, Equatable {
    let fromRoomA: DoorAction  // Action when going from roomA to roomB
    let fromRoomB: DoorAction  // Action when going from roomB to roomA
    
    init(fromRoomA: DoorAction, fromRoomB: DoorAction) {
        self.fromRoomA = fromRoomA
        self.fromRoomB = fromRoomB
    }
    
    // Helper: Create opposite actions for standard hinged doors
    static func hingedDoor(pushFromRoomA: Bool) -> DoorActions {
        if pushFromRoomA {
            return DoorActions(fromRoomA: .push, fromRoomB: .pull)
        } else {
            return DoorActions(fromRoomA: .pull, fromRoomB: .push)
        }
    }
    
    // Helper: Same action from both sides
    static func symmetrical(_ action: DoorAction) -> DoorActions {
        return DoorActions(fromRoomA: action, fromRoomB: action)
    }
}

// MARK: - Door Action (What you physically do)
enum DoorAction: String, Codable, CaseIterable {
    case push = "push"
    case pull = "pull"
    case slide = "slide"
    case automatic = "automatic"
    case walkThrough = "walk_through"
    
    var displayName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .slide: return "Slide"
        case .automatic: return "Automatic"
        case .walkThrough: return "Walk Through"
        }
    }
    
    var audioInstruction: String {
        switch self {
        case .push: return "push to open"
        case .pull: return "pull to open"
        case .slide: return "slide to open"
        case .automatic: return "will open automatically"
        case .walkThrough: return "walk through opening"
        }
    }
}

// MARK: - Doorway Types
enum DoorwayType: String, CaseIterable, Codable {
    case hinged_left = "hinged_left"
    case hinged_right = "hinged_right"
    case swinging_both = "swinging_both"  // Push from both sides
    case sliding = "sliding"
    case automatic = "automatic"
    case open_doorway = "open_doorway"
    case double_door = "double_door"
    
    var displayName: String {
        switch self {
        case .hinged_left: return "Left-Hinged Door"
        case .hinged_right: return "Right-Hinged Door"
        case .swinging_both: return "Swinging Door (Both Ways)"
        case .sliding: return "Sliding Door"
        case .automatic: return "Automatic Door"
        case .open_doorway: return "Open Doorway"
        case .double_door: return "Double Door"
        }
    }
    
    var color: (red: Float, green: Float, blue: Float) {
        switch self {
        case .hinged_left, .hinged_right: return (0.0, 0.8, 1.0)
        case .swinging_both: return (0.8, 0.0, 0.8)
        case .sliding: return (0.0, 0.6, 1.0)
        case .automatic: return (0.5, 0.0, 1.0)
        case .open_doorway: return (0.0, 1.0, 0.5)
        case .double_door: return (0.0, 0.7, 0.9)
        }
    }
}
