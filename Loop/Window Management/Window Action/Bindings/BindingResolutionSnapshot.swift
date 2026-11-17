//
//  BindingResolutionSnapshot.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation

struct BindingResolutionSnapshot {
    enum Reference: Hashable, Sendable, CustomStringConvertible {
        case key(String), gesture(String), radialMenu(String)
        var description: String {
            switch self {
            case let .key(id): "keybind '\(id)'"
            case let .gesture(id): "gesture '\(id)'"
            case let .radialMenu(id): "radial menu action '\(id)'"
            }
        }

        init?(_ target: ActionTarget) {
            switch target {
            case let .keyBinding(id): self = .key(id)
            case let .gestureBinding(id): self = .gesture(id)
            case let .radialMenuBinding(id): self = .radialMenu(id)
            case .windowAction, .radialMenuMode: return nil
            }
        }
    }

    enum ResolutionError: Error, Equatable {
        case cycle([Reference])
        case radialMenuModeReference(Reference)
        case duplicateIdentifier(Reference)
        case nestedCycle(Reference?)
    }

    fileprivate struct Walk {
        var nestedCycle: ResolutionError?
    }

    let keyBindings: [KeyBinding]
    let gestures: [GestureBinding]
    let radialMenuBindings: [RadialMenuBinding]
    private let rootTargets: [ActionTarget]
    private let destinations: [Reference: ActionTarget]
    let duplicateIdentifiers: [Reference]
    private static let noAction = WindowAction(.noAction)

    init(keyBindings: [KeyBinding], gestures: [GestureBinding], radialMenuBindings: [RadialMenuBinding]) {
        let keyBindings = keyBindings.identified()
        let gestures = gestures.identified()
        let radialMenuBindings = radialMenuBindings.identified()
        self.keyBindings = keyBindings
        self.gestures = gestures
        self.radialMenuBindings = radialMenuBindings
        var destinations: [Reference: ActionTarget] = [:]
        var duplicates: [Reference] = []
        func insert(_ reference: Reference, target: ActionTarget) {
            if destinations[reference] != nil { duplicates.append(reference) }
            else { destinations[reference] = target }
        }
        for binding in keyBindings {
            if let id = binding.configID { insert(.key(id), target: binding.target) }
        }
        for binding in gestures {
            if let id = binding.configID { insert(.gesture(id), target: binding.target) }
        }
        for binding in radialMenuBindings {
            if let id = binding.configID { insert(.radialMenu(id), target: binding.target) }
        }
        self.rootTargets = keyBindings.map(\.target) + gestures.map(\.target) + radialMenuBindings.map(\.target)
        self.destinations = destinations
        self.duplicateIdentifiers = duplicates
    }

    func resolve(_ target: ActionTarget) throws -> WindowAction? {
        var walk = Walk()
        return try resolve(target, path: [], walk: &walk)
    }

    func action(for target: ActionTarget) -> WindowAction? {
        (try? resolve(target)) ?? (target == .radialMenuMode ? nil : Self.noAction)
    }

    func validate() throws {
        if let duplicate = duplicateIdentifiers.first { throw ResolutionError.duplicateIdentifier(duplicate) }
        for target in rootTargets where target != .radialMenuMode {
            var walk = Walk()
            _ = try resolve(target, path: [], walk: &walk)
            if let nested = walk.nestedCycle { throw nested }
        }
    }

    private func resolve(_ target: ActionTarget, path: [Reference], walk: inout Walk, materializingSteps: Bool = true) throws -> WindowAction? {
        switch target {
        case let .windowAction(action):
            return materializingSteps ? try resolveSteps(of: action, path: path, walk: &walk) : action
        case .radialMenuMode: return nil
        default:
            guard let reference = Reference(target) else { preconditionFailure("Expected reference") }
            guard !path.contains(reference) else { throw ResolutionError.cycle(path + [reference]) }
            guard let destination = destinations[reference] else { return Self.noAction }
            guard let action = try resolve(destination, path: path + [reference], walk: &walk, materializingSteps: materializingSteps) else {
                throw ResolutionError.radialMenuModeReference(reference)
            }
            return action
        }
    }
}

private extension BindingResolutionSnapshot {
    func resolveSteps(of action: WindowAction, path: [Reference], walk: inout Walk) throws -> WindowAction {
        var action = action
        if case var .cycle(payload) = action.kind {
            payload.steps = try payload.steps.map { step in
                let resolved = try resolve(step, path: path, walk: &walk, materializingSteps: false) ?? Self.noAction
                guard resolved.direction != .cycle else {
                    if walk.nestedCycle == nil { walk.nestedCycle = .nestedCycle(Reference(step)) }
                    return .windowAction(Self.noAction)
                }
                return .windowAction(resolved)
            }
            action.kind = .cycle(payload)
        }
        return action
    }
}

extension ActionTarget {
    var resolvedAction: WindowAction? { WindowActionCache.shared.resolve(self) }
}

extension WindowAction {
    var resolvedCycleSteps: [WindowAction]? {
        guard case let .cycle(payload) = kind else { return nil }
        return payload.steps.map { target in
            if case let .windowAction(action) = target { return action }
            return target.resolvedAction ?? WindowAction(.noAction)
        }
    }
}
