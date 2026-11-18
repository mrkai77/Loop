//
//  LegacyMigration.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import Defaults
import Foundation
import Scribe
import SwiftUI
import Tome

/// Copies each legacy Defaults value the user set into config.toml.
/// A key present in the domain was set by the user, so it is written even when it equals the default.
@Loggable(style: .static)
struct LegacyMigration {
    let suite: UserDefaults
    let persisted: Set<String>
    let settings: Tome.Settings

    private func legacy<Value>(_ key: Defaults.Key<Value>) -> Value {
        ConfigMigrator.legacyValue(key, suite: suite)
    }

    /// An unusable value is skipped rather than aborting the migration.
    private func copy<Old, Value: Equatable & Sendable>(_ old: Defaults.Key<Old>, to key: WritableKeyPath<TomeValues, Value>, _ transform: (Old) throws -> Value) throws {
        guard persisted.contains(old.name) else { return }
        do {
            try settings.set(transform(legacy(old)), for: key)
        } catch {
            Self.log.warn("Skipped migrating \(old.name): \(error)")
        }
    }

    private func copy<Value: Equatable & Sendable>(_ old: Defaults.Key<Value>, to key: WritableKeyPath<TomeValues, Value>) throws {
        try copy(old, to: key) { $0 }
    }

    /// Legacy lengths carry float noise, so they keep one decimal place.
    private func copyRounded(_ old: Defaults.Key<CGFloat>, to key: WritableKeyPath<TomeValues, CGFloat>) throws {
        try copy(old, to: key, Self.roundedPoint)
    }

    func writeAll() throws {
        let keybinds = bindingsToMigrate()
        let names = Dictionary(keybinds.compactMap { binding in binding.configID.map { (binding.id, $0) } }, uniquingKeysWith: { first, _ in first })

        try copy(LegacyDefaults.showDockIcon, to: \.showDockIcon)
        try copy(LegacyDefaults.notificationWhenIconUnlocked, to: \.notificationWhenIconUnlocked)
        try copy(LegacyDefaults.accentColorMode, to: \.accentColorMode) { $0.current }
        try copy(LegacyDefaults.useGradient, to: \.useGradient)
        try copy(LegacyDefaults.customAccentColor, to: \.customAccentColor)
        try copy(LegacyDefaults.gradientColor, to: \.gradientColor)
        try copy(LegacyDefaults.radialMenuVisibility, to: \.radialMenuVisibility)
        try copyRounded(LegacyDefaults.radialMenuCornerRadius, to: \.radialMenuCornerRadius)
        try copyRounded(LegacyDefaults.radialMenuThickness, to: \.radialMenuThickness)
        try copyBindings(LegacyRadialMenuAction.self, names: names)
        try copy(LegacyDefaults.previewVisibility, to: \.previewVisibility)
        try copyRounded(LegacyDefaults.previewPadding, to: \.previewPadding)
        try copyRounded(LegacyDefaults.previewBorderThickness, to: \.previewBorderThickness)
        try copy(LegacyDefaults.previewUseWindowCornerRadius, to: \.previewUseWindowCornerRadius)
        try copyRounded(LegacyDefaults.previewCornerRadius, to: \.previewCornerRadius)
        try copy(LegacyDefaults.previewBackgroundStyle, to: \.previewBackgroundStyle) { $0.current }
        try copy(LegacyDefaults.previewBackgroundEnableBlur, to: \.previewBackgroundEnableBlur)
        try copy(LegacyDefaults.previewBackgroundAccentOpacity, to: \.previewBackgroundAccentOpacity)
        try copy(LegacyDefaults.animationConfiguration, to: \.animationConfiguration) { $0.current }
        try copy(LegacyDefaults.resizeWindowUnderCursor, to: \.targetWindow) { $0 ? .underCursor : .frontmost }
        try copy(LegacyDefaults.focusWindowOnResize, to: \.focusWindowOnResize)
        try copy(LegacyDefaults.useScreenWithCursor, to: \.useScreenWithCursor)
        try copy(LegacyDefaults.enablePadding, to: \.enablePadding)
        try copy(LegacyDefaults.padding, to: \.padding) { Self.roundedPadding($0.current) }
        try copy(LegacyDefaults.restoreWindowFrameOnDrag, to: \.restoreWindowFrameOnDrag)
        try copy(LegacyDefaults.windowSnapping, to: \.windowSnapping)
        try copy(LegacyDefaults.suppressMissionControlOnTopDrag, to: \.suppressMissionControlOnTopDrag)
        try copy(LegacyDefaults.respectStageManager, to: \.respectStageManager)
        try copyRounded(LegacyDefaults.stageStripSize, to: \.stageStripSize)
        try copy(LegacyDefaults.animateStashedWindows, to: \.animateStashedWindows)
        try copyRounded(LegacyDefaults.stashedWindowVisiblePadding, to: \.stashedWindowVisiblePadding)
        try copy(LegacyDefaults.shiftFocusWhenStashed, to: \.shiftFocusWhenStashed)
        try copy(LegacyDefaults.triggerKey, to: \.triggerKey) { KeyCombination(keyCodes: $0) }
        try copy(LegacyDefaults.sideDependentTriggerKey, to: \.sideDependentTriggerKey)
        try copy(LegacyDefaults.triggerDelay, to: \.triggerDelay) { try Duration.tomeBridge.deserialize(.float($0)) }
        try copy(LegacyDefaults.hideOnNoSelectionForKeybinds, to: \.hideOnNoSelectionForKeybinds)
        try copy(LegacyDefaults.doubleClickToTrigger, to: \.doubleClickToTrigger)
        try copy(LegacyDefaults.middleClickTriggersLoop, to: \.middleClickTriggersLoop)
        try copy(LegacyDefaults.enableTriggerDelayOnMiddleClick, to: \.enableTriggerDelayOnMiddleClick)
        try copy(LegacyDefaults.cycleModeRestartEnabled, to: \.cycleModeRestartEnabled)
        try copy(LegacyDefaults.cycleBackwardsOnShiftPressed, to: \.cycleBackwardsOnShiftPressed)
        if persisted.contains(LegacyDefaults.keybinds.name) {
            try settings.set(keybinds, for: \.keyBindings)
        }
        try copy(LegacyDefaults.enableGestures, to: \.enableGestures)
        try copyBindings(LegacyGestureBinding.self, names: names)
        try copy(LegacyDefaults.useSystemWindowManagerWhenAvailable, to: \.useSystemWindowManagerWhenAvailable)
        try copy(LegacyDefaults.animateWindowResizes, to: \.animateWindowResizes)
        try copy(LegacyDefaults.disableCursorInteraction, to: \.selectActionsWithCursor) { !$0 }
        try copy(LegacyDefaults.ignoreFullscreen, to: \.ignoreFullscreen)
        try copy(LegacyDefaults.hapticFeedback, to: \.hapticFeedback)
        try copy(LegacyDefaults.screenOrder, to: \.screenOrder) { $0.current }
        try copyRounded(LegacyDefaults.sizeIncrement, to: \.sizeIncrement)
        try copy(LegacyDefaults.enableRadialMenuCustomization, to: \.enableRadialMenuCustomization)
        try copy(LegacyDefaults.excludedApps, to: \.excludedApps)
        try copy(LegacyDefaults.includeDevelopmentVersions, to: \.includeDevelopmentVersions)
        try copy(LegacyDefaults.automaticallyUpdate, to: \.automaticallyUpdate)
        try copy(LegacyDefaults.hideOnNoSelectionForGestures, to: \.hideOnNoSelectionForGestures)
        try copy(LegacyDefaults.lockRadialMenuToCenter, to: \.lockRadialMenuToCenter)
        try copy(LegacyDefaults.startHidden, to: \.startHidden)
        try copy(LegacyDefaults.hideMenuBarIcon, to: \.hideMenuBarIcon)
        try copy(LegacyDefaults.moveCursorWithWindow, to: \.moveCursorWithWindow)
        try copy(LegacyDefaults.paddingMinimumScreenSize, to: \.paddingMinimumScreenSize)
        try copy(LegacyDefaults.ignoreNotch, to: \.ignoreNotch)
        try copyRounded(LegacyDefaults.snapThreshold, to: \.snapThreshold)
        try copy(LegacyDefaults.ignoreLowPowerMode, to: \.animateInLowPowerMode)
        try copy(LegacyDefaults.previewStartingPosition, to: \.previewStartingPosition) { $0.current }
        try copy(LegacyDefaults.updatesEnabled, to: \.updatesEnabled)
        try copy(LegacyDefaults.triggerKeyTimeout, to: \.triggerKeyTimeout) { try Duration.tomeBridge.deserialize(.float($0)) }
        try copyRounded(LegacyDefaults.gestureTitlebarHeight, to: \.gestureTitlebarHeight)
    }

    /// An unset list leaves the default bindings in place.
    private func copyBindings<Legacy: LegacyBinding>(_ type: Legacy.Type, names: [UUID: String]) throws {
        guard persisted.contains(Legacy.defaultsKey.name) else { return }
        try settings.set(convertedBindings(type, names: names), for: Legacy.settingsKeyPath)
    }

    private func convertedBindings<Legacy: LegacyBinding>(_: Legacy.Type, names: [UUID: String]) -> [Legacy.Binding] {
        legacy(Legacy.defaultsKey).compactMap { $0.migrated(names: names) }.map { binding in
            var binding = binding
            binding.target = Self.roundedTarget(binding.target)
            return binding
        }
    }

    /// Keybinds that radial menu or gesture entries refer to get a written `id`.
    private func bindingsToMigrate() -> [KeyBinding] {
        var linked: Set<UUID> = []
        for item in legacy(LegacyDefaults.radialMenuActions) {
            if case let .keybindReference(id) = item.type { linked.insert(id) }
        }
        for item in legacy(LegacyDefaults.gestures) {
            if case let .singleAction(.keybindReference(id)) = item.action { linked.insert(id) }
        }
        var migrated = convertedBindings(LegacyWindowAction.self, names: [:])
        let linkedIndices = migrated.indices.filter { linked.contains(migrated[$0].id) }
        // Assigned once the whole list is known, so a repeated name gets `-2`
        var taken = Set(migrated.compactMap(\.configID))
        for index in linkedIndices { taken.insert(migrated[index].ensureConfigurationID(avoiding: taken)) }
        return migrated
    }

    // MARK: Rounding

    private static func roundedPoint(_ value: CGFloat) -> CGFloat {
        let scaled = (Double(value) * 10).rounded()
        // A value too large to scale is left for the key's own validation.
        return scaled.isFinite ? CGFloat(scaled / 10) : value
    }

    private static func roundedPadding(_ padding: PaddingConfiguration) -> PaddingConfiguration {
        var padding = padding
        padding.window = roundedPoint(padding.window)
        padding.externalBar = roundedPoint(padding.externalBar)
        padding.top = roundedPoint(padding.top)
        padding.bottom = roundedPoint(padding.bottom)
        padding.right = roundedPoint(padding.right)
        padding.left = roundedPoint(padding.left)
        return padding
    }

    private static func roundedTarget(_ target: ActionTarget) -> ActionTarget {
        guard case let .windowAction(action) = target else { return target }
        return .windowAction(roundedAction(action))
    }

    private static func roundedAction(_ original: WindowAction) -> WindowAction {
        var action = original
        switch action.kind {
        case var .cycle(cycle):
            cycle.steps = cycle.steps.map(roundedTarget)
            action.kind = .cycle(cycle)
        case .custom, .stash:
            if let dimensions = action.customDimensions {
                action.customDimensions = .init(
                    width: dimensions.width?.roundedToDisplayPrecision(),
                    height: dimensions.height?.roundedToDisplayPrecision()
                )
            }
            if case let .coordinates(x, y)? = action.position {
                action.position = .coordinates(x: x?.roundedToDisplayPrecision(), y: y?.roundedToDisplayPrecision())
            }
        case .builtin: break
        }
        return action
    }
}
