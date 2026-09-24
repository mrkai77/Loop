//
//  SettingsTab.swift
//  Loop
//
//  Created by Kai Azim on 2025-12-05.
//

import AppKit
import Luminare
import SwiftUI

@MainActor
enum SettingsTab: @MainActor LuminareTabItem, CaseIterable {
    var id: String { title }

    case icon
    case accentColor
    case radialMenu
    case preview

    case behavior
    case keybinds
    case gestures

    case advanced
    case excludedApps
    case about

    var icon: some View {
        SettingsTabIconView(tab: self)
    }

    var color: Color {
        switch self {
        case .icon:
            Color(#colorLiteral(red: 0.2235294118, green: 0.3843137255, blue: 0.6274509804, alpha: 1))
        case .accentColor:
            Color(#colorLiteral(red: 0.8235294118, green: 0.3529411765, blue: 0.337254902, alpha: 1))
        case .radialMenu:
            Color(#colorLiteral(red: 0.8078431373, green: 0.6235294118, blue: 0.3254901961, alpha: 1))
        case .preview:
            Color(#colorLiteral(red: 0.2901960784, green: 0.5647058824, blue: 0.7882352941, alpha: 1))
        case .behavior:
            Color(#colorLiteral(red: 0.4373228079, green: 0.6609574352, blue: 0.2663080928, alpha: 1))
        case .keybinds:
            Color(#colorLiteral(red: 0.3882352941, green: 0.2823529412, blue: 0.1960784314, alpha: 1))
        case .gestures:
            Color(#colorLiteral(red: 0.2352941176, green: 0.5568627451, blue: 0.5882352941, alpha: 1))
        case .advanced:
            Color(#colorLiteral(red: 0.4823529412, green: 0.4745098039, blue: 0.6588235294, alpha: 1))
        case .excludedApps:
            Color(#colorLiteral(red: 0.5882352941, green: 0.3137254902, blue: 0.3019607843, alpha: 1))
        case .about:
            Color(#colorLiteral(red: 0.4509803922, green: 0.4509803922, blue: 0.4509803922, alpha: 1))
        }
    }

    var title: String {
        switch self {
        case .icon: .init(localized: "Settings tab: Icon", defaultValue: "Icon")
        case .accentColor: .init(localized: "Settings tab: Accent Color", defaultValue: "Accent Color")
        case .radialMenu: .init(localized: "Settings tab: Radial Menu", defaultValue: "Radial Menu")
        case .preview: .init(localized: "Settings tab: Preview", defaultValue: "Preview")
        case .behavior: .init(localized: "Settings tab: Behavior", defaultValue: "Behavior")
        case .keybinds: .init(localized: "Settings tab: Keybindings", defaultValue: "Keybinds")
        case .gestures: .init(localized: "Settings tab: Gestures", defaultValue: "Gestures")
        case .advanced: .init(localized: "Settings tab: Advanced", defaultValue: "Advanced")
        case .excludedApps: .init(localized: "Settings tab: Excluded Apps", defaultValue: "Excluded Apps")
        case .about: .init(localized: "Settings tab: About", defaultValue: "About")
        }
    }

    var image: Image {
        switch self {
        case .icon: Image(systemName: "sparkles")
        case .accentColor: Image(systemName: "paintbrush.pointed.fill")
        case .radialMenu: Image(.loop)
        case .preview: Image(systemName: "inset.filled.center.rectangle")
        case .behavior: Image(systemName: "gearshape.fill")
        case .keybinds: Image(systemName: "keyboard.fill")
        case .gestures: Image(systemName: "hand.draw.fill")
        case .advanced: Image(systemName: "wrench.adjustable.fill")
        case .excludedApps: Image(systemName: "xmark.octagon.fill")
        case .about: Image(systemName: "info.circle.fill")
        }
    }

    var showIndicator: Bool {
        switch self {
        case .about: Updater.shared.updateState == .available
        default: false
        }
    }

    @ViewBuilder func view() -> some View {
        switch self {
        case .icon: IconConfigurationView()
        case .accentColor: AccentColorConfigurationView()
        case .radialMenu: RadialMenuConfigurationView()
        case .preview: PreviewConfigurationView()
        case .behavior: BehaviorConfigurationView()
        case .keybinds: KeybindsConfigurationView()
        case .gestures: GesturesConfigurationView()
        case .advanced: AdvancedConfigurationView()
        case .excludedApps: ExcludedAppsConfigurationView()
        case .about: AboutConfigurationView()
        }
    }

    static let themingTabs: [Self] = [.icon, .accentColor, .radialMenu, .preview]
    static let settingsTabs: [Self] = [.behavior, .keybinds, .gestures]
    static let loopTabs: [Self] = [.advanced, .excludedApps, .about]
}

struct SettingsTabIconView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tab: SettingsTab

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .foregroundStyle(tab.color.gradient)
            .opacity(0.8)
            .overlay {
                // Only add shine in dark mode; in light mode it makes the icon look fuzzy/blurred.
                if colorScheme == .dark, #available(macOS 26.0, *) {
                    borderShine(in: .rect(cornerRadius: 6))
                }

                tab.image
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1)
            }
            .frame(width: 22, height: 22)
    }

    /// Mimics macOS Tahoe's icon shine
    private func borderShine(in shape: some InsettableShape) -> some View {
        shape
            .strokeBorder(.white, lineWidth: 1)
            .mask {
                LinearGradient(
                    colors: [
                        .white,
                        .clear,
                        .white.opacity(0.5)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .opacity(0.4)
    }
}
