//
//  PrivilegedHelperProtocol.swift
//  Loop
//
//  Created by Kai Azim on 2026-02-23.
//

import Foundation

@objc protocol PrivilegedHelperProtocol {
    /// Performs a privileged swap using a validated rollback token-derived path set.
    func atomicSwap(
        rollbackID: String,
        withReply reply: @escaping (NSError?) -> ()
    )

    /// Restores the current app from the rollback snapshot identified by the rollback token.
    func restoreFromBackup(
        rollbackID: String,
        withReply reply: @escaping (NSError?) -> ()
    )

    /// Removes the authenticated client's current app bundle.
    func removeCurrentBundle(
        withReply reply: @escaping (NSError?) -> ()
    )

    /// Installs the Loop CLI symlink at the fixed privileged destination, replacing it only when it's Loop-managed.
    func installCommandLineTool(
        withReply reply: @escaping (NSError?) -> ()
    )

    /// Removes the Loop CLI symlink, but only when it's Loop-managed.
    func uninstallCommandLineTool(
        withReply reply: @escaping (NSError?) -> ()
    )
}

enum PrivilegedHelperConstants {
    static let helperExecutableName = "LoopPrivilegedHelper"
    static let serviceName = "com.MrKai77.Loop.PrivilegedHelperJob"
    static let appBundleIdentifier = "com.MrKai77.Loop"
    static let authorizedClientRequirement = "identifier \"com.MrKai77.Loop\" and anchor apple generic and certificate leaf[subject.OU] = \"5F967GYF84\""

    static let commandLineToolExecutableName = "loop-cli"
    static let commandLineToolSymlinkName = "loop"
    static let commandLineToolInstallDirectory = "/usr/local/bin"

    static var commandLineToolInstallDirectoryURL: URL {
        URL(fileURLWithPath: commandLineToolInstallDirectory, isDirectory: true)
    }

    static var commandLineToolSymlinkURL: URL {
        commandLineToolInstallDirectoryURL.appendingPathComponent(commandLineToolSymlinkName, isDirectory: false)
    }

    static func commandLineToolURL(inBundle bundleURL: URL) -> URL {
        LoopSupportPaths.canonical(
            bundleURL
                .appendingPathComponent("Contents/MacOS", isDirectory: true)
                .appendingPathComponent(commandLineToolExecutableName, isDirectory: false)
        )
    }

    /// Matches the tool inside any app bundle, since Loop may have been renamed, e.g. "Loop 2.app"
    private static func isLoopManagedCommandLineToolPath(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).pathComponents
        guard components.count >= 4 else { return false }
        return components.suffix(3) == ["Contents", "MacOS", commandLineToolExecutableName]
            && components[components.count - 4].hasSuffix(".app")
    }

    /// Inspects the entry at `commandLineToolSymlinkURL` without following it
    static func commandLineToolLinkState(fileManager: FileManager = .default) throws -> CommandLineToolLinkState {
        let linkPath = commandLineToolSymlinkURL.path

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: linkPath)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        }

        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink else {
            return .occupied
        }

        // Resolve the raw target rather than the link URL, which stays unresolved when the target is gone
        let rawTarget = try fileManager.destinationOfSymbolicLink(atPath: linkPath)
        let destinationURL = LoopSupportPaths.canonical(
            URL(fileURLWithPath: rawTarget, relativeTo: commandLineToolInstallDirectoryURL)
        )

        guard isLoopManagedCommandLineToolPath(destinationURL.path) else {
            return .occupied
        }

        let isOwnedByRoot = (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0
        return .loopManaged(destinationURL: destinationURL, isOwnedByRoot: isOwnedByRoot)
    }
}

enum CommandLineToolLinkState: Equatable {
    case missing
    /// A symlink to a `loop-cli` inside an app bundle
    case loopManaged(destinationURL: URL, isOwnedByRoot: Bool)
    case occupied
}
