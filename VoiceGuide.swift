//
//  VoiceGuide.swift
//  GuideLight v3
//
//  Centralized voice service (Swift 6 safe) - FIXED audio session
//

import Foundation
import AVFoundation
import SwiftUI

/// All standardized cue keys your app can use.
/// Keep matching entries in Localizable.strings.
enum VoiceCue: String {
    case welcome          = "voice.welcome"
    case startPrompt      = "voice.startPrompt"
    case homeHelp         = "voice.homeHelp"
    case startingNav      = "voice.startingNav"
    case pathfinderSel    = "voice.pathfinderSel"
    case settingsSel      = "voice.settingsSel"
    case helpSel          = "voice.helpSel"
    case errorNoMap       = "voice.errorNoMap"
    case test             = "voice.test"
}

/// Centralized text-to-speech service for all voice cues in the app.
@MainActor
final class VoiceGuide: ObservableObject {
    static let shared = VoiceGuide()

    // MARK: - Audio
    private let synth = AVSpeechSynthesizer()
    private var observers: [NSObjectProtocol] = []

    // MARK: - Persisted settings
    @AppStorage("voiceFirstEnabled") private var voiceEnabled: Bool = UIAccessibility.isVoiceOverRunning
    @AppStorage("voiceLocale")       private var voiceLocale: String = AVSpeechSynthesisVoice.currentLanguageCode()
    @AppStorage("voiceRate")         private var voiceRate: Double = 0.47
    @AppStorage("voicePitch")        private var voicePitch: Double = 1.00          // 0.5 ... 2.0
    @AppStorage("voiceIdentifier")   private var voiceIdentifier: String = ""       // empty = use language

    // MARK: - Lifecycle
    private init() {
        configureAudioSession()
        wireNotifications()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
    }

    // MARK: - Public controls (for Settings UI)
    func isEnabled() -> Bool { voiceEnabled }
    func setEnabled(_ new: Bool) { voiceEnabled = new }
    func setLocale(_ code: String) { voiceLocale = code }
    func setVoiceIdentifier(_ id: String) { voiceIdentifier = id }
    func setPitch(_ value: Double) { voicePitch = min(max(value, 0.5), 2.0) }
    func setRate(_ value: Double)  { voiceRate  = min(max(value, 0.2), 0.7) }

    // MARK: - Speaking
    func speak(_ cue: VoiceCue) {
        speak(NSLocalizedString(cue.rawValue, comment: ""))
    }

    func speak(_ text: String) {
        print("[VoiceGuide] SPEAK CALLED: '\(text)'")
        #if DEBUG
        print("[VoiceGuide] Call stack: \(Thread.callStackSymbols.prefix(3))")
        #endif

        
        guard voiceEnabled, !text.isEmpty else {
            print("[VoiceGuide] Speaking disabled or empty text")
            return
        }

        synth.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)

        if !voiceIdentifier.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = v
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLocale)
        }

        utterance.rate = Float(voiceRate)                  // 0.0 ... 1.0 (system clamps)
        utterance.pitchMultiplier = Float(voicePitch)      // 0.5 ... 2.0

        DispatchQueue.main.async { [weak self] in self?.synth.speak(utterance) }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }

    // MARK: - Observe app events and speak (keeps views voice-free)
    private func wireNotifications() {
        print("[VoiceGuide] Setting up notification observers")
        
        // Initial welcome and instruction when home screen appears
        observers.append(NotificationCenter.default.addObserver(
            forName: .glHomeAppeared, object: nil, queue: .main
        ) { [weak self] _ in
            print("[VoiceGuide] Home appeared - giving initial instruction")
            Task { @MainActor in
                guard let self = self else { return }
                // Give initial guidance about voice interaction
                self.speak("You can communicate with GuideLight by saying Hey GuideLight. Use commands like start navigation or help to use the app.")
                
                // After the instruction, arm the wake word system
                DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                    print("[VoiceGuide] Instruction complete - sending voice system ready")
                    NotificationCenter.default.post(name: .glVoiceSystemReady, object: nil)
                }
            }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .glStartNavigationRequest, object: nil, queue: .main
        ) { [weak self] _ in
            print("[VoiceGuide] Navigation request - speaking starting nav")
            Task { @MainActor in self?.speak(.startingNav) }
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: .glSettingsOpened, object: nil, queue: .main
        ) { [weak self] _ in
            print("[VoiceGuide] Settings opened - speaking settings")
            Task { @MainActor in self?.speak(.settingsSel) }
        })
        
        observers.append(NotificationCenter.default.addObserver(
            forName: .glHelpOpened, object: nil, queue: .main
        ) { [weak self] _ in
            print("[VoiceGuide] Help opened - speaking Help")
            Task { @MainActor in self?.speak(.helpSel) }
        })
    }

    // MARK: - Audio Session (FIXED: Use playAndRecord for defaultToSpeaker)
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // FIXED: Use .playAndRecord to allow .defaultToSpeaker option
            try session.setCategory(
                .playAndRecord,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers, .defaultToSpeaker]
            )
            try session.setMode(.spokenAudio)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            print("VoiceGuide: AVAudioSession setup failed: \(error)")
            #endif
        }
    }

    // MARK: - Voice catalog helpers (for Settings UI)
    struct VoiceOption: Identifiable, Hashable {
        let id: String            // identifier ("" = System Default by language)
        let name: String          // "Samantha", "Daniel", etc.
        let language: String      // "en-US", "en-GB", etc.
        let display: String       // Friendly label for picker
    }

    // Multiple possible identifier formats for each voice
    private let curatedVoiceCatalog: [(ids: [String], name: String, language: String)] = [
        (["com.apple.ttsbundle.Samantha-compact", "com.apple.voice.compact.en-US.Samantha", "com.apple.speech.synthesis.voice.samantha"], "Samantha", "en-US"),
        (["com.apple.ttsbundle.Daniel-compact", "com.apple.voice.compact.en-GB.Daniel", "com.apple.speech.synthesis.voice.daniel"], "Daniel", "en-GB"),
        (["com.apple.ttsbundle.Karen-compact", "com.apple.voice.compact.en-AU.Karen"], "Karen", "en-AU"),
        (["com.apple.ttsbundle.Moira-compact", "com.apple.voice.compact.en-IE.Moira"], "Moira", "en-IE"),
        (["com.apple.ttsbundle.Rishi-compact", "com.apple.voice.compact.en-IN.Rishi"], "Rishi", "en-IN"),
        (["com.apple.ttsbundle.Monica-compact", "com.apple.voice.compact.es-ES.Monica"], "MÃ³nica", "es-ES"),
        (["com.apple.ttsbundle.Thomas-compact", "com.apple.voice.compact.fr-FR.Thomas"], "Thomas", "fr-FR"),
        (["com.apple.ttsbundle.Anna-compact", "com.apple.voice.compact.de-DE.Anna"], "Anna", "de-DE"),
    ]

    var availableVoiceOptions: [VoiceOption] {
        var options: [VoiceOption] = []
        let lang = AVSpeechSynthesisVoice(language: voiceLocale)?.language ?? voiceLocale
        options.append(VoiceOption(id: "", name: "System Default", language: lang,
                                   display: "System Default (by Language \(lang))"))
        
        // Try to find each curated voice using multiple possible identifiers
        for voiceInfo in curatedVoiceCatalog {
            var foundVoice: AVSpeechSynthesisVoice?
            var workingId: String?
            
            // Try each possible identifier for this voice
            for id in voiceInfo.ids {
                if let voice = AVSpeechSynthesisVoice(identifier: id) {
                    foundVoice = voice
                    workingId = id
                    break
                }
            }
            
            if let voice = foundVoice, let id = workingId {
                options.append(VoiceOption(
                    id: voice.identifier,
                    name: voiceInfo.name,
                    language: voiceInfo.language,
                    display: "\(voiceInfo.name) • \(voiceInfo.language)"
                ))
                #if DEBUG
                print("[VoiceGuide] Found voice: \(voiceInfo.name) with ID: \(id)")
                #endif
            } else {
                #if DEBUG
                print("[VoiceGuide] Voice not found: \(voiceInfo.name) (tried \(voiceInfo.ids.count) identifiers)")
                #endif
            }
        }
        
        // Also add any other English voices that might be available but not in our curated list
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        let englishVoices = allVoices.filter { voice in
            voice.language.hasPrefix("en") &&
            !options.contains { $0.id == voice.identifier }
        }
        
        for voice in englishVoices {
            options.append(VoiceOption(
                id: voice.identifier,
                name: voice.name,
                language: voice.language,
                display: "\(voice.name) • \(voice.language) (System)"
            ))
        }
        
        return options
    }

    func currentVoiceName() -> String {
        if voiceIdentifier.isEmpty {
            return "System Default (\(voiceLocale))"
        }
        return AVSpeechSynthesisVoice(identifier: voiceIdentifier)?.name ?? "Custom"
    }
    
    // MARK: - Debug Helper
    #if DEBUG
    func debugAvailableVoices() {
        print("=== ALL AVAILABLE VOICES ===")
        let allVoices = AVSpeechSynthesisVoice.speechVoices()
        for voice in allVoices.sorted(by: { $0.language < $1.language }) {
            print("ID: \(voice.identifier)")
            print("Name: \(voice.name)")
            print("Language: \(voice.language)")
            print("Quality: \(voice.quality.rawValue)")
            print("---")
        }
        
        print("\n=== ENGLISH VOICES ONLY ===")
        let englishVoices = allVoices.filter { $0.language.hasPrefix("en") }
        for voice in englishVoices {
            print("\(voice.name) - \(voice.identifier) (\(voice.language))")
        }
    }
    #endif
}
