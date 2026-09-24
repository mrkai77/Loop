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
    var name: String?
    var fingerCount: Int
    var kind: Kind
    var action: Action
    var activationZone: ActivationZone

    init(
        id: UUID = .init(),
        name: String? = nil,
        fingerCount: Int = 2,
        kind: Kind = .radialMenu,
        action: Action = .radialMenuActions,
        activationZone: ActivationZone = .titlebar
    ) {
        self.id = id
        self.name = name
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
            case .magnifyOut: String(localized: "Pinch", comment: "Gesture kind: magnify outward")
            case .magnifyIn: String(localized: "Spread", comment: "Gesture kind: magnify inward")
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

        /// Directional swipes point the radial menu the way the fingers moved, like its slots
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
            case .titlebar: String(localized: "Titlebar Only", comment: "Gesture activation zone restricted to a window's titlebar")
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

    var defaultName: String {
        switch kind {
        case .radialMenu:
            String(
                localized: "\(fingerCount)-finger Swipe or Magnify",
                comment: "Default title describing how to activate a radial menu gesture. Argument is the finger count."
            )
        default:
            String(
                localized: "\(fingerCount)-finger \(kind.displayName)",
                comment: "Default title describing a gesture. First argument is the finger count, second is the gesture kind name (e.g. 'Magnify In', 'Swipe Up')."
            )
        }
    }

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }

        return defaultName
    }
}

// MARK: - No Action

extension GestureBinding {
    var resolvesToNoAction: Bool {
        switch action {
        case .radialMenuActions:
            false
        case let .singleAction(actionType):
            (actionType.resolvedAction?.direction ?? .noAction) == .noAction
        }
    }
}

// MARK: - Conflict Detection

extension GestureBinding {
    /// Returns IDs for actionable gestures that conflict with at least one other actionable gesture.
    static func conflictingActionableIDs(in gestures: [GestureBinding]) -> Set<UUID> {
        conflictingIDs(in: gestures.filter { !$0.resolvesToNoAction })
    }

    /// Returns gestures that don't conflict with another actionable gesture.
    static func activeGestures(in gestures: [GestureBinding]) -> [GestureBinding] {
        let conflictingIDs = conflictingActionableIDs(in: gestures)
        return gestures.filter { !conflictingIDs.contains($0.id) }
    }

    /// Two gestures conflict when they have the same finger count and their kinds overlap.
    /// Radial menu consumes both swipe and magnify, so it conflicts with ANY other gesture at the same finger count.
    func conflicts(with other: GestureBinding) -> Bool {
        guard id != other.id, fingerCount == other.fingerCount else {
            return false
        }

        // Radial menu uses both swipe and magnify, so it conflicts with everything at the same finger count.
        if kind == .radialMenu || other.kind == .radialMenu {
            return true
        }

        // Same kind always conflicts
        if kind == other.kind {
            return true
        }

        return false
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
