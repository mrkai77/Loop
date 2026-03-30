//
//  main.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-18.
//

import Foundation

// MARK: - Socket Communication

/// Connects to the Loop Unix socket, sends a raw command string, and returns the JSON response.
func sendCommand(_ commandString: String) -> (response: String, success: Bool) {
    let socketPath = "/tmp/loop-\(getuid()).socket"

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        return (makeError("Failed to create socket"), false)
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = socketPath.utf8CString
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            pathBytes.withUnsafeBufferPointer { src in
                _ = memcpy(dest, src.baseAddress!, src.count)
            }
        }
    }

    let connectResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    guard connectResult == 0 else {
        return (makeError("Loop is not running (could not connect to \(socketPath))"), false)
    }

    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    let request = commandString + "\n"
    let sent = request.utf8.withContiguousStorageIfAvailable { buffer in
        Darwin.write(fd, buffer.baseAddress!, buffer.count)
    } ?? -1

    guard sent > 0 else {
        return (makeError("Failed to send command"), false)
    }

    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
        let bytesRead = read(fd, &buffer, buffer.count)
        if bytesRead <= 0 { break }
        responseData.append(contentsOf: buffer[..<bytesRead])
    }

    let response = String(data: responseData, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    guard !response.isEmpty else {
        return (makeError("Empty response from Loop"), false)
    }

    let isSuccess: Bool
    if let data = response.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let success = json["success"] as? Bool
    {
        isSuccess = success
    } else {
        isSuccess = false
    }

    return (response, isSuccess)
}

func makeError(_ message: String) -> String {
    #"{"success":false,"error":"\#(message)"}"#
}

// MARK: - Command Building

/// Builds a raw command string from CLI arguments.
/// Arguments are shell-escaped so quoted values such as `--keybind "My Layout"`
/// survive the socket transport and can be re-tokenized in the app.
func buildCommand(from args: [String]) -> String? {
    guard !args.isEmpty else { return nil }

    let flagsRequiringValues: Set<String> = [
        "--window-id",
        "--bundle-id",
        "--screen-id",
        "--direction",
        "--keybind",
        "--id"
    ]

    var index = 0
    while index < args.count {
        if flagsRequiringValues.contains(args[index]) {
            guard index + 1 < args.count else {
                fputs("Error: \(args[index]) requires a value\n", stderr)
                return nil
            }
            index += 2
        } else {
            index += 1
        }
    }

    return args.map(escapeArgument).joined(separator: " ")
}

func escapeArgument(_ argument: String) -> String {
    if argument.isEmpty {
        return "\"\""
    }

    let escaped = argument
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")

    return escaped.contains(where: \.isWhitespace) || escaped.contains("\"")
        ? "\"\(escaped)\""
        : escaped
}

// MARK: - Help

let executableName = URL(fileURLWithPath: CommandLine.arguments.first ?? "loop-cli").lastPathComponent

let helpText = """
\(executableName) — Command-line interface for Loop window manager

USAGE:
  \(executableName) list <windows|screens|actions> [--directions-only | --keybinds-only]
  \(executableName) exec --direction <slug> | --keybind <name> | --id <uuid> [options]

READ COMMANDS:
  list windows                     List all visible windows
  list screens                     List all connected screens
  list actions                     List all executable actions
  list actions --directions-only   List only built-in direction actions
  list actions --keybinds-only     List only keybind-backed actions

WRITE COMMANDS:
  exec --direction <slug>          Execute a built-in direction action
  exec --keybind <name>            Execute a keybind-backed action by display name
  exec --id <uuid>                 Execute any action by UUID

TARGET OPTIONS:
  --window-id <id>    Target a specific window by ID (from `list windows`)
  --bundle-id <id>    Target an app by bundle identifier (launches if needed)
  --screen-id <id>    Target a specific screen by ID (from `list screens`)

OTHER OPTIONS:
  --help, -h          Show this help message

EXAMPLES:
  \(executableName) list windows
  \(executableName) list actions --directions-only
  \(executableName) exec --direction right
  \(executableName) exec --direction next_screen --bundle-id com.apple.Safari
  \(executableName) exec --keybind "My Layout"
  \(executableName) exec --id 123e4567-e89b-12d3-a456-426614174000

All commands return JSON. Exit code is 0 on success, 1 on failure.
"""

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.contains("--help") || args.contains("-h") {
    print(helpText)
    exit(args.isEmpty ? 1 : 0)
}

guard let command = buildCommand(from: args) else {
    fputs("Error: Invalid command. Run '\(executableName) --help' for usage.\n", stderr)
    exit(1)
}

let (response, success) = sendCommand(command)
print(response)
exit(success ? 0 : 1)
