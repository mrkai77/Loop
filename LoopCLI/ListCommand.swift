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

    @Flag(name: .customLong("directions-only"), help: "List only built-in direction actions")
    var directionsOnly = false

    @Flag(name: .customLong("keybinds-only"), help: "List only keybind-backed actions")
    var keybindsOnly = false

    @OptionGroup
    var outputOptions: OutputOptions

    var outputMode: CLIOutputMode {
        outputOptions.outputMode
    }

    func validate() throws {
        if directionsOnly, keybindsOnly {
            throw ValidationError("--directions-only and --keybinds-only are mutually exclusive")
        }

        if subject != .actions, directionsOnly || keybindsOnly {
            throw ValidationError("--directions-only and --keybinds-only are only valid with `list actions`")
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
