//
//  HelpCenterView.swift
//  GuideLight v3
//
//  Hierarchical Help Center with double-tap Read Out Loud toggle.
//  Uses the previous Centered Gradient Waveform overlay (pure SwiftUI).
//

import SwiftUI
import AVFoundation

// MARK: - Read Aloud Center

final class ReadAloudCenter: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = ReadAloudCenter()

    @Published var isSpeaking: Bool = false
    @Published var currentTitle: String? = nil

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(title: String? = nil,
               text: String,
               voiceIdentifier: String? = nil,
               rate: Float = AVSpeechUtteranceDefaultSpeechRate,
               pitch: Float = 1.0,
               language: String? = nil)
    {
        stop() // prevent overlap
        let utt = AVSpeechUtterance(string: text)
        if let id = voiceIdentifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            utt.voice = v
        } else if let lang = language {
            utt.voice = AVSpeechSynthesisVoice(language: lang)
        }
        utt.rate = rate
        utt.pitchMultiplier = pitch
        currentTitle = title
        synth.speak(utt)
    }

    func stop() {
        guard isSpeaking || synth.isSpeaking else { return }
        synth.stopSpeaking(at: .immediate)
        currentTitle = nil
    }

    // MARK: AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart _: AVSpeechUtterance) {
        isSpeaking = true
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        isSpeaking = false
        currentTitle = nil
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        isSpeaking = false
        currentTitle = nil
    }
}

// MARK: - Help Topic Model

struct HelpTopic: Identifiable, Hashable {
    let id = UUID()
    let section: HelpSection
    let title: String
    let body: String
    let sfSymbol: String
}

enum HelpSection: String, CaseIterable, Identifiable {
    case gettingStarted = "Getting Started"
    case voiceCommands = "Voice Commands"
    case navigation = "Navigation & Guidance"
    case mapping = "Mapping & Beacons"
    case troubleshooting = "Troubleshooting"
    case privacy = "Privacy & Safety"
    case about = "About GuideLight"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gettingStarted: return "sparkles"
        case .voiceCommands: return "mic"
        case .navigation: return "location.north.line"
        case .mapping: return "viewfinder"
        case .troubleshooting: return "wrench.and.screwdriver"
        case .privacy: return "lock.shield"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .gettingStarted: return .blue
        case .voiceCommands: return .purple
        case .navigation: return .teal
        case .mapping: return .orange
        case .troubleshooting: return .red
        case .privacy: return .green
        case .about: return .gray
        }
    }
}

// MARK: - Content Source

private struct HelpContent {
    static let topics: [HelpTopic] = [
        // Getting Started
        HelpTopic(
            section: .gettingStarted,
            title: "What is GuideLight?",
            body: """
GuideLight is an indoor navigation companion designed for blind and visually-impaired users. It combines AR mapping, waypoints, doorway awareness, and voice/haptic guidance to help you move confidently where GPS can’t reach.
""",
            sfSymbol: "sparkles"
        ),
        HelpTopic(
            section: .gettingStarted,
            title: "Quick Start (2 minutes)",
            body: """
1) From the Home screen, say “Hey GuideLight” or tap the mic.
2) Say “Start navigation to <destination>”.
3) Follow the voice, haptics, and the on-screen arrow.
4) If you haven’t mapped the space yet, open Settings → Maps & Mapping → Start 2D Mapping.
""",
            sfSymbol: "clock.badge.checkmark"
        ),

        // Voice Commands
        HelpTopic(
            section: .voiceCommands,
            title: "Common Commands",
            body: """
- “Start navigation to Desk”
- “Cancel navigation”
- “Repeat last instruction”
- “Where am I?”
- “What’s next?”
- “Open settings”
- “Open help”
Tip: Speak naturally; you don’t need to pause between words.
""",
            sfSymbol: "mic"
        ),
        HelpTopic(
            section: .voiceCommands,
            title: "When is the app listening?",
            body: """
You will see a Mic Status Pill and hear a brief earcon when GuideLight accepts a command. States:
- Idle: app is not recording
- Listening: ready for voice
- Processing: transcribing / understanding
- Accepted: command found; brief chime plays
""",
            sfSymbol: "waveform"
        ),

        // Navigation
        HelpTopic(
            section: .navigation,
            title: "Understanding Guidance",
            body: """
- Clock-face cues: “Turn left to your 10 o’clock” correlates instruction to your body orientation.
- Breadcrumbs: Small glowing markers on the floor indicate your path; density increases near turns.
- Steps & Time: Dock shows remaining steps and ETA using your preferences from Settings → Navigation.
""",
            sfSymbol: "location.north.line"
        ),
        HelpTopic(
            section: .navigation,
            title: "Off-route & Recenter",
            body: """
If you drift off route, GuideLight will provide brief corrective voice prompts. You can also say:
- “Recenter guidance”
- “Repeat next step”
If alignment still feels off, pause, face forward, and move your phone in a slow figure-eight for a few seconds.
""",
            sfSymbol: "arrow.triangle.2.circlepath"
        ),

        // Mapping & Beacons
        HelpTopic(
            section: .mapping,
            title: "Create a 2D Map",
            body: """
Go to Settings → Maps & Mapping → Start 2D Mapping.
Place beacons at key locations: doors, intersections, desks. Save with clear names, like “Door to Passage”.
Later, navigate by saying “Start navigation to <beacon name>”.
""",
            sfSymbol: "viewfinder"
        ),
        HelpTopic(
            section: .mapping,
            title: "Doors & Doorways",
            body: """
Mark doorways between rooms and specify attributes like “left-hinged, pull to enter.” During navigation, the app will announce these details on approach.
""",
            sfSymbol: "door.left.hand.open"
        ),
        HelpTopic(
            section: .mapping,
            title: "Export / Import Maps",
            body: """
Use Settings → Maps & Mapping → Map Bundles to export a space as a portable bundle or import one you received. Bundles include your map JSON and optional ARWorldMap.
""",
            sfSymbol: "square.and.arrow.up.on.square"
        ),

        // Troubleshooting
        HelpTopic(
            section: .troubleshooting,
            title: "I’m not hearing any announcements",
            body: """
- Ensure Accessibility & Voice is enabled (Settings → Accessibility & Voice).
- Increase the device volume and ringer.
- If VoiceOver is running, confirm it doesn’t fully mute app speech.
- Try “Repeat last instruction.”
""",
            sfSymbol: "speaker.slash"
        ),
        HelpTopic(
            section: .troubleshooting,
            title: "Clock overlay looks reversed",
            body: """
This indicates heading polarity was flipped by a recent calibration or update. Recenter by facing forward and slowly moving the phone in a figure-eight. If it persists, toggle navigation off/on.
""",
            sfSymbol: "clock"
        ),
        HelpTopic(
            section: .troubleshooting,
            title: "Doorway announcements repeat",
            body: """
This can occur if you pause directly on a doorway trigger. Continue walking past the threshold, or say “Mute doorway” if you need silence briefly. (Developers: ensure debounce/cool-down is enabled.)
""",
            sfSymbol: "door.garage.open"
        ),

        // Privacy & Safety
        HelpTopic(
            section: .privacy,
            title: "Your Data",
            body: """
GuideLight stores your maps locally on device by default. You can export them when you choose. Voice commands are processed on-device when possible; otherwise, only the minimal audio needed for recognition is used.
""",
            sfSymbol: "lock.shield"
        ),
        HelpTopic(
            section: .privacy,
            title: "Safety Reminder",
            body: """
Always remain aware of your surroundings. Use GuideLight as an assistive aid, not a replacement for a cane or guide dog.
""",
            sfSymbol: "exclamationmark.triangle"
        ),

        // About
        HelpTopic(
            section: .about,
            title: "About GuideLight",
            body: """
GuideLight helps you navigate indoor spaces with confidence, using AR mapping, AI vision, and clear voice guidance.
Version 1.0
""",
            sfSymbol: "info.circle"
        ),
    ]

    static func topics(in section: HelpSection) -> [HelpTopic] {
        topics.filter { $0.section == section }
    }

    static var quickStartText: String {
        """
Say “Hey GuideLight”, then “Start navigation to Desk.” \
Follow voice and arrow. Use Settings → Maps & Mapping to create or import maps.
"""
    }

    static var contactSupportAssistiveText: String {
        "Write a short description of the issue. Turn on Include Diagnostics to send logs and device info."
    }
}

// MARK: - Root Help Center (double-tap toggles reading Quick Start)

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var showQuickStart: Bool = true
    @StateObject private var reader = ReadAloudCenter.shared

    private var allSections: [HelpSection] { HelpSection.allCases }

    private var filteredTopics: [HelpTopic] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return HelpContent.topics }
        return HelpContent.topics.filter { t in
            t.title.localizedCaseInsensitiveContains(q) ||
            t.body.localizedCaseInsensitiveContains(q) ||
            t.section.rawValue.localizedCaseInsensitiveContains(q)
        }
    }

    private func toggleRootRead() {
        let textToRead: String = showQuickStart && query.isEmpty
            ? HelpContent.quickStartText
            : "Help Center. Double tap any screen to toggle Read Out Loud."
        if reader.isSpeaking {
            reader.stop()
        } else {
            reader.speak(
                title: "Help",
                text: textToRead,
                language: AVSpeechSynthesisVoice.currentLanguageCode()
            )
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if showQuickStart && query.isEmpty {
                        QuickStartCard()
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                    }

                    ForEach(allSections) { section in
                        let topics = filteredTopics.filter { $0.section == section }
                        if !topics.isEmpty {
                            Section {
                                ForEach(topics) { topic in
                                    NavigationLink(value: topic) {
                                        Label(topic.title, systemImage: topic.sfSymbol)
                                            .accessibilityHint(section.rawValue)
                                    }
                                }
                            } header: {
                                HStack(spacing: 8) {
                                    Image(systemName: section.icon)
                                        .foregroundStyle(section.tint)
                                    Text(section.rawValue)
                                }
                                .textCase(nil)
                            }
                        }
                    }

                    Section {
                        NavigationLink {
                            ContactSupportView()
                        } label: {
                            Label("Contact Support", systemImage: "envelope")
                        }
                    } footer: {
                        Text("Can’t find what you need? Send logs and a short description so we can help.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
                .navigationDestination(for: HelpTopic.self) { topic in
                    HelpTopicDetailView(topic: topic)
                }
                .onTapGesture(count: 2) { toggleRootRead() } // double-tap toggle

                // Centered Gradient Waveform Overlay — shown while speaking
                if reader.isSpeaking {
                    WaveformOverlay()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation { showQuickStart.toggle() }
                    } label: {
                        Image(systemName: showQuickStart ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                            .accessibilityLabel(showQuickStart ? "Hide Quick Start" : "Show Quick Start")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search help")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap anywhere to toggle Read Out Loud.")
        }
    }
}

// MARK: - Quick Start Card

private struct QuickStartCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").imageScale(.large)
                Text("Quick Start").font(.headline)
            }
            Text("""
Say “Hey GuideLight” → “Start navigation to Desk”.
Follow the voice & arrow. Use Settings → Maps & Mapping to create or import maps.
""")
            .font(.subheadline)
            .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Label("Voice-first", systemImage: "mic")
                Label("Doorway cues", systemImage: "door.left.hand.open")
                Label("Breadcrumbs", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Topic Detail (double-tap reads that topic)

struct HelpTopicDetailView: View {
    let topic: HelpTopic
    @StateObject private var reader = ReadAloudCenter.shared

    private func toggleTopicRead() {
        if reader.isSpeaking {
            reader.stop()
        } else {
            reader.speak(
                title: topic.title,
                text: topic.body,
                language: AVSpeechSynthesisVoice.currentLanguageCode()
            )
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: topic.sfSymbol)
                            .foregroundStyle(color(for: topic.section))
                        Text(topic.title)
                            .font(.title3).bold()
                            .accessibilityHeading(.h1)
                    }

                    Text(topic.body)
                        .font(.body)
                        .accessibilityLabel(topic.body)

                    if topic.section == .voiceCommands {
                        ExampleBox(lines: [
                            "“Start navigation to Conference Room”",
                            "“Repeat last instruction”",
                            "“Open settings”"
                        ])
                    }
                }
                .padding()
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { toggleTopicRead() } // double-tap toggle

            if reader.isSpeaking {
                WaveformOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .navigationTitle(topic.section.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityHint("Double tap anywhere to toggle Read Out Loud.")
    }

    private func color(for section: HelpSection) -> Color {
        section.tint
    }
}

private struct ExampleBox: View {
    let lines: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples")
                .font(.subheadline).bold()
            ForEach(lines, id: \.self) { line in
                HStack(spacing: 8) {
                    Image(systemName: "quote.opening")
                    Text(line)
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        )
    }
}

// MARK: - Contact Support (double-tap reads helper text)

struct ContactSupportView: View {
    @State private var includeDiagnostics: Bool = true
    @State private var message: String = ""
    @StateObject private var reader = ReadAloudCenter.shared

    private func toggleSupportRead() {
        if reader.isSpeaking {
            reader.stop()
        } else {
            reader.speak(
                title: "Contact Support",
                text: HelpContent.contactSupportAssistiveText,
                language: AVSpeechSynthesisVoice.currentLanguageCode()
            )
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    var body: some View {
        ZStack {
            Form {
                Section("Message") {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                        .accessibilityLabel("Support message")
                }

                Section {
                    Toggle("Include Diagnostics", isOn: $includeDiagnostics)
                    Text("Includes recent logs and device info to help diagnose issues.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { toggleSupportRead() } // double-tap toggle

            if reader.isSpeaking {
                WaveformOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .navigationTitle("Contact Support")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityHint("Double tap anywhere to toggle Read Out Loud.")
    }
}

// =====================================================================
// MARK: - Centered Gradient Waveform Overlay (pure SwiftUI)  << REUSED
// =====================================================================

private struct WaveformOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    // Appearance
    private let overlayHeight: CGFloat = 120
    private let corner: CGFloat = 18
    private let lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            // Soft translucent background
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.thinMaterial)
                .background(Color.black.opacity(0.25))
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .frame(height: overlayHeight)
                .padding(.horizontal, 24)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 2)

            // Three layered harmonic waves with gradient stroke
            ZStack {
                SineWaveShape(amplitude: 18, frequency: 1.2, phase: phase)
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .blendMode(.plusLighter)
                SineWaveShape(amplitude: 26, frequency: 1.5, phase: phase + .pi / 3)
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth - 0.8, lineCap: .round, lineJoin: .round))
                    .blendMode(.plusLighter)
                SineWaveShape(amplitude: 34, frequency: 1.8, phase: phase + 2 * .pi / 3)
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth - 1.2, lineCap: .round, lineJoin: .round))
                    .blendMode(.plusLighter)
            }
            .frame(height: overlayHeight - 26)
            .padding(.horizontal, 36)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center) // centered on screen
        .onAppear { startAnimationIfNeeded() }
        .transition(.opacity)
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.0),
                Color.yellow.opacity(0.85),
                Color.green.opacity(0.95),
                Color.cyan.opacity(0.85),
                Color.white.opacity(0.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func startAnimationIfNeeded() {
        guard !reduceMotion else { return }
        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
            phase = 2 * .pi
        }
    }
}

// MARK: - Sine Wave Shape

private struct SineWaveShape: Shape {
    var amplitude: CGFloat       // in points
    var frequency: CGFloat       // cycles across width
    var phase: CGFloat           // radians; drives animation

    // Animate only phase for smooth continuous motion
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let width = rect.width

        // Adaptive step for performance + smoothness
        let step = max(1.0, width / 180.0)
        var x: CGFloat = 0
        var first = true

        while x <= width {
            let progress = x / width
            let angle = progress * frequency * 2 * .pi + phase
            let y = midY + sin(angle) * amplitude
            let point = CGPoint(x: x + rect.minX, y: y)
            if first {
                path.move(to: point)
                first = false
            } else {
                path.addLine(to: point)
            }
            x += step
        }
        return path
    }
}

// MARK: - Preview

#Preview {
    HelpCenterView()
}
