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

// MARK: - Notification Extension
extension Notification.Name {
    static let mapSelectedForNavigation = Notification.Name("MapSelectedForNavigation")
}

// MARK: - Simple JSON Maps List View
struct SimpleJSONMapsListView: View {
    @ObservedObject private var mapManager = SimpleJSONMapManager.shared
    @State private var showingAddMap = false
    @State private var showingSessionJSON = false
    @State private var showingSessionShare = false
    @State private var sessionShareURL: URL?
    
    var body: some View {
        List {
            // Selected Map for Navigation Section
            Section {
                if let selectedMap = mapManager.getSelectedMapForNavigation() {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Active Navigation Map")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(selectedMap.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                // NEW: Show ARWorldMap status
                                if selectedMap.hasARWorldMap {
                                    Label("Includes ARWorldMap", systemImage: "cube.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Spacer()
                        }
                        
                        if let beacons = selectedMap.jsonData["beacons"] as? [Any],
                           let doorways = selectedMap.jsonData["doorways"] as? [Any] {
                            HStack(spacing: 16) {
                                Label("\(beacons.count)", systemImage: "flag.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                
                                Label("\(doorways.count)", systemImage: "door.left.hand.open")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Button(role: .destructive) {
                            mapManager.selectMapForNavigation(nil)
                        } label: {
                            Text("Clear Selection")
                                .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .center, spacing: 8) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        
                        Text("No Map Selected for Navigation")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Select a map from the list below to use it for navigation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } header: {
                Text("Navigation Map")
            }
            
            // Current Session Section
            if !mapManager.currentBeacons.isEmpty || !mapManager.currentDoorways.isEmpty {
                Section("Current Session") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Active Mapping Session")
                                .font(.headline)
                            Text("Beacons: \(mapManager.currentBeacons.count), Doorways: \(mapManager.currentDoorways.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(.green)
                    }
                    
                    HStack {
                        Button("View JSON") {
                            showingSessionJSON = true
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Share JSON") {
                            shareCurrentSession()
                        }
                        .buttonStyle(.bordered)
                        
                        Spacer()
                        
                        Button("Save as Map") {
                            // NOTE: This saves without ARWorldMap
                            // You need to pass ARSession from your mapping view
                            mapManager.saveCurrentSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            
            // Debug Section
            Section("Debug Info") {
                HStack {
                    Text("Saved Maps:")
                    Spacer()
                    Text("\(mapManager.maps.count)")
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Maps with ARWorldMap:")
                    Spacer()
                    Text("\(mapManager.maps.filter { $0.hasARWorldMap }.count)")
                        .foregroundColor(.blue)
                }
                
                HStack {
                    Text("Session Beacons:")
                    Spacer()
                    Text("\(mapManager.currentBeacons.count)")
                        .foregroundColor(.green)
                }
                
                HStack {
                    Text("Session Doorways:")
                    Spacer()
                    Text("\(mapManager.currentDoorways.count)")
                        .foregroundColor(.orange)
                }
                
                HStack {
                    Text("Selected Map:")
                    Spacer()
                    Text(mapManager.selectedMapIdForNavigation != nil ? "Yes" : "None")
                        .foregroundColor(mapManager.selectedMapIdForNavigation != nil ? .green : .gray)
                }
                
                Button("Reset Session") {
                    mapManager.resetCurrentSession()
                }
                .foregroundColor(.orange)
                
                // NEW: ARWorldMap storage info
                Button("ARWorldMap Storage Info") {
                    let info = mapManager.getARWorldMapStorageInfo()
                    print("📊 ARWorldMap Storage Info:")
                    print(info)
                }
                .foregroundColor(.blue)
            }
            
            // Saved Maps Section
            if mapManager.maps.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "map")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                        Text("No Saved Maps")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Use 'Save as Map' to save your current session")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            } else {
                Section("Saved Maps") {
                    ForEach(mapManager.maps) { map in
                        NavigationLink(destination: SimpleJSONMapDetailView(map: map)) {
                            HStack(spacing: 12) {
                                // Selection indicator
                                if mapManager.selectedMapIdForNavigation == map.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.title3)
                                } else {
                                    Image(systemName: "circle")
                                        .foregroundColor(.gray)
                                        .font(.title3)
                                }
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        // NEW: Different icon for maps with ARWorldMap
                                        Image(systemName: map.hasARWorldMap ? "cube.fill" : "doc.text")
                                            .foregroundColor(map.hasARWorldMap ? .blue : .gray)
                                        
                                        VStack(alignment: .leading) {
                                            Text(map.name)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text("Created: \(map.createdDate.formatted(.dateTime.day().month().year()))")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            if !map.description.isEmpty {
                                                Text(map.description)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                            
                                            // Show beacon and doorway counts
                                            HStack {
                                                if let beacons = map.jsonData["beacons"] as? [Any] {
                                                    Text("Beacons: \(beacons.count)")
                                                        .font(.caption2)
                                                        .foregroundColor(.green)
                                                }
                                                
                                                if let doorways = map.jsonData["doorways"] as? [Any] {
                                                    Text("Doorways: \(doorways.count)")
                                                        .font(.caption2)
                                                        .foregroundColor(.orange)
                                                }
                                                
                                                // NEW: ARWorldMap indicator
                                                if map.hasARWorldMap {
                                                    Image(systemName: "cube.fill")
                                                        .font(.caption2)
                                                        .foregroundColor(.blue)
                                                }
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // Toggle selection
                                if mapManager.selectedMapIdForNavigation == map.id {
                                    mapManager.selectMapForNavigation(nil)
                                } else {
                                    mapManager.selectMapForNavigation(map.id)
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteMap)
                }
            }
        }
        .navigationTitle("JSON Maps")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Add") {
                    showingAddMap = true
                }
            }
        }
        .sheet(isPresented: $showingAddMap) {
            SimpleJSONMapAddView()
        }
        .sheet(isPresented: $showingSessionJSON) {
            SimpleSessionJSONView()
        }
        .sheet(isPresented: $showingSessionShare) {
            if let url = sessionShareURL {
                SimpleJSONMapShareSheet(activityItems: [url])
            }
        }
    }
    
    private func deleteMap(at offsets: IndexSet) {
        for index in offsets {
            mapManager.deleteMap(at: index)
        }
    }
    
    private func shareCurrentSession() {
        mapManager.shareCurrentSession { url in
            sessionShareURL = url
            showingSessionShare = url != nil
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

// MARK: - Simple JSON Map Detail View
struct SimpleJSONMapDetailView: View {
    let map: JSONMap
    @ObservedObject private var mapManager = SimpleJSONMapManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var jsonContent = ""
    @State private var isLoading = true
    @State private var showingDeleteConfirmation = false
    
    var isSelectedForNavigation: Bool {
        mapManager.selectedMapIdForNavigation == map.id
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Navigation Status
                    if isSelectedForNavigation {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Currently Selected for Navigation")
                                .font(.headline)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // NEW: ARWorldMap Status
                    if map.hasARWorldMap {
                        HStack {
                            Image(systemName: "cube.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("ARWorldMap Available")
                                    .font(.headline)
                                    .foregroundColor(.blue)
                                if let fileName = map.arWorldMapFileName {
                                    Text(fileName)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Map Information
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Map Information")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Name:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                Text(map.name)
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("Created:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                Text(map.createdDate.formatted(.dateTime.day().month().year()))
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("Description:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                Text(map.description.isEmpty ? "No description" : map.description)
                                    .font(.caption)
                            }
                            
                            HStack {
                                Text("Has ARWorldMap:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                Text(map.hasARWorldMap ? "Yes" : "No")
                                    .font(.caption)
                                    .foregroundColor(map.hasARWorldMap ? .blue : .gray)
                            }
                            
                            HStack {
                                Text("Data Keys:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 100, alignment: .leading)
                                Text(map.jsonData.keys.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            if let beacons = map.jsonData["beacons"] as? [Any] {
                                HStack {
                                    Text("Beacons:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    Text("\(beacons.count)")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if let doorways = map.jsonData["doorways"] as? [Any] {
                                HStack {
                                    Text("Doorways:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 100, alignment: .leading)
                                    Text("\(doorways.count)")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                    
                    // JSON Content
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("JSON Content")
                                .font(.headline)
                            Spacer()
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Text("\(jsonContent.count) characters")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if isLoading {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 200)
                                .overlay(
                                    Text("Loading JSON content...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                )
                                .cornerRadius(8)
                        } else if jsonContent.isEmpty {
                            Rectangle()
                                .fill(Color.red.opacity(0.1))
                                .frame(height: 200)
                                .overlay(
                                    VStack {
                                        Text("Failed to load JSON content")
                                            .font(.caption)
                                            .foregroundColor(.red)
                                        Button("Retry") {
                                            loadJSONContent()
                                        }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                    }
                                )
                                .cornerRadius(8)
                        } else {
                            ScrollView(.horizontal, showsIndicators: true) {
                                Text(jsonContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .padding()
                                    .background(Color.black.opacity(0.05))
                                    .cornerRadius(8)
                                    .textSelection(.enabled)
                            }
                            .frame(minHeight: 200)
                        }
                    }
                    
                    // Actions
                    VStack(spacing: 12) {
                        // Navigation Selection Button
                        if isSelectedForNavigation {
                            Button {
                                mapManager.selectMapForNavigation(nil)
                            } label: {
                                Label("Remove from Navigation", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        } else {
                            Button {
                                mapManager.selectMapForNavigation(map.id)
                            } label: {
                                Label("Use for Navigation", systemImage: "location.circle.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                        }
                        
                        Button("Share Map") {
                            shareMap()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(jsonContent.isEmpty)
                        
                        Button("Copy JSON") {
                            UIPasteboard.general.string = jsonContent
                            print("📋 Copied JSON to clipboard (\(jsonContent.count) characters)")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .disabled(jsonContent.isEmpty)
                        
                        Button("Delete Map") {
                            showingDeleteConfirmation = true
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.red)
                        
                        // Debug button
                        Button("Debug Map Data") {
                            print("🛠 DEBUG MAP DATA:")
                            print("   Map ID: \(map.id)")
                            print("   Map Name: \(map.name)")
                            print("   Created: \(map.createdDate)")
                            print("   Description: \(map.description)")
                            print("   Has ARWorldMap: \(map.hasARWorldMap)")
                            if let fileName = map.arWorldMapFileName {
                                print("   ARWorldMap file: \(fileName)")
                            }
                            print("   JSON Data Keys: \(map.jsonData.keys)")
                            print("   JSON Data: \(map.jsonData)")
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .foregroundColor(.orange)
                    }
                }
                .padding()
            }
            .navigationTitle(map.name)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                SimpleJSONMapShareSheet(activityItems: [url])
            }
        }
        .alert("Delete Map", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteMap()
            }
        } message: {
            Text("Are you sure you want to delete '\(map.name)'? This action cannot be undone.")
        }
        .onAppear {
            print("📖 SimpleJSONMapDetailView appeared for: \(map.name)")
            print("   Map JSON keys: \(map.jsonData.keys.joined(separator: ", "))")
            loadJSONContent()
        }
    }
    
    private func loadJSONContent() {
        print("📖 Loading JSON content for map: \(map.name)")
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: map.jsonData, options: .prettyPrinted)
                jsonContent = String(data: jsonData, encoding: .utf8) ?? ""
                print("   ✅ Loaded JSON content length: \(jsonContent.count)")
                if jsonContent.isEmpty {
                    print("   ⚠️ JSON content is empty!")
                }
            } catch {
                print("   ❌ Failed to serialize JSON: \(error)")
                jsonContent = "Error serializing JSON: \(error.localizedDescription)"
            }
            isLoading = false
        }
    }
    
    private func shareMap() {
        print("📤 Sharing map: \(map.name)")
        
        let jsonString = jsonContent.isEmpty ? SimpleJSONMapManager.shared.exportMapAsJSON(map) : jsonContent
        let fileName = "\(map.name.replacingOccurrences(of: " ", with: "_")).json"
        
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("❌ Failed to get documents directory")
            return
        }
        
        let fileURL = documentsPath.appendingPathComponent(fileName)
        
        do {
            try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
            shareURL = fileURL
            showingShareSheet = true
            print("✅ Share file created: \(fileURL)")
        } catch {
            print("❌ Failed to create share file: \(error)")
        }
    }
    
    private func deleteMap() {
        print("🗑️ Deleting map: \(map.name)")
        
        if let index = mapManager.maps.firstIndex(where: { $0.id == map.id }) {
            mapManager.deleteMap(at: index)
            print("✅ Map deleted successfully")
            dismiss()
        } else {
            print("❌ Failed to find map to delete")
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
