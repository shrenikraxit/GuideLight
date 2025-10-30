//  Notifications.swift
//  GuideLight v3

import Foundation

extension Notification.Name {
    // Home & navigation
    static let glHomeAppeared            = Notification.Name("GuideLight.HomeAppeared")
    static let glStartNavigationRequest  = Notification.Name("GuideLight.StartNavigationRequest")
    static let glSettingsOpened          = Notification.Name("GuideLight.SettingsOpened")
    static let glHelpOpened              = Notification.Name("GuideLight.HelpOpened")

    // Voice / wake
    static let glVoiceWakeHeard          = Notification.Name("GuideLight.VoiceWakeHeard")
    static let glVoiceNavigateCommand    = Notification.Name("GuideLight.VoiceNavigateCommand")
    static let glVoiceSystemReady        = Notification.Name("GuideLight.VoiceSystemReady")

    // Map selection
    static let mapSelectedForNavigation  = Notification.Name("GuideLight.MapSelectedForNavigation")
}
