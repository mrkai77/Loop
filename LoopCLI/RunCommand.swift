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
        abstract: "Run an action, " + LoopBindingKind.allCases.map(\.noun).joinedAsAlternatives(),
        discussion: """
        <target> is written like an action in Loop's settings: a built-in action from '\(LoopCLICommand.executableName) list actions', such as right-half, or a binding from \(LoopBindingKind.allCases.map { "'list \($0.listSubject.rawValue)'" }.joinedAsAlternatives()), such as keybind:portrait. A binding's ID comes from its name, so renaming or reordering bindings can change it.

        Without --window-id or --bundle-id, it acts on the window Loop would target for a keybind.
        """
    )

    @Argument(help: ArgumentHelp("What to run, such as right-half or keybind:portrait", valueName: "target"))
    var target: LoopTarget

    @OptionGroup
    var targetArguments: TargetArguments

    @OptionGroup
    var outputOptions: OutputOptions

    func makeRequest() -> CLIRequest {
        CLIRequest(route: .run(target), queryItems: targetArguments.options.queryItems)
    }
}

extension LoopTarget: ExpressibleByArgument {
    init?(argument: String) {
        self.init(argument)
    }
}
