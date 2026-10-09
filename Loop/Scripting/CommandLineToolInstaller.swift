//
//  CommandLineToolInstaller.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-29.
//

import Darwin
import SwiftUI

final class CommandLineToolInstaller {
    enum Status: Equatable {
        case notInstalled
        case installedCurrent
        case installedStale
        case blocked

        var warning: LocalizedStringKey? {
            switch self {
            case .notInstalled, .installedCurrent:
                nil
            case .installedStale:
                "`/usr/local/bin/loop` points to another copy of Loop. Click Repair to use this one."
            case .blocked:
                "`/usr/local/bin/loop` is used by another app or file. Remove it, then try again."
            }
        }
    }

    private enum ExistingFilesystemEntry {
        case missing
        case symbolicLink
        case other
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
        let symlinkURL = PrivilegedHelperConstants.commandLineToolSymlinkURL

        switch try filesystemEntry(at: symlinkURL) {
        case .missing:
            return .notInstalled
        case .other:
            return .blocked
        case .symbolicLink:
            let rawTarget = try fileManager.destinationOfSymbolicLink(atPath: symlinkURL.path)
            guard isLoopManagedCommandLineToolTarget(rawTarget) else {
                return .blocked
            }

            let currentCLIURL = currentBundledCommandLineToolURL()
            let installedCLIURL = resolvedSymbolicLinkDestinationURL(
                rawTarget,
                relativeTo: symlinkURL.deletingLastPathComponent()
            )

            return installedCLIURL.path == currentCLIURL.path ? .installedCurrent : .installedStale
        }
    }

    func install() async throws {
        try await privilegedHelperCoordinator.withPrivilegedSession(
            prompt: String(localized: "\(Bundle.main.appName) is trying to install its command-line tool.")
        ) { session in
            try await session.installCommandLineTool()
        }
    }

    func reinstall() async throws {
        try await privilegedHelperCoordinator.withPrivilegedSession(
            prompt: String(localized: "\(Bundle.main.appName) is trying to update its command-line tool.")
        ) { session in
            try await session.reinstallCommandLineTool()
        }
    }

    func uninstall() async throws {
        try await privilegedHelperCoordinator.withPrivilegedSession(
            prompt: String(localized: "\(Bundle.main.appName) is trying to uninstall its command-line tool.")
        ) { session in
            try await session.uninstallCommandLineTool()
        }
    }

    private func currentBundledCommandLineToolURL() -> URL {
        LoopSupportPaths.canonical(
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(PrivilegedHelperConstants.commandLineToolExecutableName, isDirectory: false)
        )
    }

    private func resolvedSymbolicLinkDestinationURL(_ targetPath: String, relativeTo baseURL: URL) -> URL {
        if targetPath.hasPrefix("/") {
            return URL(fileURLWithPath: targetPath).resolvingSymlinksInPath().standardizedFileURL
        }

        return URL(fileURLWithPath: targetPath, relativeTo: baseURL)
            .resolvingSymlinksInPath()
            .standardizedFileURL
    }

    private func isLoopManagedCommandLineToolTarget(_ targetPath: String) -> Bool {
        PrivilegedHelperConstants.isLoopManagedCommandLineToolPath(
            resolvedSymbolicLinkDestinationURL(
                targetPath,
                relativeTo: PrivilegedHelperConstants.commandLineToolInstallDirectoryURL
            )
            .path
        )
    }

    private func filesystemEntry(at url: URL) throws -> ExistingFilesystemEntry {
        var statBuffer = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Int(lstat(path, &statBuffer))
        }

        if result == 0 {
            let fileType = statBuffer.st_mode & S_IFMT
            return fileType == S_IFLNK ? .symbolicLink : .other
        }

        if errno == ENOENT {
            return .missing
        }

        throw NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
        )
    }
}
