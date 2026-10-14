//
//  LoopCLI.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-18.
//

import ArgumentParser
import Foundation

@main
struct LoopCLICommand: ParsableCommand {
    /// `loop` when run through the installed symlink, `loop-cli` otherwise
    static let executableName = URL(
        fileURLWithPath: CommandLine.arguments.first ?? "loop-cli"
    ).lastPathComponent

    static let configuration = CommandConfiguration(
        commandName: executableName,
        abstract: "Command-line interface for Loop window manager.",
        discussion: """
        Successful commands print human-readable text by default. Use --json to print raw JSON.
        Failures print plain-text errors to stderr.

        Action names are the ones shown by `\(executableName) list actions`.

        Examples:
          \(executableName) list windows
          \(executableName) list screens
          \(executableName) list actions --preset
          \(executableName) list actions --custom
          \(executableName) exec --preset right_half
          \(executableName) exec --custom "My Layout"
          \(executableName) exec --id 123e4567-e89b-12d3-a456-426614174000
          \(executableName) exec --preset maximize --window-id 1234
          \(executableName) exec --preset left_half --bundle-id com.apple.Safari
          \(executableName) list windows --json
        """,
        subcommands: [ListCommand.self, ExecCommand.self]
    )
}

// MARK: - Request commands

protocol CLIRequestCommand: ParsableCommand {
    var outputOptions: OutputOptions { get }
    func makeRequest() -> CLIRequest
}

extension CLIRequestCommand {
    func run() throws {
        let response: CLIResponse
        do {
            response = try LoopSocketClient().send(makeRequest())
        } catch {
            guard outputOptions.json else { throw error }
            print(LoopAutomationJSON.encodedFailure(message: error.localizedDescription))
            throw ExitCode.failure
        }

        if outputOptions.json {
            print(response.rawOutput)
            if !response.isSuccess { throw ExitCode.failure }
            return
        }

        let formatter = CLIOutputFormatter(executableName: LoopCLICommand.executableName)
        guard response.isSuccess else {
            throw formatter.error(from: response)
        }

        print(formatter.format(response))
    }
}

// MARK: - Shared options

struct OutputOptions: ParsableArguments {
    @Flag(name: .customLong("json"), help: "Print raw JSON instead of human-readable text")
    var json = false
}

struct TargetOptions: ParsableArguments {
    @Option(name: .customLong("window-id"), help: "Target a specific window by ID (from `list windows`)")
    var windowID: UInt32?

    @Option(name: .customLong("bundle-id"), help: "Target an app by bundle identifier (launches if needed)")
    var bundleID: String?

    @Option(name: .customLong("screen-id"), help: "Target a specific screen by ID (from `list screens`)")
    var screenID: UInt32?

    func validate() throws {
        if windowID != nil, bundleID != nil {
            throw ValidationError("--window-id and --bundle-id are mutually exclusive")
        }
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let windowID {
            items.append(URLQueryItem(name: "windowID", value: String(windowID)))
        }

        if let bundleID {
            items.append(URLQueryItem(name: "bundleID", value: bundleID))
        }

        if let screenID {
            items.append(URLQueryItem(name: "screenID", value: String(screenID)))
        }

        return items
    }
}
