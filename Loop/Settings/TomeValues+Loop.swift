//
//  TomeValues+Loop.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import SwiftUI
import Tome

@TomeCatalog
extension TomeValues {
    // Icon
    @TomeEntry("icon.show-in-dock") var showDockIcon = false
    @TomeEntry("icon.notify-when-unlocked") var notificationWhenIconUnlocked = true

    // Accent Color
    @TomeEntry("accent-color.mode") var accentColorMode: AccentColorOption = .system
    @TomeEntry("accent-color.gradient") var useGradient = false
    @TomeEntry("accent-color.color") var customAccentColor: Color = .teal
    @TomeEntry("accent-color.gradient-color") var gradientColor: Color = .blue

    // Radial Menu
    @TomeEntry("radial-menu.enabled") var radialMenuVisibility = true
    @TomeEntry("radial-menu.corner-radius") var radialMenuCornerRadius: CGFloat = 50
    @TomeEntry("radial-menu.thickness") var radialMenuThickness: CGFloat = 22
    @TomeEntry("radial-menu.bindings") var radialMenuActions: [RadialMenuBinding] = RadialMenuBinding.defaultRadialMenuActions

    // Preview
    @TomeEntry("preview.enabled") var previewVisibility = true
    @TomeEntry("preview.padding") var previewPadding: CGFloat = 10
    @TomeEntry("preview.border-thickness") var previewBorderThickness: CGFloat = 4
    @TomeEntry("preview.match-window-corner-radius") var previewUseWindowCornerRadius = true
    @TomeEntry("preview.corner-radius") var previewCornerRadius: CGFloat = 10
    @TomeEntry("preview.background.style") var previewBackgroundStyle: PreviewBackgroundStyle = .system
    @TomeEntry("preview.background.blur") var previewBackgroundEnableBlur = false
    @TomeEntry("preview.background.accent-opacity") var previewBackgroundAccentOpacity: CGFloat = 0.1

    // Behavior
    @TomeEntry("animation-speed") var animationConfiguration: AnimationConfiguration = .snappy
    @TomeEntry("window.target") var targetWindow: WindowSelection = .frontmost
    @TomeEntry("window.focus-on-resize") var focusWindowOnResize = true
    @TomeEntry("window.move-to-cursor-screen") var useScreenWithCursor = true
    @TomeEntry("padding.enabled") var enablePadding = false
    @TomeEntry("padding") var padding: PaddingConfiguration = .zero
    @TomeEntry("dragging.restore-size") var restoreWindowFrameOnDrag = false
    @TomeEntry("dragging.snap-to-edges") var windowSnapping = false
    @TomeEntry("dragging.prevent-mission-control") var suppressMissionControlOnTopDrag = true
    @TomeEntry("stage-manager.respect") var respectStageManager = true
    @TomeEntry("stage-manager.strip-size") var stageStripSize: CGFloat = 150
    @TomeEntry("stash.animate") var animateStashedWindows = true
    @TomeEntry("stash.peek-size") var stashedWindowVisiblePadding: CGFloat = 20
    @TomeEntry("stash.focus-next-window") var shiftFocusWhenStashed = true

    // Keybinds
    @TomeEntry("trigger.keys") var triggerKey: KeyCombination = [.kVK_Function]
    @TomeEntry("trigger.distinguish-modifier-sides") var sideDependentTriggerKey = true
    @TomeEntry("trigger.delay") var triggerDelay: Duration = .zero
    @TomeEntry("trigger.hide-on-no-selection") var hideOnNoSelectionForKeybinds = false
    @TomeEntry("trigger.double-click") var doubleClickToTrigger = false
    @TomeEntry("trigger.middle-click") var middleClickTriggersLoop = false
    @TomeEntry("trigger.middle-click-uses-delay") var enableTriggerDelayOnMiddleClick = false
    @TomeEntry("cycles.always-start-from-first") var cycleModeRestartEnabled = false
    @TomeEntry("cycles.backward-with-shift") var cycleBackwardsOnShiftPressed = true
    @TomeEntry("key.bindings") var keyBindings: [KeyBinding] = KeyBinding.defaultKeybinds

    // Gestures
    @TomeEntry("gestures.enabled") var enableGestures = false
    @TomeEntry("gestures.bindings") var gestures: [GestureBinding] = GestureBinding.defaults

    // Advanced
    @TomeEntry("integrate-with-system-window-manager") var useSystemWindowManagerWhenAvailable = false
    @TomeEntry("animate-window-resizing") var animateWindowResizes = false
    @TomeEntry("radial-menu.select-with-cursor") var selectActionsWithCursor = true
    @TomeEntry("window.ignore-full-screen") var ignoreFullscreen = false
    @TomeEntry("haptic-feedback") var hapticFeedback = true
    @TomeEntry("screen-order") var screenOrder: ScreenOrder = .zShaped
    @TomeEntry("window.size-increment") var sizeIncrement: CGFloat = 20
    @TomeEntry("radial-menu.customize-bindings") var enableRadialMenuCustomization = false
    @TomeEntry("excluded-apps", inline: .multiline) var excludedApps: [URL] = []

    #if RELEASE
        @TomeEntry("updates.include-development-versions") var includeDevelopmentVersions = false
    #else
        @TomeEntry("updates.include-development-versions") var includeDevelopmentVersions = true
    #endif
    @TomeEntry("updates.automatically-install") var automaticallyUpdate = false
    @TomeEntry("gestures.hide-on-no-selection") var hideOnNoSelectionForGestures = true
    @TomeEntry("radial-menu.lock-to-center") var lockRadialMenuToCenter = false
    @TomeEntry("start-hidden") var startHidden = false
    @TomeEntry("hide-menu-bar-icon") var hideMenuBarIcon = false
    @TomeEntry("window.move-cursor-with-window") var moveCursorWithWindow = false
    @TomeEntry("padding.minimum-screen-size") var paddingMinimumScreenSize: CGFloat = 0
    @TomeEntry("padding.ignore-notch") var ignoreNotch = false
    @TomeEntry("dragging.snap-threshold") var snapThreshold: CGFloat = 2
    @TomeEntry("animate-in-low-power-mode") var animateInLowPowerMode = false
    @TomeEntry("preview.starting-position") var previewStartingPosition: PreviewStartingPosition = .actionCenter
    @TomeEntry("updates.enabled") var updatesEnabled = true
    @TomeEntry("trigger.timeout") var triggerKeyTimeout: Duration = .zero
    @TomeEntry("gestures.title-bar-height") var gestureTitlebarHeight: CGFloat = 50
}
