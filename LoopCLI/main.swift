//
//  main.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-18.
//

import Foundation

// MARK: - Socket Communication

/// Connects to the Loop Unix socket, sends a command URL, and returns the JSON response.
func sendCommand(_ urlString: String) -> (response: String, success: Bool) {
    let socketPath = "/tmp/loop-\(getuid()).socket"

    // Create socket
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        return (makeError("Failed to create socket"), false)
    }
    defer { close(fd) }

    // Connect
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

    // Set timeout
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    // Send request
    let request = urlString + "\n"
    let sent = request.utf8.withContiguousStorageIfAvailable { buffer in
        Darwin.write(fd, buffer.baseAddress!, buffer.count)
    } ?? -1

    guard sent > 0 else {
        return (makeError("Failed to send command"), false)
    }

    // Read response (until EOF)
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

    // Check success field
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
/// The command string is sent directly over the socket — no URL wrapping.
///
/// Usage: loop-cli <command> [subcommand...] [--window-id <id>] [--bundle-id <id>] [--screen-id <id>]
///
/// Examples:
///   loop-cli windowlist                                      → "windowlist"
///   loop-cli direction right                                 → "direction right"
///   loop-cli direction right --bundle-id com.apple.Safari    → "direction right --bundle-id com.apple.Safari"
func buildCommand(from args: [String]) -> String? {
    guard !args.isEmpty else { return nil }

    // Validate that flag args have values
    var i = 0
    while i < args.count {
        if args[i] == "--window-id" || args[i] == "--bundle-id" || args[i] == "--screen-id" {
            guard i + 1 < args.count else {
                fputs("Error: \(args[i]) requires a value\n", stderr)
                return nil
            }
            i += 2
        } else {
            i += 1
        }
    }

    return args.joined(separator: " ")
}

// MARK: - Help

let helpText = """
loop-cli — Command-line interface for Loop window manager

USAGE:
  loop-cli <command> [arguments] [options]

COMMANDS:
  windowlist                    List all visible windows
  screenlist                    List all connected screens
  direction <dir>               Move/resize window (left, right, top, bottom, maximize, center, ...)
  action <action>               Execute a window action
  keybind <name>                Execute a custom keybind
  screen <next|previous>        Move window to another screen
  list <actions|keybinds|all>   List available commands

OPTIONS:
  --window-id <id>    Target a specific window by ID (from windowlist)
  --bundle-id <id>    Target an app by bundle identifier (launches if needed)
  --screen-id <id>    Target a specific screen by ID (from screenlist)
  --help, -h          Show this help message

EXAMPLES:
  loop-cli windowlist
  loop-cli direction right
  loop-cli direction right --bundle-id com.apple.Safari
  loop-cli action maximize --window-id 1234 --screen-id 5678
  loop-cli list all

All commands return JSON. Exit code is 0 on success, 1 on failure.
"""

// MARK: - Main

let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.contains("--help") || args.contains("-h") {
    print(helpText)
    exit(args.isEmpty ? 1 : 0)
}

guard let command = buildCommand(from: args) else {
    fputs("Error: No command specified. Run 'loop-cli --help' for usage.\n", stderr)
    exit(1)
}

let (response, success) = sendCommand(command)
print(response)
exit(success ? 0 : 1)
