//
//  RadialMenuActionItemView.swift
//  Loop
//
//  Created by Kai Azim on 2025-12-08.
//

import Defaults
import Luminare
import SwiftUI

struct RadialMenuActionItemView: View {
    @Environment(\.luminareItemBeingHovered) private var isHovering

    @Default(.keybinds) private var keybinds

    @State private var action: RadialMenuAction
    @State private var isConfiguringCustom: Bool = false
    @State private var isConfiguringCycle: Bool = false
    @State private var isPickerPresented = false

    @Binding private var externalAction: RadialMenuAction
    private let moveUp: () -> ()
    private let moveDown: () -> ()

    init(
        _ action: Binding<RadialMenuAction>,
        moveUp: @escaping () -> (),
        moveDown: @escaping () -> ()
    ) {
        self.action = action.wrappedValue
        self._externalAction = action
        self.moveUp = moveUp
        self.moveDown = moveDown
    }

    var body: some View {
        HStack(spacing: 12) {
            label

            Spacer()

            if action.type.isKeybindReference {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                    .help("This action is linked to a keybind. Changes made to this action will affect both.")
            }

            HStack(spacing: 8) {
                Button(action: moveUp) {
                    Image(systemName: "arrow.up")
                        .frame(width: 27, height: 27)
                        .font(.callout)
                        .contentShape(.rect)
                }
                .luminareContentSize(aspectRatio: 1.0, contentMode: .fit, hasFixedHeight: true)
                .luminareRoundingBehavior(top: true, bottom: true)

                Button(action: moveDown) {
                    Image(systemName: "arrow.down")
                        .frame(width: 27, height: 27)
                        .font(.callout)
                        .contentShape(.rect)
                }
                .luminareContentSize(aspectRatio: 1.0, contentMode: .fit, hasFixedHeight: true)
                .luminareRoundingBehavior(top: true, bottom: true)
            }
        }
        .padding(.horizontal, 12)
        .onChange(of: action) { newAction in
            externalAction = newAction

            guard let resolvedAction = action.resolved else {
                isConfiguringCustom = false
                isConfiguringCycle = false
                return
            }

            Task {
                isConfiguringCustom = resolvedAction.direction.isCustomizable
                isConfiguringCycle = resolvedAction.direction == .cycle
            }
        }
    }

    private var label: some View {
        actionIndicator
            .luminarePopover(
                isPresented: $isPickerPresented,
                arrowEdge: .top,
                attachmentAnchor: .topLeading,
                shouldHideAnchor: true,
                shouldAnimate: false
            ) {
                RadialMenuActionPickerView(selection: $action.type)
                    .frame(width: 300, height: 300)
            }
            .onChange(of: isPickerPresented) { _ in
                if !isPickerPresented {
                    PickerListEventMonitorManager.shared.removeAllMonitors()
                }
            }
    }

    var actionIndicator: some View {
        HStack(spacing: 2) {
            Button {
                isPickerPresented = true
            } label: {
                HStack(spacing: 8) {
                    if let action = action.resolved {
                        IconView(action: action)

                        Text(action.getName())
                            .fontWeight(.regular)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundStyle(.secondary)

                        Text("Failed to resolve linked keybind")
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
            .padding(.leading, -4)

            Group {
                if let resolvedAction = action.resolved {
                    let actionBinding = Binding<WindowAction>(
                        get: {
                            resolvedAction
                        },
                        set: { newAction in
                            switch action.type {
                            case .custom:
                                action.type = .custom(newAction)
                            case .keybindReference:
                                guard let index = Defaults[.keybinds].firstIndex(where: { $0.id == action.associatedActionId }) else {
                                    return
                                }

                                keybinds[index] = newAction
                            }
                        }
                    )

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
                        .luminareCornerRadius(24)
                        .help("Customize this action's custom frame.")
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
                        .luminareCornerRadius(24)
                        .help("Customize what this action cycles through.")
                    }
                }
            }
            .font(.title3)
            .foregroundStyle(isHovering ? .primary : .secondary)
        }
    }
}
