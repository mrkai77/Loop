//
//  CommandLineToolStatus.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import Foundation

/// Whether the `loop` link is installed and points at this copy of Loop
enum CommandLineToolStatus: Equatable {
    case notInstalled
    case installedCurrent
    case installedStale
    /// The link points to a copy of Loop that was moved or deleted
    case installedMissing
    case installedWithoutAdministrator
    case blocked

    var settingsWarning: AttributedString? {
        let symlinkPath = PrivilegedHelperConstants.commandLineToolSymlinkURL.path

        return switch self {
        case .notInstalled, .installedCurrent:
            nil
        case .installedStale:
            AttributedString(localized: "`\(symlinkPath)` points to another copy of Loop. Click Repair to use this one.", comment: "Warning on the command-line tool row in Advanced settings, shown when the link points to a copy of Loop other than the one running. %@ is the path to the link, such as /usr/local/bin/loop.")
        case .installedMissing:
            AttributedString(localized: "`\(symlinkPath)` points to a copy of Loop that was moved or deleted. Click Repair to use this one.", comment: "Warning on the command-line tool row in Advanced settings, shown when the copy of Loop the link points to no longer exists. %@ is the path to the link, such as /usr/local/bin/loop.")
        case .installedWithoutAdministrator:
            AttributedString(localized: "`\(symlinkPath)` isn’t owned by an administrator, so another app could have created it. Click Repair to reinstall it.", comment: "Warning on the command-line tool row in Advanced settings, shown when the link wasn’t created with administrator privileges. %@ is the path to the link, such as /usr/local/bin/loop.")
        case .blocked:
            AttributedString(localized: "`\(symlinkPath)` belongs to another app or file. Remove it, then try again.", comment: "Warning on the command-line tool row in Advanced settings, shown when something other than Loop’s link is at that path. %@ is the path to the link, such as /usr/local/bin/loop.")
        }
    }

    /// Why Loop refuses commands from the CLI, or `nil` once it's installed
    var cliRefusalMessage: String? {
        let symlinkPath = PrivilegedHelperConstants.commandLineToolSymlinkURL.path

        return switch self {
        case .installedCurrent:
            nil
        case .notInstalled:
            "Loop only accepts commands while the command-line tool is installed. Install it in Loop’s Advanced settings."
        case .installedStale:
            "\(symlinkPath) points to another copy of Loop. Click Repair in Loop’s Advanced settings."
        case .installedMissing:
            "\(symlinkPath) points to a copy of Loop that was moved or deleted. Click Repair in Loop’s Advanced settings."
        case .installedWithoutAdministrator:
            "\(symlinkPath) isn’t owned by an administrator, so another app could have created it. Click Repair in Loop’s Advanced settings."
        case .blocked:
            "\(symlinkPath) belongs to another app or file. Remove it, then install the command-line tool in Loop’s Advanced settings."
        }
    }

    /// Only reads the link, so the socket can check it before every command without the privileged helper
    static func current(fileManager: FileManager = .default) throws -> Self {
        switch try PrivilegedHelperConstants.commandLineToolLinkState(fileManager: fileManager) {
        case .missing:
            return .notInstalled
        case .occupied:
            return .blocked
        case let .loopManaged(destinationURL, isOwnedByRoot):
            let currentCLIURL = PrivilegedHelperConstants.commandLineToolURL(inBundle: Bundle.main.bundleURL)

            guard destinationURL.path == currentCLIURL.path else {
                return fileManager.fileExists(atPath: destinationURL.path) ? .installedStale : .installedMissing
            }

            return isOwnedByRoot ? .installedCurrent : .installedWithoutAdministrator
        }
    }
}
