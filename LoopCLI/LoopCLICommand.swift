//
//  LoopCLICommand.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import ArgumentParser

struct LoopCLICommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: LoopCLIApplication.executableName,
        abstract: "Command-line interface for Loop window manager.",
        discussion: """
        Successful commands print human-readable text by default. Use --json to print raw JSON.
        Failures print plain-text errors to stderr.

        Examples:
          \(LoopCLIApplication.executableName) list windows
          \(LoopCLIApplication.executableName) list windows --json
          \(LoopCLIApplication.executableName) list actions --directions-only
          \(LoopCLIApplication.executableName) exec --direction right
          \(LoopCLIApplication.executableName) exec --direction right --json
          \(LoopCLIApplication.executableName) exec --keybind "My Layout"
          \(LoopCLIApplication.executableName) exec --id 123e4567-e89b-12d3-a456-426614174000
        """,
        subcommands: [ListCommand.self, ExecCommand.self]
    )
}
