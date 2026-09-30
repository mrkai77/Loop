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
            Color(#colorLiteral(red: 0.310, green: 0.498, blue: 0.843, alpha: 1))
        case .accentColor:
            Color(#colorLiteral(red: 0.914, green: 0.404, blue: 0.380, alpha: 1))
        case .radialMenu:
            Color(#colorLiteral(red: 0.851, green: 0.663, blue: 0.310, alpha: 1))
        case .preview:
            Color(#colorLiteral(red: 0.2705882353, green: 0.662745098, blue: 0.9019607843, alpha: 1))
        case .behavior:
            Color(#colorLiteral(red: 0.463, green: 0.722, blue: 0.278, alpha: 1))
        case .keybinds:
            Color(#colorLiteral(red: 0.651, green: 0.424, blue: 0.247, alpha: 1))
        case .gestures:
            Color(#colorLiteral(red: 0.4352941176, green: 0.4588235294, blue: 0.9098039216, alpha: 1))
        case .advanced:
            Color(#colorLiteral(red: 0.5647058824, green: 0.4941176471, blue: 0.8470588235, alpha: 1))
        case .excludedApps:
            Color(#colorLiteral(red: 0.784, green: 0.357, blue: 0.341, alpha: 1))
        case .about:
            Color(#colorLiteral(red: 0.541, green: 0.541, blue: 0.541, alpha: 1))
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
                tab.image
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 1)
            }
            .frame(width: 22, height: 22)
    }
}
