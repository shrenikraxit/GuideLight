//
//  NavigationViewModel.swift
//  GuideLight v3
//
//  Multi-stop navigation with arrival messages + dynamic veil + real % progress
//

import Foundation
import ARKit
import Combine
import simd

// MARK: - Selection result for voice workflows
enum DestinationSelectionResult {
    case success(String)           // picked name
    case ambiguous([Beacon])       // top candidates
    case notFound
}

// MARK: - Navigation View Model
@MainActor
class NavigationViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var navigationState: NavigationState = .notStarted
    @Published var currentPath: NavigationPath?
    @Published var currentWaypointIndex: Int = 0
    @Published var progress: NavigationProgress?
    @Published var destinationBeacon: Beacon?
    @Published var availableDestinations: [Beacon] = []
    
    // Arrival message system
    @Published var arrivalMessage: String?
    @Published var showArrivalMessage: Bool = false
    
    // Path JSON for external visualization
    @Published var pathJSON: String?
    
    // Dynamic veil (readability in bright scenes)
    @Published var ambientLightIntensity: Float = 1000    // ~0..2000+ (ARKit)
    @Published var veilOpacity: Double = 0.72             // 0.5..0.9 dynamically adjusted
    
    // MARK: - Private Properties
    private var arSession: ARSession?
    public let map: IndoorMap
    private let pathfinder: PathfindingEngine
    private var lastUpdateTime: Date?
    private var lastDistanceToWaypoint: Float?
    private var calibration: CalibrationData

    // MARK: - AI Description Service
    private let aiService: OpenAIDescriptionService = {
        let key = APIConfiguration.getOpenAIApiKey()
        return OpenAIDescriptionService(apiKey: key)
    }()
    
    // MARK: - Doorway announce counter
    private var doorwayAnnouncementCount: Int = 0
    
    private let arrivalThreshold: Float = 0.5
    private let updateInterval: TimeInterval = 0.1
    
    // MARK: - Private Properties
    private var arrivalCooldownUntil: Date? = nil
    private var didProcessArrivalThisTick: Bool = false
    
    // ADD near other private stored properties
    private var approachSpokenForIndex = Set<Int>()
    private let averageStepLengthMeters: Float = 0.70
    
    // === ADD near other properties ===
    private var announcedDoorways = Set<UUID>()

    // ADD a tiny helper (file-private ok)
    private func metersToSteps(_ m: Float) -> Int {
        max(1, Int((m / max(0.3, averageStepLengthMeters)).rounded()))
    }

    
    // MARK: - Computed Properties
    
    var currentWaypoint: NavigationWaypoint? {
        guard let path = currentPath,
              currentWaypointIndex < path.waypoints.count else {
            return nil
        }
        return path.waypoints[currentWaypointIndex]
    }
    
    var nextWaypoint: NavigationWaypoint? {
        guard let path = currentPath,
              currentWaypointIndex + 1 < path.waypoints.count else {
            return nil
        }
        return path.waypoints[currentWaypointIndex + 1]
    }
    
    var isAtDestination: Bool {
        guard let path = currentPath else { return false }
        return currentWaypointIndex >= path.waypoints.count - 1
    }
    
    // MARK: - Initialization
    
    init(map: IndoorMap, calibration: CalibrationData) {
        self.map = map
        self.calibration = calibration
        self.pathfinder = PathfindingEngine(map: map)
        
        CoordinateTransformManager.setCalibration(calibration)
        
        availableDestinations = map.beacons.filter { beacon in
            beacon.isAccessible && !beacon.isObstacle
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        print("ðŸ§­ Navigation initialized")
        print("   Available destinations: \(availableDestinations.count)")
    }
    
    // MARK: - Voice: select by name with fuzzy match
    
    /// Voice-friendly entry point. Attempts to match a destination name and, if found (or unambiguous),
    /// starts navigation immediately.
    func selectDestination(named raw: String,
                           session: ARSession,
                           currentPosition: simd_float3) async -> DestinationSelectionResult {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notFound }
        
        let candidates = fuzzyMatchDestinations(query: trimmed)
        guard !candidates.isEmpty else { return .notFound }
        
        if candidates.count == 1 {
            self.selectDestination(candidates[0], currentPosition: currentPosition, session: session)
            return .success(candidates[0].name)
        }
        
        // If multiple candidates, prefer exact/starts-with/contains ranking; if still >1, return ambiguous
        let ranked = rank(candidates: candidates, for: trimmed)
        if ranked.count > 1 {
            return .ambiguous(Array(ranked.prefix(3)))
        } else if let only = ranked.first {
            self.selectDestination(only, currentPosition: currentPosition, session: session)
            return .success(only.name)
        }
        return .notFound
    }
    
    private func fuzzyMatchDestinations(query: String) -> [Beacon] {
        let q = normalize(query)
        if q.isEmpty { return [] }
        // 1) exact (case/diacritics-insensitive)
        let exact = availableDestinations.filter { normalize($0.name) == q }
        if !exact.isEmpty { return exact }
        // 2) starts-with
        let starts = availableDestinations.filter { normalize($0.name).hasPrefix(q) }
        if !starts.isEmpty { return starts }
        // 3) contains
        let contains = availableDestinations.filter { normalize($0.name).contains(q) }
        if !contains.isEmpty { return contains }
        // 4) whitespace-insensitive contains (e.g., "conf room a" vs "conference room a")
        let nowhiteQ = q.replacingOccurrences(of: " ", with: "")
        let nowhite = availableDestinations.filter {
            normalize($0.name).replacingOccurrences(of: " ", with: "").contains(nowhiteQ)
        }
        return nowhite
    }
    
    private func rank(candidates: [Beacon], for query: String) -> [Beacon] {
        let q = normalize(query)
        return candidates.sorted { a, b in
            let an = normalize(a.name)
            let bn = normalize(b.name)
            // exact > starts-with > contains > length proximity
            if an == q, bn != q { return true }
            if bn == q, an != q { return false }
            if an.hasPrefix(q), !bn.hasPrefix(q) { return true }
            if bn.hasPrefix(q), !an.hasPrefix(q) { return false }
            // shorter edit distance first (very lightweight proxy using length diff)
            let ad = abs(Int(an.count) - Int(q.count))
            let bd = abs(Int(bn.count) - Int(q.count))
            return ad < bd
        }
    }
    
    private func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Destination Selection (by Beacon)
    
    func selectDestination(_ beacon: Beacon, currentPosition: simd_float3, session: ARSession) {
        self.destinationBeacon = beacon
        self.arSession = session
        
        navigationState = .computingPath
        
        guard let path = pathfinder.findPath(from: currentPosition, to: beacon) else {
            navigationState = .failed("Could not find path to destination")
            return
        }
        
        currentPath = path
        currentWaypointIndex = 0
        approachSpokenForIndex.removeAll()
        navigationState = .navigating(currentWaypoint: 0, totalWaypoints: path.waypoints.count)
        
        // ADD after you compute/assign `currentPath`, set `currentWaypointIndex = 0` and set state to .navigating
        if let path = currentPath {
            // Prefer next named .intermediate; otherwise first non-start, non-destination
            let remaining = path.waypoints.dropFirst()
            let nextIntermediate = remaining.first(where: { $0.type == .intermediate && !$0.name.isEmpty })
            let nextFallback = remaining.first(where: { $0.type != .start && $0.type != .destination })
            let nextName: String = {
                guard path.waypoints.count > 1 else { return "next waypoint" }
                let next = path.waypoints[1] // immediate next node after Start
                if !next.name.isEmpty { return next.name }
                switch next.type {
                case .doorway:      return "the doorway"
                case .intermediate: return "the next point"
                default:            return "the next waypoint"
                }
            }()
            let finalName = path.waypoints.last(where: { $0.type == .destination })?.name ?? destinationBeacon?.name ?? "destination"
            VoiceGuide.shared.speak("Route to \(finalName). To begin, proceed to \(nextName).")
        }
        
        
        
        // Export path as JSON
        pathJSON = path.toJSONString()
        print("ðŸ“Š Path JSON generated:")
        print(pathJSON ?? "Error generating JSON")
        
        print("ðŸ—ºï¸ Navigation started to \(beacon.name)")
        print("   Waypoints: \(path.waypoints.count)")
        print("   Distance: \(String(format: "%.1fm", path.totalDistance))")
        
        startNavigationUpdates()
    }
    
    // MARK: - Navigation Updates
    
    private func startNavigationUpdates() {
        Task {
            while case .navigating = navigationState {
                await updateNavigationProgressWithDoorways()
                try? await Task.sleep(nanoseconds: UInt64(updateInterval * 1_000_000_000))
            }
        }
    }
    
    func updateNavigationProgress() async {
        // Block arrivals during cooldown window
        if let until = arrivalCooldownUntil, Date() < until { return }

        // Prevent more than one arrival in the same loop tick
        if didProcessArrivalThisTick { return }
        didProcessArrivalThisTick = false  // will be flipped to true only when we detect arrival
        
        guard let frame = arSession?.currentFrame,
              let waypoint = currentWaypoint else {
            return
        }
        
        // === Dynamic veil based on scene brightness ===
        if let le = frame.lightEstimate {
            ambientLightIntensity = Float(le.ambientIntensity) // ~0..2000+
            let normalized = min(2.0, Double(ambientLightIntensity) / 1000.0)
            // brighter scene => darker veil (for contrast), clamped 0.5..0.9
            veilOpacity = max(0.60, min(0.98, 0.60 + 0.28 * normalized))
        }
        
        // === Position/heading & distances ===
        let currentPosition3D = CoordinateTransformManager.extractPosition(from: frame.camera)
        let currentHeading = CoordinateTransformManager.extractHeading(from: frame.camera)
        
        let currentPosition2D = simd_float2(currentPosition3D.x, currentPosition3D.z)
        let waypointPosition2D = simd_float2(waypoint.position.x, waypoint.position.z)
        
        let distanceToWaypoint = CoordinateTransformManager.calculateDistance(
            from: currentPosition2D,
            to: waypointPosition2D
        )
        
        // ADD: single-shot “approaching … in steps” callout (no UI change)
        // Window: 0.9m–2.5m before arrival; announce only once per waypoint
        let approachMin: Float = 1.0
        let approachMax: Float = 2.5
        if distanceToWaypoint >= approachMin,
           distanceToWaypoint <= approachMax,
           !approachSpokenForIndex.contains(currentWaypointIndex),
           let path = currentPath {

            approachSpokenForIndex.insert(currentWaypointIndex)
            let steps = metersToSteps(distanceToWaypoint)
            let wp = path.waypoints[currentWaypointIndex]

            if wp.type == .destination {
                let finalName = wp.name.isEmpty ? "your destination" : wp.name
                VoiceGuide.shared.speak("Approaching \(finalName) in \(steps) steps.")
            } else {
                // Speak the *current* target (doorways included)
                let nameToSay: String = {
                    if !wp.name.isEmpty { return wp.name }
                    switch wp.type {
                    case .doorway:      return "the doorway"
                    case .intermediate: return "the next point"
                    default:            return "your next waypoint"
                    }
                }()
                VoiceGuide.shared.speak("Approaching \(nameToSay) in \(steps) steps.")
            }
        }

        
        let targetHeading = CoordinateTransformManager.calculateHeading(
            from: currentPosition2D,
            to: waypointPosition2D
        )
        
        let headingError = -CoordinateTransformManager.calculateCompassDirection(
            from: currentPosition2D,
            to: waypointPosition2D,
            currentHeading: currentHeading
        )
        
        let remainingDistance = currentPath?.distance(from: currentWaypointIndex) ?? 0
        let totalPathDistance = currentPath?.totalDistance ?? remainingDistance
        let estimatedTime = TimeInterval(remainingDistance / 1.2) // ~1.2 m/s walking
        
        progress = NavigationProgress(
            currentWaypointIndex: currentWaypointIndex,
            distanceToNextWaypoint: distanceToWaypoint,
            totalDistanceRemaining: remainingDistance,
            estimatedTimeRemaining: estimatedTime,
            currentHeading: currentHeading,
            targetHeading: targetHeading,
            headingError: headingError,
            totalPathDistance: totalPathDistance
        )
        
        if CoordinateTransformManager.hasArrived(
            currentPosition: currentPosition2D,
            destination: waypointPosition2D,
            threshold: arrivalThreshold
        ) {
            didProcessArrivalThisTick = true
            await arriveAtWaypoint()
        }
        
        if let lastDistance = lastDistanceToWaypoint, lastDistance < distanceToWaypoint {
            if CoordinateTransformManager.shouldRecalculatePath(
                currentPosition: currentPosition2D,
                expectedPosition: waypointPosition2D,
                threshold: 2.0
            ) {
                print("âš ï¸ User deviated from path")
            }
        }
        
        lastDistanceToWaypoint = distanceToWaypoint
        lastUpdateTime = Date()
        didProcessArrivalThisTick = false
    }
    
    // MARK: - Waypoint Arrival
    
    private func arriveAtWaypoint() async {
        guard let path = currentPath else { return }
        
        // Debounce: block any new arrivals for ~0.7s
        arrivalCooldownUntil = Date().addingTimeInterval(0.7)
        
        let waypoint = path.waypoints[currentWaypointIndex]
        print("✅ Arrived at waypoint: \(waypoint.name)")
        
        // Determine if this is the final waypoint
        let isFinal = (currentWaypointIndex >= path.waypoints.count - 1)
        
        // MODIFIED: Handle start position differently
        var message: String
        
        if isFinal {
            message = "Arrived"
        } else {
            // MODIFIED: Check if this is the start position (type .start)
            if waypoint.type == .start {
                // Proceed to the *immediate* next target (doorways included)
                if let next = nextWaypoint {
                    let label: String = {
                        if !next.name.isEmpty { return next.name }
                        switch next.type {
                        case .doorway:      return "the doorway"
                        case .intermediate: return "the next point"
                        default:            return "the next waypoint"
                        }
                    }()
                    message = "Proceed to \(label)"
                } else {
                    message = "Proceed to destination"
                }
            } else {
                // For other waypoints, keep the original structure
                let arrivedAtX: String = waypoint.name.isEmpty ? "Arrived" : "Arrived at \(waypoint.name)"
                
                let nextDestinationName: String? = {
                    let slice = path.waypoints.suffix(from: currentWaypointIndex + 1)
                    
                    // 🔧 Prefer next named intermediate FIRST
                    if let nextInter = slice.first(where: { $0.type == .intermediate && !$0.name.isEmpty }) {
                        return nextInter.name
                    }
                    // then fall back to final destination
                    if let nextDest = slice.first(where: { $0.type == .destination }) {
                        return nextDest.name.isEmpty ? "destination" : nextDest.name
                    }
                    // finally fall back to the immediate next waypoint name (if any)
                    if let next = nextWaypoint {
                        return next.name.isEmpty ? "next waypoint" : next.name
                    }
                    return nil
                }()
                
                if let y = nextDestinationName {
                    message = "\(arrivedAtX), now proceed to \(y)"
                } else {
                    message = arrivedAtX
                }
            }
        }
        
        // Show + speak arrival message
        arrivalMessage = message
        showArrivalMessage = true
        VoiceGuide.shared.speak(message)
        
        if let instruction = waypoint.audioInstruction {
            print("🔊 \(instruction)")
        }
        
        // Hide message after 3 seconds
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                self.showArrivalMessage = false
                self.arrivalMessage = nil
            }
        }
        
        // Advance waypoint
        currentWaypointIndex += 1
        doorwayAnnouncementCount = 0
        
        if currentWaypointIndex >= path.waypoints.count {
            navigationState = .arrived
            print("🏁 Arrived at final destination!")
        } else {
            navigationState = .navigating(
                currentWaypoint: currentWaypointIndex,
                totalWaypoints: path.waypoints.count
            )
            lastDistanceToWaypoint = nil
            print("➡️ Now navigating to: \(path.waypoints[currentWaypointIndex].name)")
        }
        // Give the next leg a short breathing room before any new arrival can occur
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.arrivalCooldownUntil = nil
        }
    }

    
    // MARK: - Navigation Control
    
    func pauseNavigation() {
        navigationState = .paused
        print("â¸ï¸ Navigation paused")
    }
    
    func resumeNavigation() {
        guard let path = currentPath else { return }
        navigationState = .navigating(
            currentWaypoint: currentWaypointIndex,
            totalWaypoints: path.waypoints.count
        )
        print("â–¶ï¸ Navigation resumed")
        startNavigationUpdates()
    }
    
    func cancelNavigation() {
        navigationState = .notStarted
        currentPath = nil
        currentWaypointIndex = 0
        progress = nil
        destinationBeacon = nil
        lastDistanceToWaypoint = nil
        pathJSON = nil
        arrivalMessage = nil
        showArrivalMessage = false
        print("âŒ Navigation cancelled")
    }
    
    // MARK: - Compass Visualization (used by UI)
    
    func getCompassRotation() -> Float {
        guard let progress = progress else { return 0 }
        return progress.headingError
    }
    
    func getCompassColor() -> String {
        guard let progress = progress else { return "gray" }
        return progress.alignmentQuality.color
    }
    
    // MARK: - Formatting helpers (used by overlays)
    
    func formatDistance(_ distance: Float) -> String {
        if distance < 1.0 {
            return String(format: "%.0fcm", distance * 100)
        } else if distance < 10.0 {
            return String(format: "%.1fm", distance)
        } else {
            return String(format: "%.0fm", distance)
        }
    }
    
    func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    // MARK: - Location Announcement
    
    /// Announces the current location based on the user's position
    func announceCurrentLocation(position: simd_float3) {
        print("📍 Announcing current location at position: \(formatPosition(position))")
        
        // Find the closest room to the current position
        let currentRoom = findClosestRoom(to: position)
        
        if let room = currentRoom {
            Task {
                do {
                    let aiText = try await aiService.generateRoomDescription(for: room)
                    await MainActor.run {
                        print("🗣️ Location announcement (AI): \(aiText)")
                        VoiceGuide.shared.speak(aiText)
                    }
                } catch {
                    let fallback = "You are in the \(room.name)."
                    await MainActor.run {
                        print("🗣️ Location announcement (fallback): \(fallback) – error: \(error)")
                        VoiceGuide.shared.speak(fallback)
                    }
                }
            }
        } else {
            // Try to find the closest beacon as a fallback
            let pos2D = simd_float2(position.x, position.z)
            if let beacon = findClosestBeacon(to: position) {
                let beacon2D = simd_float2(beacon.position.x, beacon.position.z)
                let d = simd_distance(pos2D, beacon2D)
                if d < 3.0 {
                    let msg = "You are near \(beacon.name)"
                    print("🗣️ Location announcement: \(msg)")
                    VoiceGuide.shared.speak(msg)
                } else {
                    let msg = "You are in the mapped area. Select a destination to begin navigation."
                    print("🗣️ Location announcement (fallback): \(msg)")
                    VoiceGuide.shared.speak(msg)
                }
            } else {
                let msg = "You are in the mapped area. Select a destination to begin navigation."
                print("🗣️ Location announcement (fallback): \(msg)")
                VoiceGuide.shared.speak(msg)
            }
        }

    }
    
    // MARK: - Helper Methods for Location Detection
    
    func findClosestRoom(to position: simd_float3) -> Room? {
        let position2D = simd_float2(position.x, position.z)
        var closestRoom: Room? = nil
        var closestDistance: Float = Float.infinity
        
        for room in map.rooms {
            // Check if position is inside the room bounds
            if isPosition(position2D, insideRoom: room) {
                return room  // Direct hit inside room
            }
            
            // Find closest room by center point
            let roomCenter = calculateRoomCenter(room)
            let distance = simd_distance(position2D, roomCenter)
            
            if distance < closestDistance {
                closestDistance = distance
                closestRoom = room
            }
        }
        
        // Only return closest room if it's reasonably close (within 5 meters)
        return closestDistance < 5.0 ? closestRoom : nil
    }
    
    private func findClosestBeacon(to position: simd_float3) -> Beacon? {
        let position2D = simd_float2(position.x, position.z)
        var closestBeacon: Beacon? = nil
        var closestDistance: Float = Float.infinity
        
        for beacon in map.beacons {
            let beaconPosition2D = simd_float2(beacon.position.x, beacon.position.z)
            let distance = simd_distance(position2D, beaconPosition2D)
            
            if distance < closestDistance {
                closestDistance = distance
                closestBeacon = beacon
            }
        }
        
        return closestBeacon
    }
    
    private func isPosition(_ position: simd_float2, insideRoom room: Room) -> Bool {
        // Simple bounding box check based on room's beacons
        let roomBeacons = map.beacons.filter { $0.roomId == room.id.uuidString }
        guard !roomBeacons.isEmpty else { return false }
        
        let positions = roomBeacons.map { simd_float2($0.position.x, $0.position.z) }
        let minX = positions.map { $0.x }.min() ?? 0
        let maxX = positions.map { $0.x }.max() ?? 0
        let minZ = positions.map { $0.y }.min() ?? 0
        let maxZ = positions.map { $0.y }.max() ?? 0
        
        // Add some padding to the bounds
        let padding: Float = 1.0
        return position.x >= (minX - padding) && position.x <= (maxX + padding) &&
        position.y >= (minZ - padding) && position.y <= (maxZ + padding)
    }
    
    private func calculateRoomCenter(_ room: Room) -> simd_float2 {
        let roomBeacons = map.beacons.filter { $0.roomId == room.id.uuidString }
        guard !roomBeacons.isEmpty else { return simd_float2(0, 0) }
        
        let positions = roomBeacons.map { simd_float2($0.position.x, $0.position.z) }
        let sumX = positions.map { $0.x }.reduce(0, +)
        let sumZ = positions.map { $0.y }.reduce(0, +)
        
        return simd_float2(sumX / Float(positions.count), sumZ / Float(positions.count))
    }
    
    private func formatPosition(_ position: simd_float3) -> String {
        return String(format: "(%.1f, %.1f, %.1f)", position.x, position.y, position.z)
    }

    // MARK: - Doorway Integration
        
    /// Check if we're approaching a doorway and announce it (once)
    func checkForDoorwayAnnouncement(currentPosition: simd_float3) {
        // If we've already announced for this doorway segment, skip
        if doorwayAnnouncementCount > 0 { return }

        guard let path = currentPath,
              currentWaypointIndex < path.waypoints.count else { return }

        let i = currentWaypointIndex
        let currentWP = path.waypoints[i]

        // Helper to compute 2D distance to a doorway
        func distanceToDoorway(_ doorway: Doorway) -> Float {
            let user2D = simd_float2(currentPosition.x, currentPosition.z)
            let door2D = simd_float2(doorway.position.x, doorway.position.z)
            return simd_distance(user2D, door2D)
        }

        // Threshold to trigger the approach announcement slightly before arrival
        let triggerDistance: Float = 1.8

        // A) CURRENT node is a doorway (e.g., just as we reach it)
        if currentWP.type == .doorway,
           let doorwayId = currentWP.doorwayId,
           let doorway = map.doorways.first(where: { $0.id.uuidString == doorwayId }) {

            let d = distanceToDoorway(doorway)
            // Only announce when actually close enough
            if d <= triggerDistance {
                // mark AFTER we decide to announce
                doorwayAnnouncementCount += 1
                announceDoorwayIfNeeded(doorway, anchorIndex: i, currentPosition: currentPosition)
            }
            return
        }

        // B) LOOK AHEAD: if the NEXT node is a doorway, announce as you approach it
        let nextIndex = i + 1
        if nextIndex < path.waypoints.count {
            let nextWP = path.waypoints[nextIndex]
            if nextWP.type == .doorway,
               let doorwayId = nextWP.doorwayId,
               let doorway = map.doorways.first(where: { $0.id.uuidString == doorwayId }) {

                let d = distanceToDoorway(doorway)
                if d <= triggerDistance {
                    doorwayAnnouncementCount += 1
                    announceDoorwayIfNeeded(doorway, anchorIndex: nextIndex, currentPosition: currentPosition)
                }
            }
        }
    }

    
    /// Determine approach direction (from/to) and speak hinge + push/pull
    /// Resolve from/to using the doorway's own index + neighbor, then speak hinge + push/pull.
    private func determineDoorwayDirectionAndSpeak(
        _ doorway: Doorway,
        anchorIndex i: Int,
        currentPosition: simd_float3
    ) {
        guard let path = currentPath else { return }

        // 1) Primary IDs from path (your rule)
        var fromId: String? = (i < path.waypoints.count) ? path.waypoints[i].roomId : nil
        var toId:   String? = (i + 1 < path.waypoints.count) ? path.waypoints[i + 1].roomId : nil

        // 2) Fallback: if either is nil, derive from doorway connectivity and user's side
        if fromId == nil || toId == nil {
            let a = doorway.connectsRooms.roomA
            let b = doorway.connectsRooms.roomB

            // Try to guess which side the user is on
            if fromId == nil, let cur = findClosestRoom(to: currentPosition) {
                if cur.id.uuidString == a || cur.id.uuidString == b { fromId = cur.id.uuidString }
            }

            // If we know one side, the other is the opposite
            if let f = fromId, toId == nil { toId = (f == a ? b : a) }
            if let t = toId, fromId == nil { fromId = (t == a ? b : a) }

            // Last resort: centroid side-pick by distance to room beacon centroids
            if fromId == nil || toId == nil {
                func centroid(_ roomId: String) -> simd_float2 {
                    let beacons = map.beacons.filter { $0.roomId == roomId }
                    guard !beacons.isEmpty else { return .zero }
                    let sum = beacons.reduce(simd_float2.zero) { acc, b in acc + simd_float2(b.position.x, b.position.z) }
                    return sum / Float(beacons.count)
                }
                let user2D = simd_float2(currentPosition.x, currentPosition.z)
                let ca = centroid(a), cb = centroid(b)
                if simd_distance(user2D, ca) <= simd_distance(user2D, cb) {
                    if fromId == nil { fromId = a }
                    if toId   == nil { toId   = b }
                } else {
                    if fromId == nil { fromId = b }
                    if toId   == nil { toId   = a }
                }
            }
        }

        // 3) If still missing, log and fall out (rare)
        guard let fromIdStr = fromId, let toIdStr = toId else {
            print("⚠️ Doorway announce skipped: could not resolve from/to for \(doorway.name)")
            return
        }

        // 4) Resolve names if possible; don't block on names
        let fromName = map.room(withId: fromIdStr)?.name ?? "previous room"
        let toName   = map.room(withId: toIdStr)?.name   ?? "next room"

        // 5) Speak via AI prompt (or a deterministic fallback)
        Task {
            // Try AI first
            if let fromUUID = UUID(uuidString: fromIdStr),
               let toUUID   = UUID(uuidString: toIdStr) {
                do {
                    let text = try await aiService.generateDoorwayDescription(
                        doorway: doorway,
                        fromRoomId: fromUUID,
                        toRoomId: toUUID,
                        fromRoomName: fromName,
                        toRoomName: toName
                    )
                    await MainActor.run { VoiceGuide.shared.speak(text) }
                    return
                } catch {
                    // fall through to deterministic fallback
                }
            }

            // Deterministic fallback (no UUID dependency)
            let action = doorway.action(from: fromIdStr, to: toIdStr)
            let hinge: String = {
                switch doorway.doorType {
                case .hinged_left:  return "Left-hinged door"
                case .hinged_right: return "Right-hinged door"
                case .sliding:      return "Sliding door"
                case .automatic:    return "Automatic door"
                case .open_doorway: return "Open doorway"
                case .double_door:  return "Double door"
                case .swinging_both: return "Swinging door"
                }
            }()
            let verb: String = {
                switch action {
                case .push: return "push to enter"
                case .pull: return "pull to enter"
                case .slide: return "slide to open"
                case .automatic: return "will open automatically"
                case .walkThrough: return "walk through"
                }
            }()
            let fallback = "\(hinge), \(verb) \(toName)"
            await MainActor.run { VoiceGuide.shared.speak(fallback) }
        }
    }
    
        /// Announce doorway information if user is close enough
    private func announceDoorwayIfNeeded(_ doorway: Doorway, anchorIndex i: Int, currentPosition: simd_float3) {
        let user2D = simd_float2(currentPosition.x, currentPosition.z)
        let door2D = simd_float2(doorway.position.x, doorway.position.z)
        let distance = simd_distance(user2D, door2D)

        // Announce slightly earlier so it's heard before the arrival line
        if distance <= 1.8 {
            determineDoorwayDirectionAndSpeak(doorway, anchorIndex: i, currentPosition: currentPosition)
        }
    }

        
        /// Determine which direction user is approaching doorway from and announce
        private func determineDoorwayDirection(_ doorway: Doorway, currentPosition: simd_float3) {
            // Get current room
            let currentRoom = findClosestRoom(to: currentPosition)
            
            // Get target room (next waypoint after doorway)
            var targetRoom: Room?
            var targetRoomName: String = "next room"
            
            if let nextWaypoint = nextWaypoint {
                // Try to find the room by roomId
                targetRoom = map.rooms.first(where: { $0.id.uuidString == nextWaypoint.roomId })
                targetRoomName = targetRoom?.name ?? "next room"
            }
            
            // If we don't have a target room from waypoint, determine it from doorway connections
            if targetRoom == nil {
                // Find which rooms the doorway connects
                let roomAId = doorway.connectsRooms.roomA  // This should be UUID string
                let roomBId = doorway.connectsRooms.roomB  // This should be UUID string
                
                // If current room is roomA, target is roomB (and vice versa)
                if let currentRoom = currentRoom {
                    if currentRoom.id.uuidString == roomAId {
                        targetRoom = map.rooms.first(where: { $0.id.uuidString == roomBId })
                    } else if currentRoom.id.uuidString == roomBId {
                        targetRoom = map.rooms.first(where: { $0.id.uuidString == roomAId })
                    }
                }
                
                if let targetRoom = targetRoom {
                    targetRoomName = targetRoom.name
                }
            }
            
            // Prepare UUIDs for the announcement
            let fromRoomId = currentRoom?.id ?? UUID()
            let toRoomId = targetRoom?.id ?? UUID()
            let fromRoomName = currentRoom?.name ?? "current room"
            
            // Announce the doorway directly
            print("🚪 Announcing doorway: \(doorway.name)")
            
            Task {
                do {
                    let aiDescription = try await aiService.generateDoorwayDescription(
                        doorway: doorway,
                        fromRoomId: fromRoomId,
                        toRoomId: toRoomId,
                        fromRoomName: fromRoomName,
                        toRoomName: targetRoomName
                    )
                    print("🗣️ AI Doorway announcement: \(aiDescription)")
                    await MainActor.run {
                        VoiceGuide.shared.speak(aiDescription)
                    }
                } catch {
                    print("⚠️ AI doorway description failed: \(error)")
                    // Fallback to simple description
                    let fallbackDescription = aiService.generateSimpleDoorwayDescription(
                        doorway: doorway,
                        fromRoomId: fromRoomId,
                        toRoomId: toRoomId,
                        toRoomName: targetRoomName
                    )
                    print("🗣️ Fallback doorway announcement: \(fallbackDescription)")
                    await MainActor.run {
                        VoiceGuide.shared.speak(fallbackDescription)
                    }
                }
            }
        }
        
        /// Enhanced navigation progress that includes doorway checks
        func updateNavigationProgressWithDoorways() async {
            // Call the original update method
            await updateNavigationProgress()
            
            // Check for doorway announcements
            if let frame = arSession?.currentFrame {
                let currentPosition = CoordinateTransformManager.extractPosition(from: frame.camera)
                checkForDoorwayAnnouncement(currentPosition: currentPosition)
            }
        }
    
}
