//
//  NullEncoded.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import Foundation

/// Encodes `nil` as `null` instead of leaving the key out. Decodes `null`, a missing key, or a value this version can't read,
/// such as a result kind from a newer Loop, as `nil`, so the rest of the response is still read.
@propertyWrapper
struct NullEncoded<Value: Codable>: Codable {
    var wrappedValue: Value?

    init(wrappedValue: Value?) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = container.decodeNil() ? nil : try? container.decode(Value.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue {
            try container.encode(wrappedValue)
        } else {
            try container.encodeNil()
        }
    }
}

extension NullEncoded: Sendable where Value: Sendable {}

extension KeyedDecodingContainer {
    /// Synthesized decoding would otherwise fail when the key is missing, rather than decoding `nil`
    func decode<Value>(_ type: NullEncoded<Value>.Type, forKey key: Key) throws -> NullEncoded<Value> {
        try decodeIfPresent(type, forKey: key) ?? NullEncoded(wrappedValue: nil)
    }
}
