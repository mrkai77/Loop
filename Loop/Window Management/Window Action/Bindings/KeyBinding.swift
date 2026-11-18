//
//  KeyBinding.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import CoreGraphics
import Foundation

struct KeyBinding: ActionBinding, Codable, Hashable, Sendable {
    static let bindingKind = BindingKind.key

    var id: UUID
    var configID: String?
    var keys: KeyCombination
    var bypassTriggerKey: Bool?
    var target: ActionTarget

    init(
        id: UUID = UUID(),
        configID: String? = nil,
        keys: KeyCombination = [],
        bypassTriggerKey: Bool? = nil,
        target: ActionTarget = .windowAction(.init(.noAction))
    ) {
        self.id = id
        self.configID = configID
        self.keys = keys
        self.bypassTriggerKey = bypassTriggerKey
        self.target = target
    }

    init(_ direction: WindowDirection, keys: KeyCombination = []) {
        self.init(keys: keys, target: .windowAction(.init(direction)))
    }

    init(_ name: String? = nil, cycle: [WindowAction], keys: KeyCombination = []) {
        self.init(keys: keys, target: .windowAction(.init(name, cycle: cycle)))
    }
}

// MARK: - Defaults

extension KeyBinding {
    static let defaults: [KeyBinding] = [
        KeyBinding(.maximize, keys: [.kVK_Space]),
        KeyBinding(.center, keys: [.kVK_Return]),
        KeyBinding(
            .init(localized: "Top Cycle"),
            cycle: [.init(.topHalf), .init(.topThird), .init(.topTwoThirds)],
            keys: [.kVK_UpArrow]
        ),
        KeyBinding(
            .init(localized: "Bottom Cycle"),
            cycle: [.init(.bottomHalf), .init(.bottomThird), .init(.bottomTwoThirds)],
            keys: [.kVK_DownArrow]
        ),
        KeyBinding(
            .init(localized: "Right Cycle"),
            cycle: [.init(.rightHalf), .init(.rightThird), .init(.rightTwoThirds)],
            keys: [.kVK_RightArrow]
        ),
        KeyBinding(
            .init(localized: "Left Cycle"),
            cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)],
            keys: [.kVK_LeftArrow]
        ),
        KeyBinding(.topLeftQuarter, keys: [.kVK_UpArrow, .kVK_LeftArrow]),
        KeyBinding(.topRightQuarter, keys: [.kVK_UpArrow, .kVK_RightArrow]),
        KeyBinding(.bottomRightQuarter, keys: [.kVK_DownArrow, .kVK_RightArrow]),
        KeyBinding(.bottomLeftQuarter, keys: [.kVK_DownArrow, .kVK_LeftArrow])
    ]
}

// MARK: - Trigger

extension KeyBinding {
    /// Includes the trigger key unless the binding bypasses it. `nil` while it has no keys.
    func trigger(triggerKey: KeyCombination) -> Set<String>? {
        guard !keys.isEmpty else { return nil }
        return bypassTriggerKey == true ? keys.names : triggerKey.names.union(keys.names)
    }

    static func conflictingIDs(in bindings: [Self], triggerKey: KeyCombination) -> Set<UUID> {
        conflictingIDs(in: bindings) { $0.trigger(triggerKey: triggerKey) }
    }

    static func active(in bindings: [Self], triggerKey: KeyCombination) -> [Self] {
        active(in: bindings) { $0.trigger(triggerKey: triggerKey) }
    }
}

/// `link-trigger-key = false` is the file's spelling of `bypassTriggerKey`.
extension KeyBinding {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, keys
        case linkTriggerKey = "link-trigger-key"
    }

    init(from decoder: Decoder) throws {
        let table = try decoder.container(keyedBy: CodingKeys.self)
        let configID = try Self.decodeConfigurationID(from: table, forKey: .id)
        let target = try ActionTarget(from: decoder)
        switch target {
        case let .windowAction(action) where action.direction == .noSelection:
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "'no-selection' isn't a valid action for a keybind"))
        default: break
        }
        try self.init(
            configID: configID,
            keys: table.decodeIfPresent(KeyCombination.self, forKey: .keys) ?? [],
            bypassTriggerKey: table.decodeIfPresent(Bool.self, forKey: .linkTriggerKey).map { !$0 },
            target: target
        )
        deriveIdentity()
    }

    func encode(to encoder: Encoder) throws {
        var table = encoder.container(keyedBy: CodingKeys.self)
        try encodeConfigurationID(into: &table, forKey: .id)
        if !keys.isEmpty { try table.encode(keys, forKey: .keys) }
        if bypassTriggerKey == true { try table.encode(false, forKey: .linkTriggerKey) }
        try target.encode(to: encoder)
    }
}
