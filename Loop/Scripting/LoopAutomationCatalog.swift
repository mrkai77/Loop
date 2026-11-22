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
    private let usesDefaultRadialMenu: Bool

    init(
        keybinds: [WindowAction] = Defaults[.keybinds],
        radialMenuActions: [RadialMenuAction]? = nil,
        gestures: [GestureBinding] = Defaults[.gestures]
    ) {
        self.keybinds = keybinds
        self.usesDefaultRadialMenu = radialMenuActions == nil && !Defaults[.enableRadialMenuCustomization]
        self.radialMenuActions = radialMenuActions ?? RadialMenuAction.userConfiguredActions
        self.gestures = gestures
    }

    // MARK: - Built-in Actions

    /// The Keybinds tab's action picker, minus actions that have to be configured first.
    /// The picker only offers as many desktops as there are right now, while this lists them all.
    static func builtInActions() -> [(direction: WindowDirection, category: String)] {
        var sections = PickerSection.windowDirections.filter { section in
            !section.items.contains(where: \.willChangeSpace)
        }
        let spaceSwitching = PickerSection(
            String(localized: "Space Switching", comment: "Section header in the action picker of the Keybinds tab"),
            WindowDirection.spaceSwitching
        )
        let afterScreenSwitching = sections.firstIndex { $0.items.contains(.nextScreen) }.map { $0 + 1 } ?? sections.endIndex
        sections.insert(spaceSwitching, at: afterScreenSwitching)

        return sections.flatMap { section in
            section.items
                .filter(\.isRunnableOnItsOwn)
                .map { ($0, section.title) }
        }
    }

    /// Accepts the listed key, the older spellings URLs used, and any case: `left-half`, `lefthalf` or `LeftHalf`
    static func builtInAction(named name: String) -> WindowDirection? {
        WindowDirection.matching(name).flatMap { $0.isRunnableOnItsOwn ? $0 : nil }
    }

    static func boundAction(_ action: WindowAction) -> LoopBoundAction {
        LoopBoundAction(key: action.direction.automationKey, name: action.getName())
    }

    // MARK: - Bindings

    var keyBindings: [Binding] {
        let ids = LoopAutomationIdentity.uniqueIDs(for: keybinds.map(Self.idStem))
        return zip(keybinds, ids).map { action, id in
            Binding(
                kind: .keybind,
                id: id,
                action: action,
                linkedTarget: nil,
                trigger: action.keybind.isEmpty ? nil : Self.keybindDescription(action),
                isActive: !action.keybind.isEmpty,
                note: action.keybind.isEmpty ? "No keys" : nil
            )
        }
    }

    var radialMenuBindings: [Binding] {
        let stems = usesDefaultRadialMenu
            ? RadialMenuAction.defaultAutomationIDs
            : radialMenuActions.map { Self.idStem($0.type) }
        let ids = LoopAutomationIdentity.uniqueIDs(for: stems)

        return zip(radialMenuActions.indices, ids).map { index, id in
            let action = radialMenuActions[index]
            let isCenter = index == radialMenuActions.count - 1
            return Binding(
                kind: .radialMenu,
                id: id,
                action: resolvedAction(action.type),
                linkedTarget: linkedTarget(action.type),
                trigger: isCenter ? "Center" : "Slot \(index + 1)",
                isActive: true,
                note: missingLinkNote(action.type)
            )
        }
    }

    var gestureBindings: [Binding] {
        let activeIDs = Set(GestureBinding.activeGestures(in: gestures).map(\.id))
        let runnable = gestures.filter { $0.actionType != nil }
        let ids = LoopAutomationIdentity.uniqueIDs(for: runnable.compactMap { $0.actionType.map(Self.idStem) })
        let idsByGesture = Dictionary(uniqueKeysWithValues: zip(runnable.map(\.id), ids))

        return gestures.map { gesture in
            let isActive = activeIDs.contains(gesture.id)
            let note: String? = if gesture.actionType == nil {
                "Can’t be run"
            } else if let missingLink = gesture.actionType.flatMap(missingLinkNote) {
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
                id: idsByGesture[gesture.id],
                action: gesture.actionType.flatMap(resolvedAction),
                linkedTarget: gesture.actionType.flatMap(linkedTarget),
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
        if [.custom, .stash, .cycle].contains(action.direction), let name = action.name {
            let stem = LoopAutomationIdentity.kebabCase(name)
            if !stem.isEmpty {
                return stem
            }
        }

        return action.direction.automationKey
    }

    static func idStem(_ type: RadialMenuAction.ActionType) -> String {
        switch type {
        case let .custom(action): idStem(action)
        case .keybindReference: "link"
        }
    }

    private func resolvedAction(_ type: RadialMenuAction.ActionType) -> WindowAction? {
        switch type {
        case let .custom(action):
            action
        case let .keybindReference(id):
            keybinds.first { $0.id == id }
        }
    }

    /// Settings keep a link after its keybind is deleted, and it then runs nothing
    private func missingLinkNote(_ type: RadialMenuAction.ActionType) -> String? {
        guard case let .keybindReference(id) = type, !keybinds.contains(where: { $0.id == id }) else {
            return nil
        }

        return "Links to a keybind that was removed"
    }

    private func linkedTarget(_ type: RadialMenuAction.ActionType) -> LoopTarget? {
        guard case let .keybindReference(id) = type,
              let index = keybinds.firstIndex(where: { $0.id == id })
        else {
            return nil
        }

        return keyBindings[index].target
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

    private static func keyName(_ key: CGKeyCode) -> String {
        let names: [CGKeyCode: String] = [
            .kVK_Return: "↩",
            .kVK_Tab: "⇥",
            .kVK_Space: "Space",
            .kVK_Delete: "⌫",
            .kVK_ForwardDelete: "⌦",
            .kVK_Escape: "⎋",
            .kVK_LeftArrow: "←",
            .kVK_RightArrow: "→",
            .kVK_UpArrow: "↑",
            .kVK_DownArrow: "↓",
            .kVK_Home: "↖",
            .kVK_End: "↘",
            .kVK_PageUp: "⇞",
            .kVK_PageDown: "⇟"
        ]

        if let name = names[key] {
            return name
        }

        if let name = key.humanReadable?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name.uppercased()
        }

        return "Key \(key)"
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
        ![.noAction, .noSelection, .custom, .stash, .cycle].contains(self)
    }
}

// MARK: - Radial Menu Defaults

extension RadialMenuAction {
    /// Fixed so they don't change with the language, as the default cycles' names are localized.
    /// One per entry in `defaultRadialMenuActions`.
    static let defaultAutomationIDs = [
        "top-cycle",
        "top-right-quarter",
        "right-cycle",
        "bottom-right-quarter",
        "bottom-cycle",
        "bottom-left-quarter",
        "left-cycle",
        "top-left-quarter",
        "maximize-macos-center"
    ]
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
