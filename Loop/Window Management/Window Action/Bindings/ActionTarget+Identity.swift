//
//  ActionTarget+Identity.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation

extension ActionTarget {
    /// Cycle progress and stash recovery remember actions by identity, so it must survive a restart.
    func identified(seed: String) -> ActionTarget {
        guard case var .windowAction(action) = self else { return self }
        action = action.withRuntimeID(ConfigurationIdentity.uuid(seed))
        if case var .cycle(cycle) = action.kind {
            var occurrences: [String: Int] = [:]
            cycle.steps = cycle.steps.map { step in
                let key = step.identityKey
                let occurrence = occurrences[key, default: 0]
                occurrences[key] = occurrence + 1
                guard case let .windowAction(stepAction) = step else { return step }
                return .windowAction(stepAction.withRuntimeID(ConfigurationIdentity.uuid("\(seed)/\(key)#\(occurrence)")))
            }
            action.kind = .cycle(cycle)
        }
        return .windowAction(action)
    }

    var contentKey: String {
        if case let .windowAction(action) = self, case let .cycle(cycle) = action.kind { return "cycle:\(cycle.name ?? "")" }
        return identityKey
    }

    private var identityKey: String {
        switch self {
        case let .windowAction(action):
            switch action.kind {
            case let .builtin(direction): direction.rawValue
            case .custom: "custom"
            case .cycle: "cycle"
            case var .stash(frame): { frame.name = nil; return "stash:\(frame)" }()
            }
        case let .keyBinding(id): "key:\(id)"
        case let .gestureBinding(id): "gesture:\(id)"
        case let .radialMenuBinding(id): "radial-menu:\(id)"
        case .radialMenuMode: "radialMenu"
        }
    }
}
