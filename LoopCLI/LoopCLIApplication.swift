//
//  LoopCLIApplication.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import Foundation

final class LoopCLIApplication {
    static let shared = LoopCLIApplication()

    static let executableName = URL(
        fileURLWithPath: CommandLine.arguments.first ?? "loop-cli"
    ).lastPathComponent

    private let socketClient: LoopSocketClient
    private let errorFormatter: CLIErrorFormatter
    private let outputFormatter: CLIOutputFormatter

    init(
        socketClient: LoopSocketClient = LoopSocketClient(),
        errorFormatter: CLIErrorFormatter = CLIErrorFormatter(executableName: LoopCLIApplication.executableName),
        outputFormatter: CLIOutputFormatter = CLIOutputFormatter()
    ) {
        self.socketClient = socketClient
        self.errorFormatter = errorFormatter
        self.outputFormatter = outputFormatter
    }

    func execute(_ request: CLIRequest, outputConfiguration: CLIOutputConfiguration) throws {
        let response = try socketClient.send(request)
        guard response.isSuccess else {
            throw errorFormatter.error(from: response)
        }

        print(outputFormatter.format(response, configuration: outputConfiguration))
    }
}
