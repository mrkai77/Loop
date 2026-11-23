//
//  KeybindItemView.swift
//  Loop
//
//  Created by Kai Azim on 2024-05-03.
//

import Defaults
import Luminare
import SwiftUI

struct KeybindItemView: View {
    @Default(.triggerKey) private var triggerKey
    @Default(.keybinds) private var keybinds
    @Default(.gestures) private var gestures
    @Default(.radialMenuActions) private var radialMenuActions

    @State private var action: WindowAction
    @Binding private var externalAction: WindowAction
    private let cycleIndex: Int?

    @State private var isActionPickerPresented = false
    @State private var isConfiguringCustom = false
    @State private var isConfiguringCycle = false

    init(_ action: Binding<WindowAction>, cycleIndex: Int? = nil) {
        self.action = action.wrappedValue
        self._externalAction = action
        self.cycleIndex = cycleIndex
    }

    private var hasDuplicateKeybinds: Bool {
        let others = keybinds.filter { $0.id != action.id }
        return WindowAction.conflictingIDs(in: others + [action], triggerKey: triggerKey).contains(action.id)
    }

    private var linkResolver: BindingLinkResolver {
        BindingLinkResolver(keybinds: keybinds, gestures: gestures, radialMenuActions: radialMenuActions)
    }

    /// The action this runs. Editing a linked action edits the binding it comes from.
    private var editableAction: Binding<WindowAction> {
        guard let link = action.link else {
            return $action
        }

        return Binding(
            get: { linkResolver.action(for: link) ?? WindowAction(.noAction) },
            set: { BindingLinkResolver.save($0, through: link) }
        )
    }

    private var pickerSelection: Binding<ActionPickerView.Item> {
        Binding(
            get: { action.link.map(ActionPickerView.Item.link) ?? .direction(action.direction) },
            set: { item in
                switch item {
                case let .direction(direction):
                    // A linked keybind changes the binding it links to, and is unlinked with its link button
                    if let link = action.link, BindingLinkResolver.save(direction, through: link) {
                        // Leave it unchanged
                    } else {
                        action.link = nil
                        action.direction = direction
                    }
                    configure(direction)
                case let .link(link):
                    action.link = link
                    action.direction = .noAction
                }
            }
        )
    }

    /// Opens the editor for an action picked in this row, but not for changes made from another row through a link
    private func configure(_ direction: WindowDirection) {
        if direction.isCustomizable {
            isConfiguringCustom = true
        }
        if direction == .cycle {
            isConfiguringCycle = true
        }
    }

    private func unlink() {
        guard let link = action.link else {
            return
        }

        action = (linkResolver.action(for: link) ?? WindowAction(.noAction))
            .detached(id: action.id, keybind: action.keybind, bypassTriggerKey: action.bypassTriggerKey)
    }

    var body: some View {
        ZStack {
            actionSelection
                .frame(maxWidth: .infinity, alignment: .leading)

            keybindCombination
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .onChange(of: action) { externalAction = $0 }
        // An edit made through a link from another row changes this one's binding directly
        .onChange(of: externalAction) { if $0 != action { action = $0 } }
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
                Group {
                    if cycleIndex == nil {
                        ActionPickerView(selection: pickerSelection, owner: BindingLink(.keybind, id: action.id))
                    } else {
                        // Cycle steps are actions of their own, never links
                        DirectionPickerView(
                            direction: Binding(
                                get: { action.direction },
                                set: { action.direction = $0; configure($0) }
                            ),
                            isInCycle: true
                        )
                    }
                }
                .frame(width: 300, height: 300)
            }
            .onChange(of: isActionPickerPresented) { _ in
                if !isActionPickerPresented {
                    PickerListEventMonitorManager.shared.removeAllMonitors()
                }
            }
    }

    private var actionIndicator: some View {
        let action = editableAction.wrappedValue

        return HStack(spacing: 2) {
            Button {
                isActionPickerPresented.toggle()
            } label: {
                HStack(spacing: 8) {
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
                }
                .padding(.horizontal, 4)
            }
            .luminareContentSize(contentMode: .fit, hasFixedHeight: true)
            .luminareRoundingBehavior(top: true, bottom: true)
            .luminareFilledStates([.hovering, .pressed])
            .luminareBorderedStates(.hovering)
            .luminareMinHeight(24)
            .help("Customize this keybind’s action.")
            .padding(.leading, -4)

            Group {
                if action.direction.isCustomizable {
                    Button {
                        isConfiguringCustom = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .luminareModal(isPresented: $isConfiguringCustom) {
                        if action.direction == .custom {
                            CustomActionConfigurationView(
                                action: editableAction,
                                isPresented: $isConfiguringCustom
                            )
                            .frame(width: 400)
                        } else {
                            StashActionConfigurationView(
                                action: editableAction,
                                isPresented: $isConfiguringCustom
                            )
                            .frame(width: 400)
                        }
                    }
                    .luminareModalCornerRadius(24)
                    .help("Customize this action’s custom frame.")
                }

                if action.direction == .cycle {
                    Button {
                        isConfiguringCycle = true
                    } label: {
                        Image(systemName: "repeat")
                    }
                    .buttonStyle(.plain)
                    .luminareModal(isPresented: $isConfiguringCycle) {
                        CycleActionConfigurationView(
                            action: editableAction,
                            isPresented: $isConfiguringCycle
                        )
                        .frame(width: 400)
                    }
                    .luminareModalCornerRadius(24)
                    .help("Customize what this action cycles through.")
                }
            }
            .font(.title3)
            .foregroundStyle(.secondary)

            if let link = self.action.link {
                BindingLinkBadge(kind: link.kind, unlink: unlink)
                    .padding(.leading, 6)
            }
        }
    }

    private var keybindCombination: some View {
        HStack {
            if let cycleIndex {
                Text("\(cycleIndex)")
                    .frame(width: 27, height: 27)
                    .luminareSurface()
            } else {
                HStack(spacing: 6) {
                    keycorderSection()
                        .padding(.leading, 4)
                        .luminareToolTip(attachedTo: .topLeading, hidden: !hasDuplicateKeybinds) {
                            Text("Another keybind uses this key combination.")
                                .padding(6)
                        }
                        .luminareTint(overridingWith: .red)
                }
                .fixedSize()
            }
        }
        .luminareCornerRadius(8)
    }

    // MARK: - Helper Methods

    /// Switches to standard mode (keeps the keybind)
    private func restoreStandardMode() {
        action.keybind = action.keybind.subtracting(triggerKey)
        action.bypassTriggerKey = false
    }

    /// Merges trigger key into action key and switches to bypass mode
    private func switchToBypassMode() {
        action.keybind = triggerKey.union(action.keybind)
        action.bypassTriggerKey = true
    }

    /// Clears the keybind and switches to standard mode
    private func clearKeybind() {
        action.keybind = []
        action.bypassTriggerKey = false
    }

    private func keycorderSection() -> some View {
        HStack(spacing: 6) {
            if action.bypassTriggerKey != true {
                HStack(spacing: 6) {
                    ForEach(triggerKey.sorted().compactMap(\.modifierSystemImage), id: \.self) { image in
                        Text("\(Image(systemName: image))")
                    }
                }
                .font(.callout)
                .padding(6)
                .frame(height: 27)
                .luminareSurface()

                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
            }

            Keycorder($action)
                .opacity(hasDuplicateKeybinds || action.keybind.isEmpty ? 0.5 : 1)
        }
        .contextMenu {
            if action.bypassTriggerKey == true {
                Button("Link Trigger Key", action: restoreStandardMode)
            } else {
                Button("Unlink Trigger Key", action: switchToBypassMode)
            }

            Button("Clear Keybind", action: clearKeybind)
        }
    }
}
