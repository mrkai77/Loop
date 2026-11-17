//
//  ActionTargetEditorView.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Luminare
import SwiftUI
import Tome

struct ActionTargetEditorView: View {
    @Binding var target: ActionTarget
    private let owner: ActionTarget?
    private let allowsCycles: Bool
    @TomeValue(\.keyBindings) private var keyBindings
    @TomeValue(\.gestures) private var gestures
    @TomeValue(\.radialMenuActions) private var radialMenuBindings
    @State private var isPickerPresented = false
    @State private var isCustomPresented = false
    @State private var isCyclePresented = false

    init(target: Binding<ActionTarget>, owner: ActionTarget? = nil, allowsCycles: Bool = true) {
        _target = target
        self.owner = owner
        self.allowsCycles = allowsCycles
    }

    private var graph: ActionTargetEditorGraph {
        .init(keyBindings: keyBindings, gestures: gestures, radialMenuBindings: radialMenuBindings)
    }

    private var action: WindowAction? { graph.resolve(target) }
    private var actionBinding: Binding<WindowAction> {
        Binding(
            get: { action ?? .init(.noAction) },
            set: { target = replacingAction(with: $0) }
        )
    }

    private var pickerHelp: String {
        switch owner {
        case .gestureBinding:
            String(localized: "Customize this gesture’s action.", comment: "Help text shown when hovering a gesture's action button")
        case .radialMenuBinding:
            String(localized: "Customize this radial menu action.")
        default:
            String(localized: "Customize this keybind’s action.")
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                isPickerPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    if let action {
                        IconView(action: graph.iconAction(for: action))

                        if let info = action.direction.infoText {
                            Text(action.getName())
                                .fontWeight(.regular)
                                .lineLimit(1)
                                .padding(.trailing, 4)
                                .luminareToolTip(attachedTo: .topTrailing) {
                                    Text(info)
                                        .padding(6)
                                }
                        } else {
                            Text(action.getName())
                                .fontWeight(.regular)
                                .lineLimit(1)
                        }
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundStyle(.secondary)

                        Text("Linked binding not found")
                            .fontWeight(.regular)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }

                    if target.isReference {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
            .luminareContentSize(contentMode: .fit, hasFixedHeight: true)
            .luminareRoundingBehavior(top: true, bottom: true)
            .luminareFilledStates([.hovering, .pressed])
            .luminareBorderedStates(.hovering)
            .luminareMinHeight(24)
            .help(pickerHelp)
            .padding(.leading, -4)
            .luminarePopover(
                isPresented: $isPickerPresented,
                arrowEdge: .top,
                attachmentAnchor: .topLeading,
                shouldHideAnchor: true,
                shouldAnimate: false
            ) {
                ActionPickerView(selection: $target, owner: owner, allowsCycles: allowsCycles)
                    .frame(width: 300, height: 300)
            }

            Group {
                if let action, action.direction.isCustomizable {
                    Button {
                        isCustomPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .help("Customize this action’s custom frame.")
                }

                if allowsCycles, action?.direction == .cycle {
                    Button {
                        isCyclePresented = true
                    } label: {
                        Image(systemName: "repeat")
                    }
                    .buttonStyle(.plain)
                    .help("Customize what this action cycles through.")
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
        }
        .luminareModal(isPresented: $isCustomPresented) {
            if action?.direction.isCustomizable == true {
                CustomActionConfigurationView(action: actionBinding, isPresented: $isCustomPresented)
                    .frame(width: 400)
            }
        }
        .luminareModalCornerRadius(24)
        .luminareModal(isPresented: $isCyclePresented) {
            CycleActionConfigurationView(action: actionBinding, isPresented: $isCyclePresented, owner: graph.terminalReference(for: target) ?? owner)
                .frame(width: 400)
        }
        .luminareModalCornerRadius(24)
        .onChange(of: action?.direction) { direction in
            guard !target.isReference else { return }
            isCustomPresented = direction?.isCustomizable == true
            isCyclePresented = direction == .cycle
        }
        .onChange(of: isPickerPresented) { presented in
            if !presented { PickerListEventMonitorManager.shared.removeAllMonitors() }
        }
    }

    private func replacingAction(with action: WindowAction) -> ActionTarget {
        let graph = ActionTargetEditorGraph.current
        if let old = graph.resolve(target), let holder = graph.holder(of: target, owner: owner) {
            DispatchQueue.main.async { ActionTargetEditorGraph.followRename(of: holder, from: old, to: action) }
        }
        switch graph.replacingAction(in: target, with: action) {
        case let .direct(target): return target
        case let .keyBindings(values): Tome.keyBindings = values
        case let .gestures(values): Tome.gestures = values
        case let .radialMenuBindings(values): Tome.radialMenuActions = values
        case nil: break
        }
        return target
    }
}
