//
//  PrivilegedHelperError.swift
//  Loop
//
//  Created by Kai Azim on 2026-02-23.
//

import Foundation

enum PrivilegedHelperError: LocalizedError {
    case ownershipLookupFailed(url: URL)
    case ownershipChangeFailed(url: URL, code: Int32)
    case pathValidationFailed(operation: String, path: String, reason: String)
    case bundleValidationFailed(path: String, reason: String)
    case commandLineToolFailed(reason: String)
    /// Something other than Loop's link is at the path
    case commandLineToolOccupied(path: String)
    /// A system call on the link or its folder failed, with `errno` read where it failed
    case commandLineToolSystemCallFailed(action: String, path: String, code: Int32)

    var errorDescription: String? {
        switch self {
        case let .ownershipLookupFailed(url):
            return "Could not resolve ownership for \(url.path)"
        case let .ownershipChangeFailed(url, code):
            let message = String(cString: strerror(code))
            return "Failed to set ownership for \(url.path): \(message) (\(code))"
        case let .pathValidationFailed(operation, path, reason):
            return "Rejected privileged \(operation) path \(path): \(reason)"
        case let .bundleValidationFailed(path, reason):
            return "Rejected privileged bundle at \(path): \(reason)"
        case let .commandLineToolFailed(reason):
            return reason
        case let .commandLineToolOccupied(path):
            return "\(path) belongs to another app or file."
        case let .commandLineToolSystemCallFailed(action, path, code):
            return "Couldn’t \(action) \(path): \(String(cString: strerror(code)))"
        }
    }
}
