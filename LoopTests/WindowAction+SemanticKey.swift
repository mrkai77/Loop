//
//  WindowAction+SemanticKey.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-18.
//

@testable import Loop

/// Decoding assigns new UUIDs, so tests compare actions without their identity.
extension WindowAction {
    indirect enum SemanticKey: Hashable {
        case builtin(WindowDirection)
        case custom(FrameAction)
        case stash(FrameAction)
        case cycle(name: String?, steps: [ActionTarget.SemanticKey])
    }

    var semanticKey: SemanticKey {
        switch kind {
        case let .builtin(direction): .builtin(direction)
        case let .custom(payload): .custom(payload)
        case let .stash(payload): .stash(payload)
        case let .cycle(payload): .cycle(name: payload.name, steps: payload.steps.map(\.semanticKey))
        }
    }
}

extension ActionTarget {
    indirect enum SemanticKey: Hashable {
        case action(WindowAction.SemanticKey)
        case reference(BindingReference)
    }

    var semanticKey: SemanticKey {
        switch self {
        case let .windowAction(action): .action(action.semanticKey)
        case let .reference(reference): .reference(reference)
        }
    }
}
