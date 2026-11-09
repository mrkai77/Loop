//
//  GestureBinding.swift
//  Loop
//
//  Created by Kai Azim on 2026-04-16.
//

import Defaults
import SwiftUI

struct GestureBinding: Identifiable, Codable, Hashable, Defaults.Serializable {
    let id: UUID
    var fingerCount: Int
    /// `nil` until the user picks a gesture, like a keybind with no keys
    var kind: Kind?
    var action: Action
    var activationZone: ActivationZone

    init(
        id: UUID = .init(),
        fingerCount: Int = 2,
        kind: Kind? = nil,
        action: Action = .singleAction(.custom(.init(.noAction))),
        activationZone: ActivationZone = .titlebar
    ) {
        self.id = id
        self.fingerCount = fingerCount
        self.kind = kind
        self.action = action
        self.activationZone = activationZone
    }

    enum Kind: Codable, Hashable, CaseIterable {
        /// Swipe gesture that maps angle to radial menu directional slots.
        case radialMenu
        /// Directional swipe gestures that trigger a single action.
        case swipeUp, swipeDown, swipeLeft, swipeRight
        /// Magnify Out gesture (fingers together, scale < 1).
        case magnifyOut
        /// Magnify In gesture (fingers apart, scale > 1).
        case magnifyIn

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

    enum Action: Codable, Hashable {
        /// Uses `RadialMenuAction.userConfiguredActions` for radial menu swipe mode.
        case radialMenuActions
        /// A single action, either custom or referencing a keybind.
        case singleAction(RadialMenuAction.ActionType)
    }

    enum ActivationZone: String, Codable, Hashable, CaseIterable {
        case titlebar
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
    /// Returns gestures that have a trigger set and don't conflict with another gesture.
    static func activeGestures(in gestures: [GestureBinding]) -> [GestureBinding] {
        let conflictingIDs = conflictingIDs(in: gestures)
        return gestures.filter { $0.kind != nil && !conflictingIDs.contains($0.id) }
    }

    /// Two gestures conflict when they have the same finger count and kind.
    /// A swipe or magnify sharing a radial menu's finger count overrides that direction instead.
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

    /// Returns the IDs of all gestures that conflict with at least one other gesture in the array.
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
            action: .radialMenuActions,
            activationZone: .titlebar
        )
    ]
}

extension GestureBinding: CustomStringConvertible {
    var description: String {
        "GestureBinding(fingerCount: \(fingerCount), kind: \(kind.map { "\($0)" } ?? "unset"))"
    }
}
