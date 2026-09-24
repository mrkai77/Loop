//
//  AdvancedConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-26.
//

import Combine
import Defaults
import Luminare
import Scribe
import SwiftUI

@Loggable
@MainActor
final class AdvancedConfigurationModel: ObservableObject {
    @Published private(set) var showResetRadialMenuActionsSuccessIndicator = false
    @Published private(set) var showImportKeybindsSuccessIndicator = false
    @Published private(set) var showExportKeybindsSuccessIndicator = false
    @Published private(set) var showResetKeybindsSuccessIndicator = false

    @Published private(set) var isLowPowerModeEnabled: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published private(set) var isAccessibilityAccessGranted = AccessibilityManager.shared.isGranted

    private var lowPowerModeCheckerTask: Task<(), Never>?
    private var accessibilityCheckerTask: Task<(), Never>?

    func startTracking() {
        trackLowPowerMode()
        trackAccessibilityStatus()
    }

    func stopTracking() {
        lowPowerModeCheckerTask?.cancel()
        accessibilityCheckerTask?.cancel()
    }

    private func trackLowPowerMode() {
        lowPowerModeCheckerTask = Task(priority: .background) {
            let notifications = NotificationCenter.default
                .notifications(named: Notification.Name.NSProcessInfoPowerStateDidChange)

            for await info in notifications {
                guard !Task.isCancelled else { break }
                guard let processInfo = info.object as? ProcessInfo else { continue }

                await MainActor.run {
                    isLowPowerModeEnabled = processInfo.isLowPowerModeEnabled
                }
            }
        }
    }

    private func trackAccessibilityStatus() {
        accessibilityCheckerTask = Task(priority: .background) {
            for await status in AccessibilityManager.shared.stream(initial: true) {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    isAccessibilityAccessGranted = status
                }
            }
        }
    }

    /// Prompts the user to import keybinds from a file.
    func importPrompt() {
        Task {
            do {
                try await Migrator.importPrompt {
                    showSuccessIndicator(\.showImportKeybindsSuccessIndicator)
                }
            } catch {
                log.error("Error importing keybinds: \(error)")
            }
        }
    }

    /// Prompts the user to export keybinds to a file.
    func exportPrompt() {
        Task {
            do {
                try await Migrator.exportPrompt {
                    showSuccessIndicator(\.showExportKeybindsSuccessIndicator)
                }
            } catch {
                log.error("Error exporting keybinds: \(error)")
            }
        }
    }

    /// Resets keybinds to default values.
    func resetKeybinds() {
        Defaults.reset(.keybinds)
        showSuccessIndicator(\.showResetKeybindsSuccessIndicator)
    }

    func resetRadialMenuActions() {
        Defaults.reset(.radialMenuActions)
        showSuccessIndicator(\.showResetRadialMenuActionsSuccessIndicator)
    }

    private func showSuccessIndicator(_ keyPath: ReferenceWritableKeyPath<AdvancedConfigurationModel, Bool>) {
        Task {
            withAnimation(.smooth(duration: 0.5)) {
                self[keyPath: keyPath] = true
            }

            try? await Task.sleep(for: .seconds(2))

            withAnimation(.smooth(duration: 0.5)) {
                self[keyPath: keyPath] = false
            }
        }
    }
}

struct AdvancedConfigurationView: View {
    @EnvironmentObject private var windowModel: SettingsWindowManager
    @Environment(\.luminareAnimation) var luminareAnimation
    @Environment(\.openURL) private var openURL

    @StateObject private var model = AdvancedConfigurationModel()

    @Default(.useSystemWindowManagerWhenAvailable) var useSystemWindowManagerWhenAvailable
    @Default(.ignoreLowPowerMode) var ignoreLowPowerMode
    @Default(.animateWindowResizes) var animateWindowResizes
    @Default(.disableCursorInteraction) var disableCursorInteraction
    @Default(.ignoreFullscreen) var ignoreFullscreen
    @Default(.hapticFeedback) var hapticFeedback
    @Default(.sizeIncrement) var sizeIncrement
    @Default(.enableRadialMenuCustomization) var enableRadialMenuCustomization

    @State private var isConfirmingResetKeybinds: Bool = false
    @State private var isConfirmingResetRadialMenuActions: Bool = false

    private var showLowPowerModeWarning: Bool {
        animateWindowResizes && !ignoreLowPowerMode && model.isLowPowerModeEnabled
    }

    var body: some View {
        LuminareForm {
            generalSection
            radialMenuSection
            keybindsSection
            permissionsSection
                .onAppear(perform: model.startTracking)
                .onDisappear(perform: model.stopTracking)
        }
        .animation(luminareAnimation, value: enableRadialMenuCustomization)
    }

    private var generalSection: some View {
        LuminareSection {
            if #available(macOS 15.0, *) {
                LuminareToggle("Use macOS window manager when available", isOn: $useSystemWindowManagerWhenAvailable)
            }

            LuminareToggle(isOn: $animateWindowResizes) {
                Text("Animate window resize")
                    .padding(.trailing, 4)
                    .luminareToolTip(attachedTo: .topTrailing, hidden: !showLowPowerModeWarning) {
                        HStack(spacing: 4) {
                            Text("To save power, window animations are\nunavailable in Low Power Mode.")
                                .multilineTextAlignment(.leading)

                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                                Button {
                                    openURL(url)
                                } label: {
                                    Image(systemName: "arrow.up.forward")
                                        .foregroundStyle(.secondary)
                                        .padding(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .animation(luminareAnimation, value: showLowPowerModeWarning)
            }

            LuminareToggle("Disable cursor interaction", isOn: $disableCursorInteraction)
            LuminareToggle("Ignore fullscreen windows", isOn: $ignoreFullscreen)
            LuminareToggle("Haptic feedback", isOn: $hapticFeedback)

            LuminareSlider(
                "Size increment",
                value: $sizeIncrement.doubleBinding,
                in: 5...50,
                step: 5,
                format: .number.precision(.fractionLength(0...0)),
                clampsUpper: false,
                suffix: Text("px", comment: "Unit symbol: pixels")
            )
        }
    }

    private var radialMenuSection: some View {
        LuminareSection(String(localized: "Radial Menu", comment: "Section header shown in settings")) {
            LuminareToggle(isOn: $enableRadialMenuCustomization) {
                HStack {
                    Text("Allow radial menu customization")

                    if enableRadialMenuCustomization {
                        Button {
                            windowModel.currentTab = .radialMenu
                        } label: {
                            Image(systemName: "arrow.up.right.square.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if enableRadialMenuCustomization {
                Button(role: .destructive) {
                    isConfirmingResetRadialMenuActions = true
                } label: {
                    HStack {
                        Text("Reset radial menu actions")

                        if model.showResetRadialMenuActionsSuccessIndicator {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .bold()
                        }
                    }
                }
                .luminareRoundingBehavior(bottom: true)
                .alert("Reset radial menu actions?", isPresented: $isConfirmingResetRadialMenuActions) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive, action: model.resetRadialMenuActions)
                } message: {
                    Text("This will reset all radial menu actions to their default configuration.")
                }
            }
        }
    }

    private var keybindsSection: some View {
        LuminareSection(String(localized: "Keybinds", comment: "Section header shown in settings")) {
            LuminareButtonRow {
                Button(action: model.importPrompt) {
                    HStack {
                        Text("Import")

                        if model.showImportKeybindsSuccessIndicator {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .bold()
                        }
                    }
                }

                Button(action: model.exportPrompt) {
                    HStack {
                        Text("Export")

                        if model.showExportKeybindsSuccessIndicator {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .bold()
                        }
                    }
                }

                Button(role: .destructive) {
                    isConfirmingResetKeybinds = true
                } label: {
                    HStack {
                        Text("Reset")

                        if model.showResetKeybindsSuccessIndicator {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .bold()
                        }
                    }
                }
                .alert("Reset keybinds?", isPresented: $isConfirmingResetKeybinds) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive, action: model.resetKeybinds)
                } message: {
                    Text("This will reset all keybinds to their original defaults.")
                }
            }
            .luminareRoundingBehavior(top: true, bottom: true)
        }
    }

    private var permissionsSection: some View {
        LuminareSection(String(localized: "Permissions", comment: "Section header shown in settings")) {
            accessibilityComponent()
        }
        .animation(luminareAnimation, value: model.isAccessibilityAccessGranted)
    }

    private func accessibilityComponent() -> some View {
        LuminareButton {
            HStack {
                if model.isAccessibilityAccessGranted {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }

                Text("Accessibility access")
            }
        } content: {
            Text("Request…", comment: "Button to request accessibility access")
        } action: {
            AccessibilityManager.requestAccess()
        }
        .disabled(model.isAccessibilityAccessGranted)
    }
}
