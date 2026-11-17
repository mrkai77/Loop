//
//  KeyBinding.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import CoreGraphics
import Foundation

struct KeyBinding: ConfigurationIdentifiable, Codable, Hashable, Sendable {
    static let category = "key"

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

    init(_ direction: WindowDirection, keybind: KeyCombination = []) {
        self.init(keys: keybind, target: .windowAction(.init(direction)))
    }

    init(_ name: String? = nil, cycle: [WindowAction], keybind: KeyCombination = []) {
        self.init(keys: keybind, target: .windowAction(.init(name, cycle: cycle)))
    }

    var reference: ActionTarget { .keyBinding(referenceID) }
}

/// `link-trigger-key = false` is the file's spelling of `bypassTriggerKey`.
extension KeyBinding {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, keys
        case linkTriggerKey = "link-trigger-key"
    }

    init(from decoder: Decoder) throws {
        let table = try decoder.container(keyedBy: CodingKeys.self)
        let configID = try table.decodeIfPresent(String.self, forKey: .id)
        try configID.map { try ConfigurationIdentity.validate($0, as: "keybind id") }
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
        guard target != .radialMenuMode else {
            throw EncodingError.invalidValue(target, .init(codingPath: encoder.codingPath, debugDescription: "The radial menu is only a target of a radial-menu gesture"))
        }
        var table = encoder.container(keyedBy: CodingKeys.self)
        try table.encodeIfPresent(configID, forKey: .id)
        if !keys.isEmpty { try table.encode(keys, forKey: .keys) }
        if bypassTriggerKey == true { try table.encode(false, forKey: .linkTriggerKey) }
        try target.encode(to: encoder)
    }
}
