//
//  SettingsView.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 10/25/25.
//


//
//  SettingsView.swift
//  GuideLight v3
//
//  Hierarchical Settings hub with focused subpages.
//  Pure re-layout: existing @AppStorage keys & behaviors preserved.
//

import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Notification for launching the mapping flow
extension Notification.Name {
    static let triggerPathfinderMapping = Notification.Name("TriggerPathfinderMapping")
}

// MARK: - Settings Hub
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceGuide.shared

    // ===== Persisted app settings (unchanged keys) =====
    // Accessibility & Voice
    @AppStorage("voiceFirstEnabled") private var voiceEnabled: Bool = UIAccessibility.isVoiceOverRunning
    @AppStorage("voiceRate")  private var voiceRate: Double  = 0.47
    @AppStorage("voicePitch") private var voicePitch: Double = 1.00
    @AppStorage("voiceLocale") private var voiceLocale: String = AVSpeechSynthesisVoice.currentLanguageCode()
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = ""

    // Navigation preferences (dock)
    @AppStorage("stepsPerMeter") private var stepsPerMeter: Double = 1.35
    @AppStorage("walkingSpeedMps") private var walkingSpeedMps: Double = 1.20

    // Breadcrumbs (visual guidance)
    @AppStorage("breadcrumbsEnabled") private var breadcrumbsEnabled: Bool = true
    @AppStorage("breadcrumbsTrailLengthM") private var breadcrumbsTrailLengthM: Double = 8.0
    @AppStorage("breadcrumbsSpacingM") private var breadcrumbsSpacingM: Double = 0.8
    @AppStorage("breadcrumbsGlowEnabled") private var breadcrumbsGlowEnabled: Bool = true
    @AppStorage("breadcrumbsPulseSeconds") private var breadcrumbsPulseSeconds: Double = 1.8
    @AppStorage("breadcrumbsColorScheme") private var breadcrumbsColorScheme: String = "Green"

    private let colorSchemes = ["Green","Cyan","Yellow","Magenta","White","Orange","Blue"]

    var body: some View {
        NavigationStack {
            List {
                // 1) Accessibility & Voice (drill-down)
                Section {
                    NavigationLink {
                        VoiceSettingsView(
                            voice: voice,
                            voiceEnabled: $voiceEnabled,
                            voiceIdentifier: $voiceIdentifier,
                            voiceLocale: $voiceLocale,
                            voiceRate: $voiceRate,
                            voicePitch: $voicePitch
                        )
                    } label: {
                        HStack {
                            Label("Accessibility & Voice", systemImage: "waveform")
                            Spacer()
                            Text(voiceSummary)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                    }
                }

                // 2) Navigation (dock prefs)
                Section {
                    NavigationLink {
                        NavigationPrefsView(
                            stepsPerMeter: $stepsPerMeter,
                            walkingSpeedMps: $walkingSpeedMps
                        )
                    } label: {
                        HStack {
                            Label("Navigation", systemImage: "figure.walk")
                            Spacer()
                            Text(String(format: "%.2f steps/m • %.2f m/s", stepsPerMeter, walkingSpeedMps))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 3) Visual Guidance (Breadcrumbs)
                Section {
                    NavigationLink {
                        VisualGuidanceSettingsView(
                            breadcrumbsEnabled: $breadcrumbsEnabled,
                            breadcrumbsTrailLengthM: $breadcrumbsTrailLengthM,
                            breadcrumbsSpacingM: $breadcrumbsSpacingM,
                            breadcrumbsGlowEnabled: $breadcrumbsGlowEnabled,
                            breadcrumbsPulseSeconds: $breadcrumbsPulseSeconds,
                            breadcrumbsColorScheme: $breadcrumbsColorScheme,
                            colorSchemes: colorSchemes
                        )
                    } label: {
                        HStack {
                            Label("Visual Guidance", systemImage: "sparkles")
                            Spacer()
                            Text("\(breadcrumbsEnabled ? "On" : "Off") • \(breadcrumbsColorScheme)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 4) Maps & Mapping hub
                Section {
                    NavigationLink {
                        MapsHubView()
                    } label: {
                        HStack {
                            Label("Maps & Mapping", systemImage: "map")
                            Spacer()
                            Text("Create • Manage • Share")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // 5) About
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack {
                            Label("About", systemImage: "info.circle")
                            Spacer()
                            Text("Version 1.0")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        // Keep your existing mapping launcher attached at the root
        .mappingLauncher()
    }

    // MARK: - Compact summary helpers
    private var voiceSummary: String {
        let onOff = voiceEnabled ? "On" : "Off"
        // Show chosen voice if set; else locale as fallback
        if !voiceIdentifier.isEmpty,
           let option = voice.availableVoiceOptions.first(where: { $0.id == voiceIdentifier }) {
            return "\(onOff) • \(option.display)"
        } else {
            return "\(onOff) • \(voiceLocale)"
        }
    }
}

// MARK: - Voice Settings (detail)
struct VoiceSettingsView: View {
    @ObservedObject var voice: VoiceGuide

    @Binding var voiceEnabled: Bool
    @Binding var voiceIdentifier: String
    @Binding var voiceLocale: String
    @Binding var voiceRate: Double
    @Binding var voicePitch: Double

    var body: some View {
        Form {
            // Voice toggle
            Section {
                Toggle(isOn: $voiceEnabled) {
                    Label("Voice Guidance", systemImage: "waveform")
                }
                .onChange(of: voiceEnabled) { _, new in
                    voice.setEnabled(new)
                    if new { voice.speak("Voice guidance enabled.") } else { voice.stop() }
                }
            }

            // Voice selection + language fallback
            if voiceEnabled {
                Section {
                    Picker("Voice", selection: $voiceIdentifier) {
                        ForEach(voice.availableVoiceOptions) { option in
                            Text(option.display).tag(option.id)
                        }
                    }
                    .onChange(of: voiceIdentifier) { _, new in
                        voice.setVoiceIdentifier(new)
                        voice.speak("Voice changed.")
                    }

                    Picker("Language (fallback)", selection: $voiceLocale) {
                        let common = ["en-US","en-GB","es-ES","fr-FR","de-DE","hi-IN"]
                        ForEach(common, id: \.self) { code in
                            Text(code).tag(code)
                        }
                    }
                    .onChange(of: voiceLocale) { _, new in
                        voice.setLocale(new)
                        if voiceIdentifier.isEmpty { voice.speak("Language changed.") }
                    }
                } footer: {
                    Text("If a specific voice isn’t selected, the app uses the language fallback.")
                }

                // Rate / Pitch
                Section("Speech") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Speech Speed", systemImage: "speedometer")
                            Spacer()
                            Text(String(format: "%.2f", voiceRate)).foregroundColor(.secondary)
                        }
                        Slider(value: $voiceRate, in: 0.20...0.70, step: 0.01)
                            .onChange(of: voiceRate) { _, new in
                                voice.setRate(new)
                                voice.speak("Speech speed adjusted.")
                            }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Tone (Pitch)", systemImage: "slider.horizontal.3")
                            Spacer()
                            Text(String(format: "%.2f", voicePitch)).foregroundColor(.secondary)
                        }
                        Slider(value: $voicePitch, in: 0.70...1.30, step: 0.01)
                            .onChange(of: voicePitch) { _, new in
                                voice.setPitch(new)
                                voice.speak("Pitch adjusted.")
                            }
                    }

                    Button {
                        voice.speak(.test)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2.fill")
                            Text("Test Voice")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .accessibilityLabel("Test Voice")
                    .accessibilityHint("Plays a short sample with the current voice settings.")
                    .padding(.top, 2)
                }
            }
        }
        .navigationTitle("Accessibility & Voice")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Navigation Prefs (detail)
struct NavigationPrefsView: View {
    @Binding var stepsPerMeter: Double
    @Binding var walkingSpeedMps: Double

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Steps per meter", systemImage: "figure.walk")
                        Spacer()
                        Text(String(format: "%.2f", stepsPerMeter)).foregroundColor(.secondary)
                    }
                    Slider(value: $stepsPerMeter, in: 0.80...2.50, step: 0.05)
                    Text("Typical adult stride ≈ 1.3–1.5 steps/m")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Walking speed", systemImage: "speedometer")
                        Spacer()
                        Text(String(format: "%.2f m/s", walkingSpeedMps)).foregroundColor(.secondary)
                    }
                    Slider(value: $walkingSpeedMps, in: 0.40...2.00, step: 0.05)
                    Text("Indoor pace: ~1.0–1.4 m/s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            } footer: {
                Text("These settings affect the navigation dock: distance is shown in steps, and time is calculated from your walking speed.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Navigation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Visual Guidance / Breadcrumbs (detail)
struct VisualGuidanceSettingsView: View {
    @Binding var breadcrumbsEnabled: Bool
    @Binding var breadcrumbsTrailLengthM: Double
    @Binding var breadcrumbsSpacingM: Double
    @Binding var breadcrumbsGlowEnabled: Bool
    @Binding var breadcrumbsPulseSeconds: Double
    @Binding var breadcrumbsColorScheme: String

    let colorSchemes: [String]

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $breadcrumbsEnabled) {
                    Label("Show breadcrumbs", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Trail length")
                        Spacer()
                        Text(String(format: "%.1f m", breadcrumbsTrailLengthM))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $breadcrumbsTrailLengthM, in: 3.0...20.0, step: 0.5)

                    HStack {
                        Text("Spacing")
                        Spacer()
                        Text(String(format: "%.2f m", breadcrumbsSpacingM))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $breadcrumbsSpacingM, in: 0.3...2.0, step: 0.05)
                }

                Toggle(isOn: $breadcrumbsGlowEnabled) {
                    Label("Glow", systemImage: "sparkles")
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pulse speed")
                        Spacer()
                        Text(String(format: "%.1f s", breadcrumbsPulseSeconds))
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $breadcrumbsPulseSeconds, in: 0.6...3.0, step: 0.1)
                }

                Picker("Color scheme", selection: $breadcrumbsColorScheme) {
                    ForEach(colorSchemes, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            } footer: {
                Text("Small glowing arrows on the floor show the path ahead. Density increases near turns; the trail fades on arrival.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Visual Guidance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Maps & Mapping Hub
struct MapsHubView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    MappingLauncherView()
                } label: {
                    Label("Mapping & Navigation", systemImage: "viewfinder")
                }

                NavigationLink {
                    // Your existing maps list (unchanged)
                    SimpleJSONMapsListView()
                } label: {
                    Label("Manage Maps", systemImage: "list.bullet.rectangle")
                }

                NavigationLink {
                    MapBundlesView()
                } label: {
                    Label("Map Bundles", systemImage: "square.and.arrow.up.on.square")
                }
            }
        }
        .navigationTitle("Maps & Mapping")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Mapping Launcher (posts your notification)
struct MappingLauncherView: View {
    var body: some View {
        Form {
            Section {
                Button {
                    NotificationCenter.default.post(name: .triggerPathfinderMapping, object: nil)
                } label: {
                    HStack {
                        Image(systemName: "viewfinder")
                        Text("Start 2D Mapping")
                    }
                }
                .buttonStyle(.bordered)

                Text("Create indoor maps by placing beacons at important locations and marking doorways between rooms.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Mapping & Navigation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Map Bundles (Export / Import) – moved here; logic preserved
struct MapBundlesView: View {
    @ObservedObject private var jsonMaps = SimpleJSONMapManager.shared

    @State private var selectedMapId: UUID?
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        Form {
            Section {
                if jsonMaps.maps.isEmpty {
                    Text("No JSON maps found").foregroundColor(.secondary)
                } else {
                    Picker("Select a map", selection: $selectedMapId) {
                        ForEach(jsonMaps.maps, id: \.id) { map in
                            Text("\(map.name) • \(map.createdDate.formatted(date: .abbreviated, time: .shortened))")
                                .tag(map.id as UUID?)
                        }
                    }
                    .onAppear {
                        if selectedMapId == nil { selectedMapId = jsonMaps.maps.first?.id }
                    }

                    HStack {
                        Button {
                            guard let id = selectedMapId,
                                  let map = jsonMaps.maps.first(where: { $0.id == id }) else { return }
                            do {
                                let bundle = try MapPackageManager.createBundle(for: map)
                                let archive = try MapPackageManager.zipBundle(bundle)
                                shareURL = archive
                                showShare = true
                            } catch {
                                importMessage = "Export failed: \(error.localizedDescription)"
                            }
                        } label: {
                            Label("Export Selected Map", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            showImporter = true
                        } label: {
                            Label("Import Map", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                    }

                    if let msg = importMessage {
                        Text(msg).font(.caption).foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Packages map.json + ARWorldMap (if present) and an images folder into a single portable bundle you can AirDrop or share.")
            }
        }
        .navigationTitle("Map Bundles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShare, onDismiss: { shareURL = nil }) {
            if let url = shareURL {
                ActivityView(activityItems: [url]).ignoresSafeArea()
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [UTType(filenameExtension: "zipjson")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    _ = try MapPackageManager.unzipBundle(url)
                    importMessage = "Imported bundle: \(url.lastPathComponent)"
                } catch {
                    importMessage = "Import failed: \(error.localizedDescription)"
                }
            case .failure(let error):
                importMessage = "Import cancelled: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - About (detail)
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GuideLight")
                        .font(.headline)
                    Text("Indoor navigation assistance for blind users")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0").foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Share sheet
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SettingsView()
}
