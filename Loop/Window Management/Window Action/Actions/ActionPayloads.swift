//
//  ActionPayloads.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
import TOML

/// A length in points or a percentage of the screen.
struct ScreenLength: Codable, Hashable {
    enum Unit: String, Hashable, CaseIterable {
        case percent, points

        var decimalPlaces: Int { self == .percent ? 2 : 1 }
        var format: FloatingPointFormatStyle<Double> {
            .number.precision(.fractionLength(0...decimalPlaces))
        }
    }

    var value: Double
    var unit: Unit

    init(_ value: Double, unit: Unit = .percent) {
        self.value = value
        self.unit = unit
    }

    /// Used by the UI and migration. Hand-written values keep their precision.
    func roundedToDisplayPrecision() -> Self {
        let scale = pow(10.0, Double(unit.decimalPlaces))
        return Self((value * scale).rounded() / scale, unit: unit)
    }

    /// Accepts `"25%"`, `"250pt"`, `"250px"` (points), or a bare number of points.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = try Self.parse(text, in: container)
        } else if let integer = try? container.decode(Int64.self) {
            self = Self(Double(integer), unit: .points)
        } else if let float = try? container.decode(Double.self) {
            self = Self(float, unit: .points)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a quoted length or a number of points, found \(decoder.unexpectedValueDescription())")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(configurationString())
    }

    private static func parse(_ text: String, in container: SingleValueDecodingContainer) throws -> Self {
        let unit: Unit
        let number: Substring
        if text.hasSuffix("%") {
            unit = .percent
            number = text.dropLast()
        } else if text.hasSuffix("pt") || text.hasSuffix("px") {
            unit = .points
            number = text.dropLast(2)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a length ending in %, pt or px, found \(ConfigurationMessage.quoted(text))")
        }
        guard let value = Double(number) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected a number followed by %, pt or px, found \(ConfigurationMessage.quoted(text))")
        }
        return Self(value, unit: unit)
    }

    func configurationString() -> String {
        let number = value.rounded() == value && abs(value) < Double(Int64.max) ? String(Int64(value)) : String(value)
        return number + (unit == .percent ? "%" : "pt")
    }
}

enum ActionSize: Codable, Hashable {
    case custom(width: ScreenLength?, height: ScreenLength?)
    case preserve
    case initial

    static let defaultCustom = Self.custom(width: ScreenLength(80), height: ScreenLength(80))

    /// `"preserve"`, `"initial"`, or a table of `width` and `height`.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            switch text {
            case "preserve": self = .preserve
            case "initial": self = .initial
            default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown size \(ConfigurationMessage.quoted(text))")
            }
        } else {
            let dimensions = try container.decode(ActionDimensions.self)
            self = .custom(width: dimensions.width, height: dimensions.height)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .preserve: try container.encode("preserve")
        case .initial: try container.encode("initial")
        case let .custom(width, height): try container.encode(ActionDimensions(width: width, height: height))
        }
    }
}

enum ActionPosition: Codable, Hashable {
    case anchor(CustomWindowActionAnchor)
    case coordinates(x: ScreenLength?, y: ScreenLength?)

    private struct Coordinates: Codable {
        var x: ScreenLength?
        var y: ScreenLength?
    }

    /// An anchor name such as `"bottom-left"`, or a table of `x` and `y`.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let name = try? container.decode(String.self) {
            guard let anchor = CustomWindowActionAnchor(rawValue: name) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown position \(ConfigurationMessage.quoted(name))")
            }
            self = .anchor(anchor)
        } else {
            try decoder.requireKeys(["x", "y"], message: "Expected only 'x' and 'y' in a position table")
            let coordinates = try container.decode(Coordinates.self)
            self = .coordinates(x: coordinates.x, y: coordinates.y)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .anchor(anchor): try container.encode(anchor.rawValue)
        case let .coordinates(x, y): try container.encode(Coordinates(x: x, y: y))
        }
    }
}

/// Also used by previews without a live window.
struct ActionDimensions: Codable, Hashable {
    var width: ScreenLength?
    var height: ScreenLength?

    init(width: ScreenLength? = nil, height: ScreenLength? = nil) {
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case width, height }

    init(from decoder: Decoder) throws {
        try decoder.requireKeys(["width", "height"], message: "Expected only 'width' and 'height' in a size table")
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.width = try container.decodeIfPresent(ScreenLength.self, forKey: .width)
        self.height = try container.decodeIfPresent(ScreenLength.self, forKey: .height)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue _: Int) { nil }
}

private extension Decoder {
    func requireKeys(_ allowed: Set<String>, message: String) throws {
        let keys = try container(keyedBy: AnyCodingKey.self).allKeys.map(\.stringValue)
        let extra = Set(keys).subtracting(allowed).sorted()
        guard extra.isEmpty else {
            let found = extra.map { ConfigurationMessage.quoted($0) }.joined(separator: ", ")
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "\(message), found \(found)"))
        }
    }

    /// Describes a value that is neither a string nor a number, for a "found" message.
    func unexpectedValueDescription() -> String {
        if let single = try? singleValueContainer(), let flag = try? single.decode(Bool.self) { return ConfigurationMessage.quoted(String(flag)) }
        if (try? container(keyedBy: AnyCodingKey.self)) != nil { return "a table" }
        if (try? unkeyedContainer()) != nil { return "an array" }
        return "a different kind of value"
    }
}

struct FrameAction: Codable, Hashable {
    var name: String?
    var size: ActionSize {
        didSet {
            switch size {
            case .custom: fallbackSize = .init()
            case .preserve, .initial:
                if case let .custom(width, height) = oldValue {
                    fallbackSize = .init(width: width, height: height)
                }
            }
        }
    }

    var position: ActionPosition
    var fallbackSize: ActionDimensions {
        didSet { if case .custom = size { fallbackSize = .init() } }
    }

    init(
        name: String? = nil,
        size: ActionSize = .defaultCustom,
        position: ActionPosition = .anchor(.center),
        fallbackSize: ActionDimensions = .init()
    ) {
        self.name = name
        self.size = size
        self.position = position
        if case .custom = size { self.fallbackSize = .init() }
        else { self.fallbackSize = fallbackSize }
    }

    private enum CodingKeys: String, CodingKey {
        case name, size, position
        case fallbackSize = "fallback-size"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decodeIfPresent(String.self, forKey: .name)
        self.size = try container.decode(ActionSize.self, forKey: .size)
        self.position = try container.decode(ActionPosition.self, forKey: .position)
        let fallback = try container.decodeIfPresent(ActionDimensions.self, forKey: .fallbackSize) ?? .init()
        if case .custom = size { self.fallbackSize = .init() }
        else { self.fallbackSize = fallback }
    }
}

struct CycleAction: Codable, Hashable {
    var name: String?
    var steps: [ActionTarget] = []
}
