//
//  CommandLineToolInstaller.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-29.
//

import Foundation

/// Installs and removes the `loop` link with the privileged helper
final class CommandLineToolInstaller {
    private let privilegedHelperCoordinator: PrivilegedHelperCoordinator

    init(privilegedHelperCoordinator: PrivilegedHelperCoordinator = PrivilegedHelperCoordinator()) {
        self.privilegedHelperCoordinator = privilegedHelperCoordinator
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
