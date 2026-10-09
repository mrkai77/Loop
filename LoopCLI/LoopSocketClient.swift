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

    private let socketPath: String

    init(socketPath: String = LoopSocketPath.path) {
        self.socketPath = socketPath
    }

    func send(_ request: CLIRequest) throws -> CLIResponse {
        let fileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fileDescriptor >= 0 else {
            throw SocketRuntimeError(message: "Failed to create socket")
        }
        defer { close(fileDescriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                pathBytes.withUnsafeBufferPointer { source in
                    _ = memcpy(destination, source.baseAddress!, source.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(fileDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard connectResult == 0 else {
            throw SocketRuntimeError(message: "Loop is not running")
        }

        // Longer than Loop's own command timeout, so Loop can still report it
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let serializedRequest = request.url.absoluteString + "\n"
        let bytesSent = serializedRequest.utf8.withContiguousStorageIfAvailable { buffer in
            Darwin.write(fileDescriptor, buffer.baseAddress!, buffer.count)
        } ?? -1

        guard bytesSent > 0 else {
            throw SocketRuntimeError(message: "Failed to send request")
        }

        var responseData = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = read(fileDescriptor, &buffer, buffer.count)
            if bytesRead <= 0 {
                break
            }

            responseData.append(contentsOf: buffer[..<bytesRead])
        }

        guard let response = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !response.isEmpty
        else {
            throw SocketRuntimeError(message: "Empty response from Loop")
        }

        return CLIResponse(rawOutput: response)
    }
}

// MARK: - Request & Response

struct CLIRequest {
    let url: URL

    init(routeComponents: [String], queryItems: [URLQueryItem] = []) {
        precondition(!routeComponents.isEmpty, "CLIRequest requires at least one route component")

        var components = URLComponents()
        components.scheme = "loop"
        components.host = routeComponents[0]

        if routeComponents.count > 1 {
            // Encode "/" too, so a name like "Left 1/3" stays one path component
            var allowedCharacters = CharacterSet.urlPathAllowed
            allowedCharacters.remove("/")
            components.percentEncodedPath = "/" + routeComponents.dropFirst()
                .map { $0.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? $0 }
                .joined(separator: "/")
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            preconditionFailure("Failed to construct loop:// request for \(routeComponents)")
        }

        self.url = url
    }
}

struct CLIResponse {
    let rawOutput: String
    let automationResponse: LoopAutomationResponse?

    init(rawOutput: String) {
        let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawOutput = trimmedOutput
        self.automationResponse = try? LoopAutomationJSON.decodeResponse(from: trimmedOutput)
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

    /// The same shape Loop uses for failures, for errors that happen before Loop responds
    static func encodedFailure(message: String) -> String {
        let response = LoopAutomationResponse(error: LoopAutomationError(message: message))
        return (try? LoopAutomationJSON.encodeString(response)) ?? #"{"error":{"message":"\#(message)"},"success":false}"#
    }
}
