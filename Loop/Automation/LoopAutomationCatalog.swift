//
//  LoopAutomationCatalog.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import CoreGraphics
import Defaults
import Foundation

/// Everything the CLI and URLs can list and run, with the ids they're addressed by
@MainActor
struct LoopAutomationCatalog {
    /// A keybind, gesture or radial menu action, and the action it runs
    struct Binding {
        let kind: LoopBindingKind
        /// `nil` when it can't be run, like a gesture that opens the radial menu
        let id: String?
        /// `nil` when it doesn't run an action, like a gesture that opens the radial menu
        let action: WindowAction?
        let linkedTarget: LoopTarget?
        let trigger: String?
        let isActive: Bool
        let note: String?

        var target: LoopTarget? {
            id.map { .binding(kind, id: $0) }
        }

        var summary: LoopBindingSummary {
            LoopBindingSummary(
                kind: kind,
                id: id,
                target: target?.description,
                action: action.map(LoopAutomationCatalog.boundAction),
                linkedTarget: linkedTarget?.description,
                trigger: trigger,
                isActive: isActive,
                note: note
            )
        }
    }

    let keybinds: [WindowAction]
    let radialMenuActions: [RadialMenuAction]
    let gestures: [GestureBinding]
    private let resolver: BindingLinkResolver
    private let conflictingKeybindIDs: Set<UUID>
    /// Worked out before the rows, as a row's link needs the id of a binding in another list
    private let keybindIDs: [String]
    private let radialMenuIDs: [String]
    private let gestureIDs: [UUID: String]

    init(
        keybinds: [WindowAction] = Defaults[.keybinds],
        radialMenuActions: [RadialMenuAction]? = nil,
        gestures: [GestureBinding] = Defaults[.gestures],
        triggerKey: Set<CGKeyCode> = Defaults[.triggerKey]
    ) {
        let radialMenuActions = radialMenuActions ?? RadialMenuAction.userConfiguredActions
        self.keybinds = keybinds
        self.radialMenuActions = radialMenuActions
        self.gestures = gestures
        self.resolver = BindingLinkResolver(keybinds: keybinds, gestures: gestures, radialMenuActions: radialMenuActions)
        self.conflictingKeybindIDs = WindowAction.conflictingIDs(in: keybinds, triggerKey: triggerKey)

        self.keybindIDs = LoopAutomationIdentity.uniqueIDs(for: keybinds.map(Self.idStem))
        self.radialMenuIDs = LoopAutomationIdentity.uniqueIDs(for: radialMenuActions.map { Self.idStem($0.type) })

        let runnableGestures = gestures.filter { $0.actionType != nil }
        let gestureIDs = LoopAutomationIdentity.uniqueIDs(for: runnableGestures.compactMap { $0.actionType.map(Self.idStem) })
        self.gestureIDs = Dictionary(uniqueKeysWithValues: zip(runnableGestures.map(\.id), gestureIDs))
    }

    // MARK: - Built-in Actions

    /// The Keybinds tab's action picker with every desktop, minus actions that have to be configured first
    static func builtInActions() -> [(direction: WindowDirection, category: String)] {
        PickerSection.windowDirections(allDesktops: true).flatMap { section in
            section.items
                .filter(\.isRunnableOnItsOwn)
                .map { ($0, section.title) }
        }
    }

    /// Accepts the listed key, the older spellings URLs used, and any case: `left-half`, `lefthalf` or `LeftHalf`
    static func builtInAction(named name: String) -> WindowDirection? {
        WindowDirection.matching(name).flatMap { $0.isRunnableOnItsOwn ? $0 : nil }
    }

    nonisolated static func boundAction(_ action: WindowAction) -> LoopBoundAction {
        LoopBoundAction(key: action.direction.automationKey, name: action.getName())
    }

    // MARK: - Bindings

    var keyBindings: [Binding] {
        zip(keybinds, keybindIDs).map { action, id in
            let hasConflict = conflictingKeybindIDs.contains(action.id)
            let note: String? = if let missingLink = missingLinkNote(action.link) {
                missingLink
            } else if action.keybind.isEmpty {
                "No keys"
            } else if hasConflict {
                "Conflicts with another keybind"
            } else {
                nil
            }

            return Binding(
                kind: .keybind,
                id: id,
                action: action.link.map(resolver.action) ?? action,
                linkedTarget: linkedTarget(action.link),
                trigger: action.keybind.isEmpty ? nil : Self.keybindDescription(action),
                isActive: !action.keybind.isEmpty && !hasConflict,
                note: note
            )
        }
    }

    var radialMenuBindings: [Binding] {
        zip(radialMenuActions.indices, radialMenuIDs).map { index, id in
            let action = radialMenuActions[index]
            let isCenter = index == radialMenuActions.count - 1
            return Binding(
                kind: .radialMenu,
                id: id,
                action: action.type.resolvedAction(with: resolver),
                linkedTarget: linkedTarget(action.type.link),
                trigger: isCenter ? "Center" : "Slot \(index + 1)",
                isActive: true,
                note: missingLinkNote(action.type.link)
            )
        }
    }

    var gestureBindings: [Binding] {
        let activeIDs = Set(GestureBinding.activeGestures(in: gestures).map(\.id))

        return gestures.map { gesture in
            let isActive = activeIDs.contains(gesture.id)
            let note: String? = if gesture.actionType == nil {
                "Can’t be run"
            } else if let missingLink = missingLinkNote(gesture.actionType?.link) {
                missingLink
            } else if gesture.kind == nil {
                "No gesture"
            } else if !isActive {
                "Conflicts with another gesture"
            } else {
                nil
            }

            return Binding(
                kind: .gesture,
                id: gestureIDs[gesture.id],
                action: gesture.actionType?.resolvedAction(with: resolver),
                linkedTarget: linkedTarget(gesture.actionType?.link),
                trigger: Self.gestureDescription(gesture),
                isActive: isActive,
                note: note
            )
        }
    }

    func bindings(of kind: LoopBindingKind) -> [Binding] {
        switch kind {
        case .keybind: keyBindings
        case .gesture: gestureBindings
        case .radialMenu: radialMenuBindings
        }
    }

    // MARK: - Ids

    /// Like the settings file: a custom, stash or cycle action's name, else its action's key. Links are `link`.
    static func idStem(_ action: WindowAction) -> String {
        if action.link != nil {
            return "link"
        }

        if [.custom, .stash, .cycle].contains(action.direction), let name = action.name {
            let stem = LoopAutomationIdentity.kebabCase(name)
            if !stem.isEmpty {
                return stem
            }
        }

        return action.direction.automationKey
    }

    static func idStem(_ type: RadialMenuAction.ActionType) -> String {
        type.customAction.map(idStem) ?? "link"
    }

    /// Settings keep a link after the binding it links to is deleted or stops running an action, and it then runs nothing
    private func missingLinkNote(_ link: BindingLink?) -> String? {
        guard let link, resolver.action(for: link) == nil else {
            return nil
        }

        if resolver.canBeLinked(link) {
            return "Links to something that doesn’t run an action"
        }

        if link.kind == .gesture, gestures.contains(where: { $0.id == link.id }) {
            return "Links to a gesture that opens the radial menu"
        }

        return switch link.kind {
        case .keybind: "Links to a keybind that was removed"
        case .gesture: "Links to a gesture that was removed"
        case .radialMenu: "Links to a radial menu action that was removed"
        }
    }

    private func linkedTarget(_ link: BindingLink?) -> LoopTarget? {
        guard let link else {
            return nil
        }

        let id: String? = switch link.kind {
        case .keybind:
            keybinds.firstIndex { $0.id == link.id }.map { keybindIDs[$0] }
        case .gesture:
            gestureIDs[link.id]
        case .radialMenu:
            radialMenuActions.firstIndex { $0.id == link.id }.map { radialMenuIDs[$0] }
        }

        return id.map { .binding(link.kind.loopBindingKind, id: $0) }
    }

    // MARK: - Triggers

    private static func gestureDescription(_ gesture: GestureBinding) -> String? {
        guard let name = gesture.displayName else {
            return nil
        }

        return "\(name), \(gesture.effectiveActivationZone.displayName)"
    }

    /// Modifiers first, in the order macOS menus use, such as "Trigger + ⌃⇧A"
    private static func keybindDescription(_ action: WindowAction) -> String {
        let keys = action.keybind
        let modifierOrder: [(CGKeyCode, String)] = [
            (.kVK_Function, "fn"),
            (.kVK_Control, "⌃"),
            (.kVK_Option, "⌥"),
            (.kVK_Shift, "⇧"),
            (.kVK_Command, "⌘")
        ]

        let baseModifiers = Set(keys.filter(\.isModifier).map(\.baseModifier))
        let modifiers = modifierOrder
            .filter { baseModifiers.contains($0.0) }
            .map(\.1)
            .joined()

        let others = keys
            .filter { !$0.isModifier }
            .sorted()
            .map(keyName)
            .joined(separator: " ")

        let combination = modifiers + others
        return action.bypassTriggerKey == true ? combination : "Trigger + \(combination)"
    }

    /// The same names and symbols the Keybinds tab shows, such as "↩" and "␣"
    private static func keyName(_ key: CGKeyCode) -> String {
        guard let name = key.humanReadable?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "Key \(key)"
        }

        return name.uppercased()
    }
}

// MARK: - Window Directions

extension WindowDirection {
    /// The kebab-case key the CLI and URLs use, which is also what Loop's settings file will use
    var automationKey: String {
        self == .noAction ? "none" : LoopAutomationIdentity.kebabCase(rawValue)
    }

    /// Ignores case and hyphens, so `left-half`, `lefthalf` and `LeftHalf` all match
    static func matching(_ name: String) -> WindowDirection? {
        let compact = name.lowercased().replacingOccurrences(of: "-", with: "")
        if compact == "noaction" {
            return .noAction
        }

        return allCases.first { $0.automationKey.replacingOccurrences(of: "-", with: "") == compact }
    }

    /// Built-in actions that do something without being configured first
    var isRunnableOnItsOwn: Bool {
        !isNoOp && !isCustomizable && self != .cycle
    }
}

// MARK: - Gestures

extension GestureBinding {
    /// `nil` for a gesture that opens the radial menu
    var actionType: RadialMenuAction.ActionType? {
        switch action {
        case .radialMenuActions: nil
        case let .singleAction(type): type
        }
    }
}

extension BindingLink.Kind {
    var loopBindingKind: LoopBindingKind {
        switch self {
        case .keybind: .keybind
        case .gesture: .gesture
        case .radialMenu: .radialMenu
        }
    }
}
