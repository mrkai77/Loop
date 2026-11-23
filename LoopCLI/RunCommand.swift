//
//  RunCommand.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-11-22.
//

import ArgumentParser

struct RunCommand: ParsableCommand, CLIRequestCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run an action, keybind, gesture or radial menu action",
        discussion: """
        <target> is written like an action in Loop's settings: a built-in action from '\(LoopCLICommand.executableName) list actions', such as right-half, or a binding from 'list keybinds', 'list gestures' or 'list radial-menu', such as keybind:portrait. A binding's ID comes from its name, so renaming or reordering bindings can change it.

        Without --window-id or --bundle-id, it acts on the window Loop would target for a keybind.
        """
    )

    @Argument(help: ArgumentHelp("What to run, such as right-half or keybind:portrait", valueName: "target"))
    var target: LoopTarget

    @OptionGroup
    var targetOptions: TargetOptions

    @OptionGroup
    var outputOptions: OutputOptions

    func makeRequest() -> CLIRequest {
        CLIRequest(route: .run(target), queryItems: targetOptions.queryItems)
    }
}

extension LoopTarget: ExpressibleByArgument {
    init?(argument: String) {
        self.init(argument)
    }
}
