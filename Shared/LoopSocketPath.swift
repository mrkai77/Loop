//
//  LoopSocketPath.swift
//  Loop
//
//  Created by Kai Azim on 2026-10-08.
//

import Foundation

enum LoopSocketPath {
    /// In the per-user temporary directory rather than `/tmp`, so other users can't claim the path or connect to it
    static var path: String {
        userTemporaryDirectory + "loop.socket"
    }

    /// Returns `nil` when `path` doesn't fit in `sockaddr_un`
    static func withSocketAddress<R>(_ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            return nil
        }

        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { destination.copyMemory(from: $0) }
        }

        return withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                body(socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }

    private static var userTemporaryDirectory: String {
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 0 else {
            return NSTemporaryDirectory()
        }

        var buffer = [CChar](repeating: 0, count: length)
        confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length)
        return String(cString: buffer)
    }
}

/// One request per connection: the client writes its request and shuts down writing, then Loop writes its response and closes
enum LoopSocketIO {
    /// Also stops writes to a closed peer from raising `SIGPIPE`
    static func configure(_ fileDescriptor: Int32, receiveTimeout: Duration) {
        var timeout = timeval(tv_sec: Int(receiveTimeout.components.seconds), tv_usec: 0)
        setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

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

    private static var currentError: POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
