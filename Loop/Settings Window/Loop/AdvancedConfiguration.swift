//
//  AdvancedConfiguration.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-26.
//

import Combine
import Luminare
import Scribe
import SwiftUI
import Tome

@Loggable
@MainActor
final class AdvancedConfigurationModel: ObservableObject {
    @Published private(set) var showResetRadialMenuActionsSuccessIndicator = false
    @Published private(set) var showImportConfigurationSuccessIndicator = false
    @Published private(set) var showResetConfigurationSuccessIndicator = false
    @Published var resetError: String?

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

    func importPrompt() {
        Task {
            do {
                try await Migrator.importPrompt {
                    showSuccessIndicator(\.showImportConfigurationSuccessIndicator)
                }
            } catch {
                log.error("Error importing configuration: \(error)")
            }
        }
    }

    /// Backs up config.toml first.
    func resetConfiguration() {
        do {
            try ConfigurationManager.shared.reset()
            showSuccessIndicator(\.showResetConfigurationSuccessIndicator)
        } catch {
            log.error("Error resetting configuration: \(error)")
            resetError = error.localizedDescription
        }
    }

    func resetRadialMenuActions() {
        Tome.reset(\.radialMenuBindings)
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

    @TomeValue(\.useSystemWindowManagerWhenAvailable) var useSystemWindowManagerWhenAvailable
    @TomeValue(\.animateInLowPowerMode) var animateInLowPowerMode
    @TomeValue(\.animateWindowResizes) var animateWindowResizes
    @TomeValue(\.selectActionsWithCursor) var selectActionsWithCursor
    @TomeValue(\.ignoreFullscreen) var ignoreFullscreen
    @TomeValue(\.hapticFeedback) var hapticFeedback
    @TomeValue(\.sizeIncrement) var sizeIncrement
    @TomeValue(\.enableRadialMenuCustomization) var enableRadialMenuCustomization
    @TomeValue(\.screenOrder) var screenOrder

    @State private var isConfirmingResetConfiguration: Bool = false
    @State private var isConfirmingResetRadialMenuActions: Bool = false

    private var showLowPowerModeWarning: Bool {
        animateWindowResizes && !animateInLowPowerMode && model.isLowPowerModeEnabled
    }

    /// The preference only takes effect where the macOS window manager integration is available
    private var isSystemWindowManagerIntegrated: Bool {
        if #available(macOS 15, *) {
            useSystemWindowManagerWhenAvailable
        } else {
            false
        }
    }

    var body: some View {
        LuminareForm {
            generalSection
            radialMenuSection
            configurationSection
            permissionsSection
                .onAppear(perform: model.startTracking)
                .onDisappear(perform: model.stopTracking)
        }
        .animation(luminareAnimation, value: enableRadialMenuCustomization)
        .animation(luminareAnimation, value: useSystemWindowManagerWhenAvailable)
    }

    private var generalSection: some View {
        LuminareSection {
            if #available(macOS 15.0, *) {
                LuminareToggle("Integrate with macOS window manager", isOn: $useSystemWindowManagerWhenAvailable)
            }

            // The macOS window manager's own animation setting applies instead
            if !isSystemWindowManagerIntegrated {
                LuminareToggle(isOn: $animateWindowResizes) {
                    Text("Animate window resizing")
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
            }

            LuminareToggle(
                "Select actions with cursor",
                isOn: $selectActionsWithCursor
            )
            LuminareToggle("Ignore full-screen windows", isOn: $ignoreFullscreen)
            LuminareToggle("Haptic feedback", isOn: $hapticFeedback)

            LuminarePickerMenu(
                "Next/previous screen order",
                selection: $screenOrder,
                items: ScreenOrder.allCases
            ) { order in
                Text("\(order.image) \(Text(order.name))")
            }

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
                    Text("Customize actions")

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
                        Text("Reset radial menu actions…")

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
                    Text("This resets all radial menu actions to their defaults.")
                }
            }
        }
    }

    private var configurationSection: some View {
        LuminareSection(String(localized: "Configuration", comment: "Section header shown in settings")) {
            LuminareButton {
                Text((Tome.standard.url.path as NSString).abbreviatingWithTildeInPath)
                    .monospaced()
                    .lineLimit(1)
                    .truncationMode(.middle)
            } content: {
                Text("Open…")
            } action: {
                ConfigurationManager.shared.openInEditor()
            }

            LuminareButtonRow {
                Button(action: model.importPrompt) {
                    HStack {
                        Text("Import…")

                        if model.showImportConfigurationSuccessIndicator {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .bold()
                        }
                    }
                }

                Button(role: .destructive) {
                    isConfirmingResetConfiguration = true
                } label: {
                    HStack {
                        Text("Reset…")

                        if model.showResetConfigurationSuccessIndicator {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                                .bold()
                        }
                    }
                }
                .alert("Reset all settings?", isPresented: $isConfirmingResetConfiguration) {
                    Button("Cancel", role: .cancel) {}
                    Button("Reset", role: .destructive, action: model.resetConfiguration)
                } message: {
                    Text("Every setting returns to its default. Your current configuration file is saved to \((ConfigurationManager.shared.backupsDirectory.path as NSString).abbreviatingWithTildeInPath) first.")
                }
                .alert(
                    "Couldn't reset settings",
                    isPresented: Binding(get: { model.resetError != nil }, set: { if !$0 { model.resetError = nil } })
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(model.resetError ?? "")
                }
            }
            .luminareRoundingBehavior(bottom: true)
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

                // macOS 27 renamed the Accessibility privacy pane to Device Control and Data Access
                if #available(macOS 27, *) {
                    Text("Device Control and Data Access", comment: "Name of the privacy pane in macOS 27 and later, shown as a permission in settings")
                } else {
                    Text("Accessibility access", comment: "Name of the privacy pane in macOS 26 and earlier, shown as a permission in settings")
                }
            }
        } content: {
            Text("Request…", comment: "Button to request accessibility access")
        } action: {
            AccessibilityManager.requestAccess()
        }
        .disabled(model.isAccessibilityAccessGranted)
    }
}
