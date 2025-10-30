//
//  SimpleJSONMapsListView.swift
//  GuideLight v3
//
//  Clean version with no duplicate navigation sections
//

import SwiftUI

// MARK: - Simple JSON Maps List View
struct SimpleJSONMapsListView: View {
    @ObservedObject private var mapManager = SimpleJSONMapManager.shared
    @State private var showingAddMap = false
    @State private var showingSessionJSON = false
    @State private var showingSessionShare = false
    @State private var sessionShareURL: URL?
    
    var body: some View {
        List {
            // SINGLE Navigation Map Section
            navigationSection
            
            // Current Session Section
            if !mapManager.currentBeacons.isEmpty || !mapManager.currentDoorways.isEmpty {
                currentSessionSection
            }
            
            // Debug Section
            debugSection
            
            // Saved Maps Section
            savedMapsSection
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
    
    // MARK: - Navigation Section (SINGLE)
    private var navigationSection: some View {
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
    }
    
    // MARK: - Current Session Section
    private var currentSessionSection: some View {
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
                    mapManager.saveCurrentSession()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Debug Section
    private var debugSection: some View {
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
            
            Button("ARWorldMap Storage Info") {
                let info = mapManager.getARWorldMapStorageInfo()
                print("📊 ARWorldMap Storage Info:")
                print(info)
            }
            .foregroundColor(.blue)
        }
    }
    
    // MARK: - Saved Maps Section
    @ViewBuilder
    private var savedMapsSection: some View {
        if mapManager.maps.isEmpty {
            Section(header: Text("Saved Maps")) {
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
            Section(header: Text("Saved Maps")) {
                ForEach(mapManager.maps) { map in
                    NavigationLink(
                        destination: SimpleJSONMapDetailView(jsonMap: map) // ← fix label here
                    ) {
                        mapRow(for: map)
                    }
                }
                .onDelete(perform: deleteMap)
            }
        }
    }

    
    // MARK: - Map Row
    private func mapRow(for map: JSONMap) -> some View {
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
    
    // MARK: - Helper Methods
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
