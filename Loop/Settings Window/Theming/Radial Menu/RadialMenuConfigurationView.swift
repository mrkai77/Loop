//
//  RadialMenuConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Luminare
import SwiftUI
import Tome

struct RadialMenuConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation
    @EnvironmentObject private var windowModel: SettingsWindowManager

    @TomeValue(\.radialMenuVisibility) private var radialMenuVisibility
    @TomeValue(\.radialMenuCornerRadius) private var radialMenuCornerRadius
    @TomeValue(\.radialMenuThickness) private var radialMenuThickness
    @TomeValue(\.enableRadialMenuCustomization) private var enableRadialMenuCustomization
    @TomeValue(\.radialMenuActions) private var radialMenuActions
    @TomeValue(\.keyBindings) private var keyBindings
    @TomeValue(\.gestures) private var gestures

    private var graph: ActionTargetEditorGraph {
        .init(keyBindings: keyBindings, gestures: gestures, radialMenuBindings: radialMenuActions)
    }

    @State private var selectedRadialMenuActions: Set<RadialMenuBinding> = []

    var body: some View {
        LuminareForm {
            LuminareSection {
                LuminareToggle("Radial menu", isOn: $radialMenuVisibility)

                if radialMenuVisibility {
                    LuminareSlider(
                        "Corner radius",
                        value: $radialMenuCornerRadius.doubleBinding,
                        in: 30...50,
                        format: .number.precision(.fractionLength(0...0)),
                        clampsUpper: true,
                        clampsLower: true,
                        suffix: Text("px", comment: "Unit symbol: pixels")
                    )
                    .onChange(of: radialMenuCornerRadius) { _ in
                        if radialMenuCornerRadius - 1 < radialMenuThickness {
                            radialMenuThickness = radialMenuCornerRadius - 1
                        }
                    }

                    LuminareSlider(
                        "Thickness",
                        value: $radialMenuThickness.doubleBinding,
                        in: 10...35,
                        format: .number.precision(.fractionLength(0...0)),
                        clampsUpper: true,
                        clampsLower: true,
                        suffix: Text("px", comment: "Unit symbol: pixels")
                    )
                    .onChange(of: radialMenuThickness) { _ in
                        if radialMenuThickness + 1 > radialMenuCornerRadius {
                            radialMenuCornerRadius = radialMenuThickness + 1
                        }
                    }
                }
            }
            .animation(luminareAnimation, value: radialMenuVisibility)

            if enableRadialMenuCustomization {
                LuminareSection(
                    String(localized: "Actions", comment: "Header for radial menu section shown in settings"),
                    String(localized: "Click to step through cycle actions.", comment: "Section footer shown in settings")
                ) {
                    LuminareButtonRow {
                        Button(String(localized: "Add", comment: "Used to add items to a list")) {
                            radialMenuActions.insert(.custom(.init(.noAction)), at: 0)
                        }

                        Button(String(localized: "Remove", comment: "Used to remove items from a list"), role: .destructive) {
                            let ids = Set(selectedRadialMenuActions.map(\.id))
                            radialMenuActions.removeAll { ids.contains($0.id) }
                        }
                        .disabled(selectedRadialMenuActions.isEmpty)
                        .keyboardShortcut(.delete)
                    }
                    .luminareRoundingBehavior(top: true)

                    LuminareList(
                        items: $radialMenuActions,
                        selection: $selectedRadialMenuActions,
                        id: \.id
                    ) { action in
                        RadialMenuActionItemView(
                            action,
                            moveUp: { moveAction(action.wrappedValue, down: false) },
                            moveDown: { moveAction(action.wrappedValue, down: true) }
                        )
                    } emptyView: {
                        VStack {
                            Text("No radial menu actions")
                                .font(.title3)
                            Text("Click “Add” to add an action")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding()
                    }
                    .luminareRoundingBehavior(bottom: true)
                    .onChange(of: selectedRadialMenuActions, perform: userSelectionChanged)
                    .onChange(of: graph) { _ in userSelectionChanged(selectedRadialMenuActions) }
                    .onChange(of: windowModel.previewedParentAction ?? windowModel.previewedAction, perform: previewedActionChanged)
                    .onChange(of: radialMenuActions) { updated in
                        let ids = Set(selectedRadialMenuActions.map(\.id))
                        selectedRadialMenuActions = Set(updated.filter { ids.contains($0.id) })
                    }
                    .onDisappear {
                        windowModel.isPreviewingUserSelection = false
                    }
                }
            }
        }
    }

    private func moveAction(_ action: RadialMenuBinding, down: Bool) {
        guard
            let index = radialMenuActions.firstIndex(where: { $0.id == action.id })
        else { return }

        let newIndex = index + (down ? 1 : -1)
        guard radialMenuActions.indices.contains(newIndex) else { return }

        radialMenuActions.move(
            fromOffsets: IndexSet(integer: index),
            toOffset: newIndex > index ? newIndex + 1 : newIndex
        )
    }

    private func userSelectionChanged(_ newValue: Set<RadialMenuBinding>) {
        if newValue.count == 1, let selected = newValue.first,
           let current = radialMenuActions.first(where: { $0.id == selected.id }),
           let resolved = graph.resolve(current.target) {
            windowModel.isPreviewingUserSelection = true
            windowModel.setPreviewedAction(to: resolved)
        } else {
            windowModel.isPreviewingUserSelection = false
        }
    }

    private func previewedActionChanged(_ newAction: WindowAction) {
        guard windowModel.isPreviewingUserSelection else {
            return
        }

        if let match = radialMenuActions.first(where: { graph.resolve($0.target)?.id == newAction.id }) {
            selectedRadialMenuActions = [match]
        } else {
            selectedRadialMenuActions = []
        }
    }
}
