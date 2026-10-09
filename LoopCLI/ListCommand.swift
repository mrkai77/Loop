//
//  ListCommand.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import ArgumentParser

struct ListCommand: ParsableCommand, CLIRequestCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List windows, screens, or executable actions"
    )

    @Argument(help: "What to list")
    var subject: ListSubject

    @Flag(name: .customLong("preset"), help: "List only preset actions")
    var presetOnly = false

    @Flag(name: .customLong("custom"), help: "List only custom actions")
    var customOnly = false

    @OptionGroup
    var outputOptions: OutputOptions

    var outputMode: OutputOptions.Mode {
        outputOptions.outputMode
    }

    func validate() throws {
        if presetOnly, customOnly {
            throw ValidationError("--preset and --custom are mutually exclusive")
        }

        if subject != .actions, presetOnly || customOnly {
            throw ValidationError("--preset and --custom are only valid with `list actions`")
        }
    }

    func makeRequest() throws -> CLIRequest {
        let routeComponents: [String] = switch subject {
        case .windows:
            ["list", "windows"]
        case .screens:
            ["list", "screens"]
        case .actions where presetOnly:
            ["list", "actions", "preset"]
        case .actions where customOnly:
            ["list", "actions", "custom"]
        case .actions:
            ["list", "actions"]
        }

        return CLIRequest(routeComponents: routeComponents)
    }
}

enum ListSubject: String, CaseIterable, ExpressibleByArgument {
    case windows
    case screens
    case actions
}
