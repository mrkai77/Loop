//
//  CommandLineToolInstaller.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-29.
//

import SwiftUI

final class CommandLineToolInstaller {
    enum Status: Equatable {
        case notInstalled
        case installedCurrent
        case installedStale
        /// The link points to a copy of Loop that was moved or deleted
        case installedMissing
        case installedWithoutAdministrator
        case blocked

        var warning: AttributedString? {
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
    }

    private let privilegedHelperCoordinator: PrivilegedHelperCoordinator
    private let fileManager: FileManager

    init(
        privilegedHelperCoordinator: PrivilegedHelperCoordinator = PrivilegedHelperCoordinator(),
        fileManager: FileManager = .default
    ) {
        self.privilegedHelperCoordinator = privilegedHelperCoordinator
        self.fileManager = fileManager
    }

    func status() throws -> Status {
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

    /// Installs the tool, replacing an existing Loop-managed link
    func install() async throws {
        try await privilegedHelperCoordinator.withPrivilegedSession(
            prompt: String(localized: "\(Bundle.main.appName) is trying to install its command-line tool.", comment: "Administrator password prompt shown before installing or repairing the command-line tool. %@ is the app’s name.")
        ) { session in
            try await session.installCommandLineTool()
        }
    }

    func uninstall() async throws {
        try await privilegedHelperCoordinator.withPrivilegedSession(
            prompt: String(localized: "\(Bundle.main.appName) is trying to uninstall its command-line tool.", comment: "Administrator password prompt shown before uninstalling the command-line tool. %@ is the app’s name.")
        ) { session in
            try await session.uninstallCommandLineTool()
        }
    }
}
