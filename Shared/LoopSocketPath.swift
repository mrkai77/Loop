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
