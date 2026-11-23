//
//  CycleStep.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-23.
//

import Foundation

/// A cycle step, running an action or the action of a binding it links to.
/// A linked step keeps its own id, so cycle progress follows the step
struct CycleStep: Identifiable, Hashable {
    let id: UUID
    /// An action shares the step's id, as steps were only actions before they could link
    var target: BindingTarget {
        didSet { target = target.sharingID(id) }
    }

    init(id: UUID = UUID(), target: BindingTarget) {
        self.id = id
        self.target = target.sharingID(id)
    }

    init(_ action: WindowAction) {
        self.init(id: action.id, target: .action(action))
    }

    /// A copy for a cycle copied from a binding that stops linking to it
    func detached() -> CycleStep {
        switch target {
        case let .action(action): CycleStep(action.detached())
        case .link: CycleStep(target: target)
        }
    }
}

// MARK: - Coding

/// Each step is an action on disk, as before, so older versions still read every cycle
extension CycleStep: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(), target: BindingTarget(inlineFrom: decoder))
    }

    func encode(to encoder: Encoder) throws {
        try target.encodeInline(to: encoder, id: id)
    }
}
