//
//  SettingsView.swift
//  GuideLight v3
//
//  Created by Indraneel Rakshit on 9/21/25.
//

import SwiftUI
import Foundation
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Notification for launching the mapping flow
extension Notification.Name {
    static let triggerPathfinderMapping = Notification.Name("TriggerPathfinderMapping")
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceGuide.shared

    // Persisted app settings
    @AppStorage("voiceFirstEnabled") private var voiceEnabled: Bool = UIAccessibility.isVoiceOverRunning
    @AppStorage("voiceRate")  private var voiceRate: Double  = 0.47     // 0.2...0.7 recommended
    @AppStorage("voicePitch") private var voicePitch: Double = 1.00     // 0.5...2.0
    @AppStorage("voiceLocale") private var voiceLocale: String = AVSpeechSynthesisVoice.currentLanguageCode()
    @AppStorage("voiceIdentifier") private var voiceIdentifier: String = "" // empty = system default by language

    // Navigation preferences used by the dock
    @AppStorage("stepsPerMeter") private var stepsPerMeter: Double = 1.35     // typical 1.3–1.5
    @AppStorage("walkingSpeedMps") private var walkingSpeedMps: Double = 1.20 // indoor pace ~1.0–1.4

    // NEW: Breadcrumbs preferences
    @AppStorage("breadcrumbsEnabled") private var breadcrumbsEnabled: Bool = true
    @AppStorage("breadcrumbsTrailLengthM") private var breadcrumbsTrailLengthM: Double = 8.0
    @AppStorage("breadcrumbsSpacingM") private var breadcrumbsSpacingM: Double = 0.8
    @AppStorage("breadcrumbsGlowEnabled") private var breadcrumbsGlowEnabled: Bool = true
    @AppStorage("breadcrumbsPulseSeconds") private var breadcrumbsPulseSeconds: Double = 1.8
    @AppStorage("breadcrumbsColorScheme") private var breadcrumbsColorScheme: String = "Green"

    private let colorSchemes = ["Green","Cyan","Yellow","Magenta","White","Orange","Blue"]

    // NEW: Map bundle export/import UI state
    @ObservedObject private var jsonMaps = SimpleJSONMapManager.shared
    @State private var selectedMapId: UUID?
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var showImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationView {
            Form {

                // =========================
                // MARK: Accessibility & Voice
                // =========================
                Section {
                    Toggle(isOn: $voiceEnabled) {
                        Label("Voice Guidance", systemImage: "waveform")
                    }
                    .onChange(of: voiceEnabled) { old, new in
                        voice.setEnabled(new)
                        if new { voice.speak("Voice guidance enabled.") } else { voice.stop() }
                    }

                    if voiceEnabled {
                        // Specific Voice Picker (identifier)
                        Picker("Voice", selection: $voiceIdentifier) {
                            ForEach(voice.availableVoiceOptions) { option in
                                Text(option.display).tag(option.id) // tag type = String
                            }
                        }
                        .onChange(of: voiceIdentifier) { old, new in
                            voice.setVoiceIdentifier(new)
                            voice.speak("Voice changed.")
                        }

                        // Language fallback (used only when identifier is empty)
                        Picker("Language (fallback)", selection: $voiceLocale) {
                            let common = ["en-US","en-GB","es-ES","fr-FR","de-DE","hi-IN"]
                            ForEach(common, id: \.self) { code in
                                Text(code).tag(code) // tag type = String
                            }
                        }
                        .onChange(of: voiceLocale) { old, new in
                            voice.setLocale(new)
                            if voiceIdentifier.isEmpty { voice.speak("Language changed.") }
                        }

                        // Speech speed
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Speech Speed", systemImage: "speedometer")
                                Spacer()
                                Text(String(format: "%.2f", voiceRate))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $voiceRate, in: 0.20...0.70, step: 0.01) {
                                Text("Speech Speed")
                            } minimumValueLabel: {
                                Text("Slow")
                            } maximumValueLabel: {
                                Text("Fast")
                            }
                            .onChange(of: voiceRate) { old, new in
                                voice.setRate(new)
                                voice.speak("Speech speed adjusted.")
                            }
                        }

                        // Tone (Pitch)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Tone (Pitch)", systemImage: "slider.horizontal.3")
                                Spacer()
                                Text(String(format: "%.2f", voicePitch))
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $voicePitch, in: 0.70...1.30, step: 0.01) {
                                Text("Tone")
                            } minimumValueLabel: {
                                Text("Lower")
                            } maximumValueLabel: {
                                Text("Higher")
                            }
                            .onChange(of: voicePitch) { old, new in
                                voice.setPitch(new)
                                voice.speak("Pitch adjusted.")
                            }
                        }

                        // Test Voice
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
                } header: {
                    Text("Accessibility & Voice")
                }

                // =========================
                // MARK: Navigation Preferences (Dock)
                // =========================
                Section {
                    // Steps per meter
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Steps per meter", systemImage: "figure.walk")
                            Spacer()
                            Text(String(format: "%.2f", stepsPerMeter))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $stepsPerMeter, in: 0.80...2.50, step: 0.05)
                        Text("Typical adult stride ≈ 1.3–1.5 steps/m")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Walking speed (m/s)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Walking speed", systemImage: "speedometer")
                            Spacer()
                            Text(String(format: "%.2f m/s", walkingSpeedMps))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $walkingSpeedMps, in: 0.40...2.00, step: 0.05)
                        Text("Indoor pace: ~1.0–1.4 m/s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Navigation Preferences")
                } footer: {
                    Text("These settings affect the navigation dock: distance is shown in steps, and time is calculated from your walking speed.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // =========================
                // MARK: Breadcrumbs (NEW)
                // =========================
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
                } header: {
                    Text("Breadcrumbs")
                } footer: {
                    Text("Small glowing arrows on the floor show the path ahead. Density increases near turns; the trail fades on arrival.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // =========================
                // MARK: Pathfinder Settings
                // =========================
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mapping & Navigation")
                            .font(.headline)

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
                } header: {
                    Text("Pathfinder Settings")
                }

                // =========================
                // MARK: JSON Maps Section
                // =========================
                Section {
                    NavigationLink(destination: SimpleJSONMapsListView()) {
                        Text("Manage Maps")
                    }
                } header: {
                    Text("JSON Maps")
                }

                // =========================
                // MARK: Map Bundles (Export / Import)
                // =========================
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
                } header: { Text("Map Bundles") }
                  footer: { Text("Packages map.json + ARWorldMap (if present) and an images folder into a single portable bundle you can AirDrop or share.") }

                // =========================
                // MARK: App Information
                // =========================
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
                            Text("1.0")
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("About")
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
        .sheet(isPresented: $showShare, onDismiss: { shareURL = nil }) {
            if let url = shareURL {
                ActivityView(activityItems: [url])
                    .ignoresSafeArea()
            }
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [UTType(filenameExtension: "zipjson")!],
                      allowsMultipleSelection: false) { result in
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
        // Attach mapping launcher
        .mappingLauncher()
    }
}

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
