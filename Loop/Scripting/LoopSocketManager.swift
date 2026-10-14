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
/// Each connection carries one canonical `loop://...` request URL, read until the client shuts down
/// writing. The request is dispatched to `LoopCommandHandler`, and the JSON response is written back
/// before the connection is closed.
///
/// Request format: `loop://<route>[?windowID=<id>&bundleID=<id>&screenID=<id>]`
/// Example: `loop://exec/preset/right_half?bundleID=com.apple.Safari`
@Loggable
final class LoopSocketManager {
    private let socketPath = LoopSocketPath.path
    private let commandLineToolInstaller = CommandLineToolInstaller()

    /// Only touched by `start()` and `stop()`, which run on the main thread
    private var listener: DispatchSourceRead?

    private let acceptQueue = DispatchQueue(
        label: "com.MrKai77.Loop.server.accept",
        qos: .userInitiated
    )

    /// Concurrent, so a client that never sends its request can't hold up the others
    private let connectionQueue = DispatchQueue(
        label: "com.MrKai77.Loop.server.connection",
        qos: .userInitiated,
        attributes: .concurrent
    )

    private static let maxRequestSize = 4096
    /// The CLI sends its request right after connecting, so this only has to cover a stalled client
    private static let requestReadTimeout: Duration = .seconds(5)

    func start() {
        guard listener == nil else { return }

        // Clean up stale socket from a previous crash
        unlink(socketPath)

        let serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            log.error("Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }

        let bindResult = LoopSocketPath.withSocketAddress { address, length in
            bind(serverFD, address, length)
        }

        guard let bindResult else {
            log.error("Socket path too long: \(socketPath)")
            close(serverFD)
            return
        }

        guard bindResult == 0 else {
            log.error("Failed to bind socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            return
        }

        // Set permissions to owner-only
        chmod(socketPath, 0o600)

        guard listen(serverFD, 5) == 0 else {
            log.error("Failed to listen on socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            unlink(socketPath)
            return
        }

        // So accept() can't block if a client gives up between the event and the call
        _ = fcntl(serverFD, F_SETFL, fcntl(serverFD, F_GETFL) | O_NONBLOCK)

        let listener = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: acceptQueue)
        listener.setEventHandler { [weak self] in
            self?.acceptConnection(serverFD)
        }
        listener.setCancelHandler {
            close(serverFD)
        }
        listener.resume()
        self.listener = listener

        log.info("Listening on \(socketPath)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
        unlink(socketPath)
        log.info("Server stopped")
    }

    private func acceptConnection(_ serverFD: Int32) {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else {
            if errno != EAGAIN, errno != ECONNABORTED {
                log.error("Accept failed: \(String(cString: strerror(errno)))")
            }
            return
        }

        // Accepted sockets inherit O_NONBLOCK from the listener
        _ = fcntl(clientFD, F_SETFL, fcntl(clientFD, F_GETFL) & ~O_NONBLOCK)

        connectionQueue.async { [weak self] in
            guard let self else {
                close(clientFD)
                return
            }
            handleConnection(clientFD)
        }
    }

    private func handleConnection(_ clientFD: Int32) {
        // Reject connections from other users
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(clientFD, &peerUID, &peerGID) == 0, peerUID == getuid() else {
            log.warn("Rejected socket connection from another user")
            close(clientFD)
            return
        }

        LoopSocketIO.configure(clientFD, receiveTimeout: Self.requestReadTimeout)

        // Installing the tool needs an administrator, so it doubles as consent to be controlled
        if let reason = commandLineToolRejectionReason() {
            log.warn("Rejected socket connection: \(reason)")
            respond(clientFD, LoopAutomationJSON.encodedFailure(message: reason))
            return
        }

        let request: String
        do {
            request = try LoopSocketIO.readToEnd(from: clientFD, limit: Self.maxRequestSize)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            respond(clientFD, LoopAutomationJSON.encodedFailure(message: "Couldn’t read the request: \(error.localizedDescription)"))
            return
        }

        guard !request.isEmpty else {
            respond(clientFD, LoopAutomationJSON.encodedFailure(message: "Empty request"))
            return
        }

        Task {
            let result = await LoopCommandHandler.shared.handleRequestURLString(request, source: .cli)
            respond(clientFD, result.jsonResponse)
        }
    }

    private func commandLineToolRejectionReason() -> String? {
        let path = PrivilegedHelperConstants.commandLineToolSymlinkURL.path
        let status: CommandLineToolInstaller.Status
        do {
            status = try commandLineToolInstaller.status()
        } catch {
            return "Couldn’t check \(path): \(error.localizedDescription)"
        }

        return switch status {
        case .installedCurrent:
            nil
        case .notInstalled:
            "Loop only accepts commands while the command-line tool is installed. Install it in Loop’s Advanced settings."
        case .installedStale:
            "\(path) points to another copy of Loop. Click Repair in Loop’s Advanced settings."
        case .installedWithoutAdministrator:
            "\(path) isn’t owned by root, so other apps could have created it to control Loop. Click Repair in Loop’s Advanced settings."
        case .blocked:
            "\(path) belongs to another app or file. Remove it, then install the command-line tool in Loop’s Advanced settings."
        }
    }

    /// Closing the connection is what tells the client the response is complete
    private func respond(_ clientFD: Int32, _ response: String) {
        do {
            try LoopSocketIO.write(response, to: clientFD)
        } catch {
            log.warn("Failed to write response: \(error.localizedDescription)")
        }
        close(clientFD)
    }
}
