//
//  KeybindsConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-20.
//

import Defaults
import Luminare
import SwiftUI

final class KeybindsConfigurationModel: ObservableObject {
    @Published var currentEventMonitor: LocalEventMonitor?
    @Published var selectedKeybinds = Set<WindowAction>()
}

struct KeybindsConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @EnvironmentObject private var windowModel: SettingsWindowManager
    @StateObject private var model = KeybindsConfigurationModel()

    @Default(.triggerKey) private var triggerKey
    @Default(.sideDependentTriggerKey) private var sideDependentTriggerKey
    @Default(.triggerDelay) private var triggerDelay
    @Default(.cycleModeRestartEnabled) private var cycleModeRestartEnabled
    @Default(.cycleBackwardsOnShiftPressed) private var cycleBackwardsOnShiftPressed
    @Default(.doubleClickToTrigger) private var doubleClickToTrigger
    @Default(.middleClickTriggersLoop) private var middleClickTriggersLoop
    @Default(.enableTriggerDelayOnMiddleClick) private var enableTriggerDelayOnMiddleClick
    @Default(.hideOnNoSelectionForKeybinds) private var hideOnNoSelectionForKeybinds
    @Default(.keybinds) private var keybinds

    /// If the user has "enabled" the trigger delay.
    private var useTriggerDelay: Bool {
        Defaults[.triggerDelay] != 0
    }

    /// Is Shift used in the trigger key?
    private var isShiftUsedByTriggerKey: Bool {
        triggerKey.map(\.baseModifier).contains(.kVK_Shift)
    }

    private var showMiddleClickTriggerDelayOption: Bool {
        middleClickTriggersLoop && useTriggerDelay
    }

    var body: some View {
        LuminareForm {
            triggerKeySection
            settingsSection
            keybindsSection
        }
        .animation(
            luminareAnimation,
            value: [
                showMiddleClickTriggerDelayOption,
                cycleModeRestartEnabled,
                isShiftUsedByTriggerKey
            ]
        )
    }

    private var triggerKeySection: some View {
        LuminareSection(String(localized: "Trigger Key", comment: "Section header shown in settings")) {
            TriggerKeycorder($triggerKey)
                .environmentObject(model)
                .luminareBorderedStates(.normal)
        }
        .luminareBorderedStates(.none)
    }

    @ViewBuilder
    private var settingsSection: some View {
        LuminareSection(String(localized: "Settings", comment: "Section header shown in settings")) {
            LuminareToggle("Treat left and right keys differently", isOn: $sideDependentTriggerKey)

            LuminareSlider(
                "Trigger delay",
                value: $triggerDelay,
                in: 0...1,
                step: 0.1,
                format: .number.precision(.fractionLength(1...1)),
                clampsUpper: false,
                suffix: Text("s", comment: "Unit symbol: seconds")
            )

            LuminareToggle(
                String(localized: "Hide when no action is selected", comment: "Toggle to hide the radial menu whenever no action is selected"),
                isOn: $hideOnNoSelectionForKeybinds
            )

            LuminareToggle("Double-click to trigger", isOn: $doubleClickToTrigger)
            LuminareToggle("Middle-click to trigger", isOn: $middleClickTriggersLoop)

            if showMiddleClickTriggerDelayOption {
                LuminareToggle("Apply trigger delay on middle-click", isOn: $enableTriggerDelayOnMiddleClick)
            }
        }

        LuminareSection(String(localized: "Cycles", comment: "Section header shown in settings")) {
            LuminareToggle(isOn: $cycleModeRestartEnabled) {
                Text("Always start cycles from first item")
                    .padding(.trailing, 4)
                    .luminareToolTip(attachedTo: .topTrailing) {
                        Text("By default, Loop resumes cycles from where you last left off in each window.")
                            .padding(6)
                    }
            }

            if !isShiftUsedByTriggerKey {
                LuminareToggle("Cycle backward with Shift", isOn: $cycleBackwardsOnShiftPressed)
            }
        }
    }

    private var keybindsSection: some View {
        LuminareSection(String(localized: "Keybinds", comment: "Section header shown in settings")) {
            LuminareButtonRow {
                Button("Add") {
                    keybinds.insert(.init(.noAction), at: 0)
                }

                Button("Remove", role: .destructive) {
                    keybinds.removeAll(where: model.selectedKeybinds.contains)
                }
                .disabled(model.selectedKeybinds.isEmpty)
                .keyboardShortcut(.delete)
            }
            .luminareRoundingBehavior(top: true)

            LuminareList(
                items: $keybinds,
                selection: $model.selectedKeybinds,
                id: \.id
            ) { keybind in
                KeybindItemView(keybind)
                    .environmentObject(model)
            } emptyView: {
                VStack {
                    Text("No keybinds")
                        .font(.title3)
                    Text("Press \"Add\" to add a keybind")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding()
            }
            .luminareRoundingBehavior(bottom: true)
            .onChange(of: model.selectedKeybinds, initial: true) {
                if model.selectedKeybinds.count == 1, let action = model.selectedKeybinds.first {
                    windowModel.isPreviewingUserSelection = true
                    windowModel.setPreviewedAction(to: action)
                } else {
                    windowModel.isPreviewingUserSelection = false
                }
            }
            .onDisappear {
                windowModel.isPreviewingUserSelection = false
            }
        }
    }
}

#Preview {
    KeybindsConfigurationView()
        .frame(width: 300)
}
