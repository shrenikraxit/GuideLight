//
//  SimpleSpeechCommandCenter.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/19/25.
//


//
//  SimpleSpeechCommandCenter.swift
//  GuideLight v3
//
//  Pure speech recognition - no wake word engine needed
//

import Foundation
import Speech
import AVFoundation
import SwiftUI

@MainActor
final class SimpleSpeechCommandCenter: ObservableObject {
    static let shared = SimpleSpeechCommandCenter()
    
    @Published private(set) var isListening: Bool = false
    @Published private(set) var lastHeardText: String = ""
    
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private init() {
        requestPermissions()
    }
    
    // MARK: - Public Interface
    func startListening() {
        guard !isListening else { return }
        
        Task {
            guard await hasPermissions() else {
                print("[Speech] Missing permissions")
                return
            }
            
            await startContinuousListening()
        }
    }
    
    func stopListening() {
        guard isListening else { return }
        
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        isListening = false
        print("[Speech] Stopped listening")
    }
    
    // MARK: - Continuous Speech Recognition
    private func startContinuousListening() async {
        do {
            try setupAudioSession()
            try startRecognition()
            isListening = true
            print("[Speech] Started continuous listening for commands")
        } catch {
            print("[Speech] Failed to start: \(error)")
        }
    }
    
    private func startRecognition() throws {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { throw NSError(domain: "Speech", code: 1) }
        
        recognitionRequest.shouldReportPartialResults = true
        if #available(iOS 17.0, *) {
            recognitionRequest.requiresOnDeviceRecognition = true
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            
            if let result = result {
                let transcript = result.bestTranscription.formattedString.lowercased()
                self.lastHeardText = transcript
                
                // Process complete phrases that include "hey guidelight"
                if transcript.contains("hey guidelight") || transcript.contains("hey guide light") {
                    self.processCommand(transcript)
                }
                
                // Reset recognition if it gets too long or final
                if result.isFinal || transcript.count > 100 {
                    Task { @MainActor in
                        self.restartRecognition()
                    }
                }
            }
            
            if let error = error {
                print("[Speech] Recognition error: \(error)")
                Task { @MainActor in
                    self.restartRecognition()
                }
            }
        }
    }
    
    private func restartRecognition() {
        // Restart recognition to keep listening continuously
        recognitionTask?.cancel()
        recognitionRequest?.endAudio()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            if let self = self, self.isListening {
                Task {
                    try? self.startRecognition()
                }
            }
        }
    }
    
    // MARK: - Command Processing
    private func processCommand(_ text: String) {
        print("[Speech] Processing: '\(text)'")
        
        // Navigation commands
        if text.contains("start navigation") || text.contains("begin navigation") || text.contains("open navigation") {
            print("[Speech] Starting navigation")
            NotificationCenter.default.post(
                name: .glVoiceNavigateCommand,
                object: nil,
                userInfo: ["destination": ""]
            )
            return
        }
        
        // Help command
        if text.contains("help") {
            print("[Speech] Opening help")
            NotificationCenter.default.post(name: .glHelpOpened, object: nil)
            return
        }
        
        // Settings command
        if text.contains("settings") {
            print("[Speech] Opening settings")
            NotificationCenter.default.post(name: .glSettingsOpened, object: nil)
            return
        }
        
        // Navigation with destination
        if text.contains("take me to") || text.contains("navigate to") || text.contains("go to") || text.contains("show me the path to") {
            if let destination = extractDestination(from: text) {
                print("[Speech] Navigating to: \(destination)")
                NotificationCenter.default.post(
                    name: .glVoiceNavigateCommand,
                    object: nil,
                    userInfo: ["destination": destination]
                )
                return
            }
        }
        
        print("[Speech] Command not recognized: '\(text)'")
    }
    
    private func extractDestination(from text: String) -> String? {
        let patterns = [
            #"take me to (.+)"#,
            #"navigate to (.+)"#,
            #"go to (.+)"#,
            #"show me the path to (.+)"#
        ]
        
        for pattern in patterns {
            if let destination = extractWithRegex(text: text, pattern: pattern) {
                return destination.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
    
    private func extractWithRegex(text: String, pattern: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            let range = NSRange(location: 0, length: text.utf16.count)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                let captureRange = match.range(at: 1)
                if captureRange.location != NSNotFound,
                   let swiftRange = Range(captureRange, in: text) {
                    return String(text[swiftRange])
                }
            }
        } catch {}
        return nil
    }
    
    // MARK: - Permissions & Audio
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }
    
    private func hasPermissions() async -> Bool {
        let speechAuth = SFSpeechRecognizer.authorizationStatus()
        let micAuth = AVAudioSession.sharedInstance().recordPermission
        return speechAuth == .authorized && micAuth == .granted
    }
    
    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setMode(.measurement)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
}