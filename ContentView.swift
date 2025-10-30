//
//  ContentView.swift
//  GuideLight v3
//
//  Landing page with pure speech recognition - no Porcupine
//

import SwiftUI
import UIKit

enum HubDestination: String, Identifiable {
    case navigation = "Pathfinder"
    case settings   = "Settings"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var showingPathNavigation = false
    @State private var showHelpView = false
    @State private var showSettingsSheet = false
    @StateObject private var speechCenter = SimpleSpeechCommandCenter.shared

    // Voice handoff
    @State private var pendingVoiceDestination: String? = nil
    @State private var launchedFromVoice = false
    
    // NEW: Track if welcome announcement has been played
    @State private var hasPlayedWelcomeAnnouncement = false

    // Haptics (kept local to UI)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticHeavy = UIImpactFeedbackGenerator(style: .heavy)

    private let swipeThreshold: CGFloat = 60

    // Brand colors
    private let brandNavy   = Color(red: 0.11, green: 0.17, blue: 0.29)
    private let brandYellow = Color(red: 1.00, green: 0.84, blue: 0.35)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                brandNavy.ignoresSafeArea()

                VStack(spacing: 24) {
                    // MARK: Logo + Title + Tagline
                    VStack(spacing: 8) {
                        ARPortalLogoView(imageName: "GuideLightLogo", size: 220)
                            .padding(.top, 12)
                            .accessibilityHidden(true)

                        Text("GuideLight")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)

                        Text("Indoor navigation companion for the blind")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .accessibilityHidden(true)
                        
                        Text("Just say ‘Hey GuideLight’ to begin.")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .lineSpacing(2)
                            .minimumScaleFactor(0.9)
                            .padding(.horizontal, 32)
                            .accessibilityHidden(true)
                    }
                    .accessibilitySortPriority(2)

                    // MARK: Primary CTA — Start Navigation (high contrast, large)
                    Button(action: startNavTap) {
                        HStack(spacing: 16) {
                            Image(systemName: "location.fill")
                                .font(.title2.weight(.semibold))
                            Text("Start Navigation")
                                .font(.title3.bold())
                        }
                        .foregroundStyle(brandNavy)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(brandYellow)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
                    }
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Start Navigation")
                    .accessibilityHint("Begin indoor navigation session. Swipe right or use voice command.")
                    .accessibilitySortPriority(1)

                    // Spacer to maintain layout
                    Spacer(minLength: 0)
                }
                .padding(.top, 20)

                // MARK: Help & Settings orbs (bottom corners)
                HStack {
                    // HELP (bottom-left)
                    Button(action: { showHelpView = true }) {
                        BottomOrb(icon: "questionmark")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        hapticLight.impactOccurred()
                        NotificationCenter.default.post(name: .glHelpOpened, object: nil)
                    })
                    .accessibilityLabel("Help")
                    .accessibilityHint("Opens help information and voice commands.")

                    Spacer(minLength: 0)

                    // SETTINGS (bottom-right)
                    NavigationLink(destination: SettingsView()) {
                        BottomOrb(icon: "gearshape.fill")
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        hapticLight.impactOccurred()
                        NotificationCenter.default.post(name: .glSettingsOpened, object: nil)
                    })
                    .accessibilityLabel("Settings")
                    .accessibilityHint("Opens app settings and map management.")
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .zIndex(2)

                // MARK: Full-screen "Tap anywhere to start" (tap-only, drags pass through)
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(perform: startNavTap)
                    .padding(.bottom, 96)
                    .accessibilityHidden(true)


                // MARK: Voice Debug Overlay
                /*
                 if speechCenter.isListening {
                    debugVoiceOverlay
                }
                */
            }
            // Right-swipe to start
            .contentShape(Rectangle())
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) else { return } // only horizontal

                    if dx > swipeThreshold {
                        // Swipe right → Open Settings  (NEW)
                        hapticLight.impactOccurred()
                        showSettingsSheet = true
                        NotificationCenter.default.post(name: .glSettingsOpened, object: nil)
                    } else if dx < -swipeThreshold {
                        // Swipe left → Open Help (existing)
                        hapticLight.impactOccurred()
                        showHelpView = true
                        NotificationCenter.default.post(name: .glHelpOpened, object: nil)
                    }
                }
            )

            .navigationBarHidden(true)
            .fullScreenCover(isPresented: $showingPathNavigation) {
                PathNavigationLauncherView(
                    initialDestinationName: pendingVoiceDestination,
                    fromVoice: launchedFromVoice
                )
            }
            .accessibilityAction(.magicTap, startNavTap)
            .sheet(isPresented: $showHelpView) { HelpCenterView() }
            .sheet(isPresented: $showSettingsSheet) { SettingsView() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            setupHomeScreen()
        }
        .onDisappear {
            speechCenter.stopListening()
        }
        // Help command handling
        .onReceive(NotificationCenter.default.publisher(for: .glHelpOpened)) { _ in
            print("[ContentView] Help command received")
            showHelpView = true
        }
        // Voice command handling
        .onReceive(NotificationCenter.default.publisher(for: .glVoiceNavigateCommand)) { note in
            print("[ContentView] Voice navigate command received")
            let dest = (note.userInfo?["destination"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if dest?.isEmpty != false {
                print("[ContentView] Starting navigation")
                startNavTap()
            } else {
                print("[ContentView] Starting navigation with destination: \(dest ?? "")")
                startNavVoice(destination: dest)
            }
        }
    }

    // MARK: - Voice Debug Overlay
    private var debugVoiceOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(speechCenter.isListening ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text("Speech: \(speechCenter.isListening ? "ON" : "OFF")")
                            .font(.caption2)
                            .foregroundColor(.white)
                    }
                    
                    if !speechCenter.lastHeardText.isEmpty {
                        Text("Heard: \(speechCenter.lastHeardText)")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                            .lineLimit(2)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black.opacity(0.7))
            )
            .padding(.horizontal)
            .padding(.top, 50)
            
            Spacer()
        }
    }

    // MARK: - Setup Methods
    private func setupHomeScreen() {
        hapticLight.prepare()
        hapticHeavy.prepare()
        
        // Announce screen for VoiceOver users
        UIAccessibility.post(
            notification: .announcement,
            argument: "Home. Say Hey GuideLight followed by your command. Start Navigation button. Help bottom left. Settings bottom right."
        )
        
        // NEW: Play welcome announcement only once per app session
        if !hasPlayedWelcomeAnnouncement {
            playWelcomeAnnouncement()
            hasPlayedWelcomeAnnouncement = true
        }
        
        // Start continuous speech recognition
        speechCenter.startListening()
        
        print("[ContentView] Home screen setup complete - speech recognition active")
    }

    // MARK: - NEW: Welcome Announcement
    private func playWelcomeAnnouncement() {
        // Delay the announcement slightly to let the UI settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let welcomeMessage = "Welcome to GuideLight. Your personal indoor navigation companion. To start, simply say 'Hey GuideLight'."
            
            VoiceGuide.shared.speak(welcomeMessage)
            print("[ContentView] Welcome announcement played")
        }
    }

    // MARK: Actions
    private func startNavTap() {
        launchedFromVoice = false
        pendingVoiceDestination = nil
        hapticHeavy.impactOccurred()
        showingPathNavigation = true
    }

    private func startNavVoice(destination: String?) {
        launchedFromVoice = true
        pendingVoiceDestination = destination
        hapticHeavy.impactOccurred()
        showingPathNavigation = true
    }
}

// MARK: - UI helpers

/// Consistent circular bottom button orb
private struct BottomOrb: View {
    let icon: String
    var body: some View {
        Circle()
            .fill(.white.opacity(0.10))
            .frame(width: 56, height: 56)
            .overlay(
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            )
            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
    }
}


