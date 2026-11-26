//
//  BindingActionSelection.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-23.
//

import Defaults
import Luminare
import SwiftUI

/// The action picker button of a keybind, gesture, radial menu action or cycle step, with its info, link and editors
struct BindingActionSelection: View {
    @Environment(\.luminareAnimationFast) private var animationFast
    @BindingLinks private var linkResolver

    @Binding var target: BindingTarget
    let owner: BindingIdentity?
    let help: LocalizedStringKey

    @State private var isActionPickerPresented = false
    @State private var isConfiguringCustom = false
    @State private var isConfiguringCycle = false

    private var editableAction: Binding<WindowAction> {
        Binding(
            get: { target.editableAction(with: linkResolver) ?? WindowAction(.noAction) },
            set: { target.saveEdited($0) }
        )
    }

    private var pickerSelection: Binding<ActionPickerView.Item> {
        Binding(
            get: { target.pickerItem(with: linkResolver) },
            set: { item in
                guard let direction = target.pick(item, owner: owner) else { return }
                isConfiguringCustom = direction.isCustomizable
                isConfiguringCycle = direction == .cycle
            }
        )
    }

    var body: some View {
        actionIndicator
            .luminarePopover(
                isPresented: $isActionPickerPresented,
                arrowEdge: .top,
                attachmentAnchor: .topLeading,
                shouldHideAnchor: true,
                shouldAnimate: false
            ) {
                ActionPickerView(selection: pickerSelection, owner: owner)
                    .frame(width: 300, height: 300)
            }
            .onChange(of: isActionPickerPresented) { _ in
                if !isActionPickerPresented {
                    PickerListEventMonitorManager.shared.removeAllMonitors()
                }
            }
    }

    private var actionIndicator: some View {
        let action = target.resolvedAction(with: linkResolver)

        return HStack(spacing: 2) {
            Button {
                isActionPickerPresented.toggle()
            } label: {
                BindingActionLabel(action: action, link: target.link)
                    // Keeps a truncated name against the leading edge
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .luminareContentSize(contentMode: .fit, hasFixedHeight: true, isCompressible: true)
            .luminareRoundingBehavior(top: true, bottom: true)
            .luminareFilledStates([.hovering, .pressed])
            .luminareBorderedStates(.hovering)
            .luminareMinHeight(24)
            .help(help)
            .padding(.leading, -4)

            HStack(spacing: 4) {
                if let info = action?.direction.infoText {
                    LuminareToolTip(systemImage: "info.circle.fill", text: info)
                        .transition(.opacity)
                }

                if let link = target.link {
                    BindingLinkBadge(kind: link.kind) { target.unlink(with: linkResolver) }
                        .transition(.opacity)
                }

                Group {
                    if let action, action.direction.isCustomizable {
                        Button {
                            isConfiguringCustom = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(.luminareIcon(isActive: isConfiguringCustom))
                        .luminareModal(isPresented: $isConfiguringCustom) {
                            if action.direction == .custom {
                                CustomActionConfigurationView(action: editableAction, isPresented: $isConfiguringCustom)
                                    .frame(width: 400)
                            } else {
                                StashActionConfigurationView(action: editableAction, isPresented: $isConfiguringCustom)
                                    .frame(width: 400)
                            }
                        }
                        .luminareModalCornerRadius(24)
                        .help("Customize this action’s custom frame.")
                        .transition(.opacity)
                    }

                    if action?.direction == .cycle {
                        Button {
                            isConfiguringCycle = true
                        } label: {
                            Image(systemName: "repeat")
                        }
                        .buttonStyle(.luminareIcon(isActive: isConfiguringCycle))
                        .luminareModal(isPresented: $isConfiguringCycle) {
                            CycleActionConfigurationView(action: editableAction, isPresented: $isConfiguringCycle)
                                .frame(width: 400)
                        }
                        .luminareModalCornerRadius(24)
                        .help("Customize what this action cycles through.")
                        .transition(.opacity)
                    }
                }
                .font(.title3)
            }
        }
        .animation(animationFast, value: action?.direction)
        .animation(animationFast, value: target.link)
    }
}

/// An action's icon and name, or what a broken link is missing
struct BindingActionLabel: View {
    let action: WindowAction?
    let link: BindingLink?

    var body: some View {
        HStack(spacing: 8) {
            if let action {
                IconView(action: action)

                Text(action.getName())
                    .fontWeight(.regular)
                    .lineLimit(1)
            } else {
                Image(systemName: "bolt.horizontal.fill")
                    .foregroundStyle(.secondary)

                Text(missingLinkTitle)
                    .fontWeight(.regular)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var missingLinkTitle: String {
        switch link?.kind {
        case .keybind, nil: String(localized: "Linked keybind not found")
        case .gesture: String(localized: "Linked gesture not found", comment: "Shown for an action that links to a gesture that was removed")
        case .radialMenu: String(localized: "Linked radial menu action not found", comment: "Shown for an action that links to a radial menu action that was removed")
        }
    }
}

/// The only way to unlink, as picking an action changes the linked binding
struct BindingLinkBadge: View {
    let kind: LoopBindingKind
    let unlink: () -> ()

    var body: some View {
        LuminareToolTip(systemImage: "link", arrowEdge: .top, trigger: .click) {
            LuminareToolTipPrompt(Text(help), buttonTitle: unlinkTitle, action: unlink)
        }
        .accessibilityAction(named: unlinkTitle, unlink)
    }

    private var unlinkTitle: Text {
        Text("Unlink", comment: "Button in the popover of a keybind, gesture or radial menu action that links to another, which unlinks it and keeps its action as its own")
    }

    private var help: String {
        switch kind {
        case .keybind:
            String(localized: "Linked to a keybind. Changing this action also changes the keybind.", comment: "A tooltip on a gesture or radial menu action that links to a keybind, explaining that changes to its action also change the keybind.")
        case .gesture:
            String(localized: "Linked to a gesture. Changing this action also changes the gesture.", comment: "A tooltip on a keybind, gesture or radial menu action that links to a gesture, explaining that changes to its action also change the gesture.")
        case .radialMenu:
            String(localized: "Linked to a radial menu action. Changing this action also changes the radial menu action.", comment: "A tooltip on a keybind, gesture or radial menu action that links to a radial menu action, explaining that changes to its action also change the radial menu action.")
        }
    }
}

// MARK: - Resolver

/// The bindings in settings, redrawing the view when they change
@MainActor
@propertyWrapper
struct BindingLinks: DynamicProperty {
    @Default(.keybinds) private var keybinds
    @Default(.gestures) private var gestures
    @Default(.radialMenuActions) private var radialMenuActions
    @Default(.enableRadialMenuCustomization) private var enableRadialMenuCustomization

    init() {}

    var wrappedValue: BindingLinkResolver {
        BindingLinkResolver(
            keybinds: keybinds,
            gestures: gestures,
            radialMenuActions: enableRadialMenuCustomization ? radialMenuActions : RadialMenuBinding.defaults
        )
    }
}
