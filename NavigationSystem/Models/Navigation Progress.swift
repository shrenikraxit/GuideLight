//
//  NavigationProgress+Helpers.swift
//  GuideLight v3
//
//  Clock-based navigation with 30° granularity
//

import Foundation
import SwiftUI

extension NavigationProgress {
    
    // MARK: - Clock Position (1-12)
    
    /// Get clock position (1-12) based on heading error
    var clockPosition: Int {
        let degrees = headingErrorDegrees
        
        // Special case: straight ahead
        if abs(degrees) <= 15 {
            return 12
        }
        
        // Special case: behind
        if abs(degrees) >= 165 {
            return 6
        }
        
        // Calculate clock hour (30° per hour)
        // Positive degrees = right turn = 1-5 o'clock
        // Negative degrees = left turn = 7-11 o'clock
        let hour: Int
        if degrees > 0 {
            // Right side: 1-5 o'clock
            hour = Int(round(degrees / 30.0))
        } else {
            // Left side: 7-11 o'clock
            // -30° → 11, -60° → 10, -90° → 9, -120° → 8, -150° → 7
            hour = 12 + Int(round(degrees / 30.0))
        }
        
        // Clamp to valid range
        if hour <= 0 { return 12 }
        if hour > 12 { return 12 }
        return hour
    }
    
    // MARK: - Heading Error Conversion
    
    /// Get heading error in degrees (±180°)
    var headingErrorDegrees: Float {
        return headingError * 180.0 / .pi
    }
    
    /// Get absolute degrees to turn (0-180°)
    var degreesToTurn: Int {
        return Int(abs(headingErrorDegrees))
    }
    
    /// Get turn direction: "right" or "left"
    var turnDirection: String {
        return headingError > 0 ? "right" : "left"
    }
    
    // MARK: - Clock-Based Instructions
    
    /// Primary instruction text using clock positions
    var clockInstructionText: String {
        let degrees = headingErrorDegrees
        
        // Perfect alignment (±5°)
        if abs(degrees) <= 5 {
            return "12 o'clock - Keep going straight"
        }
        
        // Near alignment (5°-15°)
        if abs(degrees) <= 15 {
            return "Slight turn to your \(turnDirection)"
        }
        
        // Behind (165°-195°)
        if abs(degrees) >= 165 {
            return "Turn around - behind you"
        }
        
        // Standard clock positions (1-5, 7-11)
        let hour = clockPosition
        return "Turn to your \(hour) o'clock"
    }
    
    /// Helper text showing degrees (temporary for testing)
    var degreeHelperText: String {
        let degrees = Int(headingErrorDegrees)
        if degrees == 0 {
            return "(0°)"
        } else if degrees > 0 {
            return "(\(degrees)° right)"
        } else {
            return "(\(-degrees)° left)"
        }
    }
    
    // MARK: - Color Coding
    
    /// Get arrow color based on clock position and urgency
    var clockArrowColor: Color {
        let absDegrees = abs(headingErrorDegrees)
        
        // Green: Aligned (±30°) - 12 o'clock region
        if absDegrees <= 30 {
            return .green
        }
        
        // Yellow: Minor turn (30°-75°) - 1-2, 10-11 o'clock
        if absDegrees <= 75 {
            return .yellow
        }
        
        // Orange: Major turn (75°-135°) - 3-4, 8-9 o'clock
        if absDegrees <= 135 {
            return .orange
        }
        
        // Red: Extreme (135°-180°) - 5-6-7 o'clock
        return .red
    }
    
    // MARK: - Backwards Compatibility
    
    /// Legacy guidance text (kept for compatibility)
    var guidanceText: String {
        return clockInstructionText
    }
    
    /// Legacy arrow color (uses clock-based colors)
    var arrowColor: Color {
        return clockArrowColor
    }
    
    /// Get detailed alignment description
    var alignmentDescription: String {
        let degrees = degreesToTurn
        if degrees < 15 { return "Aligned" }
        else if degrees < 30 { return "Slight turn needed" }
        else if degrees < 75 { return "Minor turn needed" }
        else if degrees < 135 { return "Major turn needed" }
        else { return "Turn around" }
    }
    
    // MARK: - Clock-Specific Alignment (doesn't override existing)
    
    /// Check if user is clock-aligned (within ±15°) - uses degrees
    var isClockAligned: Bool {
        return abs(headingErrorDegrees) < 15
    }
}
