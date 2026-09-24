//
//  DataPatcher.swift
//  Loop
//
//  Created by Kai Azim on 2025-09-07.
//

import AppKit
import Defaults
import Scribe

@Loggable(style: .static)
enum DataPatcher {
    static func run() {
        let initialPatches: Patches = Defaults[.patchesApplied]

        runPatchIfNeeded(patch: .changeToAccentColorMode, initialPatches: initialPatches) {
            // Migrate to accent color mode
            // We need to migrate `useSystemAccentColor` and `processWallpaper` over to `accentColorMode`
            let useSystemAccentColor: Bool = Defaults[.useSystemAccentColor]
            let processWallpaper: Bool = Defaults[.processWallpaper]

            if useSystemAccentColor {
                Defaults[.accentColorMode] = .system
            } else if processWallpaper {
                Defaults[.accentColorMode] = .wallpaper
            } else {
                Defaults[.accentColorMode] = .custom
            }

            Defaults.reset(.useSystemAccentColor)
            Defaults.reset(.processWallpaper)
        }

        runPatchIfNeeded(patch: .removeRevealedStashedWindows, initialPatches: initialPatches) {
            Defaults.reset(.stashManagerRevealedWindows)
        }

        runPatchIfNeeded(patch: .changeTohideOnNoSelection, initialPatches: initialPatches) {
            Defaults[.hideOnNoSelection] = Defaults[.hideUntilDirectionIsChosen]
            Defaults.reset(.hideUntilDirectionIsChosen)
        }

        runPatchIfNeeded(patch: .splitRadialMenuPresentationPolicies, initialPatches: initialPatches) {
            let hideOnNoSelection = Defaults[.hideOnNoSelection] || Defaults[.hideUntilDirectionIsChosen]
            Defaults[.hideOnNoSelectionForKeybinds] = hideOnNoSelection
            Defaults[.hideOnNoSelectionForGestures] = hideOnNoSelection
            Defaults.reset(.hideOnNoSelection)
            Defaults.reset(.hideUntilDirectionIsChosen)
        }
    }

    private static func runPatchIfNeeded(patch: Patches, initialPatches: Patches, with callback: () -> ()) {
        if !initialPatches.contains(patch) {
            callback()

            Defaults[.patchesApplied].formUnion(patch)
            log.info("Ran patch \(patch)")
        }
    }

    struct Patches: OptionSet, Defaults.Serializable {
        let rawValue: Int

        /// Changed accent color configuration from multiple bools to an enum
        static let changeToAccentColorMode = Self(rawValue: 1 << 0)

        /// Revealed statshed windows are no longer persisted across Loop lifecycles
        static let removeRevealedStashedWindows = Self(rawValue: 1 << 1)

        /// Key was renamed from `hideUntilDirectionIsChosen` to `hideOnNoSelection` with slightly different behavior
        static let changeTohideOnNoSelection = Self(rawValue: 1 << 2)

        /// Split the global no-selection setting into trigger-specific presentation policies.
        static let splitRadialMenuPresentationPolicies = Self(rawValue: 1 << 3)
    }
}

// MARK: - Migrated keys (private)

// swiftformat:disable docComments
private extension Defaults.Keys {
    // StashManager
    static let stashManagerRevealedWindows = Key<Set<CGWindowID>>("stashManagerRevealed", default: Set<CGWindowID>())

    // AccentColorController
    static let useSystemAccentColor = Key<Bool>("useSystemAccentColor", default: true)
    static let processWallpaper = Key<Bool>("processWallpaper", default: false)

    // IndicatorService
    static let hideOnNoSelection = Key<Bool>("hideOnNoSelection", default: false)
    static let hideUntilDirectionIsChosen = Key<Bool>("hideUntilDirectionIsChosen", default: false)
}
