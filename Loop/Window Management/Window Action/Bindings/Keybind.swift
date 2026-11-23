//
//  Keybind.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-23.
//

import CoreGraphics
import Defaults
import Foundation

/// Keys that run an action, or the action of a binding it links to
struct Keybind: ActionBinding, Codable, Defaults.Serializable {
    static let bindingKind = LoopBindingKind.keybind

    let id: UUID
    var configID: String?
    var keys: Set<CGKeyCode>
    var bypassTriggerKey: Bool
    /// An action shares the keybind's id, so cycle progress and the radial menu tell keybinds apart as before
    var target: BindingTarget {
        didSet { target = target.sharingID(id) }
    }

    init(
        id: UUID = UUID(),
        configID: String? = nil,
        keys: Set<CGKeyCode> = [],
        bypassTriggerKey: Bool = false,
        target: BindingTarget = .action(WindowAction(.noAction))
    ) {
        self.id = id
        self.configID = configID
        self.keys = keys
        self.bypassTriggerKey = bypassTriggerKey
        self.target = target.sharingID(id)
    }

    var bindingTarget: BindingTarget? {
        target
    }

    mutating func setTarget(_ target: BindingTarget) -> Bool {
        self.target = target
        return true
    }
}

// MARK: - Coding

/// One object on disk with its action, as before, so older versions still read every keybind
extension Keybind {
    private enum CodingKeys: String, CodingKey {
        case id, keybind, bypassTriggerKey, configID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            configID: container.decodeIfPresent(String.self, forKey: .configID),
            keys: container.decodeIfPresent(Set<CGKeyCode>.self, forKey: .keybind) ?? [],
            bypassTriggerKey: container.decodeIfPresent(Bool.self, forKey: .bypassTriggerKey) ?? false,
            target: BindingTarget(inlineFrom: decoder)
        )
    }

    func encode(to encoder: Encoder) throws {
        try target.encodeInline(to: encoder, id: id, keybind: keys)

        var container = encoder.container(keyedBy: CodingKeys.self)
        if bypassTriggerKey {
            try container.encode(true, forKey: .bypassTriggerKey)
        }
        try container.encodeIfPresent(configID, forKey: .configID)
    }
}

// MARK: - Keys

extension Keybind {
    func effectiveKeys(triggerKey: Set<CGKeyCode>) -> Set<CGKeyCode> {
        bypassTriggerKey ? keys : triggerKey.union(keys)
    }

    /// Keybinds sharing their keys with another. None of them run, so nothing depends on their order
    static func conflictingIDs(in keybinds: [Keybind], triggerKey: Set<CGKeyCode>) -> Set<UUID> {
        let idsByKeys = Dictionary(grouping: keybinds.filter { !$0.keys.isEmpty }) { $0.effectiveKeys(triggerKey: triggerKey) }
        return Set(idsByKeys.values.filter { $0.count > 1 }.flatMap { $0.map(\.id) })
    }
}

// MARK: - Defaults

extension Keybind {
    static let defaults: [Keybind] = [
        Keybind(configID: "maximize", keys: [.kVK_Space], target: .action(WindowAction(.maximize))),
        Keybind(configID: "center", keys: [.kVK_Return], target: .action(WindowAction(.center))),
        Keybind(
            configID: "top-cycle",
            keys: [.kVK_UpArrow],
            target: .action(WindowAction(.init(localized: "Top Cycle"), cycle: [.init(.topHalf), .init(.topThird), .init(.topTwoThirds)]))
        ),
        Keybind(
            configID: "bottom-cycle",
            keys: [.kVK_DownArrow],
            target: .action(WindowAction(.init(localized: "Bottom Cycle"), cycle: [.init(.bottomHalf), .init(.bottomThird), .init(.bottomTwoThirds)]))
        ),
        Keybind(
            configID: "right-cycle",
            keys: [.kVK_RightArrow],
            target: .action(WindowAction(.init(localized: "Right Cycle"), cycle: [.init(.rightHalf), .init(.rightThird), .init(.rightTwoThirds)]))
        ),
        Keybind(
            configID: "left-cycle",
            keys: [.kVK_LeftArrow],
            target: .action(WindowAction(.init(localized: "Left Cycle"), cycle: [.init(.leftHalf), .init(.leftThird), .init(.leftTwoThirds)]))
        ),
        Keybind(
            configID: "top-left-quarter",
            keys: [.kVK_UpArrow, .kVK_LeftArrow],
            target: .action(WindowAction(.topLeftQuarter))
        ),
        Keybind(
            configID: "top-right-quarter",
            keys: [.kVK_UpArrow, .kVK_RightArrow],
            target: .action(WindowAction(.topRightQuarter))
        ),
        Keybind(
            configID: "bottom-right-quarter",
            keys: [.kVK_DownArrow, .kVK_RightArrow],
            target: .action(WindowAction(.bottomRightQuarter))
        ),
        Keybind(
            configID: "bottom-left-quarter",
            keys: [.kVK_DownArrow, .kVK_LeftArrow],
            target: .action(WindowAction(.bottomLeftQuarter))
        )
    ]
}

extension Keybind: CustomStringConvertible {
    var description: String {
        "Keybind(keys: \(keys), target: \(target.link.map { "link to \($0.kind) \($0.id)" } ?? target.action.map(String.init(describing:)) ?? "none"))"
    }
}
