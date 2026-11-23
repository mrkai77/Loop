//
//  BindingStore.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-23.
//

import Defaults
import Foundation

/// Saves bindings to settings, including edits made through a link and the config IDs links find them by
@MainActor
enum BindingStore {
    private enum Change {
        case target(BindingTarget)
        case configID(String)
    }

    // MARK: - Editing

    /// Saves an action edited through `link` to the binding at the end of its links
    @discardableResult
    static func save(_ action: WindowAction, through link: BindingLink) -> Bool {
        guard let terminal = BindingLinkResolver.current.terminal(of: link)?.identity else {
            return false
        }

        return update(terminal, .target(.action(action)))
    }

    /// Changes the binding at the end of `link` to run `direction`, as picking an action does.
    /// Returns `false` when there's nothing to change, such as when the link leads nowhere.
    @discardableResult
    static func save(_ direction: WindowDirection, through link: BindingLink) -> Bool {
        guard var action = BindingLinkResolver.current.editableAction(for: link) else {
            return false
        }

        action.pick(direction)
        return save(action, through: link)
    }

    static func link(to identity: BindingIdentity) -> BindingLink {
        BindingLink(identity.kind, id: configID(for: identity))
    }

    // MARK: - Config IDs

    /// The binding's config ID, saving the id the CLI shows for it the first time a link or the CLI refers to it
    @discardableResult
    static func configID(for identity: BindingIdentity) -> String {
        let resolver = BindingLinkResolver.current
        if let configID = resolver.configID(of: identity) {
            return configID
        }

        // A binding that's no longer there keeps its UUID, so a link to it still reads as removed
        guard let derived = derivedID(of: identity, in: resolver) else {
            return identity.id.uuidString
        }

        update(identity, .configID(derived))
        return derived
    }

    /// Saves `id`, which the CLI found the binding by, unless it already has a config ID
    static func keep(_ id: String, for identity: BindingIdentity) {
        if BindingLinkResolver.current.configID(of: identity) == nil {
            update(identity, .configID(id))
        }
    }

    private static func derivedID(of identity: BindingIdentity, in resolver: BindingLinkResolver) -> String? {
        switch identity.kind {
        case .keybind: derivedID(of: identity.id, in: resolver.keybinds)
        case .gesture: derivedID(of: identity.id, in: LoopAutomationIdentity.runnableGestures(resolver.gestures))
        case .radialMenu: derivedID(of: identity.id, in: resolver.radialMenuActions)
        }
    }

    private static func derivedID(of id: UUID, in bindings: [some ActionBinding]) -> String? {
        zip(bindings, LoopAutomationIdentity.ids(for: bindings)).first { $0.0.id == id }?.1
    }

    // MARK: - Saving

    /// Only bindings in settings are changed. The default radial menu, shown until it's customized, isn't saved.
    @discardableResult
    private static func update(_ identity: BindingIdentity, _ change: Change) -> Bool {
        switch identity.kind {
        case .keybind: update(.keybinds, id: identity.id, change)
        case .gesture: update(.gestures, id: identity.id, change)
        case .radialMenu: update(.radialMenuActions, id: identity.id, change)
        }
    }

    private static func update(
        _ key: Defaults.Key<[some ActionBinding & Defaults.Serializable]>,
        id: UUID,
        _ change: Change
    ) -> Bool {
        guard let index = Defaults[key].firstIndex(where: { $0.id == id }) else {
            return false
        }

        switch change {
        case let .target(target):
            return Defaults[key][index].setTarget(target)
        case let .configID(configID):
            Defaults[key][index].configID = configID
            return true
        }
    }
}

// MARK: - Targets

@MainActor
extension BindingTarget {
    mutating func saveEdited(_ action: WindowAction) {
        if let link {
            BindingStore.save(action, through: link)
        } else {
            self = .action(action)
        }
    }
}
