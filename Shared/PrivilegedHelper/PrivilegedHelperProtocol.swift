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
