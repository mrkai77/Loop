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
