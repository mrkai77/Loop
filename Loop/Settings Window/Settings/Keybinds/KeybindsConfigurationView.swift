//
//  KeybindsConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-20.
//

import Luminare
import SwiftUI
import Tome

final class KeybindsConfigurationModel: ObservableObject {
    @Published var currentEventMonitor: LocalEventMonitor?
    @Published var selectedKeybinds = Set<KeyBinding>()
}

struct KeybindsConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @EnvironmentObject private var windowModel: SettingsWindowManager
    @StateObject private var model = KeybindsConfigurationModel()

    @TomeValue(\.triggerKey) private var triggerKey
    @TomeValue(\.sideDependentTriggerKey) private var sideDependentTriggerKey
    @TomeValue(\.triggerDelay) private var triggerDelay
    @TomeValue(\.cycleModeRestartEnabled) private var cycleModeRestartEnabled
    @TomeValue(\.cycleBackwardsOnShiftPressed) private var cycleBackwardsOnShiftPressed
    @TomeValue(\.doubleClickToTrigger) private var doubleClickToTrigger
    @TomeValue(\.middleClickTriggersLoop) private var middleClickTriggersLoop
    @TomeValue(\.enableTriggerDelayOnMiddleClick) private var enableTriggerDelayOnMiddleClick
    @TomeValue(\.hideOnNoSelectionForKeybinds) private var hideOnNoSelectionForKeybinds
    @TomeValue(\.keyBindings) private var keybinds
    @TomeValue(\.gestures) private var gestures
    @TomeValue(\.radialMenuActions) private var radialMenuBindings

    private var graph: ActionTargetEditorGraph {
        .init(keyBindings: keybinds, gestures: gestures, radialMenuBindings: radialMenuBindings)
    }

    /// If the user has "enabled" the trigger delay.
    private var useTriggerDelay: Bool {
        Tome.triggerDelay != .zero
    }

    /// Is Shift used in the trigger key?
    private var isShiftUsedByTriggerKey: Bool {
        triggerKey.names.map(KeyNames.baseModifier).contains(KeyNames.fixedName(for: .kVK_Shift) ?? "")
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
            TriggerKeycorder($triggerKey.names)
                .environmentObject(model)
                .luminareBorderedStates(.normal)
        }
        .luminareBorderedStates(.none)
    }

    @ViewBuilder
    private var settingsSection: some View {
        LuminareSection {
            LuminareToggle("Distinguish left and right modifier keys", isOn: $sideDependentTriggerKey)

            LuminareSlider(
                "Trigger delay",
                value: Binding(
                    get: { triggerDelay / .seconds(1) },
                    set: { if let delay = try? Duration.tomeBridge.deserialize(.float($0)) { triggerDelay = delay } }
                ),
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
                Text("Always start from the first action")
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
                Button(String(localized: "Add", comment: "Used to add items to a list")) {
                    keybinds.insert(.init(.noAction), at: 0)
                }

                Button(String(localized: "Remove", comment: "Used to remove items from a list"), role: .destructive) {
                    let ids = Set(model.selectedKeybinds.map(\.id))
                    keybinds.removeAll { ids.contains($0.id) }
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
                    Text("Click “Add” to add a keybind")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding()
            }
            .luminareRoundingBehavior(bottom: true)
            .onChange(of: model.selectedKeybinds, initial: true) { windowModel.previewSelection(model.selectedKeybinds, in: keybinds, graph: graph) }
            .onChange(of: graph) { _ in windowModel.previewSelection(model.selectedKeybinds, in: keybinds, graph: graph) }
            .onChange(of: keybinds) { updated in
                let ids = Set(model.selectedKeybinds.map(\.id))
                model.selectedKeybinds = Set(updated.filter { ids.contains($0.id) })
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
