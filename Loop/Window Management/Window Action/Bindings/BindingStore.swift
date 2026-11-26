//
//  BindingStore.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-23.
//

import Defaults
import Foundation

/// Saves bindings to settings, including edits through links and the config IDs links find them by
@MainActor
enum BindingStore {
    private enum Change {
        case target(BindingTarget)
        case configID(String)
    }

    // MARK: - Editing

    /// Saves an action edited through `link` to the binding it links to
    @discardableResult
    static func save(_ action: WindowAction, through link: BindingLink) -> Bool {
        guard let linked = BindingLinkResolver.current.linked(by: link)?.identity else {
            return false
        }

        return update(linked, .target(.action(action)))
    }

    /// Changes the linked binding to run `direction`, as picking an action does.
    /// `false` when the link leads nowhere
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

    /// Points the links to `identity` at what it now links to, as links don't chain
    static func relink(linksTo identity: BindingIdentity, to link: BindingLink) {
        let resolver = BindingLinkResolver.current
        relink(.keybinds, linksTo: identity, to: link, with: resolver)
        relink(.gestures, linksTo: identity, to: link, with: resolver)
        relink(.radialMenuActions, linksTo: identity, to: link, with: resolver)
    }

    // MARK: - Config IDs

    /// The binding's config ID, saving the id the CLI shows the first time a link or the CLI refers to it
    @discardableResult
    static func configID(for identity: BindingIdentity) -> String {
        let resolver = BindingLinkResolver.current
        if let configID = resolver.configID(of: identity) {
            return configID
        }

        // A removed binding keeps its UUID, so a link to it still reads as removed
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

    /// Only changes bindings in settings, so not the built-in radial menu
    @discardableResult
    private static func update(_ identity: BindingIdentity, _ change: Change) -> Bool {
        switch identity.kind {
        case .keybind: update(.keybinds, id: identity.id, change)
        case .gesture: update(.gestures, id: identity.id, change)
        case .radialMenu: update(.radialMenuActions, id: identity.id, change)
        }
    }

    private static func relink(
        _ key: Defaults.Key<[some ActionBinding & Defaults.Serializable]>,
        linksTo identity: BindingIdentity,
        to link: BindingLink,
        with resolver: BindingLinkResolver
    ) {
        var bindings = Defaults[key]
        for index in bindings.indices {
            if let target = bindings[index].bindingTarget?.relinking(identity, to: link, with: resolver) {
                _ = bindings[index].setTarget(target)
            }
        }

        if bindings != Defaults[key] {
            Defaults[key] = bindings
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
