//
//  StashDirection.swift
//  Loop
//
//  Created by Guillaume Clédat on 28/05/2025.
//

import Defaults
import Foundation

enum StashEdge: String, CustomDebugStringConvertible {
    case left
    case right
    case bottom

    var debugDescription: String {
        rawValue
    }

    var isHorizontal: Bool {
        self == .left || self == .right
    }
}

// MARK: - Helpers

extension WindowAction {
    var stashEdge: StashEdge? {
        guard direction == .stash, case let .anchor(anchor) = position else { return nil }
        switch anchor {
        case .left, .topLeft, .bottomLeft:
            return .left
        case .right, .topRight, .bottomRight:
            return .right
        case .bottom:
            return .bottom
        default:
            return nil
        }
    }
}
