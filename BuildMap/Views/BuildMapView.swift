//
//  BuildMapView.swift
//  GuideLight v3
//
//  Build Map with “just-added” highlight markers + name banners.
//  Surgical fixes:
//  - SpriteKit-backed banners (NaN-safe with clamped sizes)
//  - Float.pi fix
//  - Coordinator subscribes to view model changes to refresh nodes immediately
//

import SwiftUI
import ARKit
import SceneKit
import SpriteKit
import Combine

// MARK: - Build Map View (ARWorldMap support + Add-Highlight)
struct BuildMapView: View {
    @StateObject private var viewModel = BuildMapViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showingMapNameDialog = false
    @State private var showingSaveConfirmation = false
    @State private var mapNameInput = ""

    var body: some View {
        NavigationView {
            ZStack {
                if viewModel.showingRoomSetup {
                    roomSetupView
                } else {
                    arMappingView
                }
                
                // Saving progress overlay
                if viewModel.isSavingMap {
                    savingProgressOverlay
                }
            }
            .navigationTitle(viewModel.showingRoomSetup ? "Setup Rooms" : "Build Map")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSavingMap)
                }

                if !viewModel.showingRoomSetup {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            if viewModel.currentMap.name == "New Map" || viewModel.currentMap.name.isEmpty {
                                mapNameInput = ""
                                showingMapNameDialog = true
                            } else {
                                saveMapWithCurrentName()
                            }
                        }
                        .disabled(
                            (viewModel.currentMap.beacons.isEmpty && viewModel.currentMap.doorways.isEmpty)
                            || viewModel.isSavingMap
                        )
                    }
                }
            }
        }
        .alert("Name Your Map", isPresented: $showingMapNameDialog) {
            TextField("Map Name", text: $mapNameInput)
            Button("Cancel", role: .cancel) { mapNameInput = "" }
            Button("Save") { saveMapWithName(mapNameInput) }
                .disabled(mapNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Item Details", isPresented: $viewModel.showingNameDialog) {
            TextField("Name", text: $viewModel.tempItemName)
            if viewModel.placementMode == .beacon {
                Toggle("Mark as Obstacle?", isOn: $viewModel.isObstacleBeacon)
            }
            Button("Cancel", role: .cancel) { viewModel.cancelPlacement() }
            Button("Place") {
                if viewModel.placementMode == .beacon {
                    viewModel.confirmBeaconPlacement()
                } else {
                    viewModel.confirmWaypointPlacement()
                }
            }
        }
        .sheet(isPresented: $viewModel.showingDoorwayDetails) {
            doorwayDetailsSheet
        }
        .sheet(isPresented: $viewModel.showingRoomSelector) {
            roomSelectorSheet
        }
        .alert("Map Saved", isPresented: $showingSaveConfirmation) {
            Button("Continue Editing") {}
            Button("Done") { dismiss() }
        } message: {
            Text("Your map '\(viewModel.currentMap.name)' has been saved with ARWorldMap support!")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Saving Progress Overlay
    private var savingProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                Text("Saving Map")
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                if !viewModel.savingProgress.isEmpty {
                    Text(viewModel.savingProgress)
                        .font(.body)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Text("Please wait...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(40)
            .background(Color.black.opacity(0.8))
            .cornerRadius(20)
        }
    }

    // MARK: - Room Setup View
    private var roomSetupView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                Text("Setup Rooms").font(.title.weight(.bold))
                Text("Define the rooms you'll be mapping")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(viewModel.currentMap.rooms.enumerated()), id: \.element.id) { index, room in
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(room.name).font(.headline)
                                HStack(spacing: 6) {
                                    Text(room.type.displayName).font(.caption).foregroundColor(.secondary)
                                    Text("•").foregroundColor(.secondary)
                                    Text(room.floorSurface.displayName).font(.caption).foregroundColor(.secondary)
                                }
                                if let f = room.floorOfBuilding, !f.isEmpty {
                                    Text("Floor: \(f)").font(.caption).foregroundColor(.secondary)
                                }
                                if let addr = room.address, !addr.isEmpty {
                                    Text(addr).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                                }
                                if let desc = room.description, !desc.isEmpty {
                                    Text(desc).font(.caption2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                viewModel.removeRoom(at: index)
                            } label: {
                                Image(systemName: "trash").foregroundColor(.red)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }

            VStack(spacing: 12) {
                TextField("Room Name", text: $viewModel.tempRoomName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Picker("Type", selection: $viewModel.tempRoomType) {
                        ForEach(RoomType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Surface", selection: $viewModel.tempFloorSurface) {
                        ForEach(FloorSurface.allCases, id: \.self) { surface in
                            Text(surface.displayName).tag(surface)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Description").font(.footnote).foregroundColor(.secondary).padding(.horizontal)
                    TextEditor(text: $viewModel.tempRoomDescription)
                        .frame(minHeight: 80)
                        .padding(.horizontal)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2))
                                .padding(.horizontal)
                        )
                        .accessibilityLabel("Room description")
                }

                TextField("Address (optional)", text: $viewModel.tempRoomAddress)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.words)
                    .padding(.horizontal)

                TextField("Floor of building (e.g., B1, Mezz, 2, PH)", text: $viewModel.tempRoomFloor)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.allCharacters)
                    .padding(.horizontal)

                Button {
                    viewModel.addRoom(name: viewModel.tempRoomName)
                } label: {
                    Label("Add Room", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(viewModel.tempRoomName.isEmpty ? 0.3 : 1.0))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(viewModel.tempRoomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal)
            }

            Spacer()

            Button {
                viewModel.completeRoomSetup()
            } label: {
                Text("Continue to Mapping")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.currentMap.rooms.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(12)
            }
            .disabled(viewModel.currentMap.rooms.isEmpty)
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    // MARK: - AR Mapping View
    private var arMappingView: some View {
        ZStack {
            ARViewContainer(viewModel: viewModel)
                .ignoresSafeArea()

            VStack {
                topControlsView
                Spacer()
                crosshairView
                Spacer()
                bottomControlsView
            }
            .padding()

            if viewModel.arSessionState != .running {
                arSessionStatusView
            }
        }
    }

    // MARK: - Doorway Details Sheet
    private var doorwayDetailsSheet: some View {
        NavigationView {
            Form {
                Section("Doorway Name") {
                    TextField("Enter doorway name", text: $viewModel.tempItemName)
                }

                Section("Width (meters)") {
                    HStack {
                        Slider(value: $viewModel.doorwayWidth, in: 0.5...3.0, step: 0.1)
                        Text(String(format: "%.1f m", viewModel.doorwayWidth)).frame(width: 60)
                    }
                }

                Section("Door Type") {
                    Picker("Type", selection: $viewModel.selectedDoorwayType) {
                        ForEach(DoorwayType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section(header: Text("Quick Setup")) {
                    VStack(spacing: 8) {
                        Button {
                            viewModel.setDoorAsHinged(pushFromCurrent: true)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.right.square")
                                Text("Standard Door (Push to Exit)")
                                Spacer()
                                if viewModel.selectedDoorAction == .push &&
                                   viewModel.selectedDoorActionFromOther == .pull {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                }
                            }
                        }
                        Button {
                            viewModel.setDoorAsHinged(pushFromCurrent: false)
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left.square")
                                Text("Standard Door (Pull to Exit)")
                                Spacer()
                                if viewModel.selectedDoorAction == .pull &&
                                   viewModel.selectedDoorActionFromOther == .push {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                }
                            }
                        }
                        Button {
                            viewModel.setDoorAsSwinging()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left.and.right")
                                Text("Swinging Door (Push Both Ways)")
                                Spacer()
                                if viewModel.selectedDoorAction == .push &&
                                   viewModel.selectedDoorActionFromOther == .push {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                }
                            }
                        }
                        Button {
                            viewModel.setDoorAsAutomatic()
                        } label: {
                            HStack {
                                Image(systemName: "sensor")
                                Text("Automatic Door")
                                Spacer()
                                if viewModel.selectedDoorAction == .automatic {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                }
                            }
                        }
                        Button {
                            viewModel.setDoorAsOpen()
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait")
                                Text("Open Doorway")
                                Spacer()
                                if viewModel.selectedDoorAction == .walkThrough {
                                    Image(systemName: "checkmark").foregroundColor(.green)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("Custom Actions")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("From \(viewModel.currentRoom?.name ?? "Current Room"):")
                            .font(.subheadline).foregroundColor(.secondary)
                        Picker("Action", selection: $viewModel.selectedDoorAction) {
                            ForEach(DoorAction.allCases, id: \.self) { action in
                                Text(action.displayName).tag(action)
                            }
                        }
                        .pickerStyle(.segmented)

                        Divider()

                        Text("From Other Room:")
                            .font(.subheadline).foregroundColor(.secondary)
                        Picker("Action", selection: $viewModel.selectedDoorActionFromOther) {
                            ForEach(DoorAction.allCases, id: \.self) { action in
                                Text(action.displayName).tag(action)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section {
                    Text("You'll select the destination room next")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Doorway Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.showingDoorwayDetails = false
                        viewModel.cancelPlacement()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Next") {
                        viewModel.showingDoorwayDetails = false
                        viewModel.confirmDoorwayPlacement()
                    }
                    .disabled(viewModel.tempItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Room Selector Sheet
    private var roomSelectorSheet: some View {
        NavigationView {
            List {
                ForEach(viewModel.currentMap.rooms) { room in
                    Button {
                        if viewModel.isCompletingDoorway {
                            viewModel.completeDoorwayWithDestinationRoom(toRoom: room.id.uuidString)
                        } else {
                            viewModel.selectRoom(id: room.id.uuidString)
                        }
                        viewModel.showingRoomSelector = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(room.name).font(.headline)
                                Text(room.type.displayName).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if viewModel.currentRoomId == room.id.uuidString {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isCompletingDoorway ? "Select Destination Room" : "Select Current Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        viewModel.showingRoomSelector = false
                        if viewModel.isCompletingDoorway {
                            viewModel.isCompletingDoorway = false
                            viewModel.cancelPlacement()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Top Controls
    private var topControlsView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.currentMap.name)
                    .font(.headline).foregroundColor(.white)

                if let room = viewModel.currentRoom {
                    HStack {
                        Image(systemName: "location.fill").font(.caption)
                        Text("\(room.name) (\(room.type.displayName))").font(.caption)
                    }
                    .foregroundColor(.white.opacity(0.9))
                }

                Text("\(viewModel.currentMap.beacons.count) beacons, \(viewModel.currentMap.doorways.count) doorways")
                    .font(.caption).foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Button { viewModel.showingRoomSelector = true } label: {
                Image(systemName: "square.grid.3x3").font(.title2).foregroundColor(.white)
                    .padding(8).background(.black.opacity(0.3)).clipShape(Circle())
            }

            Button { viewModel.resetARSession() } label: {
                Image(systemName: "arrow.clockwise").font(.title2).foregroundColor(.white)
                    .padding(8).background(.black.opacity(0.3)).clipShape(Circle())
            }
        }
        .padding()
        .background(.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Crosshair
    private var crosshairView: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 2).frame(width: 30, height: 30)
            Circle().fill(Color.white).frame(width: 4, height: 4)
            Rectangle().fill(Color.white).frame(width: 20, height: 1)
            Rectangle().fill(Color.white).frame(width: 1, height: 20)
        }
        .shadow(color: .black, radius: 2)
    }

    // MARK: - Bottom Controls
    private var bottomControlsView: some View {
        VStack(spacing: 16) {
            placementModeSelector

            if viewModel.placementMode == .beacon {
                beaconCategorySelector
            } else if viewModel.placementMode == .doorway {
                doorwayTypeSelector
            }

            placementInstructions

            HStack(spacing: 20) {
                Button {
                    viewModel.clearMap()
                } label: {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(.red)
                        .padding(12)
                        .background(.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .disabled(viewModel.currentMap.beacons.isEmpty && viewModel.currentMap.doorways.isEmpty)

                Spacer()
            }
        }
        .padding()
        .background(.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Placement Mode Selector
    private var placementModeSelector: some View {
        HStack(spacing: 0) {
            ForEach(PlacementMode.allCases, id: \.self) { mode in
                Button { viewModel.setPlacementMode(mode) } label: {
                    HStack { Image(systemName: mode.icon); Text(mode.displayName) }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(viewModel.placementMode == mode ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.placementMode == mode ? .white : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(4)
        .background(.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Category Selectors
    private var beaconCategorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BeaconCategory.allCases, id: \.self) { category in
                    Button { viewModel.selectedBeaconCategory = category } label: {
                        Text(category.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundColor(viewModel.selectedBeaconCategory == category ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.selectedBeaconCategory == category ? .white : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var doorwayTypeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DoorwayType.allCases.prefix(5), id: \.self) { type in
                    Button { viewModel.selectedDoorwayType = type } label: {
                        Text(type.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundColor(viewModel.selectedDoorwayType == type ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(viewModel.selectedDoorwayType == type ? .white : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Instructions
    private var placementInstructions: some View {
        VStack(spacing: 4) {
            if viewModel.currentRoom == nil {
                Text("Select a room first")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.orange)
            } else if viewModel.placementMode == .beacon {
                Text("Tap to place beacon").font(.subheadline.weight(.medium)).foregroundColor(.white)
                Text("Point at floor in \(viewModel.currentRoom?.name ?? "room")")
                    .font(.caption).foregroundColor(.white.opacity(0.8))
            } else if viewModel.placementMode == .doorway {
                Text("Tap doorway center").font(.subheadline.weight(.medium)).foregroundColor(.white)
                Text("Point at center of doorway opening").font(.caption).foregroundColor(.white.opacity(0.8))
            } else {
                Text("Tap to place waypoint").font(.subheadline.weight(.medium)).foregroundColor(.white)
                Text("Navigation guidance point").font(.caption).foregroundColor(.white.opacity(0.8))
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - AR Session Status
    private var arSessionStatusView: some View {
        VStack(spacing: 12) {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(1.2)
            Text(viewModel.arSessionState.displayName).font(.headline).foregroundColor(.white)
            if case .starting = viewModel.arSessionState {
                Text("Move your device to detect the floor")
                    .font(.subheadline).foregroundColor(.white.opacity(0.8)).multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(.black.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Save helpers
    private func saveMapWithName(_ name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        viewModel.updateMapName(trimmedName)
        viewModel.saveMap { _ in
            showingSaveConfirmation = true
            mapNameInput = ""
        }
    }

    private func saveMapWithCurrentName() {
        viewModel.saveMap { _ in
            showingSaveConfirmation = true
        }
    }
}

// MARK: - AR View Container
struct ARViewContainer: UIViewRepresentable {
    let viewModel: BuildMapViewModel
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.delegate = context.coordinator
        arView.session = viewModel.session
        arView.scene = SCNScene()
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
        
        // give the coordinator a reference so it can refresh on model changes
        context.coordinator.sceneViewRef = arView
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        context.coordinator.updateScene(uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
}

// MARK: - AR View Coordinator
extension ARViewContainer {
    @MainActor
    class Coordinator: NSObject, ARSCNViewDelegate {
        let viewModel: BuildMapViewModel
        private var beaconNodes: [UUID: SCNNode] = [:]
        private var doorwayNodes: [UUID: SCNNode] = [:]
        private var waypointNodes: [UUID: SCNNode] = [:]
        private var cancellables = Set<AnyCancellable>()
        weak var sceneViewRef: ARSCNView?

        init(viewModel: BuildMapViewModel) {
            self.viewModel = viewModel
            super.init()
            
            // Immediately refresh the scene whenever the map or "just-added" set changes
            viewModel.$currentMap
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, let sv = self.sceneViewRef else { return }
                    self.updateScene(sv)
                }
                .store(in: &cancellables)

            viewModel.$recentlyAddedIDs
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    guard let self, let sv = self.sceneViewRef else { return }
                    self.updateScene(sv)
                }
                .store(in: &cancellables)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView = gesture.view as? ARSCNView else { return }
            let location = gesture.location(in: sceneView)
            Task { @MainActor in
                viewModel.handleTap(at: location, in: sceneView)
            }
        }

        func updateScene(_ sceneView: ARSCNView) {
            Task { @MainActor in
                await updateBeaconNodes(sceneView)
                await updateDoorwayNodes(sceneView)
                await updateWaypointNodes(sceneView)
            }
        }

        // MARK: - Beacon Nodes
        @MainActor
        private func updateBeaconNodes(_ sceneView: ARSCNView) async {
            let currentBeaconIds = Set(viewModel.currentMap.beacons.map { $0.id })
            for (id, node) in beaconNodes where !currentBeaconIds.contains(id) {
                node.removeFromParentNode()
                beaconNodes.removeValue(forKey: id)
            }

            for beacon in viewModel.currentMap.beacons {
                if beaconNodes[beacon.id] == nil {
                    let node = createBeaconNode(for: beacon, isJustAdded: viewModel.recentlyAddedIDs.contains(beacon.id))
                    sceneView.scene.rootNode.addChildNode(node)
                    beaconNodes[beacon.id] = node
                }
            }
        }

        // MARK: - Doorway Nodes
        @MainActor
        private func updateDoorwayNodes(_ sceneView: ARSCNView) async {
            let currentDoorwayIds = Set(viewModel.currentMap.doorways.map { $0.id })
            for (id, node) in doorwayNodes where !currentDoorwayIds.contains(id) {
                node.removeFromParentNode()
                doorwayNodes.removeValue(forKey: id)
            }

            for doorway in viewModel.currentMap.doorways {
                if doorwayNodes[doorway.id] == nil {
                    let node = createDoorwayNode(for: doorway, isJustAdded: viewModel.recentlyAddedIDs.contains(doorway.id))
                    sceneView.scene.rootNode.addChildNode(node)
                    doorwayNodes[doorway.id] = node
                }
            }
        }

        // MARK: - Waypoint Nodes
        @MainActor
        private func updateWaypointNodes(_ sceneView: ARSCNView) async {
            let currentWaypointIds = Set(viewModel.currentMap.waypoints.map { $0.id })
            for (id, node) in waypointNodes where !currentWaypointIds.contains(id) {
                node.removeFromParentNode()
                waypointNodes.removeValue(forKey: id)
            }

            for waypoint in viewModel.currentMap.waypoints {
                if waypointNodes[waypoint.id] == nil {
                    let node = createWaypointNode(for: waypoint, isJustAdded: viewModel.recentlyAddedIDs.contains(waypoint.id))
                    sceneView.scene.rootNode.addChildNode(node)
                    waypointNodes[waypoint.id] = node
                }
            }
        }

        // MARK: - Helpers: Name banner (always faces camera) — SpriteKit-backed, flip-safe
        private func makeNameBannerNode(text: String, width metersW: CGFloat, height metersH: CGFloat, bg: UIColor) -> SCNNode {
            // Clamp & sanitize inputs
            let safeW: CGFloat = (metersW.isFinite && metersW > 0.01) ? metersW : 0.30
            let safeH: CGFloat = (metersH.isFinite && metersH > 0.01) ? metersH : 0.12
            let aspect: CGFloat = max(0.2, min(5.0, safeH / safeW))

            // Build SpriteKit scene (note: we draw with an internal Y-flip, so no material UV hacks)
            let pxW: CGFloat = 512
            let pxH: CGFloat = max(128, pxW * aspect)
            let sceneSize = CGSize(width: pxW, height: pxH)

            let skScene = SKScene(size: sceneSize)
            skScene.scaleMode = .resizeFill
            skScene.backgroundColor = .clear

            // Content root at center; flip Y once so rendered texture is upright in SceneKit
            let content = SKNode()
            content.position = CGPoint(x: pxW / 2, y: pxH / 2)
            content.yScale = -1.0   // <— key: correct SpriteKit/SceneKit coordinate mismatch
            skScene.addChild(content)

            // Rounded plate (centered geometry so flip doesn't affect layout)
            let inset: CGFloat = 10
            let rect = CGRect(x: -pxW/2 + inset, y: -pxH/2 + inset, width: pxW - inset*2, height: pxH - inset*2)
            let corner: CGFloat = min(pxW, pxH) * 0.15
            let plate = SKShapeNode(rect: rect, cornerRadius: corner)
            plate.fillColor = SKColor(cgColor: bg.cgColor).withAlphaComponent(0.85)
            plate.strokeColor = .white.withAlphaComponent(0.12)
            plate.lineWidth = 2
            plate.zPosition = 0
            content.addChild(plate)

            // Label (centered)
            let label = SKLabelNode(text: text.isEmpty ? " " : text)
            label.fontName = "HelveticaNeue-Medium"
            label.fontSize = min(48, pxH * 0.46)
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = .zero
            label.zPosition = 1
            content.addChild(label)

            // Plane in meters (no contentsTransform, no wrap hacks)
            let plane = SCNPlane(width: safeW, height: safeH)
            plane.cornerRadius = min(safeW, safeH) * 0.15
            plane.firstMaterial?.diffuse.contents = skScene
            plane.firstMaterial?.isDoubleSided = true
            plane.firstMaterial?.lightingModel = .physicallyBased
            plane.firstMaterial?.diffuse.mipFilter = .linear


            let node = SCNNode(geometry: plane)

            // Billboard only around Y so it can't flip upside-down when device pitches
            let bb = SCNBillboardConstraint()
            bb.freeAxes = .Y
            node.constraints = [bb]

            // Ensure positive scale (defensive: neutralize any negative scale from parents)
            node.scale = SCNVector3(1, 1, 1)

            // Gentle appear
            node.opacity = 0.0
            node.runAction(.fadeIn(duration: 0.15))
            return node
        }

        // MARK: - Helpers: Add highlight pulse (auto-removes)
        private func addHighlightPulse(to parent: SCNNode, color: UIColor = .systemYellow) {
            let ring = SCNTorus(ringRadius: 0.25, pipeRadius: 0.01)
            ring.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.9)
            let ringNode = SCNNode(geometry: ring)
            ringNode.eulerAngles = SCNVector3(-Float.pi/2, 0, 0) // flat on floor (Float.pi fix)
            ringNode.opacity = 0.0

            parent.addChildNode(ringNode)

            let expand = SCNAction.group([
                .fadeOpacity(to: 1.0, duration: 0.15),
                .scale(to: 1.2, duration: 0.2)
            ])
            let shrink = SCNAction.group([
                .fadeOut(duration: 0.6),
                .scale(to: 1.8, duration: 0.6)
            ])
            ringNode.runAction(.sequence([expand, shrink, .removeFromParentNode()]))
        }

        // MARK: - Create Nodes (with name banners + optional “just-added” large style)
        private func createBeaconNode(for beacon: Beacon, isJustAdded: Bool) -> SCNNode {
            let node = SCNNode()
            node.position = SCNVector3(beacon.position.x, beacon.position.y, beacon.position.z)

            // Larger pin if just added
            let sphereRadius: CGFloat = isJustAdded ? 0.12 : 0.06
            let marker = SCNSphere(radius: sphereRadius)
            let color = beacon.category.color
            let ui = beacon.isObstacle
                ? UIColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 0.95)
                : UIColor(red: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 0.95)
            marker.firstMaterial?.diffuse.contents = ui
            let markerNode = SCNNode(geometry: marker)
            markerNode.position = SCNVector3(0, Float(sphereRadius)*0.9, 0)
            node.addChildNode(markerNode)

            // Name banner
            let banner = makeNameBannerNode(text: beacon.name, width: 0.38, height: 0.12, bg: .black)
            banner.position = SCNVector3(0, Float(sphereRadius)*2.2, 0)
            node.addChildNode(banner)

            // Obstacle bounds (if any)
            if let props = beacon.physicalProperties, props.isObstacle {
                let boxGeometry = SCNBox(
                    width: CGFloat(props.boundingBox.width),
                    height: CGFloat(props.boundingBox.height),
                    length: CGFloat(props.boundingBox.depth),
                    chamferRadius: 0
                )
                boxGeometry.firstMaterial?.diffuse.contents = UIColor.red.withAlphaComponent(0.25)
                let boxNode = SCNNode(geometry: boxGeometry)
                boxNode.position = SCNVector3(0, props.boundingBox.height / 2, 0)
                node.addChildNode(boxNode)
            }

            if isJustAdded { addHighlightPulse(to: node) }
            return node
        }

        private func createWaypointNode(for waypoint: Waypoint, isJustAdded: Bool) -> SCNNode {
            let node = SCNNode()
            node.position = SCNVector3(waypoint.coordinates.x, waypoint.coordinates.y, waypoint.coordinates.z)

            let markerGeometry = SCNCone(topRadius: 0.0, bottomRadius: isJustAdded ? 0.12 : 0.07, height: isJustAdded ? 0.22 : 0.14)
            markerGeometry.firstMaterial?.diffuse.contents = UIColor.cyan.withAlphaComponent(0.95)
            let markerNode = SCNNode(geometry: markerGeometry)
            markerNode.eulerAngles = SCNVector3(Float.pi, 0, 0) // pointy up
            markerNode.position = SCNVector3(0, Float((isJustAdded ? 0.22 : 0.14) / 2), 0)
            node.addChildNode(markerNode)

            let banner = makeNameBannerNode(text: waypoint.name, width: 0.34, height: 0.11, bg: .black)
            banner.position = SCNVector3(0, (isJustAdded ? 0.32 : 0.24), 0)
            node.addChildNode(banner)

            if isJustAdded { addHighlightPulse(to: node, color: .systemTeal) }
            return node
        }

        private func createDoorwayNode(for doorway: Doorway, isJustAdded: Bool) -> SCNNode {
            let node = SCNNode()
            node.position = SCNVector3(doorway.position.x, doorway.position.y, doorway.position.z)
            
            // Pillar marker
            let markerGeometry = SCNCylinder(radius: isJustAdded ? 0.08 : 0.05, height: isJustAdded ? 0.18 : 0.1)
            let c = doorway.doorType.color
            markerGeometry.firstMaterial?.diffuse.contents = UIColor(
                red: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: 0.95
            )
            let markerNode = SCNNode(geometry: markerGeometry)
            markerNode.position = SCNVector3(0, Float(markerGeometry.height/2), 0)
            node.addChildNode(markerNode)
            
            // Width indicator line
            let widthLine = SCNCylinder(radius: 0.02, height: CGFloat(doorway.width))
            widthLine.firstMaterial?.diffuse.contents = UIColor(
                red: CGFloat(c.red), green: CGFloat(c.green), blue: CGFloat(c.blue), alpha: 0.7
            )
            let lineNode = SCNNode(geometry: widthLine)
            lineNode.position = SCNVector3(0, Float(markerGeometry.height/2), 0)
            lineNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            node.addChildNode(lineNode)
            
            // Name banner
            let banner = makeNameBannerNode(text: doorway.name, width: 0.42, height: 0.12, bg: .black)
            banner.position = SCNVector3(0, Float(markerGeometry.height) + 0.06, 0)
            node.addChildNode(banner)
            
            if isJustAdded { addHighlightPulse(to: node, color: .systemBlue) }
            return node
        }
    }
}

#Preview {
    BuildMapView()
}
