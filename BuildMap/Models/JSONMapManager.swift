//
//  JSONMap.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/12/25.
//


import SwiftUI
import Foundation
import ARKit

// MARK: - Data Models
struct JSONMap: Identifiable, Codable {
    let id: UUID
    let name: String
    let createdDate: Date
    let jsonData: [String: Any]
    let description: String
    let arWorldMapFileName: String? // NEW: Track ARWorldMap file
    
    enum CodingKeys: String, CodingKey {
        case id, name, createdDate, description, jsonDataString, arWorldMapFileName
    }
    
    init(name: String, jsonData: [String: Any], description: String = "", arWorldMapFileName: String? = nil) {
        self.id = UUID()
        self.name = name
        self.jsonData = jsonData
        self.description = description
        self.createdDate = Date()
        self.arWorldMapFileName = arWorldMapFileName
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        description = try container.decode(String.self, forKey: .description)
        arWorldMapFileName = try container.decodeIfPresent(String.self, forKey: .arWorldMapFileName)
        
        // Decode jsonData from JSON string
        let jsonDataString = try container.decode(String.self, forKey: .jsonDataString)
        if let data = jsonDataString.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonData = decoded
        } else {
            jsonData = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(arWorldMapFileName, forKey: .arWorldMapFileName)
        
        // Encode jsonData as JSON string
        do {
            let jsonDataEncoded = try JSONSerialization.data(withJSONObject: jsonData)
            let jsonDataString = String(data: jsonDataEncoded, encoding: .utf8) ?? "{}"
            try container.encode(jsonDataString, forKey: .jsonDataString)
        } catch {
            try container.encode("{}", forKey: .jsonDataString)
        }
    }
    
    // NEW: Check if map has ARWorldMap data
    var hasARWorldMap: Bool {
        return arWorldMapFileName != nil
    }
}

// JSONMap.swift — for persistent saving
extension JSONMap {
    /// Create a new JSONMap by copying `base` and selectively overriding fields.
    init(copyOf base: JSONMap,
         name: String? = nil,
         jsonData: [String: Any]? = nil,
         description: String? = nil,
         arWorldMapFileName: String?? = nil) {
        self.id = base.id
        self.name = name ?? base.name
        self.createdDate = base.createdDate
        self.jsonData = jsonData ?? base.jsonData
        self.description = description ?? base.description
        self.arWorldMapFileName = arWorldMapFileName ?? base.arWorldMapFileName
    }
}


// MARK: - ARWorldMap Error Types
enum ARWorldMapError: Error, LocalizedError {
    case captureFailed(String)
    case saveFailed(String)
    case loadFailed(String)
    case fileNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            return "Failed to capture ARWorldMap: \(message)"
        case .saveFailed(let message):
            return "Failed to save ARWorldMap: \(message)"
        case .loadFailed(let message):
            return "Failed to load ARWorldMap: \(message)"
        case .fileNotFound:
            return "ARWorldMap file not found"
        case .invalidData:
            return "Invalid ARWorldMap data"
        }
    }
}

// MARK: - Simple JSON Map Manager
class SimpleJSONMapManager: ObservableObject {
    static let shared = SimpleJSONMapManager()
    
    @Published var maps: [JSONMap] = []
    @Published var currentBeacons: [[String: Any]] = []
    @Published var currentDoorways: [[String: Any]] = []
    @Published var selectedMapIdForNavigation: UUID? = nil
    
    private let userDefaults = UserDefaults.standard
    private let mapsKey = "saved_json_maps"
    private let selectedMapKey = "selected_map_for_navigation"
    
    // NEW: ARWorldMap file management
    private let arWorldMapsDirectory = "ARWorldMaps"
    
    private init() {
        createARWorldMapsDirectory()
        loadMaps()
        loadSelectedMapId()
        setupNotifications()
        print("🗺️ SimpleJSONMapManager initialized with \(maps.count) maps")
    }
    
    // MARK: - ARWorldMap Directory Management
    
    /// Creates the directory for storing ARWorldMap files
    private func createARWorldMapsDirectory() {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Failed to get documents directory")
            return
        }
        
        let arWorldMapsPath = documentsPath.appendingPathComponent(arWorldMapsDirectory)
        
        if !FileManager.default.fileExists(atPath: arWorldMapsPath.path) {
            do {
                try FileManager.default.createDirectory(at: arWorldMapsPath, withIntermediateDirectories: true)
                print("✅ Created ARWorldMaps directory at: \(arWorldMapsPath.path)")
            } catch {
                print("❌ Failed to create ARWorldMaps directory: \(error)")
            }
        }
    }
    
    /// Gets the full URL for an ARWorldMap file
    private func getARWorldMapURL(fileName: String) -> URL? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsPath.appendingPathComponent(arWorldMapsDirectory).appendingPathComponent(fileName)
    }
    
    // MARK: - ARWorldMap Capture and Save
    
    /// Captures ARWorldMap from the current AR session
    /// - Parameters:
    ///   - arSession: The ARSession to capture from
    ///   - completion: Completion handler with Result containing ARWorldMap or Error
    func captureWorldMap(from arSession: ARSession, completion: @escaping (Result<ARWorldMap, ARWorldMapError>) -> Void) {
        print("📸 Starting ARWorldMap capture...")
        
        arSession.getCurrentWorldMap { worldMap, error in
            if let error = error {
                print("❌ ARWorldMap capture failed: \(error.localizedDescription)")
                completion(.failure(.captureFailed(error.localizedDescription)))
                return
            }
            
            guard let worldMap = worldMap else {
                print("❌ ARWorldMap capture returned nil")
                completion(.failure(.captureFailed("World map is nil")))
                return
            }
            
            print("✅ ARWorldMap captured successfully")
            print("   - Anchors: \(worldMap.anchors.count)")
            print("   - Raw feature points: \(worldMap.rawFeaturePoints.points.count)")
            
            completion(.success(worldMap))
        }
    }
    
    /// Saves ARWorldMap to disk and returns the file URL
    /// - Parameters:
    ///   - worldMap: The ARWorldMap to save
    ///   - fileName: Optional custom filename (generated if nil)
    ///   - completion: Completion handler with Result containing file URL or Error
    func saveARWorldMapToFile(worldMap: ARWorldMap, fileName: String? = nil, completion: @escaping (Result<URL, ARWorldMapError>) -> Void) {
        let finalFileName = fileName ?? "worldmap_\(UUID().uuidString).arworldmap"
        
        guard let fileURL = getARWorldMapURL(fileName: finalFileName) else {
            completion(.failure(.saveFailed("Failed to generate file URL")))
            return
        }
        
        print("💾 Saving ARWorldMap to: \(fileURL.lastPathComponent)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: worldMap, requiringSecureCoding: true)
                try data.write(to: fileURL)
                
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0
                print("✅ ARWorldMap saved successfully")
                print("   - File: \(finalFileName)")
                print("   - Size: \(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))")
                
                DispatchQueue.main.async {
                    completion(.success(fileURL))
                }
            } catch {
                print("❌ Failed to save ARWorldMap: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(.saveFailed(error.localizedDescription)))
                }
            }
        }
    }
    
    /// Loads ARWorldMap from disk
    /// - Parameters:
    ///   - fileName: The filename of the ARWorldMap to load
    ///   - completion: Completion handler with Result containing ARWorldMap or Error
    func loadARWorldMap(fileName: String, completion: @escaping (Result<ARWorldMap, ARWorldMapError>) -> Void) {
        guard let fileURL = getARWorldMapURL(fileName: fileName) else {
            completion(.failure(.loadFailed("Failed to generate file URL")))
            return
        }
        
        print("📂 Loading ARWorldMap from: \(fileName)")
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("❌ ARWorldMap file not found: \(fileName)")
                DispatchQueue.main.async {
                    completion(.failure(.fileNotFound))
                }
                return
            }
            
            do {
                let data = try Data(contentsOf: fileURL)
                
                guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                    print("❌ Failed to unarchive ARWorldMap")
                    DispatchQueue.main.async {
                        completion(.failure(.invalidData))
                    }
                    return
                }
                
                print("✅ ARWorldMap loaded successfully")
                print("   - Anchors: \(worldMap.anchors.count)")
                print("   - Raw feature points: \(worldMap.rawFeaturePoints.points.count)")
                
                DispatchQueue.main.async {
                    completion(.success(worldMap))
                }
            } catch {
                print("❌ Failed to load ARWorldMap: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(.loadFailed(error.localizedDescription)))
                }
            }
        }
    }
    
    /// Loads ARWorldMap for a specific map
    /// - Parameters:
    ///   - map: The JSONMap to load ARWorldMap for
    ///   - completion: Completion handler with Result containing ARWorldMap or Error
    func loadARWorldMap(for map: JSONMap, completion: @escaping (Result<ARWorldMap, ARWorldMapError>) -> Void) {
        guard let fileName = map.arWorldMapFileName else {
            completion(.failure(.fileNotFound))
            return
        }
        loadARWorldMap(fileName: fileName, completion: completion)
    }
    
    /// Deletes ARWorldMap file for a map
    private func deleteARWorldMapFile(fileName: String) {
        guard let fileURL = getARWorldMapURL(fileName: fileName) else {
            print("⚠️ Failed to get URL for ARWorldMap file: \(fileName)")
            return
        }
        
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
                print("🗑️ Deleted ARWorldMap file: \(fileName)")
            }
        } catch {
            print("❌ Failed to delete ARWorldMap file: \(error)")
        }
    }
    
    // Saving the modified json to persist
    @discardableResult
    func updateJSON(for mapId: UUID, with newJSON: [String: Any]) -> Bool {
        guard let index = maps.firstIndex(where: { $0.id == mapId }) else {
            print("⚠️ Map not found for update")
            return false
        }

        let old = maps[index]
        let updated = JSONMap(copyOf: old, jsonData: newJSON)  // ✅ preserve id/createdDate/etc.
        maps[index] = updated

        saveMaps() // 💾 writes updated array back to UserDefaults
        print("✅ Updated JSON for \(updated.name)")
        return true
    }


    
    // MARK: - Notification Handlers
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleBeaconAdded),
            name: NSNotification.Name("BeaconAdded"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDoorwayAdded),
            name: NSNotification.Name("DoorwayAdded"),
            object: nil
        )
    }
    
    @objc private func handleBeaconAdded(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let name = userInfo["name"] as? String,
              let coordinates = userInfo["coordinates"] as? [String: Double] else {
            return
        }
        
        let beacon = [
            "id": UUID().uuidString,
            "name": name,
            "coordinates": coordinates,
            "category": userInfo["category"] as? String ?? "general",
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        currentBeacons.append(beacon)
        print("📍 BEACON ADDED: \(name) at (\(coordinates["x"] ?? 0), \(coordinates["y"] ?? 0), \(coordinates["z"] ?? 0))")
    }
    
    @objc private func handleDoorwayAdded(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let name = userInfo["name"] as? String,
              let coordinates = userInfo["coordinates"] as? [String: Double] else {
            return
        }
        
        let doorway = [
            "id": UUID().uuidString,
            "name": name,
            "coordinates": coordinates,
            "startPoint": userInfo["startPoint"] as? [String: Double] ?? [:],
            "endPoint": userInfo["endPoint"] as? [String: Double] ?? [:],
            "doorwayType": userInfo["doorwayType"] as? String ?? "standard",
            "timestamp": Date().timeIntervalSince1970
        ] as [String: Any]
        
        currentDoorways.append(doorway)
        print("🚪 DOORWAY ADDED: \(name) at (\(coordinates["x"] ?? 0), \(coordinates["y"] ?? 0), \(coordinates["z"] ?? 0))")
    }
    
    // MARK: - Map Management
    
    func addMap(_ map: JSONMap) {
        maps.append(map)
        saveMaps()
        print("📝 Added map: \(map.name)")
        if map.hasARWorldMap {
            print("   ✅ Map includes ARWorldMap data")
        }
    }
    
    func deleteMap(at index: Int) {
        guard index < maps.count else { return }
        let map = maps[index]
        let mapId = map.id
        
        // Delete associated ARWorldMap file if it exists
        if let fileName = map.arWorldMapFileName {
            deleteARWorldMapFile(fileName: fileName)
        }
        
        // If deleting the selected map, clear selection
        if selectedMapIdForNavigation == mapId {
            selectMapForNavigation(nil)
        }
        
        maps.remove(at: index)
        saveMaps()
        print("🗑️ Deleted map: \(map.name)")
    }
    
    // MARK: - Map Selection for Navigation
    
    func selectMapForNavigation(_ mapId: UUID?) {
        selectedMapIdForNavigation = mapId
        saveSelectedMapId()
        
        if let mapId = mapId {
            if let map = maps.first(where: { $0.id == mapId }) {
                print("✅ Selected map for navigation: \(map.name)")
                print("   Has ARWorldMap: \(map.hasARWorldMap)")
                
                // Post notification for navigation system
                NotificationCenter.default.post(
                    name: .mapSelectedForNavigation,
                    object: nil,
                    userInfo: [
                        "mapId": mapId,
                        "mapName": map.name,
                        "hasARWorldMap": map.hasARWorldMap,
                        "arWorldMapFileName": map.arWorldMapFileName as Any
                    ]
                )
            }
        } else {
            print("❌ Cleared navigation map selection")
            NotificationCenter.default.post(
                name: .mapSelectedForNavigation,
                object: nil,
                userInfo: nil
            )
        }
    }
    
    func getSelectedMapForNavigation() -> JSONMap? {
        guard let selectedId = selectedMapIdForNavigation else { return nil }
        return maps.first(where: { $0.id == selectedId })
    }
    
    private func saveSelectedMapId() {
        if let selectedId = selectedMapIdForNavigation {
            userDefaults.set(selectedId.uuidString, forKey: selectedMapKey)
            print("💾 Saved selected map ID: \(selectedId)")
        } else {
            userDefaults.removeObject(forKey: selectedMapKey)
            print("💾 Cleared selected map ID")
        }
    }
    
    private func loadSelectedMapId() {
        if let uuidString = userDefaults.string(forKey: selectedMapKey),
           let uuid = UUID(uuidString: uuidString) {
            selectedMapIdForNavigation = uuid
            print("📂 Loaded selected map ID: \(uuid)")
        } else {
            print("📂 No selected map ID found")
        }
    }
    
    // MARK: - Save Current Session (UPDATED with ARWorldMap support)

    /// Saves the current mapping session
    /// - Parameters:
    ///   - name: Optional name for the map (auto-generated if nil)
    ///   - arSession: Optional ARSession to capture ARWorldMap from
    ///   - completion: Called when save completes with success status
    func saveCurrentSession(name: String? = nil, arSession: ARSession? = nil, completion: ((Bool) -> Void)? = nil) {
        guard !currentBeacons.isEmpty || !currentDoorways.isEmpty else {
            print("⚠️ No current session data to save")
            completion?(false)
            return
        }
        
        let mapName = name ?? "Map \(Date().formatted(.dateTime.day().month().year().hour().minute()))"
        let mapData = [
            "mapName": mapName,
            "beacons": currentBeacons,
            "doorways": currentDoorways,
            "metadata": [
                "createdDate": Date().timeIntervalSince1970,
                "version": "1.0",
                "hasARWorldMap": arSession != nil
            ]
        ] as [String: Any]
        
        // If ARSession is provided, capture ARWorldMap and save with it
        if let arSession = arSession {
            print("📸 Capturing ARWorldMap for map: \(mapName)")
            
            captureWorldMap(from: arSession) { [weak self] captureResult in
                guard let self = self else {
                    completion?(false)
                    return
                }
                
                switch captureResult {
                case .success(let worldMap):
                    print("✅ ARWorldMap captured successfully")
                    
                    // Save ARWorldMap to file first
                    let fileName = "worldmap_\(UUID().uuidString).arworldmap"
                    self.saveARWorldMapToFile(worldMap: worldMap, fileName: fileName) { [weak self] saveResult in
                        guard let self = self else {
                            completion?(false)
                            return
                        }
                        
                        switch saveResult {
                        case .success(let fileURL):
                            print("✅ ARWorldMap file saved: \(fileURL.lastPathComponent)")
                            
                            // Create JSONMap with ARWorldMap reference
                            let newMap = JSONMap(
                                name: mapName,
                                jsonData: mapData,
                                description: "Saved with ARWorldMap on \(Date().formatted(.dateTime))",
                                arWorldMapFileName: fileName
                            )
                            
                            DispatchQueue.main.async {
                                self.addMap(newMap)
                                self.resetCurrentSession()
                                completion?(true)
                            }
                            
                        case .failure(let error):
                            print("❌ Failed to save ARWorldMap file: \(error)")
                            // Fall back to saving without ARWorldMap
                            DispatchQueue.main.async {
                                self.saveWithoutARWorldMap(mapName: mapName, mapData: mapData)
                                completion?(false)
                            }
                        }
                    }
                    
                case .failure(let error):
                    print("❌ Failed to capture ARWorldMap: \(error)")
                    // Fall back to saving without ARWorldMap
                    DispatchQueue.main.async {
                        self.saveWithoutARWorldMap(mapName: mapName, mapData: mapData)
                        completion?(false)
                    }
                }
            }
        } else {
            // No ARSession provided, save without ARWorldMap (old behavior)
            print("⚠️ Saving map WITHOUT ARWorldMap (no ARSession provided)")
            saveWithoutARWorldMap(mapName: mapName, mapData: mapData)
            completion?(true)
        }
    }

    /// Helper method to save without ARWorldMap (fallback/old behavior)
    private func saveWithoutARWorldMap(mapName: String, mapData: [String: Any]) {
        let newMap = JSONMap(
            name: mapName,
            jsonData: mapData,
            description: "Saved from mapping session"
        )
        
        addMap(newMap)
        resetCurrentSession()
        print("💾 Saved current session as map (without ARWorldMap): \(mapName)")
    }

    func resetCurrentSession() {
        currentBeacons.removeAll()
        currentDoorways.removeAll()
        print("🔄 Reset current session")
    }
    
    // MARK: - Export and Share
    
    func getCurrentSessionAsJSON() -> String {
        let sessionData = [
            "mapName": "Current Session",
            "beacons": currentBeacons,
            "doorways": currentDoorways,
            "metadata": [
                "beaconCount": currentBeacons.count,
                "doorwayCount": currentDoorways.count,
                "timestamp": Date().timeIntervalSince1970
            ]
        ] as [String: Any]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: sessionData, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            return "Error: Unable to serialize session data"
        }
    }
    
    func exportMapAsJSON(_ map: JSONMap) -> String {
        print("📤 Exporting map: \(map.name)")
        print("   JSON data keys: \(map.jsonData.keys.joined(separator: ", "))")
        
        var exportData = map.jsonData
        exportData["hasARWorldMap"] = map.hasARWorldMap
        if let fileName = map.arWorldMapFileName {
            exportData["arWorldMapFileName"] = fileName
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? ""
            print("   Export successful, length: \(jsonString.count)")
            return jsonString
        } catch {
            print("   Export failed: \(error)")
            return "Error: Unable to serialize JSON - \(error.localizedDescription)"
        }
    }
    
    func shareMap(_ map: JSONMap, completion: @escaping (URL?) -> Void) {
        let jsonString = exportMapAsJSON(map)
        let fileName = "\(map.name.replacingOccurrences(of: " ", with: "_")).json"
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion(nil)
            return
        }
        
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
            completion(fileURL)
        } catch {
            completion(nil)
        }
    }
    
    func shareCurrentSession(completion: @escaping (URL?) -> Void) {
        let jsonString = getCurrentSessionAsJSON()
        let fileName = "Current_Session_\(Date().formatted(.dateTime.day().month().hour().minute())).json"
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion(nil)
            return
        }
        
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
            completion(fileURL)
        } catch {
            completion(nil)
        }
    }
    
    // MARK: - Persistence
    
    private func saveMaps() {
        do {
            let encoded = try JSONEncoder().encode(maps)
            userDefaults.set(encoded, forKey: mapsKey)
            print("💾 Successfully saved \(maps.count) maps to UserDefaults")
            print("   Saved map names: \(maps.map { $0.name }.joined(separator: ", "))")
        } catch {
            print("❌ Failed to save maps: \(error)")
        }
    }
    
    private func loadMaps() {
        guard let data = userDefaults.data(forKey: mapsKey) else {
            print("🔭 No saved maps data found in UserDefaults")
            return
        }
        
        print("📦 Found \(data.count) bytes of maps data in UserDefaults")
        
        do {
            maps = try JSONDecoder().decode([JSONMap].self, from: data)
            print("📚 Successfully loaded \(maps.count) maps from UserDefaults")
            
            // Debug: Print loaded map details
            for (index, map) in maps.enumerated() {
                print("   Map \(index + 1): \(map.name)")
                print("     Created: \(map.createdDate)")
                print("     Has ARWorldMap: \(map.hasARWorldMap)")
                if let fileName = map.arWorldMapFileName {
                    print("     ARWorldMap file: \(fileName)")
                }
                print("     JSON keys: \(map.jsonData.keys.joined(separator: ", "))")
            }
        } catch {
            print("❌ Failed to load maps: \(error)")
            print("   Error details: \(error.localizedDescription)")
            maps = []
        }
    }
    
    func clearAllMaps() {
        // Delete all ARWorldMap files
        for map in maps {
            if let fileName = map.arWorldMapFileName {
                deleteARWorldMapFile(fileName: fileName)
            }
        }
        
        maps.removeAll()
        selectedMapIdForNavigation = nil
        userDefaults.removeObject(forKey: mapsKey)
        userDefaults.removeObject(forKey: selectedMapKey)
        print("🗑️ Cleared all maps and ARWorldMap files")
    }
    
    func reloadMaps() {
        loadMaps()
        loadSelectedMapId()
    }
    
    // MARK: - Debug Helpers
    
    func getARWorldMapStorageInfo() -> [String: Any] {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return ["error": "Failed to get documents directory"]
        }
        
        let arWorldMapsPath = documentsPath.appendingPathComponent(arWorldMapsDirectory)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: arWorldMapsPath, includingPropertiesForKeys: [.fileSizeKey])
            
            var totalSize: Int64 = 0
            var fileInfos: [[String: Any]] = []
            
            for file in files {
                if let fileSize = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                    fileInfos.append([
                        "name": file.lastPathComponent,
                        "size": ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                    ])
                }
            }
            
            return [
                "directory": arWorldMapsPath.path,
                "fileCount": files.count,
                "totalSize": ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file),
                "files": fileInfos
            ]
        } catch {
            return ["error": error.localizedDescription]
        }
    }
}

// MARK: - Simple Session JSON View
struct SimpleSessionJSONView: View {
    @ObservedObject private var mapManager = SimpleJSONMapManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current Session Data")
                            .font(.headline)
                        
                        HStack {
                            Text("Beacons: \(mapManager.currentBeacons.count)")
                                .font(.caption)
                                .foregroundColor(.green)
                            
                            Spacer()
                            
                            Text("Doorways: \(mapManager.currentDoorways.count)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("JSON Content")
                            .font(.headline)
                        
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(mapManager.getCurrentSessionAsJSON())
                                .font(.system(.caption, design: .monospaced))
                                .padding()
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(8)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        Button("Copy JSON") {
                            UIPasteboard.general.string = mapManager.getCurrentSessionAsJSON()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        
                        Button("Save as Map") {
                            // NOTE: Saves without ARWorldMap
                            mapManager.saveCurrentSession()
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding()
            }
            .navigationTitle("Current Session")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


// MARK: - Info Row Helper
private struct InfoRow: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - Simple JSON Map Add View
struct SimpleJSONMapAddView: View {
    @ObservedObject private var mapManager = SimpleJSONMapManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var jsonText = """
{
  "mapName": "Sample Map",
  "beacons": [],
  "doorways": []
}
"""
    @State private var showingError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Map Details") {
                    TextField("Map Name", text: $name)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3)
                }
                
                Section("JSON Content") {
                    TextEditor(text: $jsonText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                }
                
                Section("Quick Actions") {
                    if !mapManager.currentBeacons.isEmpty || !mapManager.currentDoorways.isEmpty {
                        Button("Use Current Session Data") {
                            jsonText = mapManager.getCurrentSessionAsJSON()
                            if name.isEmpty {
                                name = "Map from Session"
                            }
                        }
                        .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Add New Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveMap()
                    }
                    .disabled(name.isEmpty || jsonText.isEmpty)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func saveMap() {
        guard let jsonData = try? JSONSerialization.jsonObject(with: jsonText.data(using: .utf8) ?? Data()) as? [String: Any] else {
            errorMessage = "Invalid JSON format"
            showingError = true
            return
        }
        
        let newMap = JSONMap(name: name, jsonData: jsonData, description: description)
        mapManager.addMap(newMap)
        dismiss()
    }
}

// MARK: - Simple JSON Map Share Sheet
struct SimpleJSONMapShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
