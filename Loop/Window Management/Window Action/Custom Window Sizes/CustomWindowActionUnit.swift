//
//  CustomWindowActionUnit.swift
//  Loop
//
//  Created by Kai Azim on 2024-01-01.
//

import SwiftUI
import Tome
import TOML

enum CustomWindowActionUnit: String, Codable, CaseIterable, Identifiable, Tome.Serializable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        let index = raw - 0
        guard Self.allCases.indices.contains(index) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown unit \(ConfigurationMessage.quoted(String(raw)))")
        }
        self = Self.allCases[index]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.allCases.firstIndex(of: self)! + 0)
    }

    var id: Self { self }

    case pixels
    case percentage

    var suffix: String {
        switch self {
        case .pixels:
            String(localized: "px", comment: "Unit symbol: pixels")
        case .percentage:
            String(localized: "%", comment: "Unit symbol: percentage")
        }
    }

    var fractionLength: NumberFormatStyleConfiguration.Precision {
        switch self {
        case .pixels:
            .fractionLength(0)
        case .percentage:
            .fractionLength(1...3)
        }
    }

    func roundIfNeeded(_ value: Double) -> Double {
        switch self {
        case .pixels:
            value.rounded(.towardZero)
        case .percentage:
            (value * 1000.0).rounded(.towardZero) / 1000.0
        }
    }
}
