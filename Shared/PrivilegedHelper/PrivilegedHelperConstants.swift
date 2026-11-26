//
//  PrivilegedHelperConstants.swift
//  Loop
//
//  Created by Kai Azim on 2026-02-23.
//

import Foundation

enum PrivilegedHelperConstants {
    static let helperExecutableName = "LoopPrivilegedHelper"
    static let serviceName = "com.MrKai77.Loop.PrivilegedHelperJob"
    static let appBundleIdentifier = "com.MrKai77.Loop"
    static let authorizedClientRequirement = "identifier \"com.MrKai77.Loop\" and anchor apple generic and certificate leaf[subject.OU] = \"5F967GYF84\""

    /// What the helper checks before linking `loop-cli` into the user's path as root
    static let commandLineToolRequirement = "identifier \"loop-cli\" and anchor apple generic and certificate leaf[subject.OU] = \"5F967GYF84\""

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

    /// The app bundle around a tool at `Loop.app/Contents/MacOS/loop-cli`. Any app name matches, since Loop may have been renamed, e.g. "Loop 2.app".
    static func appBundleURL(containingCommandLineTool url: URL) -> URL? {
        let components = url.pathComponents
        guard components.count >= 4,
              components.suffix(3) == ["Contents", "MacOS", commandLineToolExecutableName],
              components[components.count - 4].hasSuffix(".app")
        else {
            return nil
        }

        return url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static func isLoopManagedCommandLineToolPath(_ path: String) -> Bool {
        appBundleURL(containingCommandLineTool: URL(fileURLWithPath: path)) != nil
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
