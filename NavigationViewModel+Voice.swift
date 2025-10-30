// NavigationViewModel+Voice.swift
import Foundation
import ARKit

extension NavigationViewModel {
    /// Finds a destination by name/substring and starts guidance using current camera position.
    func navigateToPOI(named name: String, session: ARSession) {
        guard let frame = session.currentFrame else {
            VoiceGuide.shared.speak("I need camera access.")
            return
        }
        let t = frame.camera.transform
        let currentPos = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)

        // Prefer exact (case-insensitive), then contains
        let candidates = availableDestinations
        let lc = name.lowercased()
        let dest = candidates.first(where: { $0.name.lowercased() == lc }) ??
                   candidates.first(where: { $0.name.lowercased().contains(lc) })

        guard let target = dest else {
            VoiceGuide.shared.speak("I couldn’t find \(name) in this map.")
            return
        }
        selectDestination(target, currentPosition: currentPos, session: session)
        VoiceGuide.shared.speak("Starting guidance to \(target.name).")
    }
}
