//
//  ExecCommand.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import ArgumentParser
import Foundation

struct ActionIdentifier: ExpressibleByArgument {
    let value: UUID

    init?(argument: String) {
        guard let value = UUID(uuidString: argument) else {
            return nil
        }

        self.value = value
    }
}

struct ExecCommand: ParsableCommand, CLIRequestCommand {
    static let configuration = CommandConfiguration(
        commandName: "exec",
        abstract: "Execute a preset action, a custom action, or an action by UUID"
    )

    @Option(name: .customLong("preset"), help: "Execute a preset action by name")
    var preset: String?

    @Option(name: .customLong("custom"), help: "Execute a custom action by name")
    var custom: String?

    @Option(name: .customLong("id"), help: "Execute an action by UUID")
    var actionID: ActionIdentifier?

    @OptionGroup
    var targetOptions: TargetOptions

    @OptionGroup
    var outputOptions: OutputOptions

    var outputMode: OutputOptions.Mode {
        outputOptions.outputMode
    }

    func validate() throws {
        let selectorCount = (preset == nil ? 0 : 1)
            + (custom == nil ? 0 : 1)
            + (actionID == nil ? 0 : 1)
        guard selectorCount == 1 else {
            throw ValidationError("Exactly one of --preset, --custom, or --id is required")
        }
    }

    func makeRequest() throws -> CLIRequest {
        let queryItems = targetOptions.queryItems

        if let preset {
            return CLIRequest(
                routeComponents: ["preset", preset],
                queryItems: queryItems
            )
        }

        if let custom {
            return CLIRequest(
                routeComponents: ["custom", custom],
                queryItems: queryItems
            )
        }

        if let actionID {
            return CLIRequest(
                routeComponents: ["id", actionID.value.uuidString.lowercased()],
                queryItems: queryItems
            )
        }

        throw ValidationError("Exactly one of --preset, --custom, or --id is required")
    }
}
