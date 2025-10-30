//
//  ARRelocalizationManager.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/12/25.
//


import Foundation
import ARKit
import Combine

// MARK: - AR Relocalization Manager
@MainActor
class ARRelocalizationManager: NSObject, ObservableObject {
    
    @Published var relocalizationState: RelocalizationState = .notStarted
    @Published var mappingStatus: ARFrame.WorldMappingStatus = .notAvailable
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var relocalizationProgress: Float = 0.0
    
    private var arSession: ARSession?
    private var loadedWorldMap: ARWorldMap?
    
    enum RelocalizationState {
        case notStarted
        case loading
        case relocating
        case mapped
        case failed(String)
        
        var displayMessage: String {
            switch self {
            case .notStarted:
                return "Ready to start"
            case .loading:
                return "Loading ARWorldMap..."
            case .relocating:
                return "Relocating... Move device slowly"
            case .mapped:
                return "Relocalized successfully"
            case .failed(let error):
                return "Failed_ARRelocalization: \(error)"
            }
        }
        
        var isReady: Bool {
            if case .mapped = self {
                return true
            }
            return false
        }
    }
    
    // MARK: - Load and Relocalize
    
    func loadAndRelocalize(mapFileName: String, session: ARSession) async throws {
        self.arSession = session
        session.delegate = self
        
        // Load ARWorldMap
        relocalizationState = .loading
        
        return try await withCheckedThrowingContinuation { continuation in
            SimpleJSONMapManager.shared.loadARWorldMap(fileName: mapFileName) { [weak self] (result: Result<ARWorldMap, ARWorldMapError>) in
                guard let self = self else { return }
                
                Task { @MainActor in
                    switch result {
                    case .success(let worldMap):
                        self.loadedWorldMap = worldMap
                        print("✅ ARWorldMap loaded successfully")
                        print("   Anchors: \(worldMap.anchors.count)")
                        print("   Feature points: \(worldMap.rawFeaturePoints.points.count)")
                        
                        // Configure and run AR session
                        let configuration = ARWorldTrackingConfiguration()
                        configuration.planeDetection = [.horizontal]
                        configuration.initialWorldMap = worldMap
                        
                        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
                        
                        self.relocalizationState = .relocating
                        continuation.resume()
                        
                    case .failure(let error):
                        print("❌ Failed to load ARWorldMap: \(error)")
                        self.relocalizationState = .failed(error.localizedDescription)
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    // MARK: - Status Monitoring
    
    func updateRelocalizationProgress() {
        switch mappingStatus {
        case .notAvailable:
            relocalizationProgress = 0.0
        case .limited:
            relocalizationProgress = 0.3
        case .extending:
            relocalizationProgress = 0.7
        case .mapped:
            relocalizationProgress = 1.0
            if case .relocating = relocalizationState {
                relocalizationState = .mapped
                print("✅ Relocalization complete")
            }
        @unknown default:
            relocalizationProgress = 0.0
        }
    }
    
    func getTrackingQuality() -> UserPositionUpdate.TrackingQuality {
        switch trackingState {
        case .normal:
            return .excellent
        case .limited(.initializing):
            return .limited
        case .limited(.insufficientFeatures):
            return .poor
        case .limited(.excessiveMotion):
            return .limited
        case .limited(.relocalizing):
            return .limited
        case .notAvailable:
            return .poor
        @unknown default:
            return .poor
        }
    }
    
    func isReadyForCalibration() -> Bool {
        return relocalizationState.isReady && 
               (mappingStatus == .mapped || mappingStatus == .extending) &&
               trackingState == .normal
    }
}

// MARK: - ARSessionDelegate
extension ARRelocalizationManager: ARSessionDelegate {
    
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.mappingStatus = frame.worldMappingStatus
            self.trackingState = frame.camera.trackingState
            self.updateRelocalizationProgress()
        }
    }
    
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in
            print("❌ AR Session failed: \(error.localizedDescription)")
            self.relocalizationState = .failed(error.localizedDescription)
        }
    }
    
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in
            print("⚠️ AR Session interrupted")
        }
    }
    
    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor in
            print("✅ AR Session interruption ended")
        }
    }
}
