//
//  CustomWindowActionSizeMode.swift
//  Loop
//
//  Created by Kai Azim on 2024-03-22.
//

import SwiftUI
import Tome
import TOML

enum CustomWindowActionSizeMode: String, Codable, CaseIterable, Identifiable, Tome.Serializable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(Int.self)
        let index = raw - 0
        guard Self.allCases.indices.contains(index) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown size mode \(ConfigurationMessage.quoted(String(raw)))")
        }
        self = Self.allCases[index]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.allCases.firstIndex(of: self)! + 0)
    }

    var id: Self { self }

    case custom
    case preserve
    case initial

    var name: LocalizedStringKey {
        switch self {
        case .custom:
            "Custom"
        case .preserve:
            "Preserve Size"
        case .initial:
            "Initial Size"
        }
    }

    var image: Image {
        switch self {
        case .custom:
            Image(systemName: "ruler.fill")
        case .preserve:
            Image(systemName: "lock.fill")
        case .initial:
            Image(systemName: "backward.fill")
        }
    }
}
