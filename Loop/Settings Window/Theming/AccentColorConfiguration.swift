//
//  AccentColorConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Defaults
import Luminare
import SwiftUI

// MARK: - View

struct AccentColorConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @ObservedObject private var accentColorController: AccentColorController = .shared

    @Default(.accentColorMode) private var accentColorMode
    @Default(.useGradient) private var useGradient
    @Default(.customAccentColor) private var customAccentColor
    @Default(.gradientColor) private var gradientColor

    @State private var didSyncWallpaper: Bool = false
    @State private var syncWallpaperTask: Task<(), Never>?

    var body: some View {
        LuminareForm {
            LuminareSection {
                accentColorModePicker

                LuminareToggle("Gradient", isOn: $useGradient)

                if accentColorMode == .wallpaper {
                    syncWallpaperButton
                }
            }

            if accentColorMode == .custom {
                LuminareSection(String(localized: "Color", comment: "Section header shown in settings")) {
                    LuminareColorPicker(
                        color: $customAccentColor,
                        style: .textFieldWithColorWell()
                    )
                    .luminareRoundingBehavior(top: true, bottom: true)

                    if useGradient {
                        LuminareColorPicker(
                            color: $gradientColor,
                            style: .textFieldWithColorWell()
                        )
                        .luminareRoundingBehavior(top: true, bottom: true)
                    }
                }
                .luminareModalClosesOnDefocus()
                .animation(luminareAnimation, value: useGradient)
            }
        }
        .animation(luminareAnimation, value: accentColorMode)
    }

    private var accentColorModePicker: some View {
        LuminarePicker(
            elements: AccentColorOption.allCases,
            selection: $accentColorMode,
            columns: 3
        ) { option in
            VStack(spacing: 6) {
                Spacer()

                option.image
                Text(option.text)

                Spacer()
            }
            .font(.title3)
            .frame(height: 90)
        }
        .luminareRoundingBehavior(top: true)
        .environment(\.appearsActive, true) // Keep on active state to show accent color
    }

    private var syncWallpaperButton: some View {
        Button(action: syncWallpaper) {
            HStack {
                Text("Match Wallpaper")

                if didSyncWallpaper {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.green)
                        .bold()
                }
            }
        }
        .luminareRoundingBehavior(bottom: true)
    }

    private func syncWallpaper() {
        if syncWallpaperTask != nil {
            return
        }

        syncWallpaperTask = Task {
            await accentColorController.refresh(ignoreThrottle: true)

            withAnimation(.smooth(duration: 0.5)) {
                didSyncWallpaper = true
            }

            try? await Task.sleep(for: .seconds(2))

            withAnimation(.smooth(duration: 0.5)) {
                didSyncWallpaper = false
            }

            syncWallpaperTask = nil
        }
    }
}
