//
//  GestureBinding.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-16.
//

import SwiftUI
import TOML
import Tome

struct GestureBinding: ConfigurationIdentifiable, Codable, Hashable, Sendable {
    static let category = "gesture"

    var id: UUID
    var fingerCount: Int
    /// `nil` until the user picks a gesture, like a keybind with no keys
    var kind: Kind?
    var configID: String?
    var target: ActionTarget
    var activationZone: ActivationZone

    var reference: ActionTarget { .gestureBinding(referenceID) }

    init(
        id: UUID = .init(),
        fingerCount: Int = 2,
        kind: Kind? = nil,
        configID: String? = nil,
        target: ActionTarget = .windowAction(.init(.noAction)),
        activationZone: ActivationZone = .titlebar
    ) {
        self.id = id
        self.fingerCount = fingerCount
        self.kind = kind
        self.configID = configID
        self.target = kind == .radialMenu ? .radialMenuMode : target
        self.activationZone = activationZone
    }

    enum Kind: String, Codable, Hashable, CaseIterable, Tome.Serializable {
        /// Swipe gesture that maps angle to radial menu directional slots.
        case radialMenu = "radial-menu"
        /// Directional swipe gestures that trigger a single action.
        case swipeUp = "swipe-up"
        case swipeDown = "swipe-down"
        case swipeLeft = "swipe-left"
        case swipeRight = "swipe-right"
        /// Magnify Out gesture (fingers together, scale < 1).
        case magnifyOut = "pinch"
        /// Magnify In gesture (fingers apart, scale > 1).
        case magnifyIn = "spread"

        var displayName: String {
            switch self {
            case .radialMenu: String(localized: "Both", comment: "Gesture kind: swipe and magnify gestures; opens the radial menu")
            case .swipeUp: String(localized: "Swipe Up", comment: "Gesture kind: directional swipe")
            case .swipeDown: String(localized: "Swipe Down", comment: "Gesture kind: directional swipe")
            case .swipeLeft: String(localized: "Swipe Left", comment: "Gesture kind: directional swipe")
            case .swipeRight: String(localized: "Swipe Right", comment: "Gesture kind: directional swipe")
            case .magnifyOut: String(localized: "Pinch", comment: "Gesture kind: pinch (fingers move together, zooming out)")
            case .magnifyIn: String(localized: "Spread", comment: "Gesture kind: spread (fingers move apart, zooming in)")
            }
        }

        var image: Image {
            switch self {
            case .radialMenu: Image(.loop)
            case .swipeUp: Image(systemName: "arrow.up")
            case .swipeDown: Image(systemName: "arrow.down")
            case .swipeLeft: Image(systemName: "arrow.left")
            case .swipeRight: Image(systemName: "arrow.right")
            case .magnifyOut: Image(systemName: "arrow.up.right.and.arrow.down.left")
            case .magnifyIn: Image(systemName: "arrow.down.left.and.arrow.up.right")
            }
        }

        var radialMenuAngle: Angle? {
            switch self {
            case .swipeUp: .degrees(-90)
            case .swipeRight: .degrees(0)
            case .swipeDown: .degrees(90)
            case .swipeLeft: .degrees(180)
            case .radialMenu, .magnifyOut, .magnifyIn: nil
            }
        }

        var isDirectionalSwipe: Bool {
            switch self {
            case .swipeUp, .swipeDown, .swipeLeft, .swipeRight:
                true
            default:
                false
            }
        }
    }

    enum ActivationZone: String, Codable, Hashable, CaseIterable, Tome.Serializable {
        case titlebar = "title-bar"
        case anywhere

        var displayName: String {
            switch self {
            case .titlebar: String(localized: "Title Bar Only", comment: "Gesture activation zone restricted to a window's title bar")
            case .anywhere: String(localized: "Anywhere", comment: "Gesture activation zone covers the entire window")
            }
        }

        var systemImage: String {
            switch self {
            case .titlebar: "menubar.rectangle"
            case .anywhere: "rectangle.dashed"
            }
        }
    }
}

// MARK: - Naming

extension GestureBinding {
    var effectiveActivationZone: ActivationZone {
        fingerCount <= 2 ? .titlebar : activationZone
    }

    /// `nil` while the gesture has no trigger
    var displayName: String? {
        switch kind {
        case nil:
            nil
        case .radialMenu:
            String(
                localized: "\(fingerCount)-finger Swipe or Magnify",
                comment: "Default title describing how to activate a radial menu gesture. Argument is the finger count."
            )
        case let .some(kind):
            String(
                localized: "\(fingerCount)-finger \(kind.displayName)",
                comment: "Default title describing a gesture. First argument is the finger count, second is the gesture kind name (e.g. '2-finger Pinch' or '3-finger Swipe Right')."
            )
        }
    }
}

// MARK: - Conflict Detection

extension GestureBinding {
    static func activeGestures(in gestures: [GestureBinding]) -> [GestureBinding] {
        let conflictingIDs = conflictingIDs(in: gestures)
        return gestures.filter { $0.kind != nil && !conflictingIDs.contains($0.id) }
    }

    func conflicts(with other: GestureBinding) -> Bool {
        guard id != other.id, kind != nil, fingerCount == other.fingerCount else {
            return false
        }

        return kind == other.kind
    }

    /// Returns IDs for gestures that take over a direction of an active radial menu gesture.
    static func radialMenuOverrideIDs(in gestures: [GestureBinding]) -> Set<UUID> {
        let active = activeGestures(in: gestures)
        let radialFingerCounts = Set(active.filter { $0.kind == .radialMenu }.map(\.fingerCount))
        return Set(
            active
                .filter { $0.kind != .radialMenu && radialFingerCounts.contains($0.fingerCount) }
                .map(\.id)
        )
    }

    static func conflictingIDs(in gestures: [GestureBinding]) -> Set<UUID> {
        var result = Set<UUID>()
        for i in gestures.indices {
            for j in (i + 1) ..< gestures.count {
                if gestures[i].conflicts(with: gestures[j]) {
                    result.insert(gestures[i].id)
                    result.insert(gestures[j].id)
                }
            }
        }
        return result
    }
}

// MARK: - Defaults

extension GestureBinding {
    static let defaults: [GestureBinding] = [
        GestureBinding(
            fingerCount: 2,
            kind: .radialMenu,
            target: .radialMenuMode,
            activationZone: .titlebar
        )
    ]
}

extension GestureBinding: CustomStringConvertible {
    var description: String {
        "GestureBinding(fingerCount: \(fingerCount), kind: \(kind.map { "\($0)" } ?? "unset"))"
    }
}

// MARK: - Configuration

extension GestureBinding {
    private static let fingerRange = 2...5

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, fingers, kind, zone
    }

    init(from decoder: Decoder) throws {
        let table = try decoder.container(keyedBy: CodingKeys.self)
        let fingers = try table.decodeIfPresent(Int.self, forKey: .fingers) ?? 2
        guard Self.fingerRange.contains(fingers) else {
            throw DecodingError.dataCorruptedError(forKey: .fingers, in: table, debugDescription: "Fingers must be from 2 to 5, found \(ConfigurationMessage.quoted(String(fingers)))")
        }
        var kind = try table.decodeIfPresent(Kind.self, forKey: .kind)
        let configID = try table.decodeIfPresent(String.self, forKey: .id)
        try configID.map { try ConfigurationIdentity.validate($0, as: "gesture id") }

        let hasTarget = try ActionTarget.isPresent(in: decoder)
        var target = ActionTarget.windowAction(.init(.noAction))
        if hasTarget {
            target = try ActionTarget(from: decoder)
        }
        if kind == .radialMenu {
            guard !hasTarget else {
                throw DecodingError.dataCorruptedError(forKey: .kind, in: table, debugDescription: "A radial-menu gesture can't have another target")
            }
            target = .radialMenuMode
        }
        try self.init(
            fingerCount: fingers,
            kind: kind,
            configID: configID,
            target: target,
            activationZone: table.decodeIfPresent(ActivationZone.self, forKey: .zone) ?? .titlebar
        )
        deriveIdentity()
    }

    func encode(to encoder: Encoder) throws {
        guard Self.fingerRange.contains(fingerCount) else {
            throw EncodingError.invalidValue(fingerCount, .init(codingPath: encoder.codingPath, debugDescription: "Gesture fingers must be from 2 to 5, found \(ConfigurationMessage.quoted(String(fingerCount)))"))
        }
        guard (target == .radialMenuMode) == (kind == .radialMenu) else {
            throw EncodingError.invalidValue(target, .init(codingPath: encoder.codingPath, debugDescription: "Only a radial-menu gesture selects the whole menu"))
        }
        var table = encoder.container(keyedBy: CodingKeys.self)
        try table.encodeIfPresent(configID, forKey: .id)
        try table.encode(fingerCount, forKey: .fingers)
        if let kind { try table.encode(kind, forKey: .kind) }
        try table.encode(activationZone, forKey: .zone)
        if target != .radialMenuMode { try target.encode(to: encoder) }
    }
}
