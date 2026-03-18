//
//  LoopAutomationJSON.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import Foundation

enum LoopAutomationJSON {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    static func encodeString(_ response: LoopAutomationResponse) throws -> String {
        let data = try makeEncoder().encode(response)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                response,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to encode Loop automation response as UTF-8"
                )
            )
        }

        return string
    }

    static func decodeResponse(from string: String) throws -> LoopAutomationResponse {
        try makeDecoder().decode(LoopAutomationResponse.self, from: Data(string.utf8))
    }
}
