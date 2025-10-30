//  AppShortcutsProvider.swift
//  GuideLight v3

import AppIntents
import Foundation

@available(iOS 16.0, *)
struct GLStartGuideLightIntent: AppIntent {
    static var title: LocalizedStringResource = "Start GuideLight"
    static var description = IntentDescription("Open GuideLight and prepare the home screen.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Post notification to bring app to foreground and initialize home
        Foundation.NotificationCenter.default.post(name: Notification.Name.glHomeAppeared, object: nil)
        return .result()
    }
}

@available(iOS 16.0, *)
struct GLStartNavigationIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Navigation"
    static var description = IntentDescription("Begin GuideLight navigation flow.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        Foundation.NotificationCenter.default.post(name: Notification.Name.glHomeAppeared, object: nil)
        Foundation.NotificationCenter.default.post(name: Notification.Name.glStartNavigationRequest, object: nil)
        return .result()
    }
}

// MARK: - App Shortcuts Provider
@available(iOS 16.0, *)
struct GuideLightShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .orange }

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GLStartGuideLightIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Open \(.applicationName)",
                "Launch \(.applicationName)"
            ],
            shortTitle: "Start",
            systemImageName: "figure.walk"
        )
        
        AppShortcut(
            intent: GLStartNavigationIntent(),
            phrases: [
                "Start navigation in \(.applicationName)",
                "Begin navigation with \(.applicationName)"
            ],
            shortTitle: "Navigate",
            systemImageName: "location.fill"
        )
    }
}
