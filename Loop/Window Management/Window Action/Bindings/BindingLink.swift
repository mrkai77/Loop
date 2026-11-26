//
//  BindingLink.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import CoreGraphics
import Defaults
import Foundation

/// A link from one keybind, gesture or radial menu action to another that holds an action, as links don't chain.
/// It runs that binding's action, and edits through the link change that binding
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

    /// The action it runs, with its link and cycle's links followed
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

    /// The action to edit, which is the linked one, with its cycle's links kept
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

    /// Its links to `identity`, including in its cycle, pointing at `link` instead. `nil` when it has none
    func relinking(_ identity: BindingIdentity, to link: BindingLink, with resolver: BindingLinkResolver) -> BindingTarget? {
        func linksToIdentity(_ target: BindingTarget) -> Bool {
            target.link.flatMap(resolver.identity(of:)) == identity
        }

        switch self {
        case .link:
            return linksToIdentity(self) ? .link(link) : nil
        case var .action(action):
            guard let cycle = action.cycle, cycle.contains(where: { linksToIdentity($0.target) }) else {
                return nil
            }

            action.cycle = cycle.map { linksToIdentity($0.target) ? CycleStep(id: $0.id, target: .link(link)) : $0 }
            return .action(action)
        }
    }
}

// MARK: - Bindings

protocol ActionBinding: Identifiable, Hashable where ID == UUID {
    static var bindingKind: LoopBindingKind { get }

    var id: UUID { get }
    /// How links and the CLI find the binding after it's renamed.
    /// `nil` until either refers to it, which sets it to the id the CLI shows
    var configID: String? { get set }
    /// What it runs. `nil` for a gesture that opens the radial menu
    var bindingTarget: BindingTarget? { get }

    /// Returns `false` when it can't run a target, like a gesture that opens the radial menu
    mutating func setTarget(_ target: BindingTarget) -> Bool
}

extension ActionBinding {
    var identity: BindingIdentity {
        BindingIdentity(Self.bindingKind, id: id)
    }

    /// The action it runs, under its own id when linked, so its keys and cycle progress stay its own
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

        guard let identity = bindingTarget?.link.flatMap(resolver.identity(of:)) else {
            return false
        }

        return identity.id == action.id || resolver.target(of: identity)?.action?.id == action.id
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

    /// The action `link` runs, with its cycle's links resolved.
    /// `nil` when the binding was removed, opens the radial menu, or is a link itself
    func resolvedAction(for link: BindingLink) -> WindowAction? {
        editableAction(for: link).map(resolvingCycle)
    }

    func editableAction(for link: BindingLink) -> WindowAction? {
        linked(by: link)?.action
    }

    /// `action` with linked cycle steps swapped for the linked action, under the step's id so cycle progress follows it.
    /// Steps that lead nowhere or to a cycle are left out, as cycles don't nest
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

    /// Cycle steps only link to a single action that doesn't repeat while held
    func canBeLinked(fromCycle identity: BindingIdentity) -> Bool {
        guard let target = target(of: identity), let action = target.editableAction(with: self) else {
            return false
        }

        return action.direction != .cycle && !action.allowsRapidRepeat
    }

    /// The binding `link` links to and its action, which edits through the link change
    func linked(by link: BindingLink) -> (identity: BindingIdentity, action: WindowAction)? {
        guard let identity = identity(of: link), case let .action(action)? = target(of: identity) else {
            return nil
        }

        return (identity, action)
    }

    /// Only bindings holding an action can be linked to, so links never chain or loop
    func canBeLinked(_ identity: BindingIdentity) -> Bool {
        target(of: identity)?.action != nil
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

/// Written as `RadialMenuAction.ActionType` was, so older versions still read radial menu actions and gestures.
/// Links to keybinds by UUID keep the case older versions run
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

/// An action, or a `noAction` action carrying the link, which older versions read as doing nothing.
/// Keybinds and cycle steps are written this way too
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
