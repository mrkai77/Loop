//
//  ActionTargetEditorGraph.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
import Tome

/// The bindings as the settings editors see them, resolved independently of the runtime cache.
struct ActionTargetEditorGraph: Equatable {
    var keyBindings: [KeyBinding]
    var gestureBindings: [GestureBinding]
    var radialMenuBindings: [RadialMenuBinding]

    static var current: Self {
        .init(keyBindings: Tome.keyBindings, gestureBindings: Tome.gestureBindings, radialMenuBindings: Tome.radialMenuBindings)
    }

    private var resolver: BindingResolutionSnapshot {
        .init(keyBindings: keyBindings, gestureBindings: gestureBindings, radialMenuBindings: radialMenuBindings)
    }

    /// Saves only the lists that changed.
    func commit() {
        if keyBindings != Tome.keyBindings { Tome.keyBindings = keyBindings }
        if gestureBindings != Tome.gestureBindings { Tome.gestureBindings = gestureBindings }
        if radialMenuBindings != Tome.radialMenuBindings { Tome.radialMenuBindings = radialMenuBindings }
    }

    // MARK: Resolving

    /// `nil` for a missing reference, a reference cycle or a radial-menu gesture.
    func resolve(_ target: ActionTarget) -> WindowAction? { terminal(target)?.action }

    /// Also resolves references in cycle steps, for previews.
    func previewAction(for target: ActionTarget) -> WindowAction? { try? resolver.resolve(target) }

    func target(of reference: BindingReference) -> ActionTarget? {
        location(of: reference).map { binding(at: $0).target }
    }

    /// `nil` when `target` is an inline action.
    func terminalReference(for target: ActionTarget) -> BindingReference? {
        (try? resolver.terminal(of: target))?.holder
    }

    /// A cycle shows its first step's icon.
    func iconAction(for action: WindowAction) -> WindowAction {
        guard case let .cycle(payload) = action.kind,
              let first = payload.steps.first,
              let resolved = resolve(first),
              resolved.direction != .cycle else { return action }
        return resolved
    }

    // MARK: Editing

    /// Gives the referenced binding a written id. Non-reference targets come back unchanged.
    mutating func promoted(_ target: ActionTarget) -> ActionTarget? {
        guard case let .reference(reference) = target else { return target }
        return location(of: reference).map { .reference(ensureConfigurationID(at: $0)) }
    }

    /// Checks a selection without writing ids or an invalid graph to Settings.
    func canSetTarget(_ candidate: ActionTarget, for owner: BindingReference) -> Bool {
        var graph = self
        let promotedCandidate = graph.promoted(candidate) ?? candidate
        // Promoting the candidate renames its reference, which may be the owner's own.
        let ownerReference = if candidate == .reference(owner), case let .reference(promoted) = promotedCandidate { promoted } else { owner }
        guard let ownerLocation = graph.location(of: ownerReference) else { return true }
        _ = graph.ensureConfigurationID(at: ownerLocation)
        graph.update(ownerLocation) { $0.target = promotedCandidate }
        return (try? graph.resolver.validate()) != nil
    }

    /// Edits through a reference go into the referenced binding. Generated ids follow the new action; hand-written ids never change.
    /// - Returns: the target with `action` inline when no binding holds it (such as a cycle step's own), otherwise `nil`.
    mutating func replaceAction(in target: ActionTarget, owner: BindingReference?, with action: WindowAction) -> ActionTarget? {
        guard let (holder, old) = terminal(target) else { return nil }
        let location: Location
        if let holder {
            location = holder
        } else if let owner, let ownerLocation = self.location(of: owner), binding(at: ownerLocation).target == target {
            location = ownerLocation
        } else {
            return .windowAction(action)
        }
        update(location) { $0.target = .windowAction(action) }
        renameGeneratedID(at: location, from: old, to: action)
        return nil
    }

    // MARK: Locations

    private struct Location {
        var kind: BindingKind
        var index: Int
    }

    private func bindings(of kind: BindingKind) -> [any ActionBinding] {
        switch kind {
        case .key: keyBindings
        case .gesture: gestureBindings
        case .radialMenu: radialMenuBindings
        }
    }

    private func binding(at location: Location) -> any ActionBinding {
        bindings(of: location.kind)[location.index]
    }

    /// Only the written id and target are taken back from `body`.
    @discardableResult
    private mutating func update<Result>(_ location: Location, _ body: (inout any ActionBinding) -> Result) -> Result {
        switch location.kind {
        case .key: Self.update(&keyBindings[location.index], body)
        case .gesture: Self.update(&gestureBindings[location.index], body)
        case .radialMenu: Self.update(&radialMenuBindings[location.index], body)
        }
    }

    private static func update<Result>(_ binding: inout some ActionBinding, _ body: (inout any ActionBinding) -> Result) -> Result {
        var edited: any ActionBinding = binding
        let result = body(&edited)
        binding.configID = edited.configID
        binding.target = edited.target
        return result
    }

    /// With `requiringWrittenID`, bindings without a written id are skipped.
    private func location(of reference: BindingReference, requiringWrittenID: Bool = false) -> Location? {
        bindings(of: reference.kind)
            .firstIndex { requiringWrittenID ? $0.configID == reference.id : $0.referenceID == reference.id }
            .map { Location(kind: reference.kind, index: $0) }
    }

    private func terminal(_ target: ActionTarget) -> (holder: Location?, action: WindowAction)? {
        guard let (holder, action) = try? resolver.terminal(of: target) else { return nil }
        guard let holder else { return (nil, action) }
        return location(of: holder, requiringWrittenID: true).map { ($0, action) }
    }

    private mutating func ensureConfigurationID(at location: Location) -> BindingReference {
        let taken = Set(bindings(of: location.kind).compactMap(\.configID))
        return update(location) {
            _ = $0.ensureConfigurationID(avoiding: taken)
            return $0.reference
        }
    }

    /// A generated id follows the new action, and so does every reference to it.
    private mutating func renameGeneratedID(at location: Location, from old: WindowAction, to new: WindowAction) {
        let siblings = bindings(of: location.kind)
        let binding = siblings[location.index]
        guard let current = binding.configID else { return }
        var before = binding
        before.target = .windowAction(old)
        var after = binding
        after.target = .windowAction(new)
        guard before.readableIDStem != after.readableIDStem,
              ConfigurationIdentity.isGenerated(current, from: before.readableIDStem) else { return }
        let taken = Set(siblings.indices.filter { $0 != location.index }.compactMap { siblings[$0].configID })
        let renamedID = ConfigurationIdentity.nextFreeID(after.readableIDStem, taken: taken)
        update(location) { $0.configID = renamedID }

        let oldReference = ActionTarget.reference(BindingReference(location.kind, current))
        let newReference = ActionTarget.reference(BindingReference(location.kind, renamedID))
        for kind in BindingKind.allCases {
            for index in bindings(of: kind).indices {
                update(Location(kind: kind, index: index)) { $0.target = $0.target.replacingReference(oldReference, with: newReference) }
            }
        }
    }
}

private extension ActionTarget {
    /// Includes references in cycle steps.
    func replacingReference(_ old: ActionTarget, with new: ActionTarget) -> ActionTarget {
        if self == old { return new }
        guard case var .windowAction(action) = self, case var .cycle(cycle) = action.kind else { return self }
        cycle.steps = cycle.steps.map { $0.replacingReference(old, with: new) }
        action.kind = .cycle(cycle)
        return .windowAction(action)
    }
}
