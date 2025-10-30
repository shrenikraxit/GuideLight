import SwiftUI
import Combine

// MARK: - JSON Editor Screen
struct MapJSONEditorView: View {
    let originalMap: IndoorMap
    @ObservedObject var mapManager: MapManagerViewModel

    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: MapJSONEditorViewModel

    init(originalMap: IndoorMap, mapManager: MapManagerViewModel) {
        self.originalMap = originalMap
        self.mapManager = mapManager
        _vm = StateObject(wrappedValue: MapJSONEditorViewModel(originalMap: originalMap))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Summary strip
                HStack(spacing: 12) {
                    Text("Map: \(originalMap.name)").font(.headline)
                    Divider()
                    Text("v\(vm.versionString)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Toggle("Protect IDs", isOn: $vm.protectIDs)
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                        .labelsHidden()
                    Text("Protect IDs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))

                // Editor
                TextEditor(text: $vm.jsonText)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 8)

                // Validation / Diff summary
                if let result = vm.validationResult {
                    ValidationResultView(result: result)
                        .padding(.vertical, 8)
                        .background(result.isValid ? Color.green.opacity(0.08) : Color.red.opacity(0.08))
                }
            }
            .navigationTitle("Edit JSON")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Reformat") { vm.reformat() }
                    Button("Validate") { vm.validate() }
                    Button("Save") { Task { await saveAction() } }
                        .disabled(!(vm.validationResult?.isValid ?? false) || vm.isWorking)
                }
            }
            .overlay {
                if vm.isWorking {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("Working…")
                            .padding(16)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                    }
                }
            }
            .alert("Error", isPresented: .constant(vm.errorMessage != nil)) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
            .alert("Saved", isPresented: $vm.showSavedToast) {
                Button("OK") { dismiss() }
            } message: {
                Text("Map updated successfully.\nA timestamped backup was created.")
            }
        }
    }

    private func saveAction() async {
        await vm.save(mapManager: mapManager)
    }
}

// MARK: - Validation result/status view
private struct ValidationResultView: View {
    let result: MapJSONValidationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: result.isValid ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .foregroundColor(result.isValid ? .green : .red)
                Text(result.isValid ? "Validation passed" : "Validation failed")
                    .font(.headline)
                Spacer()
            }

            if !result.errors.isEmpty {
                ForEach(result.errors, id: \.self) { err in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                        Text(err).font(.caption)
                    }
                }
            }

            if !result.warnings.isEmpty {
                Divider().padding(.vertical, 6)
                ForEach(result.warnings, id: \.self) { w in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle").foregroundColor(.orange)
                        Text(w).font(.caption)
                    }
                }
            }

            if let diff = result.diff, (!diff.added.isEmpty || !diff.removed.isEmpty || !diff.modified.isEmpty) {
                Divider().padding(.vertical, 6)
                Text("Changes").font(.subheadline).bold()
                if !diff.added.isEmpty { Text("Added: \(diff.added.joined(separator: ", "))").font(.caption) }
                if !diff.removed.isEmpty { Text("Removed: \(diff.removed.joined(separator: ", "))").font(.caption) }
                if !diff.modified.isEmpty { Text("Modified: \(diff.modified.joined(separator: ", "))").font(.caption) }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - ViewModel + Validator
@MainActor
final class MapJSONEditorViewModel: ObservableObject {
    @Published var jsonText: String
    @Published var validationResult: MapJSONValidationResult?
    @Published var protectIDs: Bool = true
    @Published var isWorking = false
    @Published var errorMessage: String?
    @Published var showSavedToast = false

    private let originalMap: IndoorMap
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    var versionString: String { originalMap.metadata.version }

    init(originalMap: IndoorMap) {
        self.originalMap = originalMap
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601

        self.jsonText = (try? String(data: encoder.encode(originalMap), encoding: .utf8)) ?? "{}"
    }

    func reformat() {
        do {
            let data = jsonText.data(using: .utf8) ?? Data()
            let map = try decoder.decode(IndoorMap.self, from: data)
            let pretty = try encoder.encode(map)
            self.jsonText = String(data: pretty, encoding: .utf8) ?? jsonText
        } catch {
            self.errorMessage = "Cannot reformat: \(error.localizedDescription)"
        }
    }

    func validate() {
        do {
            let data = jsonText.data(using: .utf8) ?? Data()
            let candidate = try decoder.decode(IndoorMap.self, from: data)

            var errors: [String] = []
            var warnings: [String] = []

            // Version tolerance (accepts 2.2/2.3)
            let acceptedVersions: Set<String> = ["2.2", "2.3"]
            if !acceptedVersions.contains(candidate.metadata.version) {
                warnings.append("Unknown schema version \(candidate.metadata.version). Proceed with caution.")
            }

            // ID protection
            if protectIDs {
                errors.append(contentsOf: Self.protectIDViolations(original: originalMap, edited: candidate))
            }

            // Referential integrity checks (rooms ↔ beacons/doorways/waypoints)
            errors.append(contentsOf: Self.integrityErrors(for: candidate))

            let diff = Self.diffSummary(original: originalMap, edited: candidate)
            self.validationResult = MapJSONValidationResult(isValid: errors.isEmpty, errors: errors, warnings: warnings, diff: diff)
        } catch let e as DecodingError {
            self.validationResult = MapJSONValidationResult(isValid: false, errors: [Self.prettyDecodeError(e)], warnings: [], diff: nil)
        } catch {
            self.validationResult = MapJSONValidationResult(isValid: false, errors: ["Parse error: \(error.localizedDescription)"], warnings: [], diff: nil)
        }
    }

    func save(mapManager: MapManagerViewModel) async {
        guard let result = validationResult, result.isValid else {
            self.errorMessage = "Please validate and fix errors before saving."
            return
        }

        isWorking = true
        defer { isWorking = false }

        do {
            let data = jsonText.data(using: .utf8) ?? Data()
            let edited = try decoder.decode(IndoorMap.self, from: data)

            // 1) BACKUP: duplicate the original map (lets MapManager decide filename/id for backup)
            _ = await mapManager.duplicateMap(with: originalMap.id)

            // 2) REPLACE: save edited map (same UUID preserves all links)
            let ok = await mapManager.saveMap(edited)

            if ok {
                // --- NEW: 1-line integration to persist edited JSON into UserDefaults JSON store ---
                if let dict = try? JSONSerialization.jsonObject(with: encoder.encode(edited)) as? [String: Any] { _ = SimpleJSONMapManager.shared.updateJSON(for: edited.id, with: dict) }
                // -----------------------------------------------------------------------------------

                self.showSavedToast = true
            } else {
                self.errorMessage = "Failed to save the edited map."
            }
        } catch {
            self.errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Validator helpers

    private static func protectIDViolations(original: IndoorMap, edited: IndoorMap) -> [String] {
        var issues: [String] = []

        func ids<T: Identifiable>(_ arr: [T]) -> Set<String> where T.ID == UUID {
            Set(arr.map { $0.id.uuidString })
        }

        if ids(original.rooms) != ids(edited.rooms) {
            issues.append("Room IDs changed while Protect IDs is ON. Revert `id` values or turn Protect IDs off.")
        }
        if ids(original.beacons) != ids(edited.beacons) {
            issues.append("Beacon IDs changed while Protect IDs is ON. Revert `id` values or turn Protect IDs off.")
        }
        if ids(original.doorways) != ids(edited.doorways) {
            issues.append("Doorway IDs changed while Protect IDs is ON. Revert `id` values or turn Protect IDs off.")
        }
        if ids(original.waypoints) != ids(edited.waypoints) {
            issues.append("Waypoint IDs changed while Protect IDs is ON. Revert `id` values or turn Protect IDs off.")
        }
        if original.id != edited.id {
            issues.append("Map root ID changed while Protect IDs is ON. Revert the top-level `id`.")
        }
        return issues
    }

    private static func integrityErrors(for m: IndoorMap) -> [String] {
        var errs: [String] = []

        // Rooms set
        let roomIds = Set(m.rooms.map { $0.id.uuidString })

        // Beacon.roomId must exist
        for b in m.beacons {
            if !roomIds.contains(b.roomId) {
                errs.append("Beacon '\(b.name)' references missing roomId \(b.roomId).")
            }
        }

        // Doorway connectsRooms must exist
        for d in m.doorways {
            if !roomIds.contains(d.connectsRooms.roomA) {
                errs.append("Doorway '\(d.name)' references missing roomId \(d.connectsRooms.roomA).")
            }
            if !roomIds.contains(d.connectsRooms.roomB) {
                errs.append("Doorway '\(d.name)' references missing roomId \(d.connectsRooms.roomB).")
            }
        }

        // Waypoints: if your model has roomId, validate it
        for w in m.waypoints {
            // If your Waypoint type doesn't have roomId, comment the next two lines.
            if !roomIds.contains(w.roomId) {
                errs.append("Waypoint '\(w.name)' references missing roomId \(w.roomId).")
            }
        }

        // Duplicate global UUIDs across collections
        let allIds = m.rooms.map { $0.id } + m.beacons.map { $0.id } + m.doorways.map { $0.id } + m.waypoints.map { $0.id }
        let dupes = Dictionary(grouping: allIds, by: { $0 }).filter { $1.count > 1 }
        if !dupes.isEmpty {
            errs.append("Duplicate UUIDs detected across entities: \(dupes.keys.map { $0.uuidString }.joined(separator: ", ")).")
        }

        return errs
    }

    private static func diffSummary(original: IndoorMap, edited: IndoorMap) -> MapDiff? {
        func classify<T: Identifiable & Equatable>(_ o: [T], _ e: [T]) -> (added: [String], removed: [String], modified: [String]) where T.ID == UUID {
            let oDict = Dictionary(uniqueKeysWithValues: o.map { ($0.id, $0) })
            let eDict = Dictionary(uniqueKeysWithValues: e.map { ($0.id, $0) })
            let oIds = Set(oDict.keys)
            let eIds = Set(eDict.keys)

            let display: (T) -> String = { item in
                if let r = item as? Room { return "Room:\(r.name)" }
                if let b = item as? Beacon { return "Beacon:\(b.name)" }
                if let d = item as? Doorway { return "Doorway:\(d.name)" }
                if let w = item as? Waypoint { return "Waypoint:\(w.name)" }
                return item.id.uuidString
            }

            let added = eIds.subtracting(oIds).compactMap { eDict[$0] }.map(display)
            let removed = oIds.subtracting(eIds).compactMap { oDict[$0] }.map(display)
            let modified = oIds.intersection(eIds).compactMap { id -> String? in
                guard let a = oDict[id], let b = eDict[id] else { return nil }
                return a != b ? display(b) : nil
            }
            return (added, removed, modified)
        }

        let rooms = classify(original.rooms, edited.rooms)
        let beacons = classify(original.beacons, edited.beacons)
        let doors = classify(original.doorways, edited.doorways)
        let wps = classify(original.waypoints, edited.waypoints)

        let added = rooms.added + beacons.added + doors.added + wps.added
        let removed = rooms.removed + beacons.removed + doors.removed + wps.removed
        let modified = rooms.modified + beacons.modified + doors.modified + wps.modified

        if added.isEmpty && removed.isEmpty && modified.isEmpty { return nil }
        return MapDiff(added: added, removed: removed, modified: modified)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    static func prettyDecodeError(_ e: DecodingError) -> String {
        switch e {
        case .typeMismatch(_, let ctx),
             .valueNotFound(_, let ctx),
             .keyNotFound(_, let ctx),
             .dataCorrupted(let ctx):
            return "Line/Key error: \(ctx.debugDescription)"
        @unknown default:
            return "Decoding error."
        }
    }
}

// MARK: - Validation result models
struct MapJSONValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    let diff: MapDiff?
}

struct MapDiff {
    let added: [String]
    let removed: [String]
    let modified: [String]
}
