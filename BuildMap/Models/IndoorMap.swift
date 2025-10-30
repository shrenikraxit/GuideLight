//
//  IndoorMap.swift - SIMPLIFIED
//  No room boundaries, simple structure
//

import Foundation
import simd

// MARK: - Indoor Map Model (Simplified)
struct IndoorMap: Codable, Identifiable {
    let id: UUID
    let name: String
    let description: String?
    let rooms: [Room]
    let beacons: [Beacon]
    let doorways: [Doorway]
    let waypoints: [Waypoint]
    let metadata: MapMetadata
    let createdAt: Date
    let updatedAt: Date
    
    init(name: String, description: String? = nil, rooms: [Room] = [],
         beacons: [Beacon] = [], doorways: [Doorway] = [], waypoints: [Waypoint] = []) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.rooms = rooms
        self.beacons = beacons
        self.doorways = doorways
        self.waypoints = waypoints
        self.metadata = MapMetadata()
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    func updated(rooms: [Room]? = nil, beacons: [Beacon]? = nil,
                doorways: [Doorway]? = nil, waypoints: [Waypoint]? = nil) -> IndoorMap {
        return IndoorMap(
            id: self.id,
            name: self.name,
            description: self.description,
            rooms: rooms ?? self.rooms,
            beacons: beacons ?? self.beacons,
            doorways: doorways ?? self.doorways,
            waypoints: waypoints ?? self.waypoints,
            metadata: self.metadata.updated(),
            createdAt: self.createdAt,
            updatedAt: Date()
        )
    }
    
    private init(id: UUID, name: String, description: String?, rooms: [Room],
                beacons: [Beacon], doorways: [Doorway], waypoints: [Waypoint],
                metadata: MapMetadata, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.description = description
        self.rooms = rooms
        self.beacons = beacons
        self.doorways = doorways
        self.waypoints = waypoints
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    func room(withId id: String) -> Room? {
        return rooms.first { $0.id.uuidString == id }
    }
    
    func beacon(named name: String) -> Beacon? {
        return beacons.first { $0.name.lowercased() == name.lowercased() }
    }
    
    func beacons(inRoom roomId: String) -> [Beacon] {
        return beacons.filter { $0.roomId == roomId }
    }
    
    func doorways(connectingRoom roomId: String) -> [Doorway] {
        return doorways.filter { $0.connectsRooms.contains(roomId: roomId) }
    }
    
    var totalItems: Int {
        return beacons.count + doorways.count + waypoints.count
    }
    
    var isEmpty: Bool {
        return rooms.isEmpty && beacons.isEmpty && doorways.isEmpty && waypoints.isEmpty
    }
    
    // MARK: - Statistics
    var stats: MapStats {
        return MapStats(
            roomCount: rooms.count,
            beaconCount: beacons.count,
            doorwayCount: doorways.count,
            waypointCount: waypoints.count,
            accessibleBeacons: beacons.filter { $0.isAccessible }.count,
            obstacleBeacons: beacons.filter { $0.isObstacle }.count
        )
    }
}

// MARK: - Map Statistics
struct MapStats {
    let roomCount: Int
    let beaconCount: Int
    let doorwayCount: Int
    let waypointCount: Int
    let accessibleBeacons: Int
    let obstacleBeacons: Int
    
    var totalItems: Int {
        return beaconCount + doorwayCount + waypointCount
    }
}

// MARK: - Map Metadata
struct MapMetadata: Codable {
    let version: String
    let coordinateSystem: CoordinateSystem
    let units: String
    
    init(coordinateSystem: CoordinateSystem = .arkit, units: String = "meters") {
        self.version = "2.2"
        self.coordinateSystem = coordinateSystem
        self.units = units
    }
    
    func updated() -> MapMetadata {
        return MapMetadata(coordinateSystem: self.coordinateSystem, units: self.units)
    }
}

enum CoordinateSystem: String, Codable {
    case arkit = "arkit_world"
    case local = "local"
}

// MARK: - Export to JSON
extension IndoorMap {
    
    var filename: String {
        let cleanName = name.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "[^a-zA-Z0-9_]", with: "", options: .regularExpression)
        return "\(cleanName)_\(id.uuidString.prefix(8)).json"
    }
    
    func toNewJSONFormat() -> [String: Any] {
        return [
            "metadata": [
                "version": "2.2",
                "createdDate": createdAt.timeIntervalSince1970,
                "lastModified": updatedAt.timeIntervalSince1970,
                "createdBy": "ios_app",
                "coordinateSystem": metadata.coordinateSystem.rawValue,
                "units": metadata.units
            ],
            "mapName": name,
            "description": description ?? "",
            "rooms": rooms.map { room in
                var roomData: [String: Any] = [
                    "id": room.id.uuidString,
                    "name": room.name,
                    "type": room.type.rawValue,
                    "floorSurface": room.floorSurface.rawValue
                ]
                if let description = room.description {
                    roomData["description"] = description
                }
                return roomData
            },
            "beacons": beacons.map { beacon in
                var data: [String: Any] = [
                    "id": beacon.id.uuidString,
                    "name": beacon.name,
                    "category": beacon.category.rawValue,
                    "coordinates": [
                        "x": Double(beacon.position.x),
                        "y": Double(beacon.position.y),
                        "z": Double(beacon.position.z)
                    ],
                    "roomId": beacon.roomId,
                    "audioLandmark": beacon.audioLandmark ?? beacon.name,
                    "timestamp": beacon.timestamp.timeIntervalSince1970,
                    "isAccessible": beacon.isAccessible
                ]
                
                if let props = beacon.physicalProperties {
                    data["physicalProperties"] = [
                        "isObstacle": props.isObstacle,
                        "boundingBox": [
                            "width": Double(props.boundingBox.width),
                            "depth": Double(props.boundingBox.depth),
                            "height": Double(props.boundingBox.height)
                        ],
                        "avoidanceRadius": Double(props.avoidanceRadius),
                        "canRouteAround": props.canRouteAround,
                        "obstacleType": props.obstacleType.rawValue
                    ]
                }
                
                if let description = beacon.description {
                    data["description"] = description
                }
                
                if let notes = beacon.accessibilityNotes {
                    data["accessibilityNotes"] = notes
                }
                
                return data
            },
            "doorways": doorways.map { doorway in
                var data: [String: Any] = [
                    "id": doorway.id.uuidString,
                    "name": doorway.name,
                    "position": [
                        "x": Double(doorway.position.x),
                        "y": Double(doorway.position.y),
                        "z": Double(doorway.position.z)
                    ],
                    "width": Double(doorway.width),
                    "height": Double(doorway.height),
                    "connectsRooms": [
                        "roomA": doorway.connectsRooms.roomA,
                        "roomB": doorway.connectsRooms.roomB
                    ],
                    "doorType": doorway.doorType.rawValue,
                    "doorActions": [
                        "fromRoomA": doorway.doorActions.fromRoomA.rawValue,
                        "fromRoomB": doorway.doorActions.fromRoomB.rawValue
                    ],
                    "isAccessible": doorway.isAccessible
                ]
                
                if let description = doorway.description {
                    data["description"] = description
                }
                
                if let audioLandmark = doorway.audioLandmark {
                    data["audioLandmark"] = audioLandmark
                }
                
                return data
            },
            "waypoints": waypoints.map { waypoint in
                var data: [String: Any] = [
                    "id": waypoint.id.uuidString,
                    "name": waypoint.name,
                    "coordinates": [
                        "x": Double(waypoint.coordinates.x),
                        "y": Double(waypoint.coordinates.y),
                        "z": Double(waypoint.coordinates.z)
                    ],
                    "roomId": waypoint.roomId,
                    "waypointType": waypoint.waypointType.rawValue,
                    "isAccessible": waypoint.isAccessible,
                    "connected_beacons": waypoint.connectedBeacons
                ]
                
                if let description = waypoint.description {
                    data["description"] = description
                }
                
                if let audioLandmark = waypoint.audioLandmark {
                    data["audioLandmark"] = audioLandmark
                }
                
                return data
            }
        ]
    }
    
    func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    static func fromJSONData(_ data: Data) throws -> IndoorMap {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(IndoorMap.self, from: data)
    }
}
