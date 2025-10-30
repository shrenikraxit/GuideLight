//
//  NavigationIntegrationHelper.swift
//  GuideLight v3
//
//  Navigation integration helper for ARWorldMap support

import Foundation
import SwiftUI
import ARKit
import Combine
import simd

// MARK: - Navigation Integration Helper
class NavigationIntegrationHelper: ObservableObject {
    static let shared = NavigationIntegrationHelper()
    
    @Published var selectedMapForNavigation: JSONMap?
    @Published var isARWorldMapLoaded = false
    @Published var loadingProgress: String = ""
    
    private var mapManager = SimpleJSONMapManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationListeners()
    }
    
    // MARK: - Notification Listeners
    private func setupNotificationListeners() {
        NotificationCenter.default.publisher(for: .mapSelectedForNavigation)
            .sink { [weak self] notification in
                self?.handleMapSelectionChange(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleMapSelectionChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let mapId = userInfo["mapId"] as? UUID else {
            selectedMapForNavigation = nil
            isARWorldMapLoaded = false
            return
        }
        
        if let map = mapManager.maps.first(where: { $0.id == mapId }) {
            selectedMapForNavigation = map
            print("📍 Navigation Helper: Map selected - \(map.name)")
            print("   Has ARWorldMap: \(map.hasARWorldMap)")
        }
    }
    
    // MARK: - ARWorldMap Loading
    func loadARWorldMapForNavigation(completion: @escaping (Result<ARWorldMap, ARWorldMapError>) -> Void) {
        guard let map = selectedMapForNavigation else {
            completion(.failure(.fileNotFound)); return
        }
        guard map.hasARWorldMap else {
            completion(.failure(.fileNotFound)); return
        }
        
        loadingProgress = "Loading ARWorldMap for navigation..."
        isARWorldMapLoaded = false
        
        mapManager.loadARWorldMap(for: map) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let worldMap):
                    self?.isARWorldMapLoaded = true
                    self?.loadingProgress = "ARWorldMap loaded successfully"
                    print("✅ Navigation Helper: ARWorldMap loaded for navigation")
                    completion(.success(worldMap))
                case .failure(let error):
                    self?.isARWorldMapLoaded = false
                    self?.loadingProgress = "Failed to load ARWorldMap"
                    print("❌ Navigation Helper: Failed to load ARWorldMap - \(error)")
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Map Data Access
    func getNavigationMapData() -> [String: Any]? { selectedMapForNavigation?.jsonData }
    func getNavigationMapName() -> String? { selectedMapForNavigation?.name }
    func hasARWorldMapSupport() -> Bool { selectedMapForNavigation?.hasARWorldMap ?? false }
    
    // MARK: - Clear Selection
    func clearNavigationMap() {
        selectedMapForNavigation = nil
        isARWorldMapLoaded = false
        loadingProgress = ""
        mapManager.selectMapForNavigation(nil)
    }
    
    // MARK: - Parse IndoorMap from JSONMap (ENHANCED WITH BACKWARD COMPATIBILITY)
    static func parseIndoorMap(from jsonMap: JSONMap) -> IndoorMap? {
        guard let mapName = jsonMap.jsonData["mapName"] as? String else {
            print("❌ Failed to parse map: Missing mapName"); return nil
        }
        
        // Rooms - ENHANCED with metadata support while maintaining backward compatibility
        var rooms: [Room] = []
        if let roomsData = jsonMap.jsonData["rooms"] as? [[String: Any]] {
            for roomDict in roomsData {
                guard let name = roomDict["name"] as? String,
                      let typeString = roomDict["type"] as? String,
                      let floorSurfaceString = roomDict["floorSurface"] as? String,
                      let roomType = RoomType(rawValue: typeString),
                      let floorSurface = FloorSurface(rawValue: floorSurfaceString) else { continue }
                
                // NEW: Extract additional metadata fields (backward compatible - will be nil if not present)
                let description = roomDict["description"] as? String
                let metadata = roomDict["metadata"] as? String
                let address = roomDict["address"] as? String
                
                let room = Room(
                    name: name,
                    type: roomType,
                    floorSurface: floorSurface,
                    description: description,
                    address: address
                )
                rooms.append(room)
                
                print("✅ Parsed room: \(name)")
                if let metadata = metadata {
                    print("   Metadata: \(metadata)")
                }
                if let address = address {
                    print("   Address: \(address)")
                }
                if let description = description {
                    print("   Description: \(description)")
                }
            }
        }
        
        // Beacons - UNCHANGED
        var beacons: [Beacon] = []
        if let beaconsData = jsonMap.jsonData["beacons"] as? [[String: Any]] {
            for beaconDict in beaconsData {
                guard let name = beaconDict["name"] as? String,
                      let categoryString = beaconDict["category"] as? String,
                      let category = BeaconCategory(rawValue: categoryString),
                      let roomId = beaconDict["roomId"] as? String,
                      let coordsDict = beaconDict["coordinates"] as? [String: Double],
                      let x = coordsDict["x"], let y = coordsDict["y"], let z = coordsDict["z"] else { continue }
                
                let position = simd_float3(Float(x), Float(y), Float(z))
                let audioLandmark = beaconDict["audioLandmark"] as? String
                let isAccessible = beaconDict["isAccessible"] as? Bool ?? true
                
                var physicalProperties: PhysicalProperties?
                if let propsDict = beaconDict["physicalProperties"] as? [String: Any],
                   let isObstacle = propsDict["isObstacle"] as? Bool, isObstacle,
                   let box = propsDict["boundingBox"] as? [String: Double],
                   let width = box["width"], let depth = box["depth"], let height = box["height"],
                   let avoidanceRadius = propsDict["avoidanceRadius"] as? Double,
                   let obstacleTypeString = propsDict["obstacleType"] as? String,
                   let obstacleType = ObstacleType(rawValue: obstacleTypeString) {
                    physicalProperties = PhysicalProperties(
                        isObstacle: true,
                        boundingBox: BoundingBox(width: Float(width), depth: Float(depth), height: Float(height)),
                        avoidanceRadius: Float(avoidanceRadius),
                        canRouteAround: propsDict["canRouteAround"] as? Bool ?? true,
                        obstacleType: obstacleType
                    )
                }
                
                beacons.append(
                    Beacon(
                        name: name,
                        position: position,
                        category: category,
                        roomId: roomId,
                        description: beaconDict["description"] as? String,
                        audioLandmark: audioLandmark,
                        isAccessible: isAccessible,
                        accessibilityNotes: beaconDict["accessibilityNotes"] as? String,
                        physicalProperties: physicalProperties
                    )
                )
            }
        }
        
        // Doorways - UNCHANGED
        var doorways: [Doorway] = []
        if let doorwaysData = jsonMap.jsonData["doorways"] as? [[String: Any]] {
            for doorwayDict in doorwaysData {
                guard let name = doorwayDict["name"] as? String,
                      let posDict = doorwayDict["position"] as? [String: Double],
                      let x = posDict["x"], let y = posDict["y"], let z = posDict["z"],
                      let width = doorwayDict["width"] as? Double,
                      let connectsDict = doorwayDict["connectsRooms"] as? [String: String],
                      let roomA = connectsDict["roomA"], let roomB = connectsDict["roomB"],
                      let doorTypeString = doorwayDict["doorType"] as? String,
                      let doorType = DoorwayType(rawValue: doorTypeString),
                      let actionsDict = doorwayDict["doorActions"] as? [String: String],
                      let fromAString = actionsDict["fromRoomA"],
                      let fromBString = actionsDict["fromRoomB"],
                      let fromRoomA = DoorAction(rawValue: fromAString),
                      let fromRoomB = DoorAction(rawValue: fromBString) else { continue }
                
                let position = simd_float3(Float(x), Float(y), Float(z))
                let isAccessible = doorwayDict["isAccessible"] as? Bool ?? true
                
                doorways.append(
                    Doorway(
                        name: name,
                        position: position,
                        width: Float(width),
                        height: Float(doorwayDict["height"] as? Double ?? 2.1),
                        connectsRooms: ConnectedRooms(roomA: roomA, roomB: roomB),
                        doorType: doorType,
                        doorActions: DoorActions(fromRoomA: fromRoomA, fromRoomB: fromRoomB),
                        isAccessible: isAccessible,
                        description: doorwayDict["description"] as? String,
                        audioLandmark: doorwayDict["audioLandmark"] as? String
                    )
                )
            }
        }
        
        // Waypoints (optional) - UNCHANGED
        var waypoints: [Waypoint] = []
        if let waypointsData = jsonMap.jsonData["waypoints"] as? [[String: Any]] {
            for waypointDict in waypointsData {
                guard let name = waypointDict["name"] as? String,
                      let coordsDict = waypointDict["coordinates"] as? [String: Double],
                      let x = coordsDict["x"], let y = coordsDict["y"], let z = coordsDict["z"],
                      let roomId = waypointDict["roomId"] as? String else { continue }
                
                let coordinates = simd_float3(Float(x), Float(y), Float(z))
                let waypointTypeString = waypointDict["waypointType"] as? String ?? "navigation"
                let waypointType = Waypoint.WaypointType(rawValue: waypointTypeString) ?? .navigation
                let isAccessible = waypointDict["isAccessible"] as? Bool ?? true
                
                waypoints.append(
                    Waypoint(
                        name: name,
                        coordinates: coordinates,
                        roomId: roomId,
                        waypointType: waypointType,
                        isAccessible: isAccessible,
                        description: waypointDict["description"] as? String,
                        audioLandmark: waypointDict["audioLandmark"] as? String
                    )
                )
            }
        }
        
        let indoorMap = IndoorMap(
            name: mapName,
            description: jsonMap.jsonData["description"] as? String,
            rooms: rooms,
            beacons: beacons,
            doorways: doorways,
            waypoints: waypoints
        )
        
        print("✅ Parsed IndoorMap: \(mapName)")
        print("   Rooms: \(rooms.count)")
        print("   Beacons: \(beacons.count)")
        print("   Doorways: \(doorways.count)")
        print("   Waypoints: \(waypoints.count)")
        
        return indoorMap
    }
}

// MARK: - Navigation Status View - UNCHANGED
struct NavigationMapStatusView: View {
    @ObservedObject private var navigationHelper = NavigationIntegrationHelper.shared
    
    var body: some View {
        Group {
            if let map = navigationHelper.selectedMapForNavigation {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "location.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Navigation Map")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(map.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            if map.hasARWorldMap {
                                Label("ARWorldMap Available", systemImage: "cube.fill")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                        Spacer()
                    }
                    
                    if let beacons = map.jsonData["beacons"] as? [Any],
                       let doorways = map.jsonData["doorways"] as? [Any] {
                        HStack(spacing: 16) {
                            Label("\(beacons.count)", systemImage: "flag.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Label("\(doorways.count)", systemImage: "door.left.hand.open")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)
            } else {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "map.circle")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No Navigation Map Selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Select a map to enable navigation")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
        }
    }
}
