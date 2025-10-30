//
//  NavigationVoiceManager.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/21/25.
//


//
//  NavigationVoiceManager.swift
//  GuideLight v3
//
//  Complete turn-by-turn voice guidance system
//  Centralizes all navigation-related voice announcements
//

import Foundation
import AVFoundation
import SwiftUI
import simd

/// Comprehensive voice guidance manager for navigation
@MainActor
final class NavigationVoiceManager: ObservableObject {
    
    // MARK: - Shared Instance
    static let shared = NavigationVoiceManager()
    
    // MARK: - Dependencies
    private let voiceGuide = VoiceGuide.shared
    
    // MARK: - Configuration
    private struct VoiceConfig {
        static let proximityDistance: Float = 10.0          // Announce turns 10m ahead
        static let arrivalDistance: Float = 2.0             // Arrival announcement distance
        static let progressUpdateInterval: Float = 50.0     // Progress updates every 50m
        static let directionRepeatInterval: TimeInterval = 15.0  // Repeat directions every 15s
    }
    
    // MARK: - State Tracking
    @Published private(set) var isNavigationActive: Bool = false
    @Published private(set) var lastAnnouncementTime: Date?
    @Published private(set) var lastProgressDistance: Float = 0
    
    private var currentPath: NavigationPath?
    private var lastDirectionAnnouncement: Date?
    private var announcedWaypoints: Set<UUID> = []
    private var lastProximityWarning: (waypointIndex: Int, time: Date)?
    
    // MARK: - Initialization
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Interface
    
    /// Start voice guidance for a navigation session
    func startNavigation(with path: NavigationPath) {
        currentPath = path
        isNavigationActive = true
        announcedWaypoints.removeAll()
        lastProgressDistance = 0
        lastDirectionAnnouncement = nil
        lastProximityWarning = nil
        
        announceRouteOverview(path)
    }
    
    /// Update voice guidance based on current navigation progress
    func updateProgress(_ progress: NavigationProgress, currentWaypoint: NavigationWaypoint?) {
        guard isNavigationActive else { return }
        
        // Check for proximity warnings
        checkProximityWarnings(progress)
        
        // Provide direction guidance
        provideDirectionGuidance(progress)
        
        // Check for progress updates
        checkProgressUpdates(progress)
        
        // Update state
        lastAnnouncementTime = Date()
    }
    
    /// Handle waypoint arrival
    func announceWaypointArrival(_ waypoint: NavigationWaypoint, nextWaypoint: NavigationWaypoint?, isLastWaypoint: Bool) {
        guard isNavigationActive else { return }
        
        // Mark waypoint as announced
        announcedWaypoints.insert(waypoint.id)
        
        let message = buildArrivalMessage(waypoint, nextWaypoint: nextWaypoint, isLastWaypoint: isLastWaypoint)
        speak(message)
        
        // Announce custom audio instruction if available
        if let audioInstruction = waypoint.audioInstruction {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.speak(audioInstruction)
            }
        }
    }
    
    /// Handle navigation completion
    func completeNavigation() {
        guard isNavigationActive else { return }
        
        speak("Navigation complete. You have arrived at your destination.")
        endNavigation()
    }
    
    /// Handle navigation cancellation
    func cancelNavigation() {
        guard isNavigationActive else { return }
        
        speak("Navigation cancelled.")
        endNavigation()
    }
    
    /// Handle navigation pause
    func pauseNavigation() {
        speak("Navigation paused.")
    }
    
    /// Handle navigation resume
    func resumeNavigation() {
        speak("Navigation resumed.")
        lastDirectionAnnouncement = nil // Force direction update
    }
    
    // MARK: - Route Overview
    
    private func announceRouteOverview(_ path: NavigationPath) {
        let distance = formatDistance(path.totalDistance)
        let time = formatTime(path.estimatedTime)
        let destinationName = getDestinationName(from: path)
        
        var overview = "Route calculated to \(destinationName). "
        overview += "Total distance: \(distance). "
        overview += "Estimated time: \(time). "
        
        // Add room information if available
        if !path.roomsTraversed.isEmpty && path.roomsTraversed.count > 1 {
            let roomCount = path.roomsTraversed.count
            overview += "Route passes through \(roomCount) rooms. "
        }
        
        overview += "Starting navigation."
        
        speak(overview)
    }
    
    // MARK: - Turn-by-Turn Guidance
    
    private func provideDirectionGuidance(_ progress: NavigationProgress) {
        // Don't repeat directions too frequently
        if let lastTime = lastDirectionAnnouncement,
           Date().timeIntervalSince(lastTime) < VoiceConfig.directionRepeatInterval {
            return
        }
        
        // Only provide guidance if not well aligned
        guard !progress.isAligned else { return }
        
        let instruction = buildDirectionInstruction(progress)
        speak(instruction)
        lastDirectionAnnouncement = Date()
    }
    
    private func buildDirectionInstruction(_ progress: NavigationProgress) -> String {
        let distance = formatDistance(progress.distanceToNextWaypoint)
        let clockInstruction = progress.clockInstructionText
        
        // If very close, just give direction
        if progress.distanceToNextWaypoint < 3.0 {
            return clockInstruction
        }
        
        // For longer distances, include distance
        return "In \(distance), \(clockInstruction.lowercased())"
    }
    
    // MARK: - Proximity Warnings
    
    private func checkProximityWarnings(_ progress: NavigationProgress) {
        guard let path = currentPath else { return }
        
        let currentIndex = progress.currentWaypointIndex
        let nextIndex = currentIndex + 1
        
        // Check if we're approaching the next waypoint
        if nextIndex < path.waypoints.count,
           progress.distanceToNextWaypoint <= VoiceConfig.proximityDistance {
            
            // Avoid duplicate announcements
            if let lastWarning = lastProximityWarning,
               lastWarning.waypointIndex == nextIndex,
               Date().timeIntervalSince(lastWarning.time) < 8.0 {
                return
            }
            
            let nextWaypoint = path.waypoints[nextIndex]
            let message = buildProximityWarning(for: nextWaypoint, distance: progress.distanceToNextWaypoint)
            speak(message)
            
            lastProximityWarning = (nextIndex, Date())
        }
    }
    
    private func buildProximityWarning(for waypoint: NavigationWaypoint, distance: Float) -> String {
        let distanceText = formatDistance(distance)
        
        switch waypoint.type {
        case .doorway:
            return "In \(distanceText), approach \(waypoint.name.isEmpty ? "doorway" : waypoint.name)"
        case .destination:
            return "In \(distanceText), arriving at \(waypoint.name.isEmpty ? "destination" : waypoint.name)"
        case .intermediate:
            if !waypoint.name.isEmpty {
                return "In \(distanceText), passing \(waypoint.name)"
            }
            return "" // Skip generic intermediate waypoints
        case .start:
            return "" // Should not occur
        }
    }
    
    // MARK: - Progress Updates
    
    private func checkProgressUpdates(_ progress: NavigationProgress) {
        let currentDistance = progress.totalDistanceRemaining
        let distanceTraveled = lastProgressDistance - currentDistance
        
        // Announce progress every 50 meters traveled
        if distanceTraveled >= VoiceConfig.progressUpdateInterval {
            announceProgress(progress)
            lastProgressDistance = currentDistance
        }
    }
    
    private func announceProgress(_ progress: NavigationProgress) {
        let remaining = formatDistance(progress.totalDistanceRemaining)
        let timeRemaining = formatTime(progress.estimatedTimeRemaining)
        let percent = Int(progress.percentComplete * 100)
        
        let message = "\(percent)% complete. \(remaining) remaining. Estimated time: \(timeRemaining)."
        speak(message)
    }
    
    // MARK: - Arrival Messages
    
    private func buildArrivalMessage(_ waypoint: NavigationWaypoint, nextWaypoint: NavigationWaypoint?, isLastWaypoint: Bool) -> String {
        if isLastWaypoint {
            // Final destination
            return "Arrived at \(waypoint.name.isEmpty ? "destination" : waypoint.name)."
        }
        
        // Intermediate waypoint
        let arrivedText = waypoint.name.isEmpty ? "Waypoint reached" : "Arrived at \(waypoint.name)"
        
        guard let next = nextWaypoint else {
            return arrivedText + "."
        }
        
        let nextText = getNextWaypointDescription(next)
        return arrivedText + ". " + nextText + "."
    }
    
    private func getNextWaypointDescription(_ waypoint: NavigationWaypoint) -> String {
        switch waypoint.type {
        case .doorway:
            return "Proceed to \(waypoint.name.isEmpty ? "doorway" : waypoint.name)"
        case .destination:
            return "Proceeding to \(waypoint.name.isEmpty ? "destination" : waypoint.name)"
        case .intermediate:
            if !waypoint.name.isEmpty {
                return "Continue toward \(waypoint.name)"
            }
            return "Continue forward"
        case .start:
            return "Continue"
        }
    }
    
    // MARK: - Voice Command Responses
    
    /// Handle voice destination requests
    func handleDestinationRequest(_ destination: String, navigationViewModel: NavigationViewModel, arSession: ARSession) async {
        guard let frame = arSession.currentFrame else {
            speak("Camera not ready yet.")
            return
        }
        
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            speak("Say, show me the path to, followed by a destination.")
            return
        }
        
        let currentPosition = CoordinateTransformManager.extractPosition(from: frame.camera)
        
        let result = await navigationViewModel.selectDestination(named: trimmed, session: arSession, currentPosition: currentPosition)
        
        switch result {
        case .success(let pickedName):
            speak("Taking you to \(pickedName).")
        case .ambiguous(let options):
            handleAmbiguousDestination(options)
        case .notFound:
            speak("I couldn't find \(trimmed) in this map.")
        }
    }
    
    private func handleAmbiguousDestination(_ options: [Beacon]) {
        let list = options.prefix(3).map(\.name)
        
        if list.count == 2 {
            speak("I found \(list[0]) and \(list[1]). Say first or second.")
        } else if list.count >= 3 {
            speak("I found \(list[0]), \(list[1]), and \(list[2]). Say first, second, or third.")
        } else if list.count == 1 {
            speak("Found \(list[0]). Say yes to confirm.")
        }
    }
    
    // MARK: - Error Handling
    
    func announceNavigationError(_ error: String) {
        speak("Navigation error: \(error)")
    }
    
    func announceRecalculation() {
        speak("Route updated. Recalculating path.")
    }
    
    func announceOffRoute() {
        speak("You appear to be off the planned route. Please return to the path or I'll recalculate.")
    }
    
    // MARK: - System Messages (Extracted from existing code)
    
    func announceNavigationScreen() {
        speak("Navigation screen.")
    }
    
    func announceCameraNotReady() {
        speak("Camera not ready yet.")
    }
    
    func announceNeedCameraAccess() {
        speak("I need camera access.")
    }
    
    func announceDestinationNotFound(_ name: String) {
        speak("I couldn't find \(name) in this map.")
    }
    
    func announceStartingGuidance(_ destinationName: String) {
        speak("Starting guidance to \(destinationName).")
    }
    
    // MARK: - Utility Methods
    
    private func speak(_ message: String) {
        voiceGuide.speak(message)
    }
    
    private func endNavigation() {
        isNavigationActive = false
        currentPath = nil
        announcedWaypoints.removeAll()
        lastProgressDistance = 0
        lastDirectionAnnouncement = nil
        lastProximityWarning = nil
    }
    
    private func getDestinationName(from path: NavigationPath) -> String {
        if let destination = path.waypoints.last(where: { $0.type == .destination }) {
            return destination.name.isEmpty ? "destination" : destination.name
        }
        return "destination"
    }
    
    private func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return String(format: "%.0f centimeters", distance * 100)
        } else if distance < 10.0 {
            return String(format: "%.1f meters", distance)
        } else {
            return String(format: "%.0f meters", distance)
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        
        if minutes > 0 {
            if seconds > 30 {
                return "\(minutes + 1) minutes"
            } else {
                return "\(minutes) minutes"
            }
        } else {
            return "\(max(30, seconds)) seconds"
        }
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .glVoiceNavigateCommand,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Handle navigation requests from voice commands
            // This integrates with your existing voice command system
        }
    }
}

// MARK: - Extensions for NavigationProgress

extension NavigationProgress {
    /// Enhanced clock instruction text with better voice formatting
    var voiceClockInstructionText: String {
        let degrees = headingErrorDegrees
        
        // Perfect alignment (±5°)
        if abs(degrees) <= 5 {
            return "Continue straight ahead"
        }
        
        // Near alignment (5°-15°)
        if abs(degrees) <= 15 {
            return "Slight \(turnDirection) turn"
        }
        
        // Behind (165°-195°)
        if abs(degrees) >= 165 {
            return "Turn around, destination is behind you"
        }
        
        // Standard clock positions with voice-friendly phrasing
        let hour = clockPosition
        return "Turn \(turnDirection) to your \(hour) o'clock"
    }
}

// MARK: - Voice-Optimized Extensions

extension NavigationWaypoint {
    /// Get voice-friendly name for announcements
    var voiceName: String {
        if name.isEmpty {
            switch type {
            case .start: return "starting point"
            case .intermediate: return "waypoint"
            case .doorway: return "doorway"
            case .destination: return "destination"
            }
        }
        return name
    }
}

// MARK: - Integration Helper

extension NavigationVoiceManager {
    /// Static method for easy integration with existing code
    static func speak(_ message: String) {
        shared.speak(message)
    }
    
    /// Replace existing VoiceGuide.shared.speak calls for navigation
    static func announceArrival(_ waypoint: NavigationWaypoint, next: NavigationWaypoint? = nil, isLast: Bool = false) {
        shared.announceWaypointArrival(waypoint, nextWaypoint: next, isLastWaypoint: isLast)
    }
}