//
//  LoopSocketManager.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-18.
//

import Foundation
import Scribe

/// Listens on a Unix domain socket for commands from loop-cli.
///
/// The server accepts connections, reads a newline-terminated canonical `loop://...`
/// request URL, dispatches it to `LoopCommandHandler` on the main thread, and writes
/// the JSON response back before closing the connection.
///
/// Request format: `loop://<route>[?windowID=<id>&bundleID=<id>&screenID=<id>]`
/// Example: `loop://direction/right?bundleID=com.apple.Safari`
@Loggable
final class LoopSocketManager {
    // MARK: - Properties

    private let socketPath: String
    private let handler: LoopCommandHandler
    private var serverFD: Int32 = -1
    private var isRunning = false

    private let acceptQueue = DispatchQueue(
        label: "com.MrKai77.Loop.server.accept",
        qos: .userInitiated
    )

    private static let maxRequestSize = 4096
    private static let connectionTimeout: TimeInterval = 5

    // MARK: - Initialization

    init(handler: LoopCommandHandler) {
        self.handler = handler
        self.socketPath = "/tmp/loop-\(getuid()).socket"
    }

    // MARK: - Public Methods

    func start() {
        // Clean up stale socket from a previous crash
        unlink(socketPath)

        // Create socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            log.error("Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            log.error("Socket path too long: \(socketPath)")
            close(serverFD)
            serverFD = -1
            return
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFD, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            log.error("Failed to bind socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            serverFD = -1
            return
        }

        // Set permissions to owner-only
        chmod(socketPath, 0o600)

        // Start listening
        guard listen(serverFD, 5) == 0 else {
            log.error("Failed to listen on socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            unlink(socketPath)
            serverFD = -1
            return
        }

        isRunning = true
        log.info("Listening on \(socketPath)")

        // Accept loop on background queue
        acceptQueue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
        log.info("Server stopped")
    }

    // MARK: - Private Methods

    private func acceptLoop() {
        while isRunning {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

            let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(serverFD, sockaddrPtr, &clientAddrLen)
                }
            }

            guard clientFD >= 0 else {
                if isRunning {
                    log.error("Accept failed: \(String(cString: strerror(errno)))")
                }
                continue
            }

            // Set receive timeout
            var timeout = timeval(tv_sec: Int(Self.connectionTimeout), tv_usec: 0)
            setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

            handleConnection(clientFD)
        }
    }

    private func handleConnection(_ clientFD: Int32) {
        defer { close(clientFD) }

        // Read request (until newline or max size)
        var buffer = [UInt8](repeating: 0, count: Self.maxRequestSize)
        var totalRead = 0

        while totalRead < Self.maxRequestSize {
            let bytesRead = read(clientFD, &buffer[totalRead], Self.maxRequestSize - totalRead)
            if bytesRead <= 0 { break }
            totalRead += bytesRead

            // Check for newline delimiter
            if buffer[..<totalRead].contains(UInt8(ascii: "\n")) {
                break
            }
        }

        guard totalRead > 0 else {
            writeResponse(clientFD, #"{"success":false,"error":"Empty request"}"#)
            return
        }

        // Trim newline and parse
        let requestString = String(bytes: buffer[..<totalRead], encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !requestString.isEmpty else {
            writeResponse(clientFD, #"{"success":false,"error":"Empty request"}"#)
            return
        }

        // Dispatch to main thread for window/screen API access
        let semaphore = DispatchSemaphore(value: 0)
        var response = ""

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                response = #"{"success":false,"error":"Server shutting down"}"#
                semaphore.signal()
                return
            }
            response = handler.handleRequestURLString(requestString, source: .cli).jsonResponse
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + Self.connectionTimeout)

        if response.isEmpty {
            response = #"{"success":false,"error":"Request timed out"}"#
        }

        writeResponse(clientFD, response)
    }

    private func writeResponse(_ fd: Int32, _ response: String) {
        let data = response + "\n"
        data.utf8.withContiguousStorageIfAvailable { buffer in
            _ = Darwin.write(fd, buffer.baseAddress!, buffer.count)
        }
    }
}
