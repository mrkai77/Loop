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
    var outputMode: OutputOptions.Mode { get }
    func makeRequest() throws -> CLIRequest
}

extension CLIRequestCommand {
    func run() throws {
        let formatter = CLIOutputFormatter(executableName: LoopCLICommand.executableName)
        let printsJSON = outputMode == .json

        let response: CLIResponse
        do {
            response = try LoopSocketClient().send(makeRequest())
        } catch {
            guard printsJSON else { throw error }
            print(CLIResponse.encodedFailure(message: error.localizedDescription))
            throw ExitCode.failure
        }

        guard response.isSuccess else {
            guard printsJSON else { throw formatter.error(from: response) }
            print(response.rawOutput)
            throw ExitCode.failure
        }

        print(formatter.format(response, mode: outputMode))
    }
}

// MARK: - Shared options

struct OutputOptions: ParsableArguments {
    @Flag(name: .customLong("json"), help: "Print raw JSON instead of human-readable text")
    var json = false

    var outputMode: Mode {
        json ? .json : .human
    }

    enum Mode {
        case human
        case json
    }
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
