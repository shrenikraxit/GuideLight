//
//  PathNavigationLauncherView.swift
//  GuideLight v3
//
//  FIXED: Toolbar ambiguity and added parseIndoorMap support
//  UPDATED: Voice handoff from Home (wakeword / "take me <dest>")
//

import SwiftUI

// MARK: - Path Navigation Launcher View
struct PathNavigationLauncherView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingNavigation = false
    @State private var showingMapSelection = false
    @State private var errorMessage: String?
    @State private var showingError = false

    // Carry-over from voice launch
    let initialDestinationName: String?
    let fromVoice: Bool

    // We’ll send the destination to Navigation after the screen is up
    @State private var pendingDestinationToSend: String? = nil
    
    private let mapManager = SimpleJSONMapManager.shared

    // Back-compat default init for existing call sites / previews
    init(initialDestinationName: String? = nil, fromVoice: Bool = false) {
        self.initialDestinationName = initialDestinationName
        self.fromVoice = fromVoice
    }
    
    var body: some View {
        NavigationView {
            contentView
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Home")
                            }
                            .foregroundColor(.white)
                        }
                    }
                }
        }
        .sheet(isPresented: $showingMapSelection) {
            SimpleJSONMapsListView()
        }
        .fullScreenCover(isPresented: $showingNavigation, onDismiss: {
            // Clear pending command if user comes back
            pendingDestinationToSend = nil
        }) {
            if let selectedMap = mapManager.getSelectedMapForNavigation(),
               let arWorldMapFileName = selectedMap.arWorldMapFileName,
               let indoorMap = NavigationIntegrationHelper.parseIndoorMap(from: selectedMap) {
                // Present Navigation UI
                NavigationMainView(map: indoorMap, mapFileName: arWorldMapFileName)
                    .onAppear {
                        // Defer sending the voice command slightly to ensure AR view is mounted
                        if let dest = pendingDestinationToSend, !dest.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                NotificationCenter.default.post(
                                    name: .glVoiceNavigateCommand,
                                    object: nil,
                                    userInfo: ["destination": dest]
                                )
                                // Only send once
                                pendingDestinationToSend = nil
                            }
                        }
                    }
            }
        }
        .alert("Navigation Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .onAppear {
            // Capture any destination requested by voice and auto-launch if possible
            pendingDestinationToSend = initialDestinationName
            if fromVoice {
                attemptAutoLaunchForVoice()
            }
        }
    }
    
    // MARK: - Content View
    private var contentView: some View {
        ZStack {
            // Background
            Color(red: 0.11, green: 0.17, blue: 0.29)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                // Icon
                Image(systemName: "map.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                // Title
                Text("Indoor Navigation")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                
                // Status
                mapStatusView
                
                Spacer()
                
                // Action Buttons
                actionButtonsView
            }
        }
    }
    
    // MARK: - Map Status View
    private var mapStatusView: some View {
        Group {
            if let selectedMap = mapManager.getSelectedMapForNavigation() {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Map Selected")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Text(selectedMap.name)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.8))
                    
                    if selectedMap.hasARWorldMap {
                        HStack {
                            Image(systemName: "cube.fill")
                                .foregroundColor(.blue)
                            Text("ARWorldMap Ready")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("No ARWorldMap - Navigation Limited")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    // Map stats
                    if let beacons = selectedMap.jsonData["beacons"] as? [Any],
                       let doorways = selectedMap.jsonData["doorways"] as? [Any] {
                        HStack(spacing: 20) {
                            Label("\(beacons.count) beacons", systemImage: "flag.fill")
                            Label("\(doorways.count) doorways", systemImage: "door.left.hand.open")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
                
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                        Text("No Map Selected")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Text("Please select a map to enable navigation")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Action Buttons View
    private var actionButtonsView: some View {
        VStack(spacing: 16) {
            // Start Navigation Button
            Button {
                launchNavigation()
            } label: {
                HStack {
                    Image(systemName: "location.fill")
                    Text("Start Navigation")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(canNavigate ? Color.green : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!canNavigate)
            
            // Select/Change Map Button
            Button {
                showingMapSelection = true
            } label: {
                HStack {
                    Image(systemName: "map")
                    Text(mapManager.getSelectedMapForNavigation() == nil ? "Select Map" : "Change Map")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 32)
    }
    
    // MARK: - Computed Properties
    
    private var canNavigate: Bool {
        guard let selectedMap = mapManager.getSelectedMapForNavigation() else {
            return false
        }
        
        // Must have ARWorldMap
        guard selectedMap.hasARWorldMap else {
            return false
        }
        
        // Must have minimum data
        guard let beacons = selectedMap.jsonData["beacons"] as? [Any],
              beacons.count >= 3 else {
            return false
        }
        
        return true
    }
    
    // MARK: - Actions
    
    private func launchNavigation() {
        // Validate map selection
        guard let selectedMap = mapManager.getSelectedMapForNavigation() else {
            errorMessage = "Please select a map first"
            showingError = true
            return
        }
        
        // Check for ARWorldMap - FIXED: Use hasARWorldMap property
        guard selectedMap.hasARWorldMap else {
            errorMessage = "Selected map doesn't have ARWorldMap data.\n\nPlease remap this location using 'Build Map' to enable navigation."
            showingError = true
            return
        }
        
        guard let _ = selectedMap.arWorldMapFileName else {
            errorMessage = "ARWorldMap file reference missing."
            showingError = true
            return
        }
        
        // Parse map - FIXED: Now using NavigationIntegrationHelper.parseIndoorMap
        guard let indoorMap = NavigationIntegrationHelper.parseIndoorMap(from: selectedMap) else {
            errorMessage = "Failed to parse map data.\n\nThe map file may be corrupted."
            showingError = true
            return
        }
        
        // Validate map has enough data
        guard indoorMap.beacons.count >= 3 else {
            errorMessage = "Map needs at least 3 beacons for navigation.\n\nCurrent beacons: \(indoorMap.beacons.count)"
            showingError = true
            return
        }
        
        guard !indoorMap.rooms.isEmpty else {
            errorMessage = "Map has no rooms defined.\n\nPlease remap with room definitions."
            showingError = true
            return
        }
        
        print("🚀 Launching navigation for: \(selectedMap.name)")
        print("   Beacons: \(indoorMap.beacons.count)")
        print("   Rooms: \(indoorMap.rooms.count)")
        print("   Doorways: \(indoorMap.doorways.count)")
        
        showingNavigation = true
    }

    /// Voice path: if a map is ready, auto-launch; else nudge to select a map.
    private func attemptAutoLaunchForVoice() {
        guard let selectedMap = mapManager.getSelectedMapForNavigation() else {
            // No map — open selector so the user can continue hands-free
            showingMapSelection = true
            return
        }
        guard selectedMap.hasARWorldMap else {
            errorMessage = "Selected map doesn't have ARWorldMap data.\n\nPlease remap this location using 'Build Map' to enable navigation."
            showingError = true
            return
        }
        // Everything looks good — go
        showingNavigation = true
    }
}

#Preview {
    PathNavigationLauncherView()
}
