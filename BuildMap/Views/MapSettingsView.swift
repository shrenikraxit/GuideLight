//
//  MapSettingsView.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/22/25.
//


import SwiftUI

struct MapSettingsView: View {
    @StateObject private var mapManager = MapManagerViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var editorPresented = false
    @State private var mapForEditing: IndoorMap?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            List {
                Section("Map Management") {
                    Button {
                        Task { await openEditorForSelectedMap() }
                    } label: {
                        Label("Edit Map JSON (Advanced)", systemImage: "curlybraces")
                    }
                    .disabled(mapManager.selectedMapId == nil || isLoading)

                    if mapManager.selectedMapId == nil {
                        Text("Select a map in Saved Maps, then edit here.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                mapManager.loadSavedMaps()
            }
            .sheet(isPresented: $editorPresented) {
                if let map = mapForEditing {
                    MapJSONEditorView(
                        originalMap: map,
                        mapManager: mapManager
                    )
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func openEditorForSelectedMap() async {
        guard let id = mapManager.selectedMapId else { return }
        isLoading = true
        defer { isLoading = false }
        if let loaded = await mapManager.loadMap(with: id) {
            await MainActor.run {
                self.mapForEditing = loaded
                self.editorPresented = true
            }
        } else {
            await MainActor.run {
                self.errorMessage = "Could not load the selected map."
            }
        }
    }
}
