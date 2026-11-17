//
//  CycleActionConfigurationView.swift
//  Loop
//
//  Created by Kai Azim on 2024-05-03.
//

import Luminare
import SwiftUI

struct CycleActionConfigurationView: View {
    @Binding private var action: WindowAction
    @Binding private var isPresented: Bool
    @State private var steps: [EditorStep]
    @State private var selection: Set<EditorStep> = []
    private let owner: BindingReference?

    /// Separate from the target's identity, so duplicate references stay editable.
    private struct EditorStep: Identifiable, Hashable {
        let id: UUID
        var target: ActionTarget
        init(_ target: ActionTarget) { self.id = UUID(); self.target = target }
    }

    init(action: Binding<WindowAction>, isPresented: Binding<Bool>, owner: BindingReference? = nil) {
        _action = action
        _isPresented = isPresented
        self.owner = owner
        if case let .cycle(payload) = action.wrappedValue.kind {
            _steps = State(initialValue: payload.steps.map(EditorStep.init))
        } else {
            _steps = State(initialValue: [])
        }
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
                        steps.insert(EditorStep(.windowAction(.init(.noAction))), at: 0)
                    }

                    Button(String(localized: "Remove", comment: "Used to remove items from a list"), role: .destructive) {
                        let ids = Set(selection.map(\.id))
                        steps.removeAll { ids.contains($0.id) }
                        selection = []
                    }
                    .disabled(selection.isEmpty)
                }
                .luminareRoundingBehavior(top: true)

                LuminareList(
                    items: $steps,
                    selection: $selection,
                    id: \.id
                ) { step in
                    HStack {
                        ActionTargetEditorView(target: step.target, owner: owner, allowsCycles: false)

                        Spacer()

                        if let index = steps.firstIndex(where: { $0.id == step.wrappedValue.id }) {
                            Text("\(index)")
                                .frame(width: 27, height: 27)
                                .luminareSurface()
                                .luminareCornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 12)
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

            Button {
                isPresented = false
            } label: {
                Text("Done", comment: "Label for a button that closes a modal window")
            }
            .buttonStyle(.luminare(overrideUseMainStyle: true))
            .luminareCornerRadius(8)
        }
        .onChange(of: steps) { updated in
            guard case var .cycle(payload) = action.kind else { return }
            payload.steps = updated.map(\.target)
            action.kind = .cycle(payload)
            let selectedIDs = Set(selection.map(\.id))
            selection = Set(updated.filter { selectedIDs.contains($0.id) })
        }
        .onChange(of: action.kind) { updated in
            guard case let .cycle(payload) = updated, payload.steps != steps.map(\.target) else { return }
            steps = payload.steps.map(EditorStep.init)
            selection = []
        }
    }
}
