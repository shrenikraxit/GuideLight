//
//  Room.swift
//  GuideLight v3
//
//  Simplified room model + optional address/floor fields
//

import Foundation

// MARK: - Room Model
struct Room: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: RoomType
    let floorSurface: FloorSurface
    let createdAt: Date

    /// Optional, human-authored description stored in JSON
    var description: String?

    /// NEW: e.g. "123 Main St, Springfield, NJ"
    var address: String?

    /// NEW: floor label, flexible for "B1", "Mezz", "2", "PH", etc.
    var floorOfBuilding: String?

    // JSON keys – keep Swift camelCase, JSON snake_case for floor
    enum CodingKeys: String, CodingKey {
        case id, name, type, floorSurface, createdAt, description, address
        case floorOfBuilding = "floor_of_build"
    }

    init(
        id: UUID = UUID(),
        name: String,
        type: RoomType = .general,
        floorSurface: FloorSurface = .carpet,
        createdAt: Date = Date(),
        description: String? = nil,
        address: String? = nil,
        floorOfBuilding: String? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.floorSurface = floorSurface
        self.createdAt = createdAt
        self.description = description
        self.address = address
        self.floorOfBuilding = floorOfBuilding
    }
}

// MARK: - Room Type (keep your existing cases)
enum RoomType: String, Codable, CaseIterable, Identifiable {
    case general, kitchen, living, bedroom, bathroom, hallway, office, laundry, garage, lobby, stairwell, elevator, storage, classroom, lab, cafeteria, auditorium, entrance
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .entrance: return "Entrance"
        case .general: return "General"
        case .kitchen: return "Kitchen"
        case .living: return "Living"
        case .bedroom: return "Bedroom"
        case .bathroom: return "Bathroom"
        case .hallway: return "Hallway"
        case .office: return "Office"
        case .laundry: return "Laundry"
        case .garage: return "Garage"
        case .lobby: return "Lobby"
        case .stairwell: return "Stairwell"
        case .elevator: return "Elevator"
        case .storage: return "Storage"
        case .classroom: return "Classroom"
        case .lab: return "Lab"
        case .cafeteria: return "Cafeteria"
        case .auditorium: return "Auditorium"
        }
    }
}

// MARK: - Floor surface (keep as-is; included for completeness)
enum FloorSurface: String, Codable, CaseIterable, Identifiable {
    case carpet, hardwood, tile, marble, concrete, linoleum
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .carpet: return "Carpet"
        case .hardwood: return "Hardwood"
        case .tile: return "Tile"
        case .marble: return "Marble"
        case .concrete: return "Concrete"
        case .linoleum: return "Linoleum"
        }
    }

    // Optional: Audio/feel hints you were using elsewhere
    var echoLevel: String {
        switch self {
        case .carpet: return "low echo"
        case .tile, .marble: return "high echo"
        case .hardwood: return "medium echo"
        case .concrete: return "high echo"
        case .linoleum: return "low echo"
        }
    }
}
