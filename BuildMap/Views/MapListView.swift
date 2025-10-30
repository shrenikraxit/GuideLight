//
//  MapListView.swift
//  Mapping v2
//
//  Created by Indraneel Rakshit on 9/20/25.
//


import SwiftUI

// MARK: - Map List View
struct MapListView: View {
    @StateObject private var mapManager = MapManagerViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirmation = false
    @State private var mapToDelete: MapInfo?
    
    var body: some View {
        NavigationView {
            Group {
                if mapManager.isLoading {
                    loadingView
                } else if mapManager.savedMaps.isEmpty {
                    emptyStateView
                } else {
                    mapListContent
                }
            }
            .navigationTitle("Saved Maps")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .refreshable {
                mapManager.loadSavedMaps()
            }
        }
        .alert("Delete Map", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let mapToDelete = mapToDelete {
                    Task {
                        await mapManager.deleteMap(with: mapToDelete.id)
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(mapToDelete?.name ?? "")\"? This action cannot be undone.")
        }
        .alert("Error", isPresented: .constant(mapManager.errorMessage != nil)) {
            Button("OK") {
                mapManager.clearError()
            }
        } message: {
            Text(mapManager.errorMessage ?? "")
        }
        .onAppear {
            mapManager.loadSavedMaps()
        }
    }
    
    // MARK: - Loading View
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading maps...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text("No Maps Found")
                    .font(.title2.weight(.semibold))
                
                Text("Use the \"Start 2D Mapping\" button to create your first indoor map.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Button("Create First Map") {
                // Trigger mapping notification
                NotificationCenter.default.post(name: .triggerPathfinderMapping, object: nil)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Map List Content
    private var mapListContent: some View {
        List {
            // Statistics Section
            statisticsSection
            
            // Maps Section
            Section {
                ForEach(mapManager.savedMaps) { mapInfo in
                    MapRowView(
                        mapInfo: mapInfo,
                        isSelected: mapManager.selectedMapId == mapInfo.id,
                        onSelect: {
                            mapManager.selectMap(with: mapInfo.id)
                        },
                        onDelete: {
                            mapToDelete = mapInfo
                            showingDeleteConfirmation = true
                        },
                        onDuplicate: {
                            Task {
                                await mapManager.duplicateMap(with: mapInfo.id)
                            }
                        }
                    )
                }
            } header: {
                HStack {
                    Text("Maps")
                    Spacer()
                    if mapManager.selectedMapId != nil {
                        Button("Clear Selection") {
                            mapManager.clearSelectedMap()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
    }
    
    // MARK: - Statistics Section
    private var statisticsSection: some View {
        Section {
            let stats = mapManager.getMapStatistics()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Map Statistics")
                    .font(.headline)
                
                HStack {
                    StatisticView(title: "Total Maps", value: "\(stats.totalMaps)")
                    Spacer()
                    StatisticView(title: "Total Beacons", value: "\(stats.totalBeacons)")
                    Spacer()
                    StatisticView(title: "Total Doorways", value: "\(stats.totalDoorways)")
                }
                
                HStack {
                    StatisticView(title: "Storage Used", value: stats.totalFileSizeFormatted)
                    Spacer()
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Map Row View
struct MapRowView: View {
    let mapInfo: MapInfo
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(mapInfo.name)
                            .font(.headline)
                        
                        if mapInfo.isRecent {
                            Text("NEW")
                                .font(.caption2.weight(.bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        Spacer()
                        
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                        }
                    }
                    
                    if let description = mapInfo.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Actions Menu
                Menu {
                    Button {
                        onSelect()
                    } label: {
                        Label(isSelected ? "Selected" : "Select", systemImage: "checkmark.circle")
                    }
                    .disabled(isSelected)
                    
                    Button {
                        onDuplicate()
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            
            // Details
            HStack(spacing: 16) {
                DetailItem(icon: "flag.fill", text: "\(mapInfo.beaconCount) beacons")
                DetailItem(icon: "rectangle.portrait.and.arrow.right", text: "\(mapInfo.doorwayCount) doorways")
                DetailItem(icon: "doc", text: mapInfo.fileSizeFormatted)
                
                Spacer()
                
                Text(mapInfo.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - Detail Item
struct DetailItem: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Statistic View
struct StatisticView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    MapListView()
}
