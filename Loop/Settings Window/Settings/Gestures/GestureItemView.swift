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
    @Environment(\.luminareAnimation) private var luminareAnimation
    @Environment(\.luminareSectionHorizontalPadding) private var horizontalPadding

    @Default(.keybinds) private var keybinds
    @Default(.gestures) private var gestures
    @Default(.radialMenuActions) private var radialMenuActions

    @State private var gesture: GestureBinding
    @Binding private var externalGesture: GestureBinding
    private let hasConflict: Bool
    private let overridesRadialMenu: Bool

    @State private var isActionPickerPresented = false
    @State private var isGestureConfigPresented = false
    @State private var isConfiguringCustom = false
    @State private var isConfiguringCycle = false

    init(_ gesture: Binding<GestureBinding>, hasConflict: Bool, overridesRadialMenu: Bool) {
        self.gesture = gesture.wrappedValue
        self._externalGesture = gesture
        self.hasConflict = hasConflict
        self.overridesRadialMenu = overridesRadialMenu
    }

    private var resolvedAction: WindowAction? {
        switch gesture.action {
        case .radialMenuActions:
            nil
        case let .singleAction(actionType):
            actionType.resolvedAction(with: linkResolver)
        }
    }

    private var linkResolver: BindingLinkResolver {
        BindingLinkResolver(keybinds: keybinds, gestures: gestures, radialMenuActions: radialMenuActions)
    }

    private var link: BindingLink? {
        if case let .singleAction(actionType) = gesture.action {
            return actionType.link
        }
        return nil
    }

    private var pickerSelection: Binding<ActionPickerView.Item> {
        Binding(
            get: {
                if case let .singleAction(actionType) = gesture.action {
                    return actionType.pickerItem
                }
                return .direction(.noAction)
            },
            set: { newValue in
                // A linked gesture changes the binding it links to, and is unlinked with its link button
                if case let .direction(direction) = newValue {
                    if let link, BindingLinkResolver.save(direction, through: link) {
                        // Leave it unchanged
                    } else {
                        gesture.action = .singleAction(.init(newValue))
                    }
                    configure(direction)
                } else {
                    gesture.action = .singleAction(.init(newValue))
                }
            }
        )
    }

    private func configure(_ direction: WindowDirection) {
        if direction.isCustomizable {
            isConfiguringCustom = true
        }
        if direction == .cycle {
            isConfiguringCycle = true
        }
    }

    private func unlink() {
        guard let link else {
            return
        }

        gesture.action = .singleAction(.custom((linkResolver.action(for: link) ?? WindowAction(.noAction)).detached()))
    }

    private var actionBinding: Binding<WindowAction> {
        Binding(
            get: {
                resolvedAction ?? .init(.noAction)
            },
            set: { newAction in
                if let link {
                    BindingLinkResolver.save(newAction, through: link)
                } else if case .singleAction = gesture.action {
                    gesture.action = .singleAction(.custom(newAction))
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: 8) {
            actionSelection
                .frame(maxWidth: .infinity, alignment: .leading)

            if hasConflict || overridesRadialMenu {
                LuminareToolTip(
                    image: hasConflict ? Image(systemName: "exclamationmark.triangle.fill") : Image(.handDrawFillBadge),
                    text: hasConflict
                        ? String(localized: "Another gesture is set up the same way.", comment: "Tooltip shown on a conflicting gesture in settings")
                        : String(localized: "Takes priority over the radial menu.", comment: "Tooltip shown on a gesture in settings that overrides one direction of a radial menu gesture using the same finger count")
                )
            }

            gestureConfiguration
        }
        .padding(.horizontal, 12)
        .onChange(of: gesture) { externalGesture = $0 }
        // An edit made through a link from another row changes this one's binding directly
        .onChange(of: externalGesture) { if $0 != gesture { gesture = $0 } }
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
                ActionPickerView(selection: pickerSelection, owner: BindingLink(.gesture, id: gesture.id))
                    .frame(width: 300, height: 300)
            }
            .onChange(of: isActionPickerPresented) { _ in
                if !isActionPickerPresented {
                    PickerListEventMonitorManager.shared.removeAllMonitors()
                }
            }
    }

    private var gestureConfiguration: some View {
        Group {
            if let displayName = gesture.displayName {
                Button {
                    isGestureConfigPresented = true
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(displayName)
                            .lineLimit(1)

                        if gesture.activationZone == .titlebar {
                            Text(gesture.activationZone.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .fontWeight(.regular)
                    .padding(.horizontal, 4)
                    .contentShape(.rect)
                    .animation(luminareAnimation, value: gesture.activationZone)
                }
                .luminareFilledStates([.hovering, .pressed])
                .luminareBorderedStates(.hovering)
                .opacity(hasConflict ? 0.5 : 1)
            } else {
                Button {
                    isGestureConfigPresented = true
                } label: {
                    Text(String(localized: "Set Gesture…", comment: "Button title on a gesture that has no trigger set yet. Opens the gesture configuration."))
                        .lineLimit(1)
                        .padding(.horizontal, horizontalPadding)
                }
            }
        }
        .luminareContentSize(contentMode: .fit, hasFixedHeight: true)
        .luminareRoundingBehavior(top: true, bottom: true)
        .luminareMinHeight(24)
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
            let opensRadialMenu = gesture.action == .radialMenuActions

            // The radial menu can't be changed here, but shares the button so it lines up with other actions
            Button {
                if !opensRadialMenu {
                    isActionPickerPresented.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if opensRadialMenu {
                        Image(.loop)
                            .frame(width: 18)

                        Text(String(localized: "Radial Menu", comment: "Label shown for a gesture configured to open the radial menu"))
                            .fontWeight(.regular)
                            .lineLimit(1)
                    } else if let action = resolvedAction {
                        IconView(action: action)

                        Text(action.getName())
                            .fontWeight(.regular)
                            .lineLimit(1)
                    } else {
                        // A single action only fails to resolve when its linked keybind was removed
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundStyle(.secondary)

                        Text("Linked keybind not found")
                            .fontWeight(.regular)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .luminareContentSize(contentMode: .fit, hasFixedHeight: true, isCompressible: true)
            .luminareRoundingBehavior(top: true, bottom: true)
            .luminareFilledStates([.hovering, .pressed])
            .luminareBorderedStates(.hovering)
            .luminareMinHeight(24)
            .help(String(localized: "Customize this gesture’s action.", comment: "Help text shown when hovering a gesture's action button"))
            .allowsHitTesting(!opensRadialMenu)
            .padding(.leading, -4)

            if let info = resolvedAction?.direction.infoText {
                LuminareToolTip(systemImage: "info.circle.fill", text: info)
            }

            if let link {
                BindingLinkBadge(kind: link.kind, unlink: unlink)
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
                        .help(String(localized: "Customize this action’s custom frame.", comment: "Help text on the slider icon next to a gesture action with a custom frame"))
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
