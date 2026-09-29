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
    @Default(.keybinds) private var keybinds

    @State private var action: RadialMenuAction
    @Binding private var externalAction: RadialMenuAction
    private let moveUp: () -> ()
    private let moveDown: () -> ()

    @State private var isActionPickerPresented = false
    @State private var isConfiguringCustom = false
    @State private var isConfiguringCycle = false

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

    private var actionBinding: Binding<WindowAction> {
        Binding(
            get: {
                action.resolved ?? .init(.noAction)
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
    }

    var body: some View {
        HStack(spacing: 12) {
            actionSelection

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
        .onChange(of: action.resolved?.direction) { _ in
            if action.resolved?.direction.isCustomizable == true {
                isConfiguringCustom = true
            }
            if action.resolved?.direction == .cycle {
                isConfiguringCycle = true
            }
        }
        .onChange(of: action) { externalAction = $0 }
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
                RadialMenuActionPickerView(selection: $action.type)
                    .frame(width: 300, height: 300)
            }
            .onChange(of: isActionPickerPresented) { _ in
                if !isActionPickerPresented {
                    PickerListEventMonitorManager.shared.removeAllMonitors()
                }
            }
    }

    private var actionIndicator: some View {
        HStack(spacing: 2) {
            Button {
                isActionPickerPresented.toggle()
            } label: {
                HStack(spacing: 8) {
                    if let action = action.resolved {
                        IconView(action: action)

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

                        Text("Failed to resolve linked keybind")
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
            .help("Customize this radial menu action.")
            .padding(.leading, -4)

            Group {
                if let resolvedAction = action.resolved {
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
                        .luminareModalCornerRadius(24)
                        .help("Customize what this action cycles through.")
                    }
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)
        }
    }
}
