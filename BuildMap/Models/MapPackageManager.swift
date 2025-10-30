//
//  MapPackageManager.swift
//  GuideLight v3
//
//  Packages map.json + optional ARWorldMap + (optional) images/ into a .mapbundle,
//  and provides a lightweight zip/unzip for sharing.
//

import Foundation
import UniformTypeIdentifiers

struct MapBundleManifest: Codable {
    let formatVersion: Int
    let mapId: String
    let mapName: String
    let createdAt: Date
    let includesARWorldMap: Bool
}

enum MapPackageError: Error {
    case io(String)
    case invalidBundle
}

enum MapPackageManager {

    // MARK: - Roots

    static func documentsRoot() throws -> URL {
        try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    }

    static func bundlesRoot() throws -> URL {
        let url = try documentsRoot().appendingPathComponent("MapBundles", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    static func arWorldMapsRoot() throws -> URL {
        // Must match SimpleJSONMapManager's ARWorldMaps directory name
        try documentsRoot().appendingPathComponent("ARWorldMaps", isDirectory: true)
    }

    // MARK: - Build bundle for a JSONMap (SimpleJSONMapManager entry)

    static func createBundle(for jsonMap: JSONMap) throws -> URL {
        let base = try bundlesRoot()
        let shortId = jsonMap.id.uuidString.prefix(6)
        let safe = sanitize(jsonMap.name)
        let bundleURL = base.appendingPathComponent("\(safe)_\(shortId).mapbundle", isDirectory: true)

        let fm = FileManager.default
        if fm.fileExists(atPath: bundleURL.path) {
            try fm.removeItem(at: bundleURL)
        }
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        // 1) map.json
        let mapJSON = try JSONSerialization.data(withJSONObject: jsonMap.jsonData, options: [.prettyPrinted, .sortedKeys])
        try mapJSON.write(to: bundleURL.appendingPathComponent("map.json"), options: .atomic)

        // 2) worldmap (optional)
        var hasWM = false
        if let fileName = jsonMap.arWorldMapFileName {
            let wmDir = bundleURL.appendingPathComponent("worldmap", isDirectory: true)
            try fm.createDirectory(at: wmDir, withIntermediateDirectories: true)
            let src = try arWorldMapsRoot().appendingPathComponent(fileName)
            if fm.fileExists(atPath: src.path) {
                let dst = wmDir.appendingPathComponent(fileName)
                try fm.copyItem(at: src, to: dst)
                hasWM = true
            }
        }

        // 3) images/ (optional; created empty for now to satisfy bundle format)
        let imgs = bundleURL.appendingPathComponent("images", isDirectory: true)
        try fm.createDirectory(at: imgs, withIntermediateDirectories: true)

        // 4) manifest.json
        let manifest = MapBundleManifest(formatVersion: 1,
                                         mapId: jsonMap.id.uuidString,
                                         mapName: jsonMap.name,
                                         createdAt: jsonMap.createdDate,
                                         includesARWorldMap: hasWM)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: bundleURL.appendingPathComponent("manifest.json"), options: .atomic)

        return bundleURL
    }

    // MARK: - Zip / Unzip (simple, dependency-free archive)

    /// Produces "<bundle>.zipjson" (a JSON-archive) to keep things dependency-free.
    static func zipBundle(_ bundleURL: URL) throws -> URL {
        let fm = FileManager.default
        let archiveURL = bundleURL.appendingPathExtension("zipjson")
        if fm.fileExists(atPath: archiveURL.path) { try fm.removeItem(at: archiveURL) }

        let basePath = bundleURL.path
        guard let enumerator = fm.enumerator(at: bundleURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw MapPackageError.io("Enumerator failed")
        }

        var dict: [String: Data] = [:]
        for case let fileURL as URL in enumerator {
            if fileURL.hasDirectoryPath { continue }
            let rel = String(fileURL.path.dropFirst(basePath.count + 1))
            dict[rel] = try Data(contentsOf: fileURL)
        }

        let blob = try JSONEncoder().encode(dict)
        try blob.write(to: archiveURL, options: .atomic)
        return archiveURL
    }

    /// Restores a .zipjson archive to a folder under MapBundles and returns the folder URL.
    static func unzipBundle(_ archiveURL: URL) throws -> URL {
        let fm = FileManager.default
        let data = try Data(contentsOf: archiveURL)
        let dict = try JSONDecoder().decode([String: Data].self, from: data)
        let target = try bundlesRoot().appendingPathComponent(archiveURL.deletingPathExtension().lastPathComponent,
                                                              isDirectory: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.createDirectory(at: target, withIntermediateDirectories: true)

        for (rel, fileData) in dict {
            let out = target.appendingPathComponent(rel)
            try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileData.write(to: out, options: .atomic)
        }

        return target
    }

    // MARK: - Helpers

    private static func sanitize(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return s.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce("", { $0 + String($1) })
    }
}
