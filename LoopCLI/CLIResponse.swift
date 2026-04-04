//
//  CLIResponse.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import Foundation

struct CLIResponse {
    let rawOutput: String
    let automationResponse: LoopAutomationResponse?

    init(rawOutput: String) {
        let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawOutput = trimmedOutput
        self.automationResponse = try? LoopAutomationJSON.decodeResponse(from: trimmedOutput)
    }

    var isSuccess: Bool {
        automationResponse?.success == true
    }

    var result: LoopAutomationResult? {
        automationResponse?.result
    }

    var automationError: LoopAutomationError? {
        automationResponse?.error
    }
}
