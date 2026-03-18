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

    @Flag(name: .customLong("directions"), help: "List only built-in direction actions")
    var directionsOnly = false

    @Flag(name: .customLong("keybinds"), help: "List only keybind-backed actions")
    var keybindsOnly = false

    @Flag(name: .customLong("ids"), help: "Show action UUIDs in `list actions` output")
    var ids = false

    @OptionGroup
    var outputOptions: OutputOptions

    var outputConfiguration: CLIOutputConfiguration {
        CLIOutputConfiguration(
            mode: outputOptions.outputMode,
            showIDs: ids
        )
    }

    func validate() throws {
        if directionsOnly, keybindsOnly {
            throw ValidationError("--directions and --keybinds are mutually exclusive")
        }

        if subject != .actions, directionsOnly || keybindsOnly {
            throw ValidationError("--directions and --keybinds are only valid with `list actions`")
        }

        if subject != .actions, ids {
            throw ValidationError("--ids is only valid with `list actions`")
        }
    }

    func makeRequest(using _: LoopCLIApplication) throws -> CLIRequest {
        let routeComponents: [String] = switch subject {
        case .windows:
            ["list", "windows"]
        case .screens:
            ["list", "screens"]
        case .actions where directionsOnly:
            ["list", "actions", "directions"]
        case .actions where keybindsOnly:
            ["list", "actions", "keybinds"]
        case .actions:
            ["list", "actions"]
        }

        return CLIRequest(routeComponents: routeComponents)
    }
}
