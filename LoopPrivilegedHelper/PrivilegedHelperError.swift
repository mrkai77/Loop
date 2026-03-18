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
    case commandLineToolInstallFailed(reason: String)

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
        case let .commandLineToolInstallFailed(reason):
            return "Could not install Loop command-line tool: \(reason)"
        }
    }
}
