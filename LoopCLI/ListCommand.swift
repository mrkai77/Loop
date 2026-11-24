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
        abstract: "List windows, screens, actions, keybinds, gestures or radial menu actions"
    )

    @Argument(help: ArgumentHelp("What to list", valueName: "subject"))
    var subject: LoopListSubject

    @OptionGroup
    var outputOptions: OutputOptions

    func makeRequest() -> CLIRequest {
        CLIRequest(route: .list(subject))
    }
}

extension LoopListSubject: ExpressibleByArgument {}
