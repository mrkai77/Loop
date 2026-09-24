//
//  Defaults+Extensions.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-14.
//
// NOTE: While iCloud is enabled, its service is currently disabled to make GitHub actions work.

import Defaults
import Scribe
import SwiftUI

// MARK: - UI-configurable Settings

extension Defaults.Keys {
    // Icon
    static let currentIcon = Key<String>("currentIcon", default: "AppIcon-Classic")
    static let timesLooped = Key<Int>("timesLooped", default: 0)
    static let showDockIcon = Key<Bool>("showDockIcon", default: false)
    static let notificationWhenIconUnlocked = Key<Bool>("notificationWhenIconUnlocked", default: true)

    // Accent Color
    static let accentColorMode: Key<AccentColorOption> = Key("accentColorMode", default: .system)
    static let customAccentColor = Key<Color>("customAccentColor", default: .teal)
    static let useGradient = Key<Bool>("useGradient", default: false)
    static let gradientColor = Key<Color>("gradientColor", default: .blue)

    // Radial Menu
    static let radialMenuVisibility = Key<Bool>("radialMenuVisibility", default: true)
    static let radialMenuCornerRadius = Key<CGFloat>("radialMenuCornerRadius", default: 50)
    static let radialMenuThickness = Key<CGFloat>("radialMenuThickness", default: 22)
    static let radialMenuActions = Key<[RadialMenuAction]>("radialMenuActions", default: RadialMenuAction.defaultRadialMenuActions)

    // Preview
    static let previewVisibility = Key<Bool>("previewVisibility", default: true)
    static let previewPadding = Key<CGFloat>("previewPadding", default: 10)
    static let previewCornerRadius = Key<CGFloat>("previewCornerRadius", default: 10)
    static let previewBorderThickness = Key<CGFloat>("previewBorderThickness", default: 4)
    static let previewUseWindowCornerRadius = Key<Bool>("previewUseWindowCornerRadius", default: true)
    static let previewBackgroundEnableBlur = Key<Bool>("previewBackgroundEnableBlur", default: true)
    static let previewBackgroundAccentOpacity = Key<CGFloat>("previewBackgroundAccentOpacity", default: 0.1)

    // Behavior
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let startHidden = Key<Bool>("startHidden", default: false)
    static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false, iCloud: false)
    static let animationConfiguration = Key<AnimationConfiguration>("animationConfiguration", default: .snappy)
    static let windowSnapping = Key<Bool>("windowSnapping", default: false)
    static let suppressMissionControlOnTopDrag = Key<Bool>("suppressMissionControlOnTopDrag", default: true)
    static let restoreWindowFrameOnDrag = Key<Bool>("restoreWindowFrameOnDrag", default: false)
    static let enablePadding = Key<Bool>("enablePadding", default: false)
    static let padding = Key<PaddingConfiguration>("padding", default: .zero)
    static let useScreenWithCursor = Key<Bool>("useScreenWithCursor", default: true)
    static let moveCursorWithWindow = Key<Bool>("moveCursorWithWindow", default: false)
    static let resizeWindowUnderCursor = Key<Bool>("resizeWindowUnderCursor", default: false)
    static let focusWindowOnResize = Key<Bool>("focusWindowOnResize", default: true)
    static let respectStageManager = Key<Bool>("respectStageManager", default: true)
    static let stageStripSize = Key<CGFloat>("stageStripSize", default: 150)
    static let animateStashedWindows = Key<Bool>("animateStashedWindows", default: true)
    static let stashedWindowVisiblePadding = Key<CGFloat>("stashedWindowVisiblePadding", default: 20)
    static let shiftFocusWhenStashed = Key<Bool>("shiftFocusWhenStashed", default: true)
    static let cycleModeRestartEnabled = Key<Bool>("cycleModeRestartEnabled", default: false)

    // Keybinds
    static let triggerKey = Key<Set<CGKeyCode>>("trigger", default: [.kVK_Function])
    static let sideDependentTriggerKey = Key<Bool>("sideDependentTriggerKey", default: true)
    static let triggerDelay = Key<Double>("triggerDelay", default: 0)
    static let doubleClickToTrigger = Key<Bool>("doubleClickToTrigger", default: false)
    static let middleClickTriggersLoop = Key<Bool>("middleClickTriggersLoop", default: false)
    static let enableTriggerDelayOnMiddleClick = Key<Bool>("enableTriggerDelayOnMiddleClick", default: false)
    static let cycleBackwardsOnShiftPressed = Key<Bool>("cycleBackwardsOnShiftPressed", default: true)
    static let keybinds = Key<[WindowAction]>("keybinds", default: WindowAction.defaultKeybinds)

    // Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: false)
    static let gestures = Key<[GestureBinding]>("gestures", default: GestureBinding.defaults)

    // Advanced
    static let useSystemWindowManagerWhenAvailable = Key<Bool>("useSystemWindowManagerWhenAvailable", default: false)
    static let animateWindowResizes = Key<Bool>("animateWindowResizes", default: false)
    static let disableCursorInteraction = Key<Bool>("disableCursorInteraction", default: false)
    static let ignoreFullscreen = Key<Bool>("ignoreFullscreen", default: false)
    static let hideOnNoSelectionForKeybinds = Key<Bool>("hideOnNoSelectionForKeybinds", default: false)
    static let hapticFeedback = Defaults.Key<Bool>("hapticFeedback", default: true)
    static let enableRadialMenuCustomization = Defaults.Key<Bool>("enableRadialMenuCustomization", default: false)
    static let sizeIncrement = Key<CGFloat>("sizeIncrement", default: 20)

    /// Excluded apps
    static let excludedApps = Key<[URL]>("excludedApps", default: [])

    // About
    #if RELEASE
        static let includeDevelopmentVersions = Key<Bool>("includeDevelopmentVersions", default: false)
    #else
        /// Development versions should check for development updates by default.
        static let includeDevelopmentVersions = Key<Bool>("includeDevelopmentVersions", default: true)
    #endif
    static let automaticallyUpdate = Key<Bool>("automaticallyUpdate", default: false)
}

// MARK: - Hidden Settings

extension Defaults.Keys {
    /// Hide the radial menu whenever a trackpad gesture has no selected action.
    /// Adjust with `defaults write com.MrKai77.Loop hideOnNoSelectionForGestures -bool false`
    /// Reset with `defaults delete com.MrKai77.Loop hideOnNoSelectionForGestures`
    static let hideOnNoSelectionForGestures = Key<Bool>("hideOnNoSelectionForGestures", default: true)

    /// Lock radial menu to the center of the screen
    /// Adjust with `defaults write com.MrKai77.Loop lockRadialMenuToCenter -bool true`
    /// Reset with `defaults delete com.MrKai77.Loop lockRadialMenuToCenter`
    static let lockRadialMenuToCenter = Key<Bool>("lockRadialMenuToCenter", default: false)

    /// Minimum screen size, defined in inches on the diagonal, for which padding will be applied on windows.
    /// Adjust with `defaults write com.MrKai77.Loop paddingMinimumScreenSize -float x`
    /// Reset with `defaults delete com.MrKai77.Loop paddingMinimumScreenSize`
    static let paddingMinimumScreenSize = Key<CGFloat>("paddingMinimumScreenSize", default: 0)

    /// Ignore the notch height when calculating top padding, so the effective
    /// distance from the screen top matches non-notch displays.
    /// Adjust with `defaults write com.MrKai77.Loop ignoreNotch -bool true`
    /// Reset with `defaults delete com.MrKai77.Loop ignoreNotch`
    static let ignoreNotch = Key<Bool>("ignoreNotch", default: false)

    /// Snap threshold for window snapping, defined in points.
    /// Adjust with `defaults write com.MrKai77.Loop snapThreshold -float x`
    /// Reset with `defaults delete com.MrKai77.Loop snapThreshold`
    static let snapThreshold = Key<CGFloat>("snapThreshold", default: 2)

    /// Whether to ignore low power mode for certain features, such as window animations.
    /// Adjust with `defaults write com.MrKai77.Loop ignoreLowPowerMode -bool x`
    /// Reset with `defaults delete com.MrKai77.Loop ignoreLowPowerMode`
    static let ignoreLowPowerMode = Key<Bool>("ignoreLowPowerMode", default: false)

    /// Adjust with `defaults write com.MrKai77.Loop previewStartingPosition [option]`
    /// Reset with `defaults delete com.MrKai77.Loop previewStartingPosition`
    ///
    /// Available options:
    /// - `screenCenter`: Center of the screen
    /// - `radialMenu`: Center of radial menu
    /// - `actionCenter`: Center of the selected action (e.g. for left half, it will grow from the center of that left half)
    static let previewStartingPosition = Key<PreviewStartingPosition>("previewStartingPosition", default: .actionCenter)

    /// Disable automatic updates with `defaults write com.MrKai77.Loop updatesEnabled -bool false`
    /// Reset with `defaults delete com.MrKai77.Loop updatesEnabled`
    static let updatesEnabled = Key<Bool>("updatesEnabled", default: true)

    /// Trigger key timeout, defined in seconds. Automatically closes Loop if no action is taken within the specified time.
    /// When set to 0 (default: disabled), the feature is disabled and Loop stays open until manually closed.
    /// Adjust with `defaults write com.MrKai77.Loop triggerKeyTimeout -float x`
    /// Reset with `defaults delete com.MrKai77.Loop triggerKeyTimeout`
    static let triggerKeyTimeout = Key<Double>("triggerKeyTimeout", default: 0)

    /// Height of the titlebar activation zone for gestures, defined in points.
    /// Gestures with the `.titlebar` activation zone will only trigger when the cursor is within this distance from the top of a window.
    /// Adjust with `defaults write com.MrKai77.Loop gestureTitlebarHeight -float x`
    /// Reset with `defaults delete com.MrKai77.Loop gestureTitlebarHeight`
    static let gestureTitlebarHeight = Key<CGFloat>("gestureTitlebarHeight", default: 50)

    /// Whether to sync all Loop settings to iCloud.
    /// Adjust with `defaults write com.MrKai77.Loop enableiCloudSync -bool false`
    /// Reset with `defaults delete com.MrKai77.Loop enableiCloudSync`
    static let enableiCloudSync = Key<Bool>("enableiCloudSync", default: true)
}

// MARK: - Non-user-intended Settings

extension Defaults.Keys {
    // Migrator

    static let lastMigratorURL = Key<URL?>("lastMigratorURL", default: nil)

    // StashManager

    static let stashManagerStashedWindows = Key<[CGWindowID: WindowAction]>("stashManagerStashed", default: [:])

    // AccentColorController

    static let lastUsedAccentColor1 = Key<Color>("lastUsedAccentColor1", default: .black)
    static let lastUsedAccentColor2 = Key<Color>("lastUsedAccentColor2", default: .black)

    // DataPatcher

    static let patchesApplied = Key<DataPatcher.Patches>("patchesApplied", default: [])

    // Settings

    static let showSettingsInspector = Key<Bool>("showSettingsInspector", default: true)
}

// MARK: - iCloud Sync (not really an extension per se but feel like this is an approriate location)

@Loggable(style: .static)
enum DefaultsiCloudSyncRegistrar {
    static func register() {
        let enabled = Defaults[.enableiCloudSync]
        updateiCloudSync(enabled: enabled)
        log.info("iCloud sync \(enabled ? "enabled" : "disabled")")

        Task { @MainActor in
            for await enabled in Defaults.updates(.enableiCloudSync, initial: false) {
                updateiCloudSync(enabled: enabled)
                log.info("iCloud sync updated: \(enabled ? "enabled" : "disabled")")
            }
        }
    }

    private static func updateiCloudSync(enabled: Bool) {
        guard enabled else {
            Defaults.iCloud.removeAll()
            return
        }

        Defaults.iCloud.add(.currentIcon)
        Defaults.iCloud.add(.timesLooped)
        Defaults.iCloud.add(.showDockIcon)
        Defaults.iCloud.add(.notificationWhenIconUnlocked)

        Defaults.iCloud.add(.accentColorMode)
        Defaults.iCloud.add(.customAccentColor)
        Defaults.iCloud.add(.useGradient)
        Defaults.iCloud.add(.gradientColor)

        Defaults.iCloud.add(.radialMenuVisibility)
        Defaults.iCloud.add(.radialMenuCornerRadius)
        Defaults.iCloud.add(.radialMenuThickness)
        Defaults.iCloud.add(.radialMenuActions)

        Defaults.iCloud.add(.previewVisibility)
        Defaults.iCloud.add(.previewPadding)
        Defaults.iCloud.add(.previewCornerRadius)
        Defaults.iCloud.add(.previewBorderThickness)
        Defaults.iCloud.add(.previewUseWindowCornerRadius)
        Defaults.iCloud.add(.previewBackgroundEnableBlur)
        Defaults.iCloud.add(.previewBackgroundAccentOpacity)

        Defaults.iCloud.add(.startHidden)
        Defaults.iCloud.add(.animationConfiguration)
        Defaults.iCloud.add(.windowSnapping)
        Defaults.iCloud.add(.suppressMissionControlOnTopDrag)
        Defaults.iCloud.add(.restoreWindowFrameOnDrag)
        Defaults.iCloud.add(.enablePadding)
        Defaults.iCloud.add(.padding)
        Defaults.iCloud.add(.useScreenWithCursor)
        Defaults.iCloud.add(.moveCursorWithWindow)
        Defaults.iCloud.add(.resizeWindowUnderCursor)
        Defaults.iCloud.add(.focusWindowOnResize)
        Defaults.iCloud.add(.respectStageManager)
        Defaults.iCloud.add(.stageStripSize)
        Defaults.iCloud.add(.animateStashedWindows)
        Defaults.iCloud.add(.stashedWindowVisiblePadding)
        Defaults.iCloud.add(.shiftFocusWhenStashed)
        Defaults.iCloud.add(.cycleModeRestartEnabled)

        Defaults.iCloud.add(.triggerKey)
        Defaults.iCloud.add(.sideDependentTriggerKey)
        Defaults.iCloud.add(.triggerDelay)
        Defaults.iCloud.add(.doubleClickToTrigger)
        Defaults.iCloud.add(.middleClickTriggersLoop)
        Defaults.iCloud.add(.enableTriggerDelayOnMiddleClick)
        Defaults.iCloud.add(.cycleBackwardsOnShiftPressed)
        Defaults.iCloud.add(.keybinds)

        Defaults.iCloud.add(.enableGestures)
        Defaults.iCloud.add(.gestures)

        Defaults.iCloud.add(.useSystemWindowManagerWhenAvailable)
        Defaults.iCloud.add(.animateWindowResizes)
        Defaults.iCloud.add(.disableCursorInteraction)
        Defaults.iCloud.add(.ignoreFullscreen)
        Defaults.iCloud.add(.hideOnNoSelectionForKeybinds)
        Defaults.iCloud.add(.hapticFeedback)
        Defaults.iCloud.add(.enableRadialMenuCustomization)
        Defaults.iCloud.add(.sizeIncrement)

        Defaults.iCloud.add(.excludedApps)
    }
}
