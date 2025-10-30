//
//  MapManagerViewModel.swift
//  Mapping v2
//
//  Created by Indraneel Rakshit on 9/20/25.
//


import Foundation
import Combine

// MARK: - Map Manager View Model
@MainActor
class MapManagerViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var savedMaps: [MapInfo] = []
    @Published var selectedMapId: UUID?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let documentsDirectory: URL
    private let mapsDirectory: URL
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        mapsDirectory = documentsDirectory.appendingPathComponent("Maps", isDirectory: true)
        
        createMapsDirectoryIfNeeded()
        loadSavedMaps()
        loadSelectedMapId()
    }
    
    // MARK: - Directory Management
    private func createMapsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: mapsDirectory.path) {
            try? fileManager.createDirectory(at: mapsDirectory, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Map Loading
    func loadSavedMaps() {
        isLoading = true
        
        Task {
            do {
                let mapFiles = try fileManager.contentsOfDirectory(at: mapsDirectory,
                                                                  includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
                    .filter { $0.pathExtension.lowercased() == "json" }
                
                var mapInfos: [MapInfo] = []
                
                for file in mapFiles {
                    if let mapInfo = await loadMapInfo(from: file) {
                        mapInfos.append(mapInfo)
                    }
                }
                
                // Sort by creation date (newest first)
                mapInfos.sort { $0.createdAt > $1.createdAt }
                
                await MainActor.run {
                    self.savedMaps = mapInfos
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load maps: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadMapInfo(from fileURL: URL) async -> MapInfo? {
        do {
            let data = try Data(contentsOf: fileURL)
            let map = try IndoorMap.fromJSONData(data)
            
            let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            return MapInfo(
                id: map.id,
                name: map.name,
                description: map.description,
                beaconCount: map.beacons.count,
                doorwayCount: map.doorways.count,
                createdAt: map.createdAt,
                updatedAt: map.updatedAt,
                fileSize: fileSize,
                fileURL: fileURL
            )
            
        } catch {
            print("Failed to load map from \(fileURL.lastPathComponent): \(error)")
            return nil
        }
    }
    
    // MARK: - Map Saving
    func saveMap(_ map: IndoorMap) async -> Bool {
        isLoading = true
        
        do {
            let jsonData = try map.toJSONData()
            let fileURL = mapsDirectory.appendingPathComponent(map.filename)
            
            try jsonData.write(to: fileURL)
            
            await MainActor.run {
                self.isLoading = false
                self.loadSavedMaps() // Refresh the list
            }
            
            return true
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save map: \(error.localizedDescription)"
                self.isLoading = false
            }
            return false
        }
    }
    
    // MARK: - Map Loading
    func loadMap(with id: UUID) async -> IndoorMap? {
        guard let mapInfo = savedMaps.first(where: { $0.id == id }) else {
            await MainActor.run {
                self.errorMessage = "Map not found"
            }
            return nil
        }
        
        do {
            let data = try Data(contentsOf: mapInfo.fileURL)
            let map = try IndoorMap.fromJSONData(data)
            return map
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load map: \(error.localizedDescription)"
            }
            return nil
        }
    }
    
    // MARK: - Map Selection
    func selectMap(with id: UUID) {
        selectedMapId = id
        saveSelectedMapId()
    }
    
    func clearSelectedMap() {
        selectedMapId = nil
        saveSelectedMapId()
    }
    
    private func loadSelectedMapId() {
        if let uuidString = UserDefaults.standard.string(forKey: "SelectedMapId"),
           let uuid = UUID(uuidString: uuidString) {
            selectedMapId = uuid
        }
    }
    
    private func saveSelectedMapId() {
        if let selectedMapId = selectedMapId {
            UserDefaults.standard.set(selectedMapId.uuidString, forKey: "SelectedMapId")
        } else {
            UserDefaults.standard.removeObject(forKey: "SelectedMapId")
        }
    }
    
    // MARK: - Map Deletion
    func deleteMap(with id: UUID) async -> Bool {
        guard let mapInfo = savedMaps.first(where: { $0.id == id }) else {
            await MainActor.run {
                self.errorMessage = "Map not found"
            }
            return false
        }
        
        do {
            try fileManager.removeItem(at: mapInfo.fileURL)
            
            // Clear selection if deleting selected map
            if selectedMapId == id {
                await MainActor.run {
                    self.clearSelectedMap()
                }
            }
            
            await MainActor.run {
                self.loadSavedMaps() // Refresh the list
            }
            
            return true
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete map: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    // MARK: - Map Duplication
    func duplicateMap(with id: UUID) async -> Bool {
        guard let originalMap = await loadMap(with: id) else { return false }
        
        let duplicatedMap = IndoorMap(
            name: "\(originalMap.name) Copy",
            description: originalMap.description,
            beacons: originalMap.beacons,
            doorways: originalMap.doorways
        )
        
        return await saveMap(duplicatedMap)
    }
    
    // MARK: - Statistics
    func getMapStatistics() -> MapStatistics {
        let totalMaps = savedMaps.count
        let totalBeacons = savedMaps.reduce(0) { $0 + $1.beaconCount }
        let totalDoorways = savedMaps.reduce(0) { $0 + $1.doorwayCount }
        let totalFileSize = savedMaps.reduce(0) { $0 + $1.fileSize }
        
        return MapStatistics(
            totalMaps: totalMaps,
            totalBeacons: totalBeacons,
            totalDoorways: totalDoorways,
            totalFileSize: totalFileSize
        )
    }
    
    // MARK: - Error Handling
    func clearError() {
        errorMessage = nil
    }
    
    // MARK: - Export/Import
    func exportMap(with id: UUID) -> URL? {
        guard let mapInfo = savedMaps.first(where: { $0.id == id }) else { return nil }
        return mapInfo.fileURL
    }
    
    func importMap(from url: URL) async -> Bool {
        do {
            let data = try Data(contentsOf: url)
            let map = try IndoorMap.fromJSONData(data)
            
            // Create a new map with a new ID to avoid conflicts
            let importedMap = IndoorMap(
                name: "\(map.name) (Imported)",
                description: map.description,
                beacons: map.beacons,
                doorways: map.doorways
            )
            
            return await saveMap(importedMap)
            
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to import map: \(error.localizedDescription)"
            }
            return false
        }
    }
}

// MARK: - Map Info
struct MapInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let description: String?
    let beaconCount: Int
    let doorwayCount: Int
    let createdAt: Date
    let updatedAt: Date
    let fileSize: Int64
    let fileURL: URL
    
    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    var isRecent: Bool {
        Date().timeIntervalSince(createdAt) < 7 * 24 * 60 * 60 // Within 7 days
    }
}

// MARK: - Map Statistics
struct MapStatistics {
    let totalMaps: Int
    let totalBeacons: Int
    let totalDoorways: Int
    let totalFileSize: Int64
    
    var totalFileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
    }
}
