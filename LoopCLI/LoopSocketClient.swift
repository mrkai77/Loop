//
//  LoopSocketClient.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import Foundation

final class LoopSocketClient {
    /// Past Loop's own command timeout, so Loop can still report it
    private static let receiveTimeout = LoopAutomationJSON.commandTimeout + .seconds(5)
    /// Far past any real response, so a misbehaving peer can't use up memory
    private static let maxResponseSize = 16 * 1024 * 1024

    func send(_ request: CLIRequest) throws(LoopAutomationError) -> CLIResponse {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw LoopAutomationError(.unavailable, message: "Couldn’t create a socket: \(LoopSocketIO.errnoDescription())")
        }
        defer { close(fileDescriptor) }

        let connectResult = LoopSocketPath.withSocketAddress { address, length in
            connect(fileDescriptor, address, length)
        }

        guard let connectResult else {
            throw LoopAutomationError(.unavailable, message: "Loop’s socket path is too long: \(LoopSocketPath.path)")
        }

        guard connectResult == 0 else {
            throw Self.connectionError(errno: errno)
        }

        LoopSocketIO.configure(fileDescriptor, timeout: Self.receiveTimeout)

        do {
            try LoopSocketIO.write(request.url.absoluteString, to: fileDescriptor)
            shutdown(fileDescriptor, SHUT_WR)
        } catch {
            throw LoopAutomationError(.unavailable, message: "Couldn’t send the command to Loop: \(LoopSocketIO.description(of: error))")
        }

        let response: String
        do {
            response = try LoopSocketIO.readToEnd(from: fileDescriptor, limit: Self.maxResponseSize)
        } catch POSIXError.EAGAIN {
            throw LoopAutomationError(.timeout, message: "Loop didn’t respond in time, so the action may still complete")
        } catch {
            throw LoopAutomationError(.unavailable, message: "Couldn’t read Loop’s response: \(LoopSocketIO.description(of: error))")
        }

        guard !response.isEmpty else {
            throw LoopAutomationError(.unavailable, message: "Loop closed the connection without responding")
        }

        // Cut short or from a different version, so `--json` never prints something scripts can't parse
        let cliResponse = CLIResponse(rawOutput: response)
        guard cliResponse.automationResponse != nil else {
            throw LoopAutomationError(.unavailable, message: "Loop’s response couldn’t be read. Make sure Loop is up to date, then try again.")
        }

        return cliResponse
    }

    private static func connectionError(errno code: Int32) -> LoopAutomationError {
        switch code {
        case ENOENT, ECONNREFUSED:
            // No socket at all also covers versions of Loop from before the command-line tool
            LoopAutomationError(.unavailable, message: "Couldn’t reach Loop. Make sure Loop is open and up to date, then try again.")
        default:
            LoopAutomationError(.unavailable, message: "Couldn’t connect to Loop at \(LoopSocketPath.path): \(LoopSocketIO.errnoDescription(code))")
        }
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
