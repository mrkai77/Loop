//
//  LoopSocketIO.swift
//  Loop
//
//  Created by Kai Azim on 2026-10-08.
//

import Foundation

/// One request per connection: the client writes its request and shuts down writing, then Loop writes its response and closes
enum LoopSocketIO {
    /// Times out both directions, so neither side blocks forever on a stalled peer.
    /// Also stops writes to a closed peer from raising `SIGPIPE`.
    static func configure(_ fileDescriptor: Int32, timeout: Duration) {
        var timeout = timeval(tv_sec: Int(timeout.components.seconds), tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var noSIGPIPE: Int32 = 1
        setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSIGPIPE, socklen_t(MemoryLayout<Int32>.size))
    }

    static func write(_ string: String, to fileDescriptor: Int32) throws {
        try Array(string.utf8).withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(fileDescriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    guard errno == EINTR else { throw currentError }
                    continue
                }
                offset += written
            }
        }
    }

    /// Throws `EMSGSIZE` past `limit`, and `EAGAIN` when the receive timeout expires
    static func readToEnd(from fileDescriptor: Int32, limit: Int = .max) throws -> String {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(fileDescriptor, $0.baseAddress, $0.count) }
            if count < 0 {
                guard errno == EINTR else { throw currentError }
                continue
            }
            if count == 0 {
                return String(decoding: data, as: UTF8.self)
            }

            data.append(contentsOf: buffer[..<count])
            guard data.count <= limit else {
                throw POSIXError(.EMSGSIZE)
            }
        }
    }

    /// The system's short description of an error number, like "Connection refused"
    static func errnoDescription(_ code: Int32 = errno) -> String {
        String(cString: strerror(code))
    }

    /// The short description for the `POSIXError`s these functions throw, which are wordier by default
    static func description(of error: Error) -> String {
        (error as? POSIXError).map { errnoDescription($0.code.rawValue) } ?? error.localizedDescription
    }

    private static var currentError: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
