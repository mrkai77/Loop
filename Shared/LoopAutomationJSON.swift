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
            return #"{"error":{"availableRoutes":null,"code":"failed","message":"Couldn’t encode the response","replacementRoute":null},"result":null,"success":false,"version":1}"#
        }

        return String(decoding: data, as: UTF8.self)
    }

    static func encodedFailure(_ code: LoopAutomationErrorCode, message: String) -> String {
        encodeString(LoopAutomationResponse(error: LoopAutomationError(code, message: message)))
    }

    static func decodeResponse(from string: String) throws -> LoopAutomationResponse {
        try JSONDecoder().decode(LoopAutomationResponse.self, from: Data(string.utf8))
    }
}
