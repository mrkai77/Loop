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
/// Example: `loop://run/right-half?bundleID=com.apple.Safari`
@Loggable
final class LoopSocketManager {
    static let shared = LoopSocketManager()

    private let socketPath = LoopSocketPath.path
    private let commandLineToolInstaller = CommandLineToolInstaller()

    /// Only touched by `start()` and `shutdown()`, which run on the main thread
    private var listener: DispatchSourceRead?
    /// The socket file this instance bound, so shutting down never removes a newer instance's socket
    private var boundSocketFile: (device: dev_t, inode: ino_t)?

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
    /// The CLI sends its request right after connecting and reads the response straight away,
    /// so this only has to cover a stalled client
    private static let clientTimeout: Duration = .seconds(5)

    private init() {}

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

        var socketFile = stat()
        if lstat(socketPath, &socketFile) == 0 {
            boundSocketFile = (socketFile.st_dev, socketFile.st_ino)
        }

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

    func shutdown() {
        listener?.cancel()
        listener = nil

        // A newer instance may already have replaced the socket file while this one was quitting
        var socketFile = stat()
        if let boundSocketFile, lstat(socketPath, &socketFile) == 0,
           socketFile.st_dev == boundSocketFile.device, socketFile.st_ino == boundSocketFile.inode {
            unlink(socketPath)
        }
        boundSocketFile = nil

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

        LoopSocketIO.configure(clientFD, timeout: Self.clientTimeout)

        // Only answer once the user has installed the tool, so running the copy inside Loop.app does nothing until they opt in.
        // This isn't a security boundary: any app of this user can already send the same commands through loop:// URLs.
        if let reason = commandLineToolRejectionReason() {
            log.warn("Rejected socket connection: \(reason)")
            respond(clientFD, LoopAutomationJSON.encodedFailure(.unavailable, message: reason))
            return
        }

        let request: String
        do {
            request = try LoopSocketIO.readToEnd(from: clientFD, limit: Self.maxRequestSize)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch POSIXError.EAGAIN {
            respond(clientFD, LoopAutomationJSON.encodedFailure(.invalidRequest, message: "Loop didn’t receive the full request in time"))
            return
        } catch POSIXError.EMSGSIZE {
            respond(clientFD, LoopAutomationJSON.encodedFailure(.invalidRequest, message: "The request is too long"))
            return
        } catch {
            respond(clientFD, LoopAutomationJSON.encodedFailure(.invalidRequest, message: "Couldn’t read the request: \(error.localizedDescription)"))
            return
        }

        guard !request.isEmpty else {
            respond(clientFD, LoopAutomationJSON.encodedFailure(.invalidRequest, message: "Empty request"))
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
            "\(path) isn’t owned by an administrator, so another app could have created it. Click Repair in Loop’s Advanced settings."
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
