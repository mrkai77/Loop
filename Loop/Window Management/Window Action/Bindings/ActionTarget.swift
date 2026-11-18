//
//  ActionTarget.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
import TOML

/// References invoke a destination's target, never its physical input.
indirect enum ActionTarget: Codable, Hashable, Identifiable, Sendable {
    case windowAction(WindowAction)
    case reference(BindingReference)

    var id: String {
        switch self {
        case let .windowAction(action): "action:" + action.id.uuidString
        case let .reference(reference): reference.configurationString
        }
    }

    var isReference: Bool {
        if case .reference = self { true } else { false }
    }
}

// MARK: - Configuration

/// Written as fields of its owner's table, so a binding decodes its own fields and then this from the same decoder.
extension ActionTarget {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case action, name, size, position, cycle
    }

    /// A gesture opens the radial menu with `kind = "radial-menu"`, never as an action.
    static let radialMenuMarker = "radial-menu"

    static func isPresent(in decoder: Decoder) throws -> Bool {
        try decoder.container(keyedBy: CodingKeys.self).contains(.action)
    }

    init(from decoder: Decoder) throws {
        let table = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try table.decode(String.self, forKey: .action)
        if let kind = BindingKind.allCases.first(where: { raw.hasPrefix($0.referencePrefix) }) {
            let id = String(raw.dropFirst(kind.referencePrefix.count))
            try ConfigurationIdentity.validate(id, as: "\(kind.label) id")
            self = .reference(BindingReference(kind, id))
            return
        }
        self = try Self.decodeAction(raw, from: table)
    }

    private static func decodeAction(_ raw: String, from table: KeyedDecodingContainer<CodingKeys>) throws -> ActionTarget {
        if raw == radialMenuMarker {
            throw DecodingError.dataCorruptedError(forKey: .action, in: table, debugDescription: "Use kind = \"radial-menu\" on a gesture to open the radial menu")
        }
        guard let direction = WindowDirection(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .action, in: table, debugDescription: "Unknown action \(ConfigurationMessage.quoted(raw))")
        }
        var action = WindowAction(direction)
        guard direction == .custom || direction == .stash || direction == .cycle else { return .windowAction(action) }
        let name = try table.decodeIfPresent(String.self, forKey: .name)
        if direction == .cycle {
            let steps = try table.decodeIfPresent([ActionTarget].self, forKey: .cycle) ?? []
            guard steps.allSatisfy(\.isValidCycleStep) else {
                throw DecodingError.dataCorruptedError(forKey: .cycle, in: table, debugDescription: invalidCycleStepMessage)
            }
            action.kind = .cycle(CycleAction(name: name, steps: steps))
        } else {
            let frame = try FrameAction(
                name: name,
                size: table.decodeIfPresent(ActionSize.self, forKey: .size) ?? .custom(width: nil, height: nil),
                position: table.decodeIfPresent(ActionPosition.self, forKey: .position) ?? .anchor(.none)
            )
            action.kind = direction == .stash ? .stash(frame) : .custom(frame)
        }
        return .windowAction(action)
    }

    /// A reference to a cycle is caught when references resolve.
    private var isValidCycleStep: Bool {
        if case let .windowAction(step) = self { step.direction != .cycle } else { true }
    }

    private static let invalidCycleStepMessage = "A cycle step can't be a cycle, found \(ConfigurationMessage.quoted(WindowDirection.cycle.rawValue))"

    func encode(to encoder: Encoder) throws {
        var table = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .windowAction(action): try Self.encode(action, into: &table)
        case let .reference(reference):
            try ConfigurationIdentity.validate(reference.id, as: "\(reference.kind.label) id")
            try table.encode(reference.configurationString, forKey: .action)
        }
    }

    private static func encode(_ action: WindowAction, into table: inout KeyedEncodingContainer<CodingKeys>) throws {
        try table.encode(action.direction.rawValue, forKey: .action)
        if let name = action.name, !name.isEmpty { try table.encode(name, forKey: .name) }
        if case let .cycle(cycle) = action.kind {
            guard cycle.steps.allSatisfy(\.isValidCycleStep) else {
                throw EncodingError.invalidValue(cycle, .init(codingPath: table.codingPath, debugDescription: invalidCycleStepMessage))
            }
            try table.encode(TOMLInlineArray(wrappedValue: cycle.steps), forKey: .cycle)
        }
        switch action.size {
        case let .custom(width, height)?:
            if width != nil || height != nil { try table.encode(TOMLInlineTable(wrappedValue: ActionSize.custom(width: width, height: height)), forKey: .size) }
        case let size?: try table.encode(size, forKey: .size)
        case nil: break
        }
        switch action.position {
        case let .anchor(anchor)?: try table.encode(anchor.rawValue, forKey: .position)
        case let position?: try table.encode(TOMLInlineTable(wrappedValue: position), forKey: .position)
        case nil: break
        }
    }
}
