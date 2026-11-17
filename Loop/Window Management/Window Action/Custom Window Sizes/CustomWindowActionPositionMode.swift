//
//  CustomWindowActionPositionMode.swift
//  Loop
//
//  Created by Kai Azim on 2024-03-22.
//

import SwiftUI
import Tome
import TOML

enum CustomWindowActionPositionMode: String, Codable, CaseIterable, Identifiable, Tome.Serializable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        let index = raw - 0
        guard Self.allCases.indices.contains(index) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown position mode \(ConfigurationMessage.quoted(String(raw)))")
        }
        self = Self.allCases[index]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.allCases.firstIndex(of: self)! + 0)
    }

    var id: Self { self }

    case generic
    case coordinates
}
