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
        case installedWithoutAdministrator
        case blocked

        var warning: LocalizedStringKey? {
            let symlinkPath = PrivilegedHelperConstants.commandLineToolSymlinkURL.path

            return switch self {
            case .notInstalled, .installedCurrent:
                nil
            case .installedStale:
                "`\(symlinkPath)` points to another copy of Loop. Click Repair to use this one."
            case .installedWithoutAdministrator:
                "`\(symlinkPath)` wasn’t installed by Loop. Click Repair to reinstall it."
            case .blocked:
                "`\(symlinkPath)` is used by another app or file. Remove it, then try again."
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
                return .installedStale
            }

            return isOwnedByRoot ? .installedCurrent : .installedWithoutAdministrator
        }
    }

    /// Installs the tool, replacing an existing Loop-managed link
    func install() async throws {
        try await privilegedHelperCoordinator.withPrivilegedSession(
            prompt: String(localized: "\(Bundle.main.appName) is trying to install its command-line tool.")
        ) { session in
            try await session.installCommandLineTool()
        }
    }

    func uninstall() async throws {
        try await privilegedHelperCoordinator.withPrivilegedSession(
            prompt: String(localized: "\(Bundle.main.appName) is trying to uninstall its command-line tool.")
        ) { session in
            try await session.uninstallCommandLineTool()
        }
    }
}
