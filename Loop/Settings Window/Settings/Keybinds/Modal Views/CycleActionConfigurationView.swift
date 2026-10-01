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
    @Binding private var windowAction: WindowAction
    @Binding private var isPresented: Bool

    @State private var action: WindowAction // this is so that onChange is called for each property

    @State private var selectedKeybinds = Set<WindowAction>()

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

                        action.cycle?.insert(.init(.noAction), at: 0)
                    }

                    Button(String(localized: "Remove", comment: "Used to remove items from a list"), role: .destructive) {
                        action.cycle?.removeAll(where: { selectedKeybinds.contains($0) })
                    }
                    .disabled(selectedKeybinds.isEmpty)
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
                    selection: $selectedKeybinds,
                    id: \.id
                ) { item in
                    KeybindItemView(
                        item,
                        cycleIndex: action.cycle?.firstIndex(of: item.wrappedValue)
                    )
                    .environmentObject(KeybindsConfigurationModel())
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
        .onAppear {
            if action.cycle == nil {
                action.cycle = []
            }
        }
    }
}
