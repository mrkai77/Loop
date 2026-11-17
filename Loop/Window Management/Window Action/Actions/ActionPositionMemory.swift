//
//  ActionPositionMemory.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation

/// Keeps the inactive position mode's values, so toggling between anchor and coordinates loses nothing.
struct ActionPositionMemory: Equatable {
    private var anchor: CustomWindowActionAnchor?
    private var coordinates: (x: ScreenLength?, y: ScreenLength?)?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.anchor == rhs.anchor && lhs.coordinates?.x == rhs.coordinates?.x && lhs.coordinates?.y == rhs.coordinates?.y
    }

    mutating func switched(from position: ActionPosition?, toCoordinates: Bool) -> ActionPosition {
        switch position {
        case let .anchor(value): anchor = value
        case let .coordinates(x, y): coordinates = (x, y)
        case nil: break
        }
        if toCoordinates {
            let remembered = coordinates ?? (x: ScreenLength(0), y: ScreenLength(0))
            return .coordinates(x: remembered.x, y: remembered.y)
        }
        return .anchor(anchor ?? .center)
    }
}
