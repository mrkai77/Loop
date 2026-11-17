//
//  CustomWindowActionAnchor.swift
//  Loop
//
//  Created by Kai Azim on 2024-01-01.
//

import Luminare
import SwiftUI
import Tome
import TOML

enum CustomWindowActionAnchor: String, Codable, CaseIterable, Identifiable, LuminareSelectionData, Tome.Serializable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        let index = raw - -1
        guard Self.allCases.indices.contains(index) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown anchor \(ConfigurationMessage.quoted(String(raw)))")
        }
        self = Self.allCases[index]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.allCases.firstIndex(of: self)! + -1)
    }

    var id: Self { self }

    case none
    case topLeft = "top-left"
    case top
    case topRight = "top-right"
    case right
    case bottomRight = "bottom-right"
    case bottom
    case bottomLeft = "bottom-left"
    case left
    case center
    case macOSCenter = "macos-center"

    var isSelectable: Bool {
        self != .none
    }
}

extension CustomWindowActionAnchor {
    private static var iconActionCache: [CustomWindowActionAnchor: WindowAction] = [:]

    var iconAction: WindowAction? {
        // Prevents re-initializing the same action multiple times
        if let cachedAction = CustomWindowActionAnchor.iconActionCache[self] {
            return cachedAction
        }

        let newAction: WindowAction? = switch self {
        case .none: nil
        case .topLeft: .init(.topLeftQuarter)
        case .top: .init(.topHalf)
        case .topRight: .init(.topRightQuarter)
        case .right: .init(.rightHalf)
        case .bottomRight: .init(.bottomRightQuarter)
        case .bottom: .init(.bottomHalf)
        case .bottomLeft: .init(.bottomLeftQuarter)
        case .left: .init(.leftHalf)
        case .center: .init(.center)
        case .macOSCenter: .init(.macOSCenter)
        }

        CustomWindowActionAnchor.iconActionCache[self] = newAction
        return newAction
    }
}
