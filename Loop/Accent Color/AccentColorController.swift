//
//  AccentColorController.swift
//  Loop
//
//  Created by Kai Azim on 2025-09-06.
//

import Defaults
import Scribe
import SwiftUI
import Tome

/// In charge of processing and storing an up-to-date version of the user's accent color(s), according to their settings.
/// Automatically refreshes when the user updates the following preferences: `accentColorMode`, `customAccentColor`, `useGradient` and `gradientColor`.
@Loggable
@MainActor
final class AccentColorController: ObservableObject {
    static let shared = AccentColorController()

    @Published var color1: Color = Defaults[.lastUsedAccentColor1]
    @Published var color2: Color = Defaults[.lastUsedAccentColor2]

    private let wallpaperProcessor = WallpaperProcessor()
    private var observationTask: Task<(), Never>?

    private init() {
        self.observationTask = Task { [weak self] in
            let updates = Tome.updates(
                \.accentColorMode,
                \.customAccentColor,
                \.useGradient,
                \.gradientColor
            )

            for await _ in updates {
                guard
                    !Task.isCancelled,
                    let self
                else {
                    break
                }
                await refresh()
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    func refresh(ignoreThrottle: Bool = false) async {
        switch Tome.accentColorMode {
        case .system:
            log.info("Refreshing accent color based on system accent setting")
            color1 = Color.accentColor
            color2 = Tome.useGradient ? Color(nsColor: NSColor.controlAccentColor.blended(withFraction: 0.5, of: .black)!) : Color.accentColor
        case .wallpaper:
            log.info("Refreshing accent color based on wallpaper analysis")
            let colors = await wallpaperProcessor.fetchLatest(ignoreThrottle: ignoreThrottle)
            color1 = colors.primary
            color2 = Tome.useGradient ? colors.secondary : colors.primary
        case .custom:
            log.info("Refreshing accent color based on custom selection")
            color1 = Tome.customAccentColor
            color2 = Tome.useGradient ? Tome.gradientColor : Tome.customAccentColor
        }

        Defaults[.lastUsedAccentColor1] = color1
        Defaults[.lastUsedAccentColor2] = color2
    }
}

extension Color {
    static var systemGray: Color {
        Color(nsColor: NSColor.systemGray.blended(withFraction: 0.2, of: .black)!)
    }
}
