//
//  SpokenNavCoach.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/17/25.
//


// SpokenNavCoach.swift
import Foundation
import Combine

@MainActor
final class SpokenNavCoach: ObservableObject {
    private var bag = Set<AnyCancellable>()
    private var lastThresholdIndex = -1
    private let thresholds: [Float] = [10, 5, 3, 2, 1, 0.5] // meters
    private let stepsPerMeter: Float = 1.35 // adjust or pull from Settings

    func attach(to vm: NavigationViewModel) {
        lastThresholdIndex = -1

        vm.$progress
            .compactMap { $0 }
            .removeDuplicates(by: { $0.distanceToNextWaypoint == $1.distanceToNextWaypoint })
            .throttle(for: .milliseconds(800), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] p in self?.speakIfThresholdCrossed(distance: p.distanceToNextWaypoint) }
            .store(in: &bag)

        vm.$navigationState
            .sink { state in
                if case .arrived = state {
                    VoiceGuide.shared.speak("Arrived.")
                }
            }
            .store(in: &bag)
    }

    private func speakIfThresholdCrossed(distance d: Float) {
        // Announce once when crossing downward thresholds
        for (i, th) in thresholds.enumerated() where i > lastThresholdIndex {
            if d <= th {
                let steps = Int((d * stepsPerMeter).rounded())
                if steps > 0 { VoiceGuide.shared.speak("\(steps) steps.") }
                lastThresholdIndex = i
                break
            }
        }
    }
}
