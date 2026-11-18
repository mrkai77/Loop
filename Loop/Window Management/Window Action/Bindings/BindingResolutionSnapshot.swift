//
//  BindingResolutionSnapshot.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation

/// An immutable view of all reference destinations.
struct BindingResolutionSnapshot {
    enum ResolutionError: LocalizedError, Equatable {
        case missingReference(BindingReference)
        case cycle([BindingReference])
        /// A radial-menu gesture opens the whole menu, so it has no action to share.
        case radialMenuGestureReference(BindingReference)
        case duplicateIdentifier(BindingReference)
        /// `nil` for a cycle written inline in the step.
        case nestedCycle(BindingReference?)

        var errorDescription: String? {
            switch self {
            case let .missingReference(reference): "Nothing has the id of \(reference)"
            case let .cycle(path): "References form a cycle: " + path.map(\.description).joined(separator: " \u{2192} ")
            case let .radialMenuGestureReference(reference): "\(reference) opens the radial menu, so it can't be referenced"
            case let .duplicateIdentifier(reference): "Duplicate \(reference)"
            case let .nestedCycle(reference): reference.map { "A cycle step references a cycle: \($0)" } ?? "A cycle step can't be a cycle"
            }
        }
    }

    /// A nested cycle doesn't stop the walk; the step resolves to no action.
    fileprivate struct Walk {
        var nestedCycle: ResolutionError?
    }

    private let rootTargets: [ActionTarget]
    private let destinations: [BindingReference: ActionTarget]
    private let radialMenuGestures: Set<BindingReference>
    let duplicateIdentifiers: [BindingReference]
    private static let noAction = WindowAction(.noAction)

    /// Runtime lookups must pass `identified()` lists.
    init(keyBindings: [KeyBinding], gestureBindings: [GestureBinding], radialMenuBindings: [RadialMenuBinding]) {
        var destinations: [BindingReference: ActionTarget] = [:]
        var duplicates: [BindingReference] = []
        func insert(_ bindings: [some ActionBinding]) {
            for binding in bindings where binding.configID != nil {
                if destinations[binding.reference] != nil { duplicates.append(binding.reference) }
                else { destinations[binding.reference] = binding.target }
            }
        }
        insert(keyBindings)
        insert(gestureBindings)
        insert(radialMenuBindings)
        self.rootTargets = keyBindings.map(\.target) + gestureBindings.map(\.target) + radialMenuBindings.map(\.target)
        self.destinations = destinations
        self.radialMenuGestures = Set(gestureBindings.filter { $0.configID != nil && $0.kind == .radialMenu }.map(\.reference))
        self.duplicateIdentifiers = duplicates
    }

    /// Also resolves references in cycle steps. A missing reference runs no action.
    func resolve(_ target: ActionTarget) throws -> WindowAction {
        var walk = Walk()
        return try resolve(target, path: [], walk: &walk)
    }

    /// No action when `target` can't be resolved.
    func action(for target: ActionTarget) -> WindowAction {
        (try? resolve(target)) ?? Self.noAction
    }

    /// `holder` is `nil` when `target` is an inline action.
    func terminal(of target: ActionTarget) throws -> (holder: BindingReference?, action: WindowAction) {
        var target = target
        var path: [BindingReference] = []
        while true {
            switch target {
            case let .windowAction(action):
                return (path.last, action)
            case let .reference(reference):
                guard !path.contains(reference) else { throw ResolutionError.cycle(path + [reference]) }
                path.append(reference)
                target = try destination(of: reference)
            }
        }
    }

    /// A missing reference isn't a problem; it runs no action.
    func validate() throws {
        if let duplicate = duplicateIdentifiers.first { throw ResolutionError.duplicateIdentifier(duplicate) }
        for target in rootTargets {
            var walk = Walk()
            do { _ = try resolve(target, path: [], walk: &walk) }
            catch ResolutionError.missingReference {}
            if let nested = walk.nestedCycle { throw nested }
        }
    }

    private func destination(of reference: BindingReference) throws -> ActionTarget {
        guard !radialMenuGestures.contains(reference) else { throw ResolutionError.radialMenuGestureReference(reference) }
        guard let destination = destinations[reference] else { throw ResolutionError.missingReference(reference) }
        return destination
    }

    private func resolve(_ target: ActionTarget, path: [BindingReference], walk: inout Walk, materializingSteps: Bool = true) throws -> WindowAction {
        switch target {
        case let .windowAction(action):
            return materializingSteps ? try resolveSteps(of: action, path: path, walk: &walk) : action
        case let .reference(reference):
            guard !path.contains(reference) else { throw ResolutionError.cycle(path + [reference]) }
            return try resolve(destination(of: reference), path: path + [reference], walk: &walk, materializingSteps: materializingSteps)
        }
    }
}

private extension BindingResolutionSnapshot {
    /// A step that is or references a cycle becomes no action and is recorded for `validate()`.
    func resolveSteps(of action: WindowAction, path: [BindingReference], walk: inout Walk) throws -> WindowAction {
        var action = action
        if case var .cycle(payload) = action.kind {
            payload.steps = try payload.steps.map { step in
                let resolved: WindowAction
                do { resolved = try resolve(step, path: path, walk: &walk, materializingSteps: false) }
                catch ResolutionError.missingReference { resolved = Self.noAction }
                guard resolved.direction != .cycle else {
                    if walk.nestedCycle == nil {
                        let reference: BindingReference? = if case let .reference(reference) = step { reference } else { nil }
                        walk.nestedCycle = .nestedCycle(reference)
                    }
                    return .windowAction(Self.noAction)
                }
                return .windowAction(resolved)
            }
            action.kind = .cycle(payload)
        }
        return action
    }
}

extension WindowAction {
    var resolvedCycleSteps: [WindowAction]? {
        guard case let .cycle(payload) = kind else { return nil }
        return payload.steps.map { step in
            if case let .windowAction(action) = step { action } else { WindowAction(.noAction) }
        }
    }
}
