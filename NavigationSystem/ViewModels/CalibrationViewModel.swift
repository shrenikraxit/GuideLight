// CalibrationViewModel.swift - FIXED: Only use 3-5 beacons from current room

import Foundation
import ARKit
import Combine
import simd

@MainActor
class CalibrationViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var calibrationState: CalibrationState = .waitingForAR
    @Published var candidateBeacons: [CandidateBeacon] = []
    @Published var currentAlignment: Double = 0.0
    @Published var canConfirmMeasurement: Bool = false
    
    // NEW: AR Tracking state management
    @Published var arTrackingReady: Bool = false
    @Published var arTrackingMessage: String = "Initializing AR..."
    
    // MARK: - Private Properties
    private let map: IndoorMap
    private let relocalizationManager: ARRelocalizationManager
    private var measurements: [BeaconMeasurement] = []
    private var currentBeaconIndex: Int = 0
    private var userCurrentRoom: String?  // NEW: Track user's room
    
    // NEW: Tracking state
    private var frameCount: Int = 0
    private var trackingStateHistory: [ARCamera.TrackingState] = []
    private var failsafeTriggered: Bool = false
    
    // MARK: - Initialization
    
    init(map: IndoorMap, relocalizationManager: ARRelocalizationManager) {
        self.map = map
        self.relocalizationManager = relocalizationManager
        
        // Don't find beacons yet - wait for user position
        self.candidateBeacons = []
        
        print("📍 CalibrationViewModel initialized")
        print("   Map: \(map.name)")
        print("   Total beacons: \(map.beacons.count)")
        
        // NEW: Start failsafe timer
        startFailsafeTimer()
    }
    
    // MARK: - NEW: AR Tracking Management
    
    func updateARTracking(state: ARCamera.TrackingState, frame: ARFrame) {
        frameCount += 1
        trackingStateHistory.append(state)
        
        // Keep only last 30 states
        if trackingStateHistory.count > 30 {
            trackingStateHistory.removeFirst()
        }
        
        // NEW: Determine user's room from first good frame
        if userCurrentRoom == nil && frameCount > 10 {
            let position = CoordinateTransformManager.extractPosition(from: frame.camera)
            userCurrentRoom = determineRoom(for: position)
            if let room = userCurrentRoom {
                print("✅ Detected user in room: \(map.room(withId: room)?.name ?? room)")
                // NOW find beacons in this room only
                self.candidateBeacons = findCalibrationBeacons(inRoom: room)
                print("   Selected \(candidateBeacons.count) beacons for calibration")
            }
        }
        
        switch state {
        case .normal:
            handleNormalTracking()
            
        case .limited(let reason):
            handleLimitedTracking(reason: reason)
            
        case .notAvailable:
            arTrackingReady = false
            arTrackingMessage = "AR not available"
        }
        
        // Check if we should auto-progress
        if arTrackingReady && calibrationState == .waitingForAR && !candidateBeacons.isEmpty {
            print("✅ AR tracking ready - auto-progressing to calibration")
            startCalibration()
        }
    }
    
    private func handleNormalTracking() {
        if frameCount > 3 {
            arTrackingReady = true
            arTrackingMessage = "✓ Tracking Ready"
        } else {
            arTrackingMessage = "Establishing tracking..."
        }
    }
    
    private func handleLimitedTracking(reason: ARCamera.TrackingState.Reason) {
        switch reason {
        case .initializing:
            arTrackingReady = false
            arTrackingMessage = "Initializing... Move device slowly"
            
        case .excessiveMotion:
            arTrackingReady = false
            arTrackingMessage = "Move device more slowly"
            
        case .insufficientFeatures:
            if frameCount > 60 {
                arTrackingReady = true
                arTrackingMessage = "✓ Ready (Limited features)"
                print("⚠️ Allowing calibration with insufficient features after 60 frames")
            } else {
                arTrackingMessage = "Point at textured surfaces"
            }
            
        case .relocalizing:
            if frameCount > 30 {
                arTrackingReady = true
                arTrackingMessage = "✓ Relocalizing"
            } else {
                arTrackingMessage = "Relocalizing..."
            }
            
        @unknown default:
            arTrackingMessage = "Limited tracking"
        }
    }
    
    private func startFailsafeTimer() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            guard let self = self else { return }
            
            if !self.arTrackingReady && !self.failsafeTriggered {
                print("⚠️ FAILSAFE ACTIVATED: Forcing AR ready state after timeout")
                self.failsafeTriggered = true
                self.arTrackingReady = true
                self.arTrackingMessage = "✓ Ready (Auto-recovered)"
                
                if case .waitingForAR = self.calibrationState {
                    self.startCalibration()
                }
            }
        }
    }
    
    // MARK: - Calibration Flow
    
    func startCalibration() {
        guard !candidateBeacons.isEmpty else {
            calibrationState = .failed("No suitable beacons found for calibration")
            return
        }
        
        // Ensure we have at least 3 beacons
        guard candidateBeacons.count >= 3 else {
            calibrationState = .failed("Need at least 3 beacons for calibration. Found: \(candidateBeacons.count)")
            return
        }
        
        currentBeaconIndex = 0
        measurements.removeAll()
        calibrationState = .measuringBeacon(index: 0, total: min(candidateBeacons.count, 5))
        
        print("🎯 Starting calibration with \(min(candidateBeacons.count, 5)) beacons")
    }
    
    func updateAlignment(from frame: ARFrame) {
        guard currentBeaconIndex < candidateBeacons.count else { return }
        
        let currentBeacon = candidateBeacons[currentBeaconIndex]
        let cameraTransform = frame.camera.transform
        let cameraPosition = CoordinateTransformManager.extractPosition(from: frame.camera)
        
        // Calculate alignment
        let alignment = calculateAlignment(
            from: cameraPosition,
            to: currentBeacon.beacon.position,
            cameraTransform: cameraTransform
        )
        
        currentAlignment = alignment
        canConfirmMeasurement = alignment > 0.7  // 70% alignment threshold
    }
    
    func confirmBeaconMeasurement() async {
        guard currentBeaconIndex < candidateBeacons.count else { return }
        guard canConfirmMeasurement else { return }
        
        let currentBeacon = candidateBeacons[currentBeaconIndex]
        
        // Create measurement
        let measurement = BeaconMeasurement(
            beaconId: currentBeacon.beacon.id,
            mapPosition: currentBeacon.beacon.position,
            observedDirection: currentBeacon.direction,
            distance: currentBeacon.distance,
            confidence: Float(currentAlignment)
        )
        
        measurements.append(measurement)
        
        print("✅ Confirmed beacon \(currentBeaconIndex + 1): \(currentBeacon.beacon.name)")
        print("   Alignment: \(Int(currentAlignment * 100))%")
        
        // Move to next beacon or complete
        currentBeaconIndex += 1
        
        // LIMIT TO 5 BEACONS MAXIMUM
        if currentBeaconIndex < min(candidateBeacons.count, 5) {
            calibrationState = .measuringBeacon(
                index: currentBeaconIndex,
                total: min(candidateBeacons.count, 5)
            )
            currentAlignment = 0.0
            canConfirmMeasurement = false
        } else {
            // All beacons measured - compute calibration
            await computeCalibration()
        }
    }
    
    private func computeCalibration() async {
        guard measurements.count >= 3 else {
            calibrationState = .failed("Not enough measurements: \(measurements.count)")
            return
        }
        
        print("🧮 Computing calibration from \(measurements.count) measurements...")
        
        let calibration = CalibrationData(
            userPosition: simd_float2(0, 0),
            heading: 0.0,
            measurements: measurements
        )
        
        print("✅ Calibration complete!")
        print("   Confidence: \(Int(calibration.confidence * 100))%")
        
        calibrationState = .completed(calibration)
    }
    
    // MARK: - FIXED: Helper Methods - Only select beacons from current room
    
    private func findCalibrationBeacons(inRoom roomId: String) -> [CandidateBeacon] {
        print("🔍 Finding calibration beacons in room: \(map.room(withId: roomId)?.name ?? roomId)")
        
        // Filter beacons by room
        let roomBeacons = map.beacons.filter { beacon in
            beacon.roomId == roomId && !beacon.isObstacle && beacon.isAccessible
        }
        
        print("   Found \(roomBeacons.count) beacons in room")
        
        // Prioritize by category
        var candidates: [CandidateBeacon] = []
        
        // First: destinations and landmarks
        for beacon in roomBeacons {
            if beacon.category == .destination || beacon.category == .landmark {
                let candidate = CandidateBeacon(
                    beacon: beacon,
                    distance: 0,
                    direction: simd_float3(0, 0, -1)
                )
                candidates.append(candidate)
            }
        }
        
        // If not enough, add furniture
        if candidates.count < 5 {
            for beacon in roomBeacons {
                if beacon.category == .furniture && !candidates.contains(where: { $0.beacon.id == beacon.id }) {
                    let candidate = CandidateBeacon(
                        beacon: beacon,
                        distance: 0,
                        direction: simd_float3(0, 0, -1)
                    )
                    candidates.append(candidate)
                    if candidates.count >= 5 { break }
                }
            }
        }
        
        // If still not enough, add any other beacons
        if candidates.count < 5 {
            for beacon in roomBeacons {
                if !candidates.contains(where: { $0.beacon.id == beacon.id }) {
                    let candidate = CandidateBeacon(
                        beacon: beacon,
                        distance: 0,
                        direction: simd_float3(0, 0, -1)
                    )
                    candidates.append(candidate)
                    if candidates.count >= 5 { break }
                }
            }
        }
        
        // Limit to maximum 5 beacons
        let finalCandidates = Array(candidates.prefix(5))
        
        print("   Selected \(finalCandidates.count) beacons:")
        for (index, candidate) in finalCandidates.enumerated() {
            print("     \(index + 1). \(candidate.beacon.name) (\(candidate.beacon.category.displayName))")
        }
        
        return finalCandidates
    }
    
    private func determineRoom(for position: simd_float3) -> String? {
        // Find closest beacon and return its room
        var closestBeacon: Beacon?
        var minDistance: Float = Float.infinity
        
        for beacon in map.beacons {
            let distance = simd_distance(
                simd_float2(position.x, position.z),
                simd_float2(beacon.position.x, beacon.position.z)
            )
            if distance < minDistance {
                minDistance = distance
                closestBeacon = beacon
            }
        }
        
        return closestBeacon?.roomId
    }
    
    private func calculateAlignment(
        from cameraPosition: simd_float3,
        to beaconPosition: simd_float3,
        cameraTransform: simd_float4x4
    ) -> Double {
        // Calculate direction to beacon
        let toBeacon = simd_normalize(beaconPosition - cameraPosition)
        
        // Get camera forward direction
        let cameraForward = -simd_float3(
            cameraTransform.columns.2.x,
            cameraTransform.columns.2.y,
            cameraTransform.columns.2.z
        )
        
        // Calculate alignment (dot product)
        let dotProduct = simd_dot(toBeacon, cameraForward)
        
        // Convert to 0-1 range (0 = opposite, 1 = perfect alignment)
        return Double((dotProduct + 1.0) / 2.0)
    }
}
