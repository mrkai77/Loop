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

    func execute(_ request: CLIRequest, outputMode: CLIOutputMode) throws {
        let response = try socketClient.send(request)
        guard response.isSuccess else {
            throw errorFormatter.error(from: response)
        }

        print(outputFormatter.format(response, mode: outputMode))
    }

    func resolveKeybind(named displayName: String) throws -> CLIActionDescriptor {
        let response = try socketClient.send(
            CLIRequest(routeComponents: ["list", "actions", "keybinds"])
        )

        guard response.isSuccess else {
            throw errorFormatter.error(from: response)
        }

        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = response.keybindActions.filter {
            $0.name.caseInsensitiveCompare(normalizedDisplayName) == .orderedSame
        }

        if let match = matches.only {
            return match
        }

        if matches.isEmpty {
            throw errorFormatter.runtimeError(
                """
                Unknown keybind name: \(displayName)
                Try: \(Self.executableName) list actions --keybinds-only
                """
            )
        }

        let matchingIdentifiers = matches.map(\.idString).joined(separator: ", ")
        throw errorFormatter.runtimeError(
            """
            Multiple keybind actions share the name "\(displayName)".
            Matching IDs: \(matchingIdentifiers)
            Try: \(Self.executableName) exec --id <uuid>
            """
        )
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
