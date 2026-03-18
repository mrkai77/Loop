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

    /// Installs the Loop CLI symlink at the fixed privileged destination.
    func installCommandLineTool(
        withReply reply: @escaping (NSError?) -> ()
    )

    /// Reinstalls the Loop CLI symlink when the existing destination is already Loop-managed.
    func reinstallCommandLineTool(
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

    static let loopManagedCommandLineToolSuffix = "/Loop.app/Contents/MacOS/\(commandLineToolExecutableName)"
}
