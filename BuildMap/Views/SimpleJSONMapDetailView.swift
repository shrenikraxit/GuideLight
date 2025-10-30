//
//  SimpleJSONMapDetailView.swift
//  GuideLight v3
//
//  Clean version with no duplicate navigation sections
//

import SwiftUI

// MARK: - Simple JSON Map Detail View
struct SimpleJSONMapDetailView: View {
    let jsonMap: JSONMap
    @ObservedObject private var mapManager = SimpleJSONMapManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var shareURL: URL?
    @State private var jsonContent = ""
    @State private var isLoading = true
    @State private var showingDeleteConfirmation = false

    // Inline JSON editing (added)
    @State private var isEditingJSON = false
    @State private var editableJSON: String = ""

    // Controls the MapJSONEditorView sheet (existing)
    @State private var showingJSONEditor = false
    
    var isSelectedForNavigation: Bool {
        mapManager.selectedMapIdForNavigation == jsonMap.id
    }
    
    var body: some View {
        SwiftUI.NavigationView {
            SwiftUI.ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    // SINGLE Navigation Status Section
                    navigationStatusSection
                    
                    // ARWorldMap Status
                    if jsonMap.hasARWorldMap {
                        arWorldMapStatusSection
                    }
                    
                    // Map Information
                    mapInformationSection
                    
                    // JSON Content (now supports inline edit & save)
                    jsonContentSection
                    
                    // Actions
                    actionsSection
                }
                .padding()
            }
            .navigationTitle(jsonMap.name)
            .navigationBarTitleDisplayMode(.large)
            // Use navigationBarItems to avoid ambiguous .toolbar overloads
            .navigationBarItems(
                leading:
                    Button("Edit JSON") { showingJSONEditor = true },
                trailing:
                    Button("Done") { dismiss() }
            )
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = shareURL {
                SimpleJSONMapShareSheet(activityItems: [url])
            }
        }
        // Present the editor via a local wrapper that adapts types (existing)
        .sheet(isPresented: $showingJSONEditor, onDismiss: { loadJSONContent() }) {
            JSONMapEditorSheet(jsonMap: jsonMap)
        }
        .alert("Delete Map", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteMap() }
        } message: {
            Text("Are you sure you want to delete '\(jsonMap.name)'? This action cannot be undone.")
        }
        .onAppear {
            print("📖 SimpleJSONMapDetailView appeared for: \(jsonMap.name)")
            print("   Map JSON keys: \(jsonMap.jsonData.keys.joined(separator: ", "))")
            loadJSONContent()
        }
    }
    
    // MARK: - Navigation Status Section (SINGLE)
    private var navigationStatusSection: some View {
        Group {
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
        }
    }
    
    // MARK: - ARWorldMap Status Section
    private var arWorldMapStatusSection: some View {
        HStack {
            Image(systemName: "cube.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("ARWorldMap Available")
                    .font(.headline)
                    .foregroundColor(.blue)
                if let fileName = jsonMap.arWorldMapFileName {
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
    
    // MARK: - Map Information Section
    private var mapInformationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Map Information")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                infoRow(label: "Name:", value: jsonMap.name)
                infoRow(label: "Created:", value: jsonMap.createdDate.formatted(.dateTime.day().month().year()))
                infoRow(label: "Description:", value: jsonMap.description.isEmpty ? "No description" : jsonMap.description)
                infoRow(label: "Has ARWorldMap:", value: jsonMap.hasARWorldMap ? "Yes" : "No", valueColor: jsonMap.hasARWorldMap ? .blue : .gray)
                infoRow(label: "Data Keys:", value: jsonMap.jsonData.keys.joined(separator: ", "), valueColor: .blue)
                
                if let beacons = jsonMap.jsonData["beacons"] as? [Any] {
                    infoRow(label: "Beacons:", value: "\(beacons.count)", valueColor: .green)
                }
                
                if let doorways = jsonMap.jsonData["doorways"] as? [Any] {
                    infoRow(label: "Doorways:", value: "\(doorways.count)", valueColor: .orange)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Info Row Helper
    private func infoRow(label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(valueColor)
        }
    }
    
    // MARK: - JSON Content Section (editable)
    private var jsonContentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("JSON Content")
                    .font(.headline)
                Spacer()
                if isLoading {
                    SwiftUI.ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text("\(jsonContent.count) characters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if isLoading {
                loadingPlaceholder
            } else if jsonContent.isEmpty {
                errorPlaceholder
            } else {
                // Inline edit toggle + editor/preview and controls
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Edit inline", isOn: $isEditingJSON.animation())
                        .font(.caption)
                    
                    if isEditingJSON {
                        // Editable TextEditor
                        TextEditor(text: $editableJSON)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 220)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2)))
                        
                        HStack {
                            Button {
                                prettyPrintEditableJSON()
                            } label: {
                                Label("Pretty-print", systemImage: "wand.and.stars")
                            }
                            
                            Button {
                                _ = validateEditableJSON(showToast: true)
                            } label: {
                                Label("Validate", systemImage: "checkmark.seal")
                            }
                            
                            Spacer()
                            
                            Button(role: .none) {
                                saveEditedJSON()
                            } label: {
                                Label("Save JSON", systemImage: "square.and.arrow.down")
                                    .bold()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        // Read-only horizontal scroller (existing UX)
                        SwiftUI.ScrollView(.horizontal, showsIndicators: true) {
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
            }
        }
    }
    
    private var loadingPlaceholder: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.2))
            .frame(height: 200)
            .overlay(
                Text("Loading JSON content...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            )
            .cornerRadius(8)
    }
    
    private var errorPlaceholder: some View {
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
    }
    
    // (kept) Original read-only scroller now shown in non-edit mode above
    private var jsonScrollView: some View {
        SwiftUI.ScrollView(.horizontal, showsIndicators: true) {
            Text(jsonContent)
                .font(.system(.caption, design: .monospaced))
                .padding()
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                .textSelection(.enabled)
        }
        .frame(minHeight: 200)
    }
    
    // MARK: - Actions Section
    private var actionsSection: some View {
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
                    mapManager.selectMapForNavigation(jsonMap.id)
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
            
            Button("Debug Map Data") {
                debugMapData()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .foregroundColor(.orange)
        }
    }
    
    // MARK: - Helper Methods
    private func loadJSONContent() {
        print("📖 Loading JSON content for map: \(jsonMap.name)")
        isLoading = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: jsonMap.jsonData, options: .prettyPrinted)
                jsonContent = String(data: jsonData, encoding: .utf8) ?? ""
                // seed editable buffer to current content
                editableJSON = jsonContent
                print("   ✅ Loaded JSON content length: \(jsonContent.count)")
                if jsonContent.isEmpty {
                    print("   ⚠️ JSON content is empty!")
                }
            } catch {
                print("   ❌ Failed to serialize JSON: \(error)")
                jsonContent = "Error serializing JSON: \(error.localizedDescription)"
                // keep editableJSON unchanged to avoid losing edits
            }
            isLoading = false
        }
    }
    

    
    private func shareMap() {
        print("📤 Sharing map: \(jsonMap.name)")
        
        let jsonString = jsonContent.isEmpty ? SimpleJSONMapManager.shared.exportMapAsJSON(jsonMap) : jsonContent
        let fileName = "\(jsonMap.name.replacingOccurrences(of: " ", with: "_")).json"
        
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
        print("🗑️ Deleting map: \(jsonMap.name)")
        
        if let index = mapManager.maps.firstIndex(where: { $0.id == jsonMap.id }) {
            mapManager.deleteMap(at: index)
            print("✅ Map deleted successfully")
            dismiss()
        } else {
            print("❌ Failed to find map to delete")
        }
    }
    
    private func debugMapData() {
        print("🛠 DEBUG MAP DATA:")
        print("   Map ID: \(jsonMap.id)")
        print("   Map Name: \(jsonMap.name)")
        print("   Created: \(jsonMap.createdDate)")
        print("   Description: \(jsonMap.description)")
        print("   Has ARWorldMap: \(jsonMap.hasARWorldMap)")
        if let fileName = jsonMap.arWorldMapFileName {
            print("   ARWorldMap file: \(fileName)")
        }
        print("   JSON Data Keys: \(jsonMap.jsonData.keys)")
        print("   JSON Data: \(jsonMap.jsonData)")
    }

    // MARK: - Inline JSON edit helpers (added)
    private func prettyPrintEditableJSON() {
        do {
            guard let data = editableJSON.data(using: .utf8) else { return }
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            if let s = String(data: pretty, encoding: .utf8) {
                editableJSON = s
            }
        } catch {
            print("❌ Pretty-print failed: \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func validateEditableJSON(showToast: Bool = false) -> [String: Any]? {
        do {
            guard let data = editableJSON.data(using: .utf8) else { return nil }
            guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Invalid JSON: root must be an object")
                return nil
            }
            if showToast { print("✅ JSON valid (\(dict.keys.count) top-level keys)") }
            return dict
        } catch {
            print("❌ Invalid JSON: \(error.localizedDescription)")
            return nil
        }
    }

    private func saveEditedJSON() {
        guard let newDict = validateEditableJSON() else { return }

        // Rebuild a JSONMap with the SAME identity & metadata, but new jsonData.
        let iso = ISO8601DateFormatter()
        var payload: [String: Any] = [
            "id": jsonMap.id.uuidString,
            "name": jsonMap.name,
            "createdDate": iso.string(from: jsonMap.createdDate),
            "description": jsonMap.description
        ]
        if let f = jsonMap.arWorldMapFileName { payload["arWorldMapFileName"] = f }

        do {
            // 1) Convert edited JSON (Dictionary) to a stable JSON string
            let jsonBlob = try JSONSerialization.data(withJSONObject: newDict, options: [.sortedKeys])
            let jsonString = String(data: jsonBlob, encoding: .utf8) ?? "{}"
            payload["jsonDataString"] = jsonString

            // 2) Build a JSONMap from the payload
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let rebuilt = try dec.decode(JSONMap.self, from: data)

            // 3) Swap it into the manager's array
            if let idx = mapManager.maps.firstIndex(where: { $0.id == jsonMap.id }) {
                mapManager.maps[idx] = rebuilt
                print("💾 Saved inline JSON edits for “\(rebuilt.name)”")

                // 4) PERSIST the full maps array so edits survive relaunch
                //    (matches SimpleJSONMapManager.saveMaps() behavior)
                let encoded = try JSONEncoder().encode(mapManager.maps)
                UserDefaults.standard.set(encoded, forKey: "saved_json_maps")
                print("✅ Persisted edited map to UserDefaults")
            } else {
                print("⚠️ Could not find map in manager to update")
            }

            // 5) Update local UI state
            jsonContent = editableJSON
            isEditingJSON = false
        } catch {
            print("❌ Rebuild/Persist JSONMap failed: \(error)")
        }
    }

}


// MARK: - Local wrapper to adapt JSONMap → IndoorMap for MapJSONEditorView
private struct JSONMapEditorSheet: View {
    let jsonMap: JSONMap

    @StateObject private var editorManager = MapManagerViewModel() // expects default init

    var body: some View {
        if let indoor = try? decodeIndoorMap(from: jsonMap.jsonData) {
            // Your editor expects (originalMap: IndoorMap, mapManager: MapManagerViewModel)
            MapJSONEditorView(originalMap: indoor, mapManager: editorManager)
        } else {
            // Fallback UI if decoding fails (keeps build green)
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                Text("Unable to open JSON Editor")
                    .font(.headline)
                Text("The JSON couldn’t be decoded into an IndoorMap.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }

    private func decodeIndoorMap(from dict: [String: Any]) throws -> IndoorMap {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [])
        let decoder = JSONDecoder()
        // Configure here if your IndoorMap uses different strategies:
        // decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(IndoorMap.self, from: data)
    }
}
