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
        abstract: "Command-line interface for the Loop window manager.",
        discussion: """
        Successful commands print to stdout: aligned tables in a terminal, and tab-separated lines without a header when piped. Pass --json for JSON instead. Errors go to stderr, except with --json, where Loop's error is printed to stdout as JSON. Mistyped commands and options always print to stderr.

        Exit codes: 0 on success, \(EXIT_FAILURE) when a command fails, \(EX_USAGE) for invalid usage, \(EX_UNAVAILABLE) when Loop can't run commands, such as when it isn't running, and \(EX_TEMPFAIL) when Loop doesn't respond in time.

        Examples:
          \(executableName) list actions
          \(executableName) list keybinds
          \(executableName) run right-half
          \(executableName) run keybind:portrait
          \(executableName) run radial-menu:top-cycle --bundle-id com.apple.Safari
          \(executableName) run maximize --window-id 1234
          \(executableName) run left-half --screen-id 2
          \(executableName) list windows --json
        """,
        version: version,
        subcommands: [ListCommand.self, RunCommand.self]
    )

    /// The installed tool lives inside Loop.app, so this is the version of the Loop it belongs to
    private static var version: String {
        guard let bundle = appBundle, let version = bundle.appVersion else {
            return "unknown (not inside Loop.app)"
        }

        return bundle.appBuild.map { "\(version) (\($0))" } ?? version
    }

    /// `Bundle.main` doesn't follow the `/usr/local/bin/loop` symlink, so this resolves the executable's real path first
    private static var appBundle: Bundle? {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else {
            return nil
        }

        let executableURL = URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
        return PrivilegedHelperConstants.appBundleURL(containingCommandLineTool: executableURL).flatMap(Bundle.init(url:))
    }
}

// MARK: - Requests

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
            if outputOptions.json {
                print(LoopAutomationJSON.encodeString(LoopAutomationResponse(error: error)))
            } else {
                printError(error.message)
            }
            throw ExitCode(error.code)
        }

        if outputOptions.json {
            print(response.rawOutput)
            if !response.isSuccess {
                throw ExitCode(response.automationError?.code ?? .failed)
            }
            return
        }

        let formatter = CLIOutputFormatter(executableName: LoopCLICommand.executableName)
        guard response.isSuccess else {
            printError(formatter.errorMessage(from: response))
            throw ExitCode(response.automationError?.code ?? .failed)
        }

        if let output = formatter.format(response) {
            print(output)
        }
    }

    private func printError(_ message: String) {
        let label = LoopAutomationText("Error:", style: .failure)
        let styledLabel = CLIOutputFormatter.usesColor(on: STDERR_FILENO) ? label.ansiText : label.plainText
        FileHandle.standardError.write(Data("\(styledLabel) \(message)\n".utf8))
    }
}

extension ExitCode {
    init(_ code: LoopAutomationErrorCode) {
        self.init(code.exitCode)
    }
}

// MARK: - Shared Options

struct OutputOptions: ParsableArguments {
    @Flag(name: .customLong("json"), help: "Print JSON instead of human-readable text")
    var json = false
}

/// The CLI's spelling of `LoopTargetOptions`
struct TargetArguments: ParsableArguments {
    @Option(name: .customLong("window-id"), help: ArgumentHelp("Act on a window from '\(LoopCLICommand.executableName) list windows'", valueName: "id"))
    var windowID: UInt32?

    @Option(name: .customLong("bundle-id"), help: ArgumentHelp("Act on an app's frontmost window, opening the app if needed", valueName: "bundle-id"))
    var bundleID: String?

    @Option(name: .customLong("screen-id"), help: ArgumentHelp("Use a screen from '\(LoopCLICommand.executableName) list screens'", valueName: "id"))
    var screenID: UInt32?

    var options: LoopTargetOptions {
        LoopTargetOptions(windowID: windowID, bundleID: bundleID, screenID: screenID)
    }

    func validate() throws {
        switch options.problem {
        case .windowAndBundleID:
            throw ValidationError("--window-id and --bundle-id can’t be used together")
        case .emptyBundleID:
            throw ValidationError("--bundle-id can’t be empty")
        case nil:
            break
        }
    }
}

extension [String] {
    /// "a, b or c", for help text
    func joinedAsAlternatives() -> String {
        guard let last, count > 1 else {
            return first ?? ""
        }

        return dropLast().joined(separator: ", ") + " or " + last
    }
}
