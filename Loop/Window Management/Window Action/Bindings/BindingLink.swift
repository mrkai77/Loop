//
//  BindingLink.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import CoreGraphics
import Defaults
import Foundation

/// A link from one keybind, gesture or radial menu action to another.
/// It runs whatever the other binding runs, and editing the action through the link edits that binding.
struct BindingLink: Hashable {
    var kind: LoopBindingKind
    /// The linked binding's config ID, or its UUID for links made before config IDs
    var id: String

    init(_ kind: LoopBindingKind, id: String) {
        self.kind = kind
        self.id = id
    }
}

/// Written as the CLI spells it, like `gesture:swipe-up`
extension BindingLink: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard case let .binding(kind, id)? = LoopTarget(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a link to a binding: \(string)")
        }

        self.init(kind, id: id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(LoopTarget.binding(kind, id: id).description)
    }
}

/// Which binding something is, however a link refers to it
struct BindingIdentity: Hashable {
    let kind: LoopBindingKind
    let id: UUID

    init(_ kind: LoopBindingKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

/// What a binding runs: an action of its own, or the action of another binding it links to
enum BindingTarget: Hashable {
    case action(WindowAction)
    case link(BindingLink)

    var action: WindowAction? {
        if case let .action(action) = self { action } else { nil }
    }

    var link: BindingLink? {
        if case let .link(link) = self { link } else { nil }
    }

    /// The action it runs, following its link and the links in its cycle
    func resolvedAction(with resolver: BindingLinkResolver) -> WindowAction? {
        switch self {
        case let .action(action): resolver.resolvingCycle(of: action)
        case let .link(link): resolver.resolvedAction(for: link)
        }
    }

    func sharingID(_ id: UUID) -> BindingTarget {
        if case let .action(action) = self, action.id != id {
            return .action(action.withID(id))
        }
        return self
    }

    /// The action to edit, which is the one at the end of its link, with the links in its cycle kept
    func editableAction(with resolver: BindingLinkResolver) -> WindowAction? {
        switch self {
        case let .action(action): action
        case let .link(link): resolver.editableAction(for: link)
        }
    }
    /// Keeps running what the link ran, as an action of its own
    mutating func unlink(with resolver: BindingLinkResolver) {
        guard let link else {
            return
        }

        self = .action((resolver.editableAction(for: link) ?? WindowAction(.noAction)).detached())
    }
}

// MARK: - Bindings

protocol ActionBinding: Identifiable, Hashable where ID == UUID {
    static var bindingKind: LoopBindingKind { get }

    var id: UUID { get }
    /// How links and the CLI refer to the binding, so they keep finding it after it's renamed.
    /// `nil` until one of them does, which then sets it to the id the CLI shows for it.
    var configID: String? { get set }
    /// What it runs. `nil` for a gesture that opens the radial menu.
    var bindingTarget: BindingTarget? { get }

    /// Returns `false` when it can't run a target, like a gesture that opens the radial menu
    mutating func setTarget(_ target: BindingTarget) -> Bool
}

extension ActionBinding {
    var identity: BindingIdentity {
        BindingIdentity(Self.bindingKind, id: id)
    }

    /// The action it runs. A linked binding runs it under its own id, so its keys and cycle progress stay its own.
    func resolvedAction(with resolver: BindingLinkResolver) -> WindowAction? {
        switch bindingTarget {
        case let .link(link)?: resolver.resolvedAction(for: link)?.withID(id)
        case let target?: target.resolvedAction(with: resolver)
        case nil: nil
        }
    }

    /// Whether `action` came from this binding, or from one it links to
    func runs(_ action: WindowAction, with resolver: BindingLinkResolver) -> Bool {
        if resolvedAction(with: resolver)?.id == action.id {
            return true
        }

        return resolver.chain(from: bindingTarget?.link).contains { identity in
            identity.id == action.id || resolver.target(of: identity)?.action?.id == action.id
        }
    }

    func isLinked(by link: BindingLink) -> Bool {
        guard link.kind == Self.bindingKind else {
            return false
        }

        return link.id == configID || UUID(uuidString: link.id) == id
    }
}

// MARK: - Resolver

/// Follows links between keybinds, gestures and radial menu actions to the action they run
struct BindingLinkResolver {
    let keybinds: [Keybind]
    let gestures: [GestureBinding]
    let radialMenuActions: [RadialMenuBinding]

    /// The bindings in settings, with the radial menu Loop shows
    static var current: BindingLinkResolver {
        BindingLinkResolver(keybinds: Defaults[.keybinds], gestures: Defaults[.gestures], radialMenuActions: RadialMenuBinding.userConfigured)
    }

    func identity(of link: BindingLink) -> BindingIdentity? {
        bindings(of: link.kind).first { $0.isLinked(by: link) }?.identity
    }

    /// The action `link` runs, with the links in its cycle resolved.
    /// `nil` when the binding was removed, opens the radial menu, or its links loop back on themselves.
    func resolvedAction(for link: BindingLink) -> WindowAction? {
        editableAction(for: link).map(resolvingCycle)
    }

    func editableAction(for link: BindingLink) -> WindowAction? {
        terminal(of: link)?.action
    }

    /// `action` with each cycle step that links to another binding swapped for that binding's action, under the step's id
    /// so cycle progress follows the step. Steps that lead nowhere, or to a cycle, are left out, as cycles don't nest.
    func resolvingCycle(of action: WindowAction) -> WindowAction {
        guard let cycle = action.cycle, cycle.contains(where: { $0.target.link != nil }) else {
            return action
        }

        var resolved = action
        resolved.cycle = cycle.compactMap { step in
            guard let link = step.target.link else {
                return step
            }

            guard let linked = editableAction(for: link), linked.direction != .cycle else {
                return nil
            }

            return CycleStep(id: step.id, target: .action(linked))
        }
        return resolved
    }

    /// Whether a cycle step can link to a binding: one running a single action that doesn't repeat while held
    func canBeLinked(fromCycle identity: BindingIdentity) -> Bool {
        guard let target = target(of: identity), let action = target.editableAction(with: self) else {
            return false
        }

        return action.direction != .cycle && !action.allowsRapidRepeat
    }

    /// The binding at the end of the links, which holds the action, so edits made through a link change it
    func terminal(of link: BindingLink) -> (identity: BindingIdentity, action: WindowAction)? {
        guard let last = chain(from: link).last, case let .action(action)? = target(of: last) else {
            return nil
        }

        return (last, action)
    }

    /// Whether linking `owner` to `target` would make links that never reach an action, such as a binding linking to itself
    func wouldLoop(linking owner: BindingIdentity, to target: BindingIdentity) -> Bool {
        let chain = chain(from: target)
        let next = chain.last.flatMap { self.target(of: $0)?.link }.flatMap(identity(of:))
        return chain.contains(owner) || next != nil
    }

    /// The bindings a link leads through, in order, up to a binding that's missing or already in the chain
    func chain(from link: BindingLink?) -> [BindingIdentity] {
        link.flatMap(identity(of:)).map(chain(from:)) ?? []
    }

    private func chain(from identity: BindingIdentity) -> [BindingIdentity] {
        var chain = [identity]
        while let next = target(of: chain[chain.count - 1])?.link.flatMap(identity(of:)), !chain.contains(next) {
            chain.append(next)
        }
        return chain
    }

    func canBeLinked(_ identity: BindingIdentity) -> Bool {
        target(of: identity)?.resolvedAction(with: self) != nil
    }

    func target(of identity: BindingIdentity) -> BindingTarget? {
        bindings(of: identity.kind).first { $0.id == identity.id }?.bindingTarget
    }

    func configID(of identity: BindingIdentity) -> String? {
        bindings(of: identity.kind).first { $0.id == identity.id }?.configID
    }

    private func bindings(of kind: LoopBindingKind) -> [any ActionBinding] {
        switch kind {
        case .keybind: keybinds
        case .gesture: gestures
        case .radialMenu: radialMenuActions
        }
    }
}

// MARK: - Coding

/// Written as `RadialMenuAction.ActionType` was, so older versions of Loop still read radial menu actions and gestures.
/// Links to keybinds by UUID keep the case older versions run.
extension BindingTarget: Codable {
    private enum CodingKeys: String, CodingKey {
        case custom, keybindReference
    }

    private enum PayloadKeys: String, CodingKey {
        case value = "_0"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.keybindReference) {
            let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .keybindReference)
            self = try .link(BindingLink(.keybind, id: payload.decode(UUID.self, forKey: .value).uuidString))
            return
        }

        let payload = try container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .custom)
        self = try BindingTarget(inlineFrom: payload.superDecoder(forKey: .value))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .link(link) where link.kind == .keybind && UUID(uuidString: link.id) != nil:
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .keybindReference)
            try payload.encode(UUID(uuidString: link.id), forKey: .value)
        case .link, .action:
            var payload = container.nestedContainer(keyedBy: PayloadKeys.self, forKey: .custom)
            try encodeInline(to: payload.superEncoder(forKey: .value))
        }
    }
}

/// An action of its own, or a `noAction` action carrying the link, which older versions of Loop read as doing nothing.
/// Keybinds and cycle steps are written this way too.
extension BindingTarget {
    private enum InlineKeys: String, CodingKey {
        case link
    }

    init(inlineFrom decoder: Decoder) throws {
        if let link = try decoder.container(keyedBy: InlineKeys.self).decodeIfPresent(BindingLink.self, forKey: .link) {
            self = .link(link)
        } else {
            self = try .action(WindowAction(from: decoder))
        }
    }

    /// `id` is the binding's, given to the `noAction` action a link is written as
    func encodeInline(to encoder: Encoder, id: UUID = UUID(), keybind: Set<CGKeyCode> = []) throws {
        switch self {
        case let .action(action):
            try action.encode(to: encoder, keybind: keybind)
        case let .link(link):
            try WindowAction(.noAction).withID(id).encode(to: encoder, keybind: keybind)
            var container = encoder.container(keyedBy: InlineKeys.self)
            try container.encode(link, forKey: .link)
        }
    }
}
