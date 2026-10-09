//
//  LoopSocketClient.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import Foundation

final class LoopSocketClient {
    private struct SocketRuntimeError: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
    }

    /// Past Loop's own command timeout, so Loop can still report it
    private static let receiveTimeout = LoopAutomationJSON.commandTimeout + .seconds(5)

    func send(_ request: CLIRequest) throws -> CLIResponse {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw SocketRuntimeError(message: "Failed to create socket")
        }
        defer { close(fileDescriptor) }

        let connectResult = LoopSocketPath.withSocketAddress { address, length in
            connect(fileDescriptor, address, length)
        }

        guard let connectResult else {
            throw SocketRuntimeError(message: "Socket path too long: \(LoopSocketPath.path)")
        }

        guard connectResult == 0 else {
            throw SocketRuntimeError(message: "Loop is not running")
        }

        LoopSocketIO.configure(fileDescriptor, receiveTimeout: Self.receiveTimeout)

        do {
            try LoopSocketIO.write(request.url.absoluteString, to: fileDescriptor)
            shutdown(fileDescriptor, SHUT_WR)
        } catch {
            throw SocketRuntimeError(message: "Failed to send request: \(error.localizedDescription)")
        }

        let response: String
        do {
            response = try LoopSocketIO.readToEnd(from: fileDescriptor)
        } catch POSIXError.EAGAIN {
            throw SocketRuntimeError(message: "Loop didn’t respond in time")
        } catch {
            throw SocketRuntimeError(message: "Failed to read Loop’s response: \(error.localizedDescription)")
        }

        guard !response.isEmpty else {
            throw SocketRuntimeError(message: "Empty response from Loop")
        }

        return CLIResponse(rawOutput: response)
    }
}

struct CLIRequest {
    let url: URL

    init(route: LoopRoute, queryItems: [URLQueryItem] = []) {
        self.url = route.url(queryItems: queryItems)
    }
}

struct CLIResponse {
    let rawOutput: String
    let automationResponse: LoopAutomationResponse?

    init(rawOutput: String) {
        self.rawOutput = rawOutput
        self.automationResponse = try? LoopAutomationJSON.decodeResponse(from: rawOutput)
    }

    var isSuccess: Bool {
        automationResponse?.success == true
    }

    var result: LoopAutomationResult? {
        automationResponse?.result
    }

    var automationError: LoopAutomationError? {
        automationResponse?.error
    }
}
