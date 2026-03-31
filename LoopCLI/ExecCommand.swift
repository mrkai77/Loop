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
        abstract: "Execute a direction action, keybind-backed action, or UUID-addressed action"
    )

    @Option(name: .customLong("direction"), help: "Execute a built-in direction action")
    var direction: String?

    @Option(name: .customLong("keybind"), help: "Execute a keybind-backed action by display name")
    var keybind: String?

    @Option(name: .customLong("id"), help: "Execute any action by UUID")
    var actionID: ActionIdentifier?

    @OptionGroup
    var targetOptions: TargetOptions

    @OptionGroup
    var outputOptions: OutputOptions

    var outputConfiguration: CLIOutputConfiguration {
        CLIOutputConfiguration(
            mode: outputOptions.outputMode,
            showIDs: false
        )
    }

    func validate() throws {
        let selectorCount = (direction == nil ? 0 : 1)
            + (keybind == nil ? 0 : 1)
            + (actionID == nil ? 0 : 1)
        guard selectorCount == 1 else {
            throw ValidationError("Exactly one of --direction, --keybind, or --id is required")
        }
    }

    func makeRequest(using application: LoopCLIApplication) throws -> CLIRequest {
        let queryItems = targetOptions.queryItems

        if let direction {
            return CLIRequest(
                routeComponents: ["direction", direction],
                queryItems: queryItems
            )
        }

        if let keybind {
            let descriptor = try application.resolveKeybind(named: keybind)
            return CLIRequest(
                routeComponents: ["id", descriptor.idString],
                queryItems: queryItems
            )
        }

        if let actionID {
            return CLIRequest(
                routeComponents: ["id", actionID.value.uuidString.lowercased()],
                queryItems: queryItems
            )
        }

        throw ValidationError("Exactly one of --direction, --keybind, or --id is required")
    }
}
