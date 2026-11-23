//
//  CycleActionConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-05-03.
//

import Defaults
import Luminare
import SwiftUI

struct CycleActionConfigurationView: View {
    @Environment(\.luminareAnimation) private var luminareAnimation

    @Binding private var windowAction: WindowAction
    @Binding private var isPresented: Bool

    @State private var action: WindowAction // this is so that onChange is called for each property

    @State private var selectedSteps = Set<CycleStep>()

    init(action: Binding<WindowAction>, isPresented: Binding<Bool>) {
        self._windowAction = action
        self._isPresented = isPresented
        self._action = State(initialValue: action.wrappedValue)
    }

    var body: some View {
        LuminareForm {
            LuminareSection(outerPadding: 0) {
                LuminareTextField(
                    WindowDirection.cycle.name,
                    text: Binding(get: { action.name ?? "" }, set: { action.name = $0 })
                )
                .luminareFilledStates(.none)
                .luminareBorderedStates(.none)
            }

            LuminareSection(outerPadding: 0) {
                LuminareButtonRow {
                    Button(String(localized: "Add", comment: "Used to add items to a list")) {
                        if action.cycle == nil {
                            action.cycle = []
                        }

                        action.cycle?.insert(CycleStep(target: .action(WindowAction(.noAction))), at: 0)
                    }

                    Button(String(localized: "Remove", comment: "Used to remove items from a list"), role: .destructive) {
                        action.cycle?.removeAll(where: { selectedSteps.contains($0) })
                    }
                    .disabled(selectedSteps.isEmpty)
                }
                .luminareRoundingBehavior(top: true)

                LuminareList(
                    items: Binding(
                        get: {
                            action.cycle ?? []
                        },
                        set: { newValue in
                            action.cycle = newValue
                        }
                    ),
                    selection: $selectedSteps,
                    id: \.id
                ) { item in
                    CycleStepItemView(step: item, index: action.cycle?.firstIndex(of: item.wrappedValue) ?? 0)
                } emptyView: {
                    VStack {
                        Text("Nothing to cycle through")
                            .font(.title3)
                        Text("Click “Add” to add an action")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding()
                }
                .luminareRoundingBehavior(bottom: true)
                .luminareListFixedHeight(until: .infinity)
            }
            .onChange(of: action) { windowAction = $0 }

            Button {
                isPresented = false
            } label: {
                Text("Done", comment: "Label for a button that closes a modal window")
            }
            .buttonStyle(.luminare(overrideUseMainStyle: true))
            .luminareCornerRadius(8)
        }
        // The window resizes to fit, so adding or removing a step moves everything below the list
        .animation(luminareAnimation, value: action.cycle?.count)
        .onAppear {
            action.fillDefaults()
        }
    }
}
