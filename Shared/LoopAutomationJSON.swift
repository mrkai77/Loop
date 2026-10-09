//
//  LoopAutomationJSON.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import Foundation

enum LoopAutomationJSON {
    /// Long enough for an app to launch when targeting by bundle ID; the CLI waits a little longer than Loop does
    static let commandTimeout: Duration = .seconds(10)

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func encodeString(_ response: LoopAutomationResponse) -> String {
        guard let data = try? makeEncoder().encode(response) else {
            return #"{"error":{"message":"Couldn’t encode the response"},"success":false}"#
        }

        return String(decoding: data, as: UTF8.self)
    }

    static func encodedFailure(message: String) -> String {
        encodeString(LoopAutomationResponse(error: LoopAutomationError(message: message)))
    }

    static func decodeResponse(from string: String) throws -> LoopAutomationResponse {
        try JSONDecoder().decode(LoopAutomationResponse.self, from: Data(string.utf8))
    }
}
