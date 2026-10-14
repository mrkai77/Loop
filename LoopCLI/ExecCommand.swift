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

    /// One per selector given; `validate()` makes sure there's exactly one
    private var routes: [LoopRoute] {
        let selected: [LoopRoute?] = [
            preset.map { .exec(.preset, name: $0) },
            custom.map { .exec(.custom, name: $0) },
            actionID.map { .execID($0.value.uuidString.lowercased()) }
        ]
        return selected.compactMap(\.self)
    }

    func validate() throws {
        guard routes.count == 1 else {
            throw ValidationError("Exactly one of --preset, --custom, or --id is required")
        }
    }

    func makeRequest() -> CLIRequest {
        CLIRequest(route: routes[0], queryItems: targetOptions.queryItems)
    }
}
