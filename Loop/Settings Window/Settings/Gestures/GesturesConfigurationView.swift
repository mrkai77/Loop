//
//  GesturesConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-16.
//

import Luminare
import SwiftUI
import Tome

final class GesturesConfigurationModel: ObservableObject {
    @Published var selectedGestures = Set<GestureBinding>()
}

struct GesturesConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @EnvironmentObject private var windowModel: SettingsWindowManager
    @StateObject private var model = GesturesConfigurationModel()

    @TomeValue(\.enableGestures) private var enableGestures
    @TomeValue(\.gestures) private var gestures
    @TomeValue(\.keyBindings) private var keyBindings
    @TomeValue(\.radialMenuActions) private var radialMenuBindings

    private var graph: ActionTargetEditorGraph {
        .init(keyBindings: keyBindings, gestures: gestures, radialMenuBindings: radialMenuBindings)
    }

    private var conflictingGestureIDs: Set<UUID> {
        GestureBinding.conflictingIDs(in: gestures)
    }

    private var radialMenuOverrideIDs: Set<UUID> {
        GestureBinding.radialMenuOverrideIDs(in: gestures)
    }

    var body: some View {
        LuminareForm {
            settingsSection

            if enableGestures {
                gesturesSection
            }
        }
        .animation(luminareAnimation, value: enableGestures)
    }

    private var settingsSection: some View {
        LuminareSection {
            LuminareToggle(String(localized: "Trackpad gestures", comment: "Toggle in gestures settings"), isOn: $enableGestures)
        }
    }

    private var gesturesSection: some View {
        LuminareSection {
            LuminareButtonRow {
                Button(String(localized: "Add", comment: "Used to add items to a list")) {
                    gestures.insert(
                        GestureBinding(),
                        at: 0
                    )
                }

                Button(String(localized: "Remove", comment: "Used to remove items from a list"), role: .destructive) {
                    let selectedIDs = Set(model.selectedGestures.map(\.id))
                    gestures.removeAll { selectedIDs.contains($0.id) }
                }
                .disabled(model.selectedGestures.isEmpty)
                .keyboardShortcut(.delete)
            }
            .luminareRoundingBehavior(top: true)

            LuminareList(
                items: $gestures,
                selection: $model.selectedGestures,
                id: \.id
            ) { gesture in
                GestureItemView(
                    gesture,
                    hasConflict: conflictingGestureIDs.contains(gesture.wrappedValue.id),
                    overridesRadialMenu: radialMenuOverrideIDs.contains(gesture.wrappedValue.id)
                )
            } emptyView: {
                VStack {
                    Text(String(localized: "No gestures", comment: "Empty state title in gestures settings"))
                        .font(.title3)
                    Text(String(localized: "Click “Add” to add a gesture", comment: "Empty state subtitle in gestures settings"))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .padding()
            }
            .luminareRoundingBehavior(bottom: true)
            .onChange(of: model.selectedGestures, initial: true) { windowModel.previewSelection(model.selectedGestures, in: gestures, graph: graph) }
            .onChange(of: graph) { _ in windowModel.previewSelection(model.selectedGestures, in: gestures, graph: graph) }
            .onChange(of: gestures) { updated in
                let ids = Set(model.selectedGestures.map(\.id))
                model.selectedGestures = Set(updated.filter { ids.contains($0.id) })
            }
            .onDisappear {
                windowModel.isPreviewingUserSelection = false
            }
        } header: {
            Text("Gestures", comment: "Section header shown in gestures settings")
                .fontWeight(.medium)
        } footer: {
            Text("Continue the swipe or magnify gesture to step through cycle actions.", comment: "Section footer shown in settings")
                .font(.caption)
        }
    }
}
