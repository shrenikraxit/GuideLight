//
//  CalibrationData.swift
//  GuideLight v3
//
//  CORRECT FIX: Don't calculate angular error during calibration
//

import Foundation
import simd

// MARK: - Calibration Data
struct CalibrationData: Equatable {
    let userPosition: simd_float2
    let heading: Float
    let confidence: Float
    let measurements: [BeaconMeasurement]
    let qualityRating: CalibrationQuality
    let residualError: Float  // Now represents measurement consistency, not angular error
    let timestamp: Date
    
    init(userPosition: simd_float2, heading: Float, measurements: [BeaconMeasurement]) {
        self.userPosition = userPosition
        self.heading = heading
        self.measurements = measurements
        self.timestamp = Date()
        
        // FIXED: Use measurement confidence and consistency only
        if measurements.isEmpty {
            self.confidence = 0.0
            self.qualityRating = .poor
            self.residualError = 999.0
        } else {
            // 1. Calculate average measurement confidence (0-1)
            let avgMeasurementConfidence = measurements.map { $0.confidence }.reduce(0, +) / Float(measurements.count)
            
            // 2. Calculate measurement consistency (how similar are the confidence values?)
            let confidenceVariance = measurements.reduce(Float(0)) { result, measurement in
                let diff = measurement.confidence - avgMeasurementConfidence
                return result + (diff * diff)
            } / Float(measurements.count)
            let confidenceStdDev = sqrt(confidenceVariance)
            
            // High consistency = low std dev = good
            let consistencyScore: Float
            if confidenceStdDev < 0.1 {
                consistencyScore = 1.0  // Very consistent
            } else if confidenceStdDev < 0.2 {
                consistencyScore = 0.85
            } else if confidenceStdDev < 0.3 {
                consistencyScore = 0.7
            } else {
                consistencyScore = 0.5  // Inconsistent measurements
            }
            
            // 3. Combined confidence: average quality × consistency
            self.confidence = avgMeasurementConfidence * consistencyScore
            
            // 4. Calculate "error" as consistency metric (NOT angular error)
            // Lower std dev = better calibration
            // Convert to degrees-like scale for user display
            self.residualError = confidenceStdDev * 100.0  // 0-30 range
            
            // 5. Determine quality based on confidence and consistency
            if self.confidence > 0.85 && residualError < 10.0 {
                self.qualityRating = .excellent
            } else if self.confidence > 0.70 && residualError < 15.0 {
                self.qualityRating = .good
            } else if self.confidence > 0.55 && residualError < 25.0 {
                self.qualityRating = .fair
            } else {
                self.qualityRating = .poor
            }
            
            print("📊 Calibration Metrics:")
            print("   Avg confidence: \(String(format: "%.1f%%", avgMeasurementConfidence * 100))")
            print("   Std deviation: \(String(format: "%.3f", confidenceStdDev))")
            print("   Consistency score: \(String(format: "%.1f%%", consistencyScore * 100))")
            print("   Final confidence: \(String(format: "%.1f%%", self.confidence * 100))")
            print("   Consistency metric: \(String(format: "%.1f", residualError))")
            print("   Quality: \(self.qualityRating.rawValue)")
        }
    }
    
    static func == (lhs: CalibrationData, rhs: CalibrationData) -> Bool {
        return lhs.timestamp == rhs.timestamp &&
               lhs.userPosition == rhs.userPosition &&
               lhs.heading == rhs.heading
    }
}

// MARK: - Calibration Quality
enum CalibrationQuality: String, Codable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    
    var color: (red: Float, green: Float, blue: Float) {
        switch self {
        case .excellent: return (0.0, 1.0, 0.0)
        case .good: return (0.5, 1.0, 0.0)
        case .fair: return (1.0, 0.8, 0.0)
        case .poor: return (1.0, 0.0, 0.0)
        }
    }
}

// MARK: - Calibration State
enum CalibrationState: Equatable {
    case waitingForAR
    case ready
    case measuringBeacon(index: Int, total: Int)
    case completed(CalibrationData)
    case failed(String)
    
    var displayMessage: String {
        switch self {
        case .waitingForAR:
            return "Initializing AR tracking..."
        case .ready:
            return "Ready to calibrate"
        case .measuringBeacon(let index, let total):
            return "Point camera at beacon \(index + 1) of \(total)"
        case .completed:
            return "Calibration complete!"
        case .failed(let message):
            return "Failed: \(message)"
        }
    }
    
    static func == (lhs: CalibrationState, rhs: CalibrationState) -> Bool {
        switch (lhs, rhs) {
        case (.waitingForAR, .waitingForAR): return true
        case (.ready, .ready): return true
        case (.measuringBeacon(let l1, let l2), .measuringBeacon(let r1, let r2)):
            return l1 == r1 && l2 == r2
        case (.completed, .completed): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
}

// MARK: - Candidate Beacon
struct CandidateBeacon: Identifiable {
    let beacon: Beacon
    let distance: Float
    let direction: simd_float3
    
    var id: UUID {
        beacon.id
    }
}

// MARK: - Beacon Measurement
struct BeaconMeasurement: Codable {
    let beaconId: UUID
    let mapPosition: simd_float3
    let observedDirection: simd_float3
    let distance: Float
    let confidence: Float
    
    enum CodingKeys: String, CodingKey {
        case beaconId, mapPositionX, mapPositionY, mapPositionZ
        case observedDirectionX, observedDirectionY, observedDirectionZ
        case distance, confidence
    }
    
    init(beaconId: UUID, mapPosition: simd_float3, observedDirection: simd_float3, distance: Float, confidence: Float) {
        self.beaconId = beaconId
        self.mapPosition = mapPosition
        self.observedDirection = observedDirection
        self.distance = distance
        self.confidence = confidence
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beaconId = try container.decode(UUID.self, forKey: .beaconId)
        
        let x = try container.decode(Float.self, forKey: .mapPositionX)
        let y = try container.decode(Float.self, forKey: .mapPositionY)
        let z = try container.decode(Float.self, forKey: .mapPositionZ)
        mapPosition = simd_float3(x, y, z)
        
        let dx = try container.decode(Float.self, forKey: .observedDirectionX)
        let dy = try container.decode(Float.self, forKey: .observedDirectionY)
        let dz = try container.decode(Float.self, forKey: .observedDirectionZ)
        observedDirection = simd_float3(dx, dy, dz)
        
        distance = try container.decode(Float.self, forKey: .distance)
        confidence = try container.decode(Float.self, forKey: .confidence)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(beaconId, forKey: .beaconId)
        try container.encode(mapPosition.x, forKey: .mapPositionX)
        try container.encode(mapPosition.y, forKey: .mapPositionY)
        try container.encode(mapPosition.z, forKey: .mapPositionZ)
        try container.encode(observedDirection.x, forKey: .observedDirectionX)
        try container.encode(observedDirection.y, forKey: .observedDirectionY)
        try container.encode(observedDirection.z, forKey: .observedDirectionZ)
        try container.encode(distance, forKey: .distance)
        try container.encode(confidence, forKey: .confidence)
    }
}
