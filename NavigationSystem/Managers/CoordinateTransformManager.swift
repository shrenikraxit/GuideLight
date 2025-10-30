//
//  CoordinateTransformManager.swift
//  GuideLight v3
//
//  FIXED: Added extensive debugging for heading calculations
//

import Foundation
import ARKit
import simd

// MARK: - Coordinate Transform Manager
class CoordinateTransformManager {
    
    // MARK: - Map to AR Coordinate Transformation
    
    static func mapToAR(
        mapPosition: simd_float2,
        calibration: CalibrationData
    ) -> simd_float3 {
        let relativePosition = mapPosition - calibration.userPosition
        let rotated = rotatePoint(relativePosition, byAngle: calibration.heading)
        return simd_float3(rotated.x, 0, rotated.y)
    }
    
    static func arToMap(
        arPosition: simd_float3,
        calibration: CalibrationData
    ) -> simd_float2 {
        let position2D = simd_float2(arPosition.x, arPosition.z)
        let rotated = rotatePoint(position2D, byAngle: -calibration.heading)
        return rotated + calibration.userPosition
    }
    
    // MARK: - Direction Transformation
    
    static func mapDirectionToAR(
        direction: simd_float2,
        calibration: CalibrationData
    ) -> simd_float3 {
        let rotated = rotatePoint(direction, byAngle: calibration.heading)
        return simd_float3(rotated.x, 0, rotated.y)
    }
    
    static func arDirectionToMap(
        direction: simd_float3,
        calibration: CalibrationData
    ) -> simd_float2 {
        let direction2D = simd_float2(direction.x, direction.z)
        return rotatePoint(direction2D, byAngle: -calibration.heading)
    }
    
    // MARK: - Heading Transformation
    
    static func mapHeadingToAR(
        heading: Float,
        calibration: CalibrationData
    ) -> Float {
        return normalizeAngle(heading + calibration.heading)
    }
    
    static func arHeadingToMap(
        heading: Float,
        calibration: CalibrationData
    ) -> Float {
        return normalizeAngle(heading - calibration.heading)
    }
    
    // MARK: - Camera Utilities
    
    static func extractPosition(from camera: ARCamera) -> simd_float3 {
        let transform = camera.transform
        return simd_float3(
            transform.columns.3.x,
            transform.columns.3.y,
            transform.columns.3.z
        )
    }
    
    /// Extract heading (yaw) from AR camera - FIXED: Proper angle calculation
    static func extractHeading(from camera: ARCamera) -> Float {
        let transform = camera.transform
        
        // Get forward direction (negative Z in camera space)
        let forward = -simd_float3(
            transform.columns.2.x,
            transform.columns.2.y,
            transform.columns.2.z
        )
        
        // Calculate heading (rotation around Y axis)
        // atan2(x, z) gives angle from north (positive Z axis)
        let heading = atan2(forward.x, forward.z)
        
        print("🧭 DEBUG Camera Heading:")
        print("   Forward vector: (\(forward.x), \(forward.z))")
        print("   Raw heading: \(heading * 180 / .pi)°")
        
        return heading
    }
    
    static func extractDirection(from camera: ARCamera) -> simd_float3 {
        let transform = camera.transform
        return -simd_float3(
            transform.columns.2.x,
            transform.columns.2.y,
            transform.columns.2.z
        )
    }
    
    // MARK: - Distance and Bearing
    
    static func distance(from: simd_float2, to: simd_float2) -> Float {
        return simd_distance(from, to)
    }
    
    /// Calculate bearing from one position to another - FIXED: Proper bearing calculation
    static func bearing(from: simd_float2, to: simd_float2) -> Float {
        let delta = to - from
        // atan2(x, y) where y is "forward" (positive Z in world)
        let bearing = atan2(delta.x, delta.y)
        
        print("🎯 DEBUG Bearing Calculation:")
        print("   From: (\(from.x), \(from.y))")
        print("   To: (\(to.x), \(to.y))")
        print("   Delta: (\(delta.x), \(delta.y))")
        print("   Bearing: \(bearing * 180 / .pi)°")
        
        return bearing
    }
    
    /// Calculate relative bearing - FIXED: Proper sign convention
    static func relativeBearing(
        from: simd_float2,
        to: simd_float2,
        currentHeading: Float
    ) -> Float {
        let absoluteBearing = bearing(from: from, to: to)
        let relative = normalizeAngle(absoluteBearing - currentHeading)
        
        print("📐 DEBUG Relative Bearing:")
        print("   Current heading: \(currentHeading * 180 / .pi)°")
        print("   Absolute bearing: \(absoluteBearing * 180 / .pi)°")
        print("   Relative bearing: \(relative * 180 / .pi)°")
        print("   → Meaning: Turn \(relative > 0 ? "RIGHT" : "LEFT") by \(abs(relative * 180 / .pi))°")
        
        return relative
    }
    
    // MARK: - Helper Methods
    
    private static func rotatePoint(_ point: simd_float2, byAngle angle: Float) -> simd_float2 {
        let cos = cosf(angle)
        let sin = sinf(angle)
        
        return simd_float2(
            point.x * cos - point.y * sin,
            point.x * sin + point.y * cos
        )
    }
    
    static func normalizeAngle(_ angle: Float) -> Float {
        var normalized = angle
        while normalized > .pi {
            normalized -= 2 * .pi
        }
        while normalized < -.pi {
            normalized += 2 * .pi
        }
        return normalized
    }
    
    static func angleDifference(_ angle1: Float, _ angle2: Float) -> Float {
        let diff = angle2 - angle1
        return normalizeAngle(diff)
    }
    
    static func isNear(
        position: simd_float2,
        target: simd_float2,
        threshold: Float
    ) -> Bool {
        return distance(from: position, to: target) < threshold
    }
    
    static func isAligned(
        currentHeading: Float,
        targetHeading: Float,
        tolerance: Float
    ) -> Bool {
        let diff = abs(angleDifference(currentHeading, targetHeading))
        return diff < tolerance
    }
    
    // MARK: - Navigation Helpers
    
    static func calculateDistance(from: simd_float2, to: simd_float2) -> Float {
        return distance(from: from, to: to)
    }
    
    static func calculateHeading(from: simd_float2, to: simd_float2) -> Float {
        return bearing(from: from, to: to)
    }
    
    static func calculateCompassDirection(
        from: simd_float2,
        to: simd_float2,
        currentHeading: Float
    ) -> Float {
        return relativeBearing(from: from, to: to, currentHeading: currentHeading)
    }
    
    static func hasArrived(
        currentPosition: simd_float2,
        destination: simd_float2,
        threshold: Float = 1.5
    ) -> Bool {
        return isNear(position: currentPosition, target: destination, threshold: threshold)
    }
    
    static func shouldRecalculatePath(
        currentPosition: simd_float2,
        expectedPosition: simd_float2,
        threshold: Float = 2.0
    ) -> Bool {
        return distance(from: currentPosition, to: expectedPosition) > threshold
    }
    
    // MARK: - Calibration Storage
    
    private static var storedCalibration: CalibrationData?
    
    static func setCalibration(_ calibration: CalibrationData) {
        storedCalibration = calibration
        print("📍 Calibration Set:")
        print("   User position: (\(calibration.userPosition.x), \(calibration.userPosition.y))")
        print("   Heading: \(calibration.heading * 180 / .pi)°")
        print("   Confidence: \(Int(calibration.confidence * 100))%")
        print("   Error: ±\(calibration.residualError)°")
    }
    
    static func getCalibration() -> CalibrationData? {
        return storedCalibration
    }
    
    static func clearCalibration() {
        storedCalibration = nil
    }
}

// MARK: - Transform Extensions

extension simd_float3 {
    var xz: simd_float2 {
        return simd_float2(x, z)
    }
    
    func horizontalDistance(to other: simd_float3) -> Float {
        let delta = simd_float2(other.x - x, other.z - z)
        return simd_length(delta)
    }
}

extension simd_float2 {
    var xyz: simd_float3 {
        return simd_float3(x, 0, y)
    }
}
