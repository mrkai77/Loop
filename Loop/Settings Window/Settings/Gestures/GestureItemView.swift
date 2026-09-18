//
//  GestureItemView.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-16.
//

import Defaults
import Luminare
import SwiftUI

struct GestureItemView: View {
    @Environment(\.luminareAnimation) var luminareAnimation

    @Default(.keybinds) private var keybinds

    @State private var gesture: GestureBinding
    @Binding private var externalGesture: GestureBinding
    private let hasConflict: Bool

    @State private var isActionPickerPresented = false
    @State private var isGestureConfigPresented = false
    @State private var isConfiguringCustom = false
    @State private var isConfiguringCycle = false

    init(_ gesture: Binding<GestureBinding>, hasConflict: Bool) {
        self.gesture = gesture.wrappedValue
        self._externalGesture = gesture
        self.hasConflict = hasConflict
    }

    private var resolvedAction: WindowAction? {
        switch gesture.action {
        case .radialMenuActions:
            nil
        case let .singleAction(actionType):
            actionType.resolvedAction
        }
    }

    private var actionTypeBinding: Binding<RadialMenuAction.ActionType> {
        Binding(
            get: {
                if case let .singleAction(actionType) = gesture.action {
                    return actionType
                }
                return .custom(.init(.noAction))
            },
            set: { newValue in
                gesture.action = .singleAction(newValue)
            }
        )
    }

    private var actionBinding: Binding<WindowAction> {
        Binding(
            get: {
                resolvedAction ?? .init(.noAction)
            },
            set: { newAction in
                if case let .singleAction(actionType) = gesture.action {
                    switch actionType {
                    case .custom:
                        gesture.action = .singleAction(.custom(newAction))
                    case let .keybindReference(id):
                        if let index = Defaults[.keybinds].firstIndex(where: { $0.id == id }) {
                            keybinds[index] = newAction
                        }
                    }
                }
            }
        )
    }

    var body: some View {
        ZStack {
            actionSelection
                .frame(maxWidth: .infinity, alignment: .leading)

            gestureConfiguration
                .luminareToolTip(attachedTo: .topTrailing, hidden: !hasConflict) {
                    Text(String(localized: "There are other gestures that conflict with this gesture.", comment: "Tooltip shown on a conflicting gesture in settings"))
                        .padding(6)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .onChange(of: resolvedAction?.direction) { _ in
            if resolvedAction?.direction.isCustomizable == true {
                isConfiguringCustom = true
            }
            if resolvedAction?.direction == .cycle {
                isConfiguringCycle = true
            }
        }
        .onChange(of: gesture) { externalGesture = $0 }
    }

    
    private var actionSelection: some View {
        actionIndicator
            .luminarePopover(
                isPresented: $isActionPickerPresented,
                arrowEdge: .top,
                attachmentAnchor: .topLeading,
                shouldHideAnchor: true,
                shouldAnimate: false
            ) {
                RadialMenuActionPickerView(selection: actionTypeBinding)
                    .frame(width: 300, height: 300)
            }
            .onChange(of: isActionPickerPresented) { _ in
                if !isActionPickerPresented {
                    PickerListEventMonitorManager.shared.removeAllMonitors()
                }
            }
    }

    private var gestureConfiguration: some View {
        Button {
            isGestureConfigPresented = true
        } label: {
            VStack(alignment: .trailing, spacing: 2) {
                Text(gesture.displayName)
                    .fontWeight(.regular)
                    .lineLimit(1)

                if gesture.activationZone == .titlebar {
                    Text(gesture.activationZone.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            .contentShape(.rect)
            .animation(luminareAnimation, value: gesture.activationZone)
        }
        .luminareContentSize(contentMode: .fit, hasFixedHeight: true)
        .luminareRoundingBehavior(top: true, bottom: true)
        .luminareFilledStates([.hovering, .pressed])
        .luminareBorderedStates(.hovering)
        .luminareMinHeight(24)
        .opacity(hasConflict ? 0.5 : 1)
        .help(String(localized: "Customize this gesture.", comment: "Help text shown when hovering a gesture configuration button"))
        .padding(.leading, -4)
        .luminareModal(isPresented: $isGestureConfigPresented) {
            GestureConfigurationView(
                gesture: $gesture,
                isPresented: $isGestureConfigPresented
            )
            .frame(width: 380)
        }
        .luminareModalCornerRadius(24)
    }

    private var actionIndicator: some View {
        HStack(spacing: 2) {
            if case .radialMenuActions = gesture.action {
                HStack(spacing: 4) {
                    Image(.loop)
                    Text(String(localized: "Radial Menu", comment: "Label shown for a gesture configured to open the radial menu"))
                        .fontWeight(.regular)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .foregroundStyle(.secondary)
            } else {
                Button {
                    isActionPickerPresented = true
                } label: {
                    HStack(spacing: 8) {
                        if let action = resolvedAction {
                            IconView(action: action)

                            Text(action.getName())
                                .fontWeight(.regular)
                                .lineLimit(1)
                        } else {
                            Image(systemName: "bolt.horizontal.fill")
                                .foregroundStyle(.secondary)

                            Text(String(localized: "No Action", comment: "Label shown for a gesture with no configured action"))
                                .fontWeight(.regular)
                                .lineLimit(1)
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
                .help(String(localized: "Customize this gesture's action.", comment: "Help text shown when hovering a gesture's action button"))
                .padding(.leading, -4)
            }

            Group {
                if let resolvedAction {
                    if resolvedAction.direction.isCustomizable {
                        Button {
                            isConfiguringCustom = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.plain)
                        .luminareModal(isPresented: $isConfiguringCustom) {
                            if resolvedAction.direction == .custom {
                                CustomActionConfigurationView(
                                    action: actionBinding,
                                    isPresented: $isConfiguringCustom
                                )
                                .frame(width: 400)
                            } else {
                                StashActionConfigurationView(
                                    action: actionBinding,
                                    isPresented: $isConfiguringCustom
                                )
                                .frame(width: 400)
                            }
                        }
                        .luminareModalCornerRadius(24)
                        .help(String(localized: "Customize this action's custom frame.", comment: "Help text on the slider icon next to a gesture action with a custom frame"))
                    }

                    if resolvedAction.direction == .cycle {
                        Button {
                            isConfiguringCycle = true
                        } label: {
                            Image(systemName: "repeat")
                        }
                        .buttonStyle(.plain)
                        .luminareModal(isPresented: $isConfiguringCycle) {
                            CycleActionConfigurationView(
                                action: actionBinding,
                                isPresented: $isConfiguringCycle
                            )
                            .frame(width: 400)
                        }
                        .luminareModalCornerRadius(24)
                        .help(String(localized: "Customize what this action cycles through.", comment: "Help text on the cycle icon next to a gesture action that cycles"))
                    }
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }
}
