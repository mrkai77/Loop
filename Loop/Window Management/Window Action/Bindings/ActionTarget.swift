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
    case keyBinding(String)
    case gestureBinding(String)
    case radialMenuBinding(String)
    case radialMenuMode

    var id: String {
        switch self {
        case let .windowAction(action): "action:" + action.id.uuidString
        case let .keyBinding(id): "key:" + id
        case let .gestureBinding(id): "gesture:" + id
        case let .radialMenuBinding(id): "radial-menu:" + id
        case .radialMenuMode: "radialMenuMode"
        }
    }

    var isReference: Bool {
        switch self {
        case .keyBinding, .gestureBinding, .radialMenuBinding: true
        case .windowAction, .radialMenuMode: false
        }
    }
}

// MARK: - Configuration

extension ActionTarget {
    enum CodingKeys: String, CodingKey, CaseIterable {
        case action, name, size, position, cycle
    }

    static let radialMenuMarker = "radial-menu"

    private static let references: [(prefix: String, label: String, target: (String) -> ActionTarget)] = [
        ("key:", "key binding", ActionTarget.keyBinding),
        ("gesture:", "gesture", ActionTarget.gestureBinding),
        ("radial-menu:", "radial menu item", ActionTarget.radialMenuBinding),
    ]

    static func isPresent(in decoder: Decoder) throws -> Bool {
        try decoder.container(keyedBy: CodingKeys.self).contains(.action)
    }

    init(from decoder: Decoder) throws {
        let table = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try table.decode(String.self, forKey: .action)
        if let reference = Self.references.first(where: { raw.hasPrefix($0.prefix) }) {
            let id = String(raw.dropFirst(reference.prefix.count))
            try ConfigurationIdentity.validate(id, as: "\(reference.label) id")
            self = reference.target(id)
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
            let isInvalidStep: (ActionTarget) -> Bool = {
                switch $0 {
                case let .windowAction(step): step.direction == .cycle
                case .radialMenuMode: true
                default: false
                }
            }
            if let invalid = steps.first(where: isInvalidStep) {
                let found = invalid == .radialMenuMode ? radialMenuMarker : WindowDirection.cycle.rawValue
                throw DecodingError.dataCorruptedError(forKey: .cycle, in: table, debugDescription: "A cycle step can't be a cycle or the radial menu, found \(ConfigurationMessage.quoted(found))")
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

    func encode(to encoder: Encoder) throws {
        var table = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .windowAction(action): try Self.encode(action, into: &table)
        case let .keyBinding(id): try Self.encodeReference("key:", id, into: &table)
        case let .gestureBinding(id): try Self.encodeReference("gesture:", id, into: &table)
        case let .radialMenuBinding(id): try Self.encodeReference("radial-menu:", id, into: &table)
        case .radialMenuMode:
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "The radial menu is a gesture kind, not an action"))
        }
    }

    private static func encodeReference(_ prefix: String, _ id: String, into table: inout KeyedEncodingContainer<CodingKeys>) throws {
        let label = references.first { $0.prefix == prefix }!.label
        try ConfigurationIdentity.validate(id, as: "\(label) id")
        try table.encode(prefix + id, forKey: .action)
    }

    private static func encode(_ action: WindowAction, into table: inout KeyedEncodingContainer<CodingKeys>) throws {
        try table.encode(action.direction.rawValue, forKey: .action)
        if let name = action.name, !name.isEmpty { try table.encode(name, forKey: .name) }
        if case let .cycle(cycle) = action.kind {
            let invalid = cycle.steps.contains {
                switch $0 {
                case let .windowAction(step): step.direction == .cycle
                case .radialMenuMode: true
                default: false
                }
            }
            guard !invalid else {
                throw EncodingError.invalidValue(cycle, .init(codingPath: table.codingPath, debugDescription: "A cycle step can't be a cycle or the radial menu"))
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
