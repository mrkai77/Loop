//
//  BindingLink.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import Defaults
import Foundation

/// A link from one keybind, gesture or radial menu action to another.
/// It runs whatever the other binding runs, and editing the action through the link edits that binding.
struct BindingLink: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case keybind
        case gesture
        case radialMenu
    }

    var kind: Kind
    var id: UUID

    init(_ kind: Kind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// Follows links between keybinds, gestures and radial menu actions to the action they run
struct BindingLinkResolver {
    let keybinds: [WindowAction]
    let gestures: [GestureBinding]
    let radialMenuActions: [RadialMenuAction]

    /// Radial menu links resolve against the saved radial menu, even while customization is off,
    /// as Loop saves it before linking to one of its actions
    init(
        keybinds: [WindowAction] = Defaults[.keybinds],
        gestures: [GestureBinding] = Defaults[.gestures],
        radialMenuActions: [RadialMenuAction] = Defaults[.radialMenuActions]
    ) {
        self.keybinds = keybinds
        self.gestures = gestures
        self.radialMenuActions = radialMenuActions
    }

    /// `nil` when the binding was removed, opens the radial menu, or its links loop back on themselves
    func action(for link: BindingLink) -> WindowAction? {
        terminal(of: link)?.action
    }

    /// The binding at the end of the links, which holds the action, so edits made through a link change it
    func terminal(of link: BindingLink) -> (link: BindingLink, action: WindowAction)? {
        var visited: Set<BindingLink> = []
        var current = link

        while visited.insert(current).inserted {
            switch target(of: current) {
            case let .action(action)?:
                return (current, action)
            case let .link(next)?:
                current = next
            case nil:
                return nil
            }
        }

        return nil
    }

    /// Whether linking `owner` to `target` would make links that never reach an action, such as a binding linking to itself
    func wouldLoop(linking owner: BindingLink, to target: BindingLink) -> Bool {
        var visited: Set<BindingLink> = []
        var current: BindingLink? = target

        while let link = current, visited.insert(link).inserted {
            if link == owner {
                return true
            }

            if case let .link(next)? = self.target(of: link) {
                current = next
            } else {
                current = nil
            }
        }

        return current != nil
    }

    /// Whether `link` points at a binding that runs an action. Gestures that open the radial menu don't.
    func canBeLinked(_ link: BindingLink) -> Bool {
        target(of: link) != nil
    }

    private enum Target {
        case action(WindowAction)
        case link(BindingLink)
    }

    private func target(of link: BindingLink) -> Target? {
        switch link.kind {
        case .keybind:
            guard let keybind = keybinds.first(where: { $0.id == link.id }) else {
                return nil
            }
            return keybind.link.map(Target.link) ?? .action(keybind)
        case .gesture:
            guard let gesture = gestures.first(where: { $0.id == link.id }),
                  case let .singleAction(type) = gesture.action
            else {
                return nil
            }
            return target(of: type)
        case .radialMenu:
            return radialMenuActions.first { $0.id == link.id }.map { target(of: $0.type) }
        }
    }

    private func target(of type: RadialMenuAction.ActionType) -> Target {
        type.link.map(Target.link) ?? .action(type.customAction ?? WindowAction(.noAction))
    }
}

// MARK: - Editing

extension BindingLinkResolver {
    /// Saves an action edited through `link` to the binding at the end of its links
    static func save(_ action: WindowAction, through link: BindingLink) {
        guard let terminal = BindingLinkResolver().terminal(of: link)?.link else {
            return
        }

        switch terminal.kind {
        case .keybind:
            if let index = Defaults[.keybinds].firstIndex(where: { $0.id == terminal.id }) {
                Defaults[.keybinds][index] = action
            }
        case .gesture:
            if let index = Defaults[.gestures].firstIndex(where: { $0.id == terminal.id }) {
                Defaults[.gestures][index].action = .singleAction(.custom(action))
            }
        case .radialMenu:
            if let index = Defaults[.radialMenuActions].firstIndex(where: { $0.id == terminal.id }) {
                Defaults[.radialMenuActions][index].type = .custom(action)
            }
        }
    }

    /// Changes the binding at the end of `link`'s links to run `direction`, keeping the rest of its action, as picking an action for a keybind does.
    /// Returns `false` when the link leads nowhere, so there's nothing to change.
    @discardableResult
    static func save(_ direction: WindowDirection, through link: BindingLink) -> Bool {
        guard var action = BindingLinkResolver().action(for: link) else {
            return false
        }

        action.direction = direction
        save(action, through: link)
        return true
    }
}

// MARK: - Keybinds

extension WindowAction {
    /// What a keybind runs: its own action, or the action it links to with the keybind's own keys, so reverse cycling still follows them
    func resolvingLink(with resolver: BindingLinkResolver) -> WindowAction {
        guard let link else {
            return self
        }

        var resolved = resolver.action(for: link) ?? WindowAction(.noAction)
        resolved.keybind = keybind
        resolved.bypassTriggerKey = bypassTriggerKey
        return resolved
    }
}
