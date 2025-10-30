//
//  TriangulationSolver.swift
//  GuideLight v3
//
//  FIXED: Now uses BeaconSighting type
//

import Foundation
import simd

// MARK: - Triangulation Solver
class TriangulationSolver {
    
    // MARK: - Position Estimation
    
    /// Estimate user position from beacon sightings using triangulation
    static func estimatePosition(
        from sightings: [BeaconSighting],
        currentHeading: Float
    ) -> PositionEstimate? {
        
        // Need at least 2 sightings for triangulation
        guard sightings.count >= 2 else {
            print("⚠️ Need at least 2 beacon sightings for triangulation")
            return nil
        }
        
        // Filter to high confidence sightings
        let validSightings = sightings.highConfidence(threshold: 0.6)
        
        guard validSightings.count >= 2 else {
            print("⚠️ Not enough high-confidence sightings")
            return nil
        }
        
        print("🎯 Triangulating position from \(validSightings.count) sightings")
        
        // Use different methods based on available data
        if validSightings.count >= 3 {
            return multilateration(sightings: validSightings, heading: currentHeading)
        } else {
            return simpleTriangulation(sightings: validSightings, heading: currentHeading)
        }
    }
    
    // MARK: - Simple Triangulation (2 beacons)
    
    private static func simpleTriangulation(
        sightings: [BeaconSighting],
        heading: Float
    ) -> PositionEstimate? {
        
        guard sightings.count >= 2 else { return nil }
        
        let s1 = sightings[0]
        let s2 = sightings[1]
        
        // Get beacon positions
        let b1 = s1.beacon.position
        let b2 = s2.beacon.position
        
        // Convert sighting directions to world space using current heading
        let dir1 = rotateDirection(s1.direction, byHeading: heading)
        let dir2 = rotateDirection(s2.direction, byHeading: heading)
        
        // Find intersection point of two rays
        guard let intersection = rayIntersection(
            origin1: b1,
            direction1: -dir1,  // Ray from beacon to user
            origin2: b2,
            direction2: -dir2
        ) else {
            print("⚠️ No intersection found")
            return nil
        }
        
        // Calculate confidence based on intersection quality
        let confidence = calculateIntersectionConfidence(
            sighting1: s1,
            sighting2: s2,
            intersection: intersection
        )
        
        return PositionEstimate(
            position: simd_float2(intersection.x, intersection.z),
            confidence: confidence,
            heading: heading,
            method: .triangulation
        )
    }
    
    // MARK: - Multilateration (3+ beacons)
    
    private static func multilateration(
        sightings: [BeaconSighting],
        heading: Float
    ) -> PositionEstimate? {
        
        guard sightings.count >= 3 else { return nil }
        
        // Use weighted least squares to find best fit position
        var sumX: Float = 0
        var sumZ: Float = 0
        var totalWeight: Float = 0
        
        // Try all pairs of beacons
        for i in 0..<sightings.count {
            for j in (i+1)..<sightings.count {
                let s1 = sightings[i]
                let s2 = sightings[j]
                
                // Get pair triangulation
                if let pairEstimate = simpleTriangulation(
                    sightings: [s1, s2],
                    heading: heading
                ) {
                    let weight = pairEstimate.confidence
                    sumX += pairEstimate.position.x * weight
                    sumZ += pairEstimate.position.y * weight
                    totalWeight += weight
                }
            }
        }
        
        guard totalWeight > 0 else { return nil }
        
        let finalPosition = simd_float2(
            sumX / totalWeight,
            sumZ / totalWeight
        )
        
        // Calculate confidence based on consistency
        let confidence = calculateMultilaterationConfidence(
            sightings: sightings,
            estimatedPosition: finalPosition,
            heading: heading
        )
        
        return PositionEstimate(
            position: finalPosition,
            confidence: confidence,
            heading: heading,
            method: .multilateration
        )
    }
    
    // MARK: - Helper Methods
    
    /// Rotate a direction vector by a heading angle
    private static func rotateDirection(_ direction: simd_float3, byHeading heading: Float) -> simd_float3 {
        let cosH = cos(heading)
        let sinH = sin(heading)
        
        return simd_float3(
            direction.x * cosH - direction.z * sinH,
            direction.y,
            direction.x * sinH + direction.z * cosH
        )
    }
    
    /// Find intersection of two rays in 3D space (projected to 2D)
    private static func rayIntersection(
        origin1: simd_float3,
        direction1: simd_float3,
        origin2: simd_float3,
        direction2: simd_float3
    ) -> simd_float3? {
        
        // Project to 2D (XZ plane)
        let p1 = simd_float2(origin1.x, origin1.z)
        let p2 = simd_float2(origin2.x, origin2.z)
        let d1 = simd_float2(direction1.x, direction1.z)
        let d2 = simd_float2(direction2.x, direction2.z)
        
        // Solve for intersection parameters
        let denom = d1.x * d2.y - d1.y * d2.x
        
        // Check if rays are parallel
        guard abs(denom) > 0.001 else { return nil }
        
        let t = ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / denom
        
        // Calculate intersection point
        let intersection2D = p1 + t * d1
        
        // Use average Y from beacons
        let y = (origin1.y + origin2.y) / 2
        
        return simd_float3(intersection2D.x, y, intersection2D.y)
    }
    
    /// Calculate confidence for simple triangulation
    private static func calculateIntersectionConfidence(
        sighting1: BeaconSighting,
        sighting2: BeaconSighting,
        intersection: simd_float3
    ) -> Float {
        
        // Base confidence from sighting confidences
        let baseConfidence = (sighting1.confidence + sighting2.confidence) / 2
        
        // Check angle between rays (better if closer to 90°)
        let angle = acos(simd_dot(sighting1.direction, sighting2.direction))
        let idealAngle: Float = .pi / 2  // 90 degrees
        let angleDiff = abs(angle - idealAngle)
        let angleQuality = max(0, 1 - angleDiff / (.pi / 2))
        
        // Check distance consistency if available
        var distanceQuality: Float = 1.0
        if let d1 = sighting1.distance, let d2 = sighting2.distance {
            let calculatedD1 = simd_distance(intersection, sighting1.beacon.position)
            let calculatedD2 = simd_distance(intersection, sighting2.beacon.position)
            
            let error1 = abs(d1 - calculatedD1) / d1
            let error2 = abs(d2 - calculatedD2) / d2
            distanceQuality = max(0, 1 - (error1 + error2) / 2)
        }
        
        // Combine factors
        return baseConfidence * 0.5 + angleQuality * 0.3 + distanceQuality * 0.2
    }
    
    /// Calculate confidence for multilateration
    private static func calculateMultilaterationConfidence(
        sightings: [BeaconSighting],
        estimatedPosition: simd_float2,
        heading: Float
    ) -> Float {
        
        // Check consistency of all sightings with estimated position
        var totalError: Float = 0
        var count: Float = 0
        
        for sighting in sightings {
            let beaconPos2D = simd_float2(
                sighting.beacon.position.x,
                sighting.beacon.position.z
            )
            
            // Calculate expected direction from position to beacon
            let expectedDir = simd_normalize(beaconPos2D - estimatedPosition)
            
            // Rotate sighting direction to world space
            let worldDir = rotateDirection(sighting.direction, byHeading: heading)
            let worldDir2D = simd_normalize(simd_float2(worldDir.x, worldDir.z))
            
            // Calculate angular error
            let dotProduct = simd_dot(expectedDir, worldDir2D)
            let angularError = acos(max(-1, min(1, dotProduct)))
            
            totalError += angularError
            count += 1
        }
        
        let avgError = totalError / count
        
        // Convert error to confidence (lower error = higher confidence)
        let maxAcceptableError: Float = .pi / 6  // 30 degrees
        return max(0, 1 - avgError / maxAcceptableError)
    }
}

// MARK: - Position Estimate
struct PositionEstimate {
    let position: simd_float2
    let confidence: Float
    let heading: Float
    let method: TriangulationMethod
    let timestamp: Date
    
    init(position: simd_float2, confidence: Float, heading: Float, method: TriangulationMethod) {
        self.position = position
        self.confidence = confidence
        self.heading = heading
        self.method = method
        self.timestamp = Date()
    }
    
    var position3D: simd_float3 {
        return simd_float3(position.x, 0, position.y)
    }
}

// MARK: - Triangulation Method
enum TriangulationMethod {
    case triangulation      // 2 beacons
    case multilateration    // 3+ beacons
    case kalmanFiltered     // Filtered over time
}
