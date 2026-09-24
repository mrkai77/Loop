//
//  RadialMenuConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-04-19.
//

import Defaults
import Luminare
import SwiftUI

struct RadialMenuConfigurationView: View {
    @EnvironmentObject private var windowModel: SettingsWindowManager
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Default(.radialMenuVisibility) private var radialMenuVisibility
    @Default(.radialMenuCornerRadius) private var radialMenuCornerRadius
    @Default(.radialMenuThickness) private var radialMenuThickness
    @Default(.enableRadialMenuCustomization) var enableRadialMenuCustomization
    @Default(.radialMenuActions) private var radialMenuActions
    @State private var selectedRadialMenuActions: Set<RadialMenuAction> = []

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
                    String(localized: "Left-click to step through cycle actions.", comment: "Section footer shown in settings")
                ) {
                    LuminareButtonRow {
                        Button("Add") {
                            radialMenuActions.insert(.custom(.init(.noAction)), at: 0)
                        }

                        Button("Remove", role: .destructive) {
                            radialMenuActions.removeAll(where: selectedRadialMenuActions.contains)
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
                            Text("Press \"Add\" to add an action")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .padding()
                    }
                    .luminareRoundingBehavior(bottom: true)
                    .onChange(of: selectedRadialMenuActions, perform: userSelectionChanged)
                    .onChange(of: windowModel.previewedParentAction ?? windowModel.previewedAction, perform: previewedActionChanged)
                    .onDisappear {
                        windowModel.isPreviewingUserSelection = false
                    }
                }
            }
        }
    }

    private func moveAction(_ action: RadialMenuAction, down: Bool) {
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

    private func userSelectionChanged(_ newValue: Set<RadialMenuAction>) {
        if newValue.count == 1, let resolved = newValue.first?.resolved {
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

        if let match = radialMenuActions.first(where: { $0.associatedActionId == newAction.id }) {
            selectedRadialMenuActions = [match]
        } else {
            selectedRadialMenuActions = []
        }
    }
}
