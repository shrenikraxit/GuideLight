//
//  CalibrationARView.swift
//  GuideLight v3
//
//  FIXED: MainActor isolation, UUID comparison, and session.run arguments
//

import SwiftUI
import ARKit
import SceneKit

// MARK: - Calibration AR View
struct CalibrationARView: UIViewRepresentable {
    @ObservedObject var viewModel: CalibrationViewModel
    let session: ARSession
    let mapFileName: String
    
    func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView()
        arView.session = session
        arView.delegate = context.coordinator
        arView.scene = SCNScene()
        
        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic
        configuration.worldAlignment = .gravity
        
        // Enable scene reconstruction if available
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
        }
        
        // Load ARWorldMap if available
        if let arWorldMap = context.coordinator.loadARWorldMap(fileName: mapFileName) {
            configuration.initialWorldMap = arWorldMap
            print("✅ Loaded ARWorldMap for calibration: \(mapFileName)")
        } else {
            print("⚠️ No ARWorldMap found, starting fresh tracking")
        }
        
        // Run session with configuration
        // FIXED: Removed invalid arguments from run()
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        
        return arView
    }
    
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        // Update happens via delegate callbacks
        Task { @MainActor in
            context.coordinator.updateBeaconVisualizations(in: uiView)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, session: session)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        let viewModel: CalibrationViewModel
        let session: ARSession
        private var beaconNodes: [UUID: SCNNode] = [:]
        
        init(viewModel: CalibrationViewModel, session: ARSession) {
            self.viewModel = viewModel
            self.session = session
            super.init()
            session.delegate = self
        }
        
        // MARK: - ARWorldMap Loading
        func loadARWorldMap(fileName: String) -> ARWorldMap? {
            guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("❌ Failed to get documents directory")
                return nil
            }
            
            let arWorldMapsPath = documentsPath
                .appendingPathComponent("ARWorldMaps")
                .appendingPathComponent(fileName)
            
            guard FileManager.default.fileExists(atPath: arWorldMapsPath.path) else {
                print("⚠️ ARWorldMap file not found: \(fileName)")
                return nil
            }
            
            do {
                let data = try Data(contentsOf: arWorldMapsPath)
                guard let worldMap = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: data) else {
                    print("❌ Failed to unarchive ARWorldMap")
                    return nil
                }
                
                print("✅ Successfully loaded ARWorldMap")
                print("   Anchors: \(worldMap.anchors.count)")
                print("   Feature points: \(worldMap.rawFeaturePoints.points.count)")
                
                return worldMap
            } catch {
                print("❌ Failed to load ARWorldMap: \(error)")
                return nil
            }
        }
        
        // MARK: - ARSessionDelegate
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            DispatchQueue.main.async {
                // Update AR tracking state
                self.viewModel.updateARTracking(
                    state: frame.camera.trackingState,
                    frame: frame
                )
                
                // Update alignment if measuring
                if case .measuringBeacon = self.viewModel.calibrationState {
                    self.viewModel.updateAlignment(from: frame)
                }
            }
        }
        
        func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
            DispatchQueue.main.async {
                let state = camera.trackingState
                print("🔍 AR Tracking State Changed: \(state)")
                
                switch state {
                case .normal:
                    print("   ✅ Normal tracking")
                case .limited(let reason):
                    print("   ⚠️ Limited tracking: \(reason)")
                case .notAvailable:
                    print("   ❌ Tracking not available")
                }
            }
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            print("❌ AR Session failed: \(error.localizedDescription)")
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            print("⚠️ AR Session interrupted")
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            print("✅ AR Session interruption ended")
        }
        
        // MARK: - Beacon Visualizations
        func updateBeaconVisualizations(in arView: ARSCNView) {
            // Access MainActor properties safely
            Task { @MainActor in
                let candidateBeacons = self.viewModel.candidateBeacons
                
                // Process on background thread
                Task.detached {
                    let currentBeaconIds = Set(candidateBeacons.map { $0.beacon.id })
                    let existingBeaconIds = Set(self.beaconNodes.keys)
                    
                    // Remove old nodes
                    await MainActor.run {
                        for beaconId in existingBeaconIds {
                            if !currentBeaconIds.contains(beaconId) {
                                self.beaconNodes[beaconId]?.removeFromParentNode()
                                self.beaconNodes.removeValue(forKey: beaconId)
                            }
                        }
                        
                        // Add/update nodes for current beacons
                        for candidateBeacon in candidateBeacons {
                            let beaconId = candidateBeacon.beacon.id
                            
                            if self.beaconNodes[beaconId] == nil {
                                let node = self.createBeaconNode(for: candidateBeacon)
                                arView.scene.rootNode.addChildNode(node)
                                self.beaconNodes[beaconId] = node
                            } else {
                                // Update existing node highlighting if needed
                                self.updateBeaconNodeHighlight(beaconId: beaconId, candidateBeacons: candidateBeacons, in: arView)
                            }
                        }
                    }
                }
            }
        }
        
        private func createBeaconNode(for candidateBeacon: CandidateBeacon) -> SCNNode {
            let beacon = candidateBeacon.beacon
            let node = SCNNode()
            node.position = SCNVector3(
                beacon.position.x,
                beacon.position.y,
                beacon.position.z
            )
            
            // Create pole
            let poleGeometry = SCNCylinder(radius: 0.02, height: 0.5)
            poleGeometry.firstMaterial?.diffuse.contents = UIColor.darkGray
            let poleNode = SCNNode(geometry: poleGeometry)
            poleNode.position = SCNVector3(0, 0.25, 0)
            node.addChildNode(poleNode)
            
            // Create sphere at top
            let sphereGeometry = SCNSphere(radius: 0.1)
            sphereGeometry.firstMaterial?.diffuse.contents = UIColor.blue
            sphereGeometry.firstMaterial?.emission.contents = UIColor.blue
            let sphereNode = SCNNode(geometry: sphereGeometry)
            sphereNode.position = SCNVector3(0, 0.55, 0)
            node.addChildNode(sphereNode)
            
            // Create label
            let textGeometry = SCNText(string: beacon.name, extrusionDepth: 0.01)
            textGeometry.font = UIFont.systemFont(ofSize: 0.08)
            textGeometry.firstMaterial?.diffuse.contents = UIColor.white
            let textNode = SCNNode(geometry: textGeometry)
            textNode.position = SCNVector3(-0.1, 0.65, 0)
            textNode.scale = SCNVector3(0.01, 0.01, 0.01)
            node.addChildNode(textNode)
            
            return node
        }
        
        private func updateBeaconNodeHighlight(beaconId: UUID, candidateBeacons: [CandidateBeacon], in arView: ARSCNView) {
            guard let node = beaconNodes[beaconId] else { return }
            
            // Access calibrationState safely
            Task { @MainActor in
                let calibrationState = self.viewModel.calibrationState
                
                // Check if this is the current beacon being measured
                if case .measuringBeacon(let index, _) = calibrationState {
                    let currentBeacon = candidateBeacons[index]
                    let isCurrentBeacon = currentBeacon.beacon.id == beaconId
                    
                    // Highlight current beacon
                    if let sphereNode = node.childNodes.first(where: { $0.geometry is SCNSphere }) {
                        let color = isCurrentBeacon ? UIColor.green : UIColor.blue
                        sphereNode.geometry?.firstMaterial?.diffuse.contents = color
                        sphereNode.geometry?.firstMaterial?.emission.contents = color
                    }
                }
            }
        }
        
        // MARK: - ARSCNViewDelegate
        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            // Update visualizations
        }
    }
}

#Preview {
    let sampleMap = IndoorMap(name: "Sample")
    let viewModel = CalibrationViewModel(
        map: sampleMap,
        relocalizationManager: ARRelocalizationManager()
    )
    
    return CalibrationARView(
        viewModel: viewModel,
        session: ARSession(),
        mapFileName: "sample.arworldmap"
    )
}
