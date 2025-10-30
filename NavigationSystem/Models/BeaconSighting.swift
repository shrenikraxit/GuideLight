//
//  BeaconSighting.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/13/25.
//


//
//  BeaconSighting.swift
//  GuideLight v3
//
//  Represents a beacon observation from the user's perspective
//

import Foundation
import simd

// MARK: - Beacon Sighting
struct BeaconSighting {
    let beacon: Beacon
    let direction: simd_float3  // Observed direction vector to beacon
    let distance: Float?        // Estimated distance (if available)
    let confidence: Float       // Confidence in this sighting (0-1)
    let timestamp: Date
    
    init(beacon: Beacon, direction: simd_float3, distance: Float? = nil, confidence: Float = 1.0) {
        self.beacon = beacon
        self.direction = simd_normalize(direction)  // Ensure normalized
        self.distance = distance
        self.confidence = confidence
        self.timestamp = Date()
    }
    
    // Helper: Create from bearing angle
    init(beacon: Beacon, bearing: Float, distance: Float? = nil, confidence: Float = 1.0) {
        self.beacon = beacon
        // Convert bearing to direction vector (assuming Y-up coordinate system)
        self.direction = simd_float3(
            sin(bearing),
            0,
            cos(bearing)
        )
        self.distance = distance
        self.confidence = confidence
        self.timestamp = Date()
    }
    
    // Helper: Calculate bearing from direction
    var bearing: Float {
        return atan2(direction.x, direction.z)
    }
    
    // Helper: Check if sighting is recent
    func isRecent(within seconds: TimeInterval) -> Bool {
        return Date().timeIntervalSince(timestamp) < seconds
    }
}

// MARK: - Beacon Sighting Collection
extension Array where Element == BeaconSighting {
    /// Filter to only recent sightings
    func recent(within seconds: TimeInterval) -> [BeaconSighting] {
        return filter { $0.isRecent(within: seconds) }
    }
    
    /// Filter to high confidence sightings
    func highConfidence(threshold: Float = 0.7) -> [BeaconSighting] {
        return filter { $0.confidence >= threshold }
    }
    
    /// Get sightings sorted by confidence (highest first)
    func sortedByConfidence() -> [BeaconSighting] {
        return sorted { $0.confidence > $1.confidence }
    }
}