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

    @Flag
    var filter: ActionFilter?

    @OptionGroup
    var outputOptions: OutputOptions

    func validate() throws {
        if subject != .actions, filter != nil {
            throw ValidationError("--preset and --custom are only valid with `list actions`")
        }
    }

    func makeRequest() -> CLIRequest {
        let route: LoopRoute = switch subject {
        case .windows:
            .listWindows
        case .screens:
            .listScreens
        case .actions:
            switch filter {
            case .preset: .listActions(.presetOnly)
            case .custom: .listActions(.customOnly)
            case nil: .listActions(.all)
            }
        }

        return CLIRequest(route: route)
    }
}

enum ListSubject: String, CaseIterable, ExpressibleByArgument {
    case windows
    case screens
    case actions
}

enum ActionFilter: String, EnumerableFlag {
    case preset
    case custom

    static func help(for value: ActionFilter) -> ArgumentHelp? {
        switch value {
        case .preset: "List only preset actions"
        case .custom: "List only custom actions"
        }
    }
}
