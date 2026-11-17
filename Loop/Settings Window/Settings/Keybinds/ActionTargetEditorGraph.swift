//
//  ActionTargetEditorGraph.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
import Tome

struct ActionTargetEditorGraph: Equatable {
    var keyBindings: [KeyBinding]
    var gestures: [GestureBinding]
    var radialMenuBindings: [RadialMenuBinding]

    static var current: Self {
        .init(keyBindings: Tome.keyBindings, gestures: Tome.gestures, radialMenuBindings: Tome.radialMenuActions)
    }

    enum Replacement {
        case direct(ActionTarget)
        case keyBindings([KeyBinding])
        case gestures([GestureBinding])
        case radialMenuBindings([RadialMenuBinding])
    }

    private enum Destination {
        case keyBinding(Int)
        case gesture(Int)
        case radialMenuBinding(Int)
    }

    private func terminal(_ target: ActionTarget) -> (Destination?, WindowAction)? {
        var target = target
        var destination: Destination?
        var visited = Set<String>()
        while visited.insert(target.id).inserted {
            switch target {
            case let .windowAction(action): return (destination, action)
            case let .keyBinding(id):
                guard let index = keyBindings.firstIndex(where: { $0.configID == id }) else { return nil }
                destination = .keyBinding(index)
                target = keyBindings[index].target
            case let .gestureBinding(id):
                guard let index = gestures.firstIndex(where: { $0.configID == id && $0.kind != .radialMenu }) else { return nil }
                destination = .gesture(index)
                target = gestures[index].target
            case let .radialMenuBinding(id):
                guard let index = radialMenuBindings.firstIndex(where: { $0.configID == id }) else { return nil }
                destination = .radialMenuBinding(index)
                target = radialMenuBindings[index].target
            case .radialMenuMode: return nil
            }
        }
        return nil
    }

    func resolve(_ target: ActionTarget) -> WindowAction? { terminal(target)?.1 }

    func terminalReference(for target: ActionTarget) -> ActionTarget? {
        guard let (destination, _) = terminal(target) else { return nil }
        switch destination {
        case let .keyBinding(index): return keyBindings[index].reference
        case let .gesture(index): return gestures[index].reference
        case let .radialMenuBinding(index): return radialMenuBindings[index].reference
        case nil: return nil
        }
    }

    mutating func promoted(_ target: ActionTarget) -> ActionTarget? {
        switch target {
        case .keyBinding:
            guard let index = keyBindings.firstIndex(where: { $0.reference == target }) else { return nil }
            keyBindings.ensureConfigurationID(at: index)
            return keyBindings[index].reference
        case .gestureBinding:
            guard let index = gestures.firstIndex(where: { $0.reference == target }) else { return nil }
            gestures.ensureConfigurationID(at: index)
            return gestures[index].reference
        case .radialMenuBinding:
            guard let index = radialMenuBindings.firstIndex(where: { $0.reference == target }) else { return nil }
            radialMenuBindings.ensureConfigurationID(at: index)
            return radialMenuBindings[index].reference
        case .windowAction, .radialMenuMode: return target
        }
    }

    func canSetTarget(_ candidate: ActionTarget, for owner: ActionTarget) -> Bool {
        var graph = self
        // Promoting the candidate renames its reference, which may be the owner's own.
        let promotedCandidate = graph.promoted(candidate) ?? candidate
        let ownerReference = owner == candidate ? promotedCandidate : owner
        switch ownerReference {
        case .keyBinding:
            guard let index = graph.keyBindings.firstIndex(where: { $0.reference == ownerReference }) else { return true }
            graph.keyBindings.ensureConfigurationID(at: index)
            graph.keyBindings[index].target = promotedCandidate
        case .gestureBinding:
            guard let index = graph.gestures.firstIndex(where: { $0.reference == ownerReference }) else { return true }
            graph.gestures.ensureConfigurationID(at: index)
            graph.gestures[index].target = promotedCandidate
        case .radialMenuBinding:
            guard let index = graph.radialMenuBindings.firstIndex(where: { $0.reference == ownerReference }) else { return true }
            graph.radialMenuBindings.ensureConfigurationID(at: index)
            graph.radialMenuBindings[index].target = promotedCandidate
        case .windowAction, .radialMenuMode: return true
        }
        return (try? BindingResolutionSnapshot(
            keyBindings: graph.keyBindings, gestures: graph.gestures,
            radialMenuBindings: graph.radialMenuBindings
        ).validate()) != nil
    }

    func replacingAction(in target: ActionTarget, with action: WindowAction) -> Replacement? {
        guard let (destination, _) = terminal(target) else { return nil }
        switch destination {
        case nil: return .direct(.windowAction(action))
        case let .keyBinding(index):
            var values = keyBindings
            values[index].target = .windowAction(action)
            return .keyBindings(values)
        case let .gesture(index):
            var values = gestures
            values[index].target = .windowAction(action)
            return .gestures(values)
        case let .radialMenuBinding(index):
            var values = radialMenuBindings
            values[index].target = .windowAction(action)
            return .radialMenuBindings(values)
        }
    }

    func holder(of target: ActionTarget, owner: ActionTarget?) -> UUID? {
        guard let (destination, _) = terminal(target) else { return nil }
        switch destination {
        case let .keyBinding(index): return keyBindings[index].id
        case let .gesture(index): return gestures[index].id
        case let .radialMenuBinding(index): return radialMenuBindings[index].id
        case nil:
            guard let owner else { return nil }
            if let binding = keyBindings.first(where: { $0.reference == owner }) { return binding.target == target ? binding.id : nil }
            if let binding = gestures.first(where: { $0.reference == owner }) { return binding.target == target ? binding.id : nil }
            if let binding = radialMenuBindings.first(where: { $0.reference == owner }) { return binding.target == target ? binding.id : nil }
            return nil
        }
    }

    mutating func renameGeneratedID(of holder: UUID, from old: WindowAction, to new: WindowAction) -> Bool {
        let renamed: (old: ActionTarget, new: ActionTarget)? = if let index = keyBindings.firstIndex(where: { $0.id == holder }) {
            Self.renameGeneratedID(in: &keyBindings, at: index, from: old, to: new, reference: ActionTarget.keyBinding)
        } else if let index = gestures.firstIndex(where: { $0.id == holder }) {
            Self.renameGeneratedID(in: &gestures, at: index, from: old, to: new, reference: ActionTarget.gestureBinding)
        } else if let index = radialMenuBindings.firstIndex(where: { $0.id == holder }) {
            Self.renameGeneratedID(in: &radialMenuBindings, at: index, from: old, to: new, reference: ActionTarget.radialMenuBinding)
        } else {
            nil
        }
        guard let renamed else { return false }
        for index in keyBindings.indices { keyBindings[index].target = keyBindings[index].target.replacingReference(renamed.old, with: renamed.new) }
        for index in gestures.indices { gestures[index].target = gestures[index].target.replacingReference(renamed.old, with: renamed.new) }
        for index in radialMenuBindings.indices {
            radialMenuBindings[index].target = radialMenuBindings[index].target.replacingReference(renamed.old, with: renamed.new)
        }
        return true
    }

    private static func renameGeneratedID<Binding: ConfigurationIdentifiable>(
        in bindings: inout [Binding], at index: Int, from old: WindowAction, to new: WindowAction, reference: (String) -> ActionTarget
    ) -> (old: ActionTarget, new: ActionTarget)? {
        guard let current = bindings[index].configID else { return nil }
        var before = bindings[index]
        before.target = .windowAction(old)
        var after = bindings[index]
        after.target = .windowAction(new)
        guard before.readableIDStem != after.readableIDStem,
              ConfigurationIdentity.isGenerated(current, from: before.readableIDStem) else { return nil }
        let taken = Set(bindings.indices.filter { $0 != index }.compactMap { bindings[$0].configID })
        bindings[index].configID = ConfigurationIdentity.nextFreeID(after.readableIDStem, taken: taken)
        return (reference(current), reference(bindings[index].referenceID))
    }

    static func followRename(of holder: UUID, from old: WindowAction, to new: WindowAction) {
        var graph = Self.current
        guard graph.renameGeneratedID(of: holder, from: old, to: new) else { return }
        Tome.keyBindings = graph.keyBindings
        Tome.gestures = graph.gestures
        Tome.radialMenuActions = graph.radialMenuBindings
    }

    func iconAction(for action: WindowAction) -> WindowAction {
        guard case let .cycle(payload) = action.kind,
              let first = payload.steps.first,
              let resolved = resolve(first),
              resolved.direction != .cycle else { return action }
        return resolved
    }
}

private extension ActionTarget {
    func replacingReference(_ old: ActionTarget, with new: ActionTarget) -> ActionTarget {
        if self == old { return new }
        guard case var .windowAction(action) = self, case var .cycle(cycle) = action.kind else { return self }
        cycle.steps = cycle.steps.map { $0.replacingReference(old, with: new) }
        action.kind = .cycle(cycle)
        return .windowAction(action)
    }
}
