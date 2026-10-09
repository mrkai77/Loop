//
//  PrivilegedHelper.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-01.
//

import Foundation
import Scribe
import Security

@Loggable
final class PrivilegedHelper: NSObject, PrivilegedHelperProtocol {
    private struct AtomicSwapPaths {
        let currentURL: URL
        let stagedURL: URL
        let rollbackContainerURL: URL
        let backupBundleURL: URL
    }

    private struct RestorePaths {
        let currentURL: URL
        let rollbackContainerURL: URL
        let backupBundleURL: URL
    }

    private static let maxRollbackIDLength = 128
    private static let allowedRollbackIDScalars = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "._-"))

    private let context: PrivilegedHelperService.TrustedClientContext
    private let fileManager: FileManager

    init(
        context: PrivilegedHelperService.TrustedClientContext,
        fileManager: FileManager = .default
    ) {
        self.context = context
        self.fileManager = fileManager
    }

    func atomicSwap(rollbackID: String, withReply reply: @escaping (NSError?) -> ()) {
        do {
            try executeAtomicSwap(rollbackID: rollbackID)
            reply(nil)
        } catch {
            reply(Self.xpcError(error))
        }
    }

    func restoreFromBackup(rollbackID: String, withReply reply: @escaping (NSError?) -> ()) {
        do {
            try executeRestoreFromBackup(rollbackID: rollbackID)
            reply(nil)
        } catch {
            reply(Self.xpcError(error))
        }
    }

    func removeCurrentBundle(withReply reply: @escaping (NSError?) -> ()) {
        do {
            try executeRemoveCurrentBundle()
            reply(nil)
        } catch {
            reply(Self.xpcError(error))
        }
    }

    func installCommandLineTool(withReply reply: @escaping (NSError?) -> ()) {
        do {
            try executeInstallCommandLineTool()
            reply(nil)
        } catch {
            reply(Self.xpcError(error))
        }
    }

    func uninstallCommandLineTool(withReply reply: @escaping (NSError?) -> ()) {
        do {
            try executeUninstallCommandLineTool()
            reply(nil)
        } catch {
            reply(Self.xpcError(error))
        }
    }

    /// Swift error descriptions don't survive XPC, so send the message as a plain `NSError`
    private static func xpcError(_ error: Error) -> NSError {
        NSError(
            domain: "com.MrKai77.Loop.PrivilegedHelper",
            code: (error as NSError).code,
            userInfo: [NSLocalizedDescriptionKey: error.localizedDescription]
        )
    }

    /// Executes a privileged atomic swap using rollback-token-derived paths in user Application Support.
    private func executeAtomicSwap(rollbackID: String) throws {
        let operation = "atomic swap"

        do {
            let paths = try deriveAndValidateAtomicSwapPaths(
                for: rollbackID,
                operation: operation
            )
            try validateBundleForInstall(
                at: paths.stagedURL,
                operation: operation,
                rollbackID: rollbackID
            )

            try performAtomicSwap(
                currentURL: paths.currentURL,
                stagedURL: paths.stagedURL,
                rollbackContainerURL: paths.rollbackContainerURL,
                backupBundleURL: paths.backupBundleURL
            )
        } catch {
            log.error("Privileged \(operation) failed for rollbackID \(rollbackID): \(error.localizedDescription)")
            throw error
        }
    }

    /// Restores the current app directly from rollback-token-derived backup path in user Application Support.
    private func executeRestoreFromBackup(rollbackID: String) throws {
        let operation = "restore"

        do {
            let paths = try deriveAndValidateRestorePaths(
                for: rollbackID,
                operation: operation
            )

            guard fileManager.fileExists(atPath: paths.backupBundleURL.path) else {
                log.info("No backup found at \(paths.backupBundleURL.path); privileged restore is a no-op")
                return
            }

            try validateBundleForInstall(
                at: paths.backupBundleURL,
                operation: operation,
                rollbackID: rollbackID
            )

            try performRestoreFromBackup(
                currentURL: paths.currentURL,
                backupBundleURL: paths.backupBundleURL
            )
        } catch {
            log.error("Privileged \(operation) failed for rollbackID \(rollbackID): \(error.localizedDescription)")
            throw error
        }
    }

    /// Removes the authenticated client's current app bundle path.
    private func executeRemoveCurrentBundle() throws {
        let currentBundleURL = LoopSupportPaths.canonical(context.clientBundleURL)

        guard fileManager.fileExists(atPath: currentBundleURL.path) else {
            log.info("No current app bundle found at \(currentBundleURL.path); privileged cleanup is a no-op")
            return
        }

        try fileManager.removeItem(at: currentBundleURL)
        log.success("Removed current app bundle at \(currentBundleURL.path)")
    }

    private func executeInstallCommandLineTool() throws {
        let sourceURL = try validatedCommandLineToolSourceURL()
        let destinationURL = PrivilegedHelperConstants.commandLineToolSymlinkURL

        try ensureCommandLineToolInstallDirectoryExists()

        switch try commandLineToolLinkState() {
        case .missing:
            break
        case .loopManaged:
            // Removes the link itself, never its target
            do {
                try fileManager.removeItem(at: destinationURL)
            } catch {
                throw PrivilegedHelperError.commandLineToolFailed(
                    reason: "Couldn’t replace \(destinationURL.path): \(error.localizedDescription)"
                )
            }
        case .occupied:
            throw PrivilegedHelperError.commandLineToolFailed(
                reason: "\(destinationURL.path) is used by another app or file."
            )
        }

        do {
            try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
            log.success("Installed Loop CLI symlink at \(destinationURL.path) -> \(sourceURL.path)")
        } catch {
            throw PrivilegedHelperError.commandLineToolFailed(
                reason: "Couldn’t create \(destinationURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func executeUninstallCommandLineTool() throws {
        let destinationURL = PrivilegedHelperConstants.commandLineToolSymlinkURL

        switch try commandLineToolLinkState() {
        case .missing:
            return
        case .loopManaged:
            do {
                try fileManager.removeItem(at: destinationURL)
                log.success("Removed Loop CLI symlink at \(destinationURL.path)")
            } catch {
                throw PrivilegedHelperError.commandLineToolFailed(
                    reason: "Couldn’t remove \(destinationURL.path): \(error.localizedDescription)"
                )
            }
        case .occupied:
            throw PrivilegedHelperError.commandLineToolFailed(
                reason: "\(destinationURL.path) is used by another app or file."
            )
        }
    }

    private func commandLineToolLinkState() throws -> CommandLineToolLinkState {
        do {
            return try PrivilegedHelperConstants.commandLineToolLinkState(fileManager: fileManager)
        } catch {
            throw PrivilegedHelperError.commandLineToolFailed(
                reason: "Couldn’t inspect \(PrivilegedHelperConstants.commandLineToolSymlinkURL.path): \(error.localizedDescription)"
            )
        }
    }

    private func validatedCommandLineToolSourceURL() throws -> URL {
        let sourceURL = PrivilegedHelperConstants.commandLineToolURL(inBundle: context.clientBundleURL)

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw PrivilegedHelperError.commandLineToolFailed(
                reason: "This copy of Loop is missing its command-line tool at \(sourceURL.path)."
            )
        }

        guard fileManager.isExecutableFile(atPath: sourceURL.path) else {
            throw PrivilegedHelperError.commandLineToolFailed(
                reason: "The command-line tool at \(sourceURL.path) isn’t executable."
            )
        }

        return sourceURL
    }

    private func ensureCommandLineToolInstallDirectoryExists() throws {
        let installDirectoryURL = PrivilegedHelperConstants.commandLineToolInstallDirectoryURL

        do {
            // Succeeds if the folder already exists, and fails if a file is in the way
            try fileManager.createDirectory(at: installDirectoryURL, withIntermediateDirectories: true)
        } catch {
            throw PrivilegedHelperError.commandLineToolFailed(
                reason: "Couldn’t create \(installDirectoryURL.path): \(error.localizedDescription)"
            )
        }
    }

    /// Derives and validates atomic swap paths from trusted connection context and rollback token.
    private func deriveAndValidateAtomicSwapPaths(
        for rollbackID: String,
        operation: String
    ) throws -> AtomicSwapPaths {
        try validateRollbackID(rollbackID, operation: operation)

        let currentURL = LoopSupportPaths.canonical(context.clientBundleURL)
        let stagedURL = LoopSupportPaths.canonical(
            context.stagingRoot.appendingPathComponent(
                "\(context.clientBundleURL.lastPathComponent).staging",
                isDirectory: true
            )
        )
        let rollbackContainerURL = LoopSupportPaths.canonical(
            context.rollbackRoot.appendingPathComponent(rollbackID, isDirectory: true)
        )
        let backupBundleURL = LoopSupportPaths.canonical(
            rollbackContainerURL.appendingPathComponent(
                context.clientBundleURL.lastPathComponent,
                isDirectory: true
            )
        )

        try ensurePathInside(
            stagedURL,
            root: context.stagingRoot,
            operation: operation,
            rollbackID: rollbackID,
            role: "staged bundle",
            expectedDescription: "Loop staging directory"
        )
        try ensurePathInside(
            rollbackContainerURL,
            root: context.rollbackRoot,
            operation: operation,
            rollbackID: rollbackID,
            role: "rollback container",
            expectedDescription: "Loop rollback directory"
        )
        try ensurePathInside(
            backupBundleURL,
            root: context.rollbackRoot,
            operation: operation,
            rollbackID: rollbackID,
            role: "backup bundle",
            expectedDescription: "Loop rollback directory"
        )

        return AtomicSwapPaths(
            currentURL: currentURL,
            stagedURL: stagedURL,
            rollbackContainerURL: rollbackContainerURL,
            backupBundleURL: backupBundleURL
        )
    }

    /// Derives and validates restore paths from trusted connection context and rollback token.
    private func deriveAndValidateRestorePaths(
        for rollbackID: String,
        operation: String
    ) throws -> RestorePaths {
        try validateRollbackID(rollbackID, operation: operation)

        let currentURL = LoopSupportPaths.canonical(context.clientBundleURL)
        let rollbackContainerURL = LoopSupportPaths.canonical(
            context.rollbackRoot.appendingPathComponent(rollbackID, isDirectory: true)
        )
        let backupBundleURL = LoopSupportPaths.canonical(
            rollbackContainerURL.appendingPathComponent(
                context.clientBundleURL.lastPathComponent,
                isDirectory: true
            )
        )

        try ensurePathInside(
            rollbackContainerURL,
            root: context.rollbackRoot,
            operation: operation,
            rollbackID: rollbackID,
            role: "rollback container",
            expectedDescription: "Loop rollback directory"
        )
        try ensurePathInside(
            backupBundleURL,
            root: context.rollbackRoot,
            operation: operation,
            rollbackID: rollbackID,
            role: "backup bundle",
            expectedDescription: "Loop rollback directory"
        )

        return RestorePaths(
            currentURL: currentURL,
            rollbackContainerURL: rollbackContainerURL,
            backupBundleURL: backupBundleURL
        )
    }

    /// Validates bundle code signature using the same static validation path as non-privileged install flow.
    private func validateBundleForInstall(
        at bundleURL: URL,
        operation: String,
        rollbackID: String
    ) throws {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: bundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw bundleValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: bundleURL.path,
                reason: "Bundle path does not exist or is not a directory"
            )
        }

        var staticCode: SecStaticCode?
        let creationStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, SecCSFlags(), &staticCode)
        guard creationStatus == errSecSuccess, let staticCode else {
            throw bundleValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: bundleURL.path,
                reason: "Could not create static code object: \(securityErrorMessage(for: creationStatus))"
            )
        }

        let validationFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        let validationStatus = SecStaticCodeCheckValidity(staticCode, validationFlags, nil)
        guard validationStatus == errSecSuccess else {
            throw bundleValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: bundleURL.path,
                reason: "Code signature validation failed: \(securityErrorMessage(for: validationStatus))"
            )
        }
    }

    /// Validates rollback token format to prevent traversal and unexpected path materialization.
    private func validateRollbackID(_ rollbackID: String, operation: String) throws {
        guard !rollbackID.isEmpty else {
            throw pathValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: rollbackID,
                reason: "Rollback ID must not be empty"
            )
        }

        guard rollbackID.count <= Self.maxRollbackIDLength else {
            throw pathValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: rollbackID,
                reason: "Rollback ID exceeds \(Self.maxRollbackIDLength) characters"
            )
        }

        guard rollbackID != ".", rollbackID != ".." else {
            throw pathValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: rollbackID,
                reason: "Rollback ID cannot be a directory traversal segment"
            )
        }

        guard rollbackID.unicodeScalars.allSatisfy({ Self.allowedRollbackIDScalars.contains($0) }) else {
            throw pathValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: rollbackID,
                reason: "Rollback ID contains invalid characters"
            )
        }
    }

    /// Ensures a candidate path remains within the expected root after canonicalization.
    private func ensurePathInside(
        _ candidate: URL,
        root: URL,
        operation: String,
        rollbackID: String,
        role: String,
        expectedDescription: String
    ) throws {
        guard isPath(candidate, inside: root) else {
            throw pathValidationFailure(
                operation: operation,
                rollbackID: rollbackID,
                path: candidate.path,
                reason: "\(role) must be inside \(expectedDescription): \(root.path)"
            )
        }
    }

    /// Converts Security framework status codes to readable log/error strings.
    private func securityErrorMessage(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (OSStatus \(status))"
        }
        return "OSStatus \(status)"
    }

    /// Logs and constructs a privileged path validation failure with operation context.
    private func pathValidationFailure(
        operation: String,
        rollbackID: String,
        path: String,
        reason: String
    ) -> PrivilegedHelperError {
        log.warn(
            """
            Rejected privileged \(operation) path for pid \(context.clientPID), uid \(context.clientUID), rollbackID \(rollbackID). \
            Path: \(path). Reason: \(reason). \
            Expected support root: \(context.loopSupportRoot.path)
            """
        )

        return .pathValidationFailed(operation: operation, path: path, reason: reason)
    }

    /// Logs and constructs a privileged bundle validation failure with operation context.
    private func bundleValidationFailure(
        operation: String,
        rollbackID: String,
        path: String,
        reason: String
    ) -> PrivilegedHelperError {
        log.warn(
            """
            Rejected privileged \(operation) bundle for pid \(context.clientPID), uid \(context.clientUID), rollbackID \(rollbackID). \
            Bundle path: \(path). Reason: \(reason). \
            Expected support root: \(context.loopSupportRoot.path)
            """
        )

        return .bundleValidationFailed(path: path, reason: reason)
    }

    /// Returns true when a canonicalized URL is equal to or contained within a canonicalized root.
    private func isPath(_ url: URL, inside root: URL) -> Bool {
        let canonicalURLPath = LoopSupportPaths.canonical(url).path
        let canonicalRootPath = LoopSupportPaths.canonical(root).path
        return canonicalURLPath == canonicalRootPath || canonicalURLPath.hasPrefix("\(canonicalRootPath)/")
    }

    /// Moves current app to backup and installs the staged app atomically with rollback on failure.
    private func performAtomicSwap(
        currentURL: URL,
        stagedURL: URL,
        rollbackContainerURL: URL,
        backupBundleURL: URL
    ) throws {
        log.info("Starting privileged atomic swap")
        log.info("Current app: \(currentURL.path)")
        log.info("Staged app: \(stagedURL.path)")
        log.info("Rollback container: \(rollbackContainerURL.path)")
        log.info("Backup app: \(backupBundleURL.path)")

        let backupUID = context.clientUID
        let backupGID = context.clientGID
        log.success("Using backup ownership uid/gid from authenticated client (uid: \(backupUID), gid: \(backupGID))")

        try fileManager.createDirectory(at: rollbackContainerURL, withIntermediateDirectories: true)
        log.success("Backup directory ready at \(rollbackContainerURL.path)")
        try applyOwnership(to: rollbackContainerURL, uid: backupUID, gid: backupGID)
        log.success("Applied client ownership to rollback container")

        if fileManager.fileExists(atPath: backupBundleURL.path) {
            try fileManager.removeItem(at: backupBundleURL)
            log.success("Removed existing backup at \(backupBundleURL.path)")
        }

        try fileManager.moveItem(at: currentURL, to: backupBundleURL)
        log.success("Moved current app to backup location")
        try applyOwnershipRecursively(at: backupBundleURL, uid: backupUID, gid: backupGID)
        log.success("Applied client ownership to backup")

        do {
            try fileManager.moveItem(at: stagedURL, to: currentURL)
            log.success("Moved staged app into current location")
            try applyRootOwnershipRecursively(at: currentURL)
            log.success("Applied root ownership to installed app")
        } catch {
            log.warn("Swap failed after backup move; attempting rollback")

            do {
                if fileManager.fileExists(atPath: currentURL.path) {
                    try fileManager.removeItem(at: currentURL)
                    log.info("Removed partially installed app before rollback restore")
                }

                try fileManager.moveItem(at: backupBundleURL, to: currentURL)
                log.info("Moved backup app back into current location")
                try applyRootOwnershipRecursively(at: currentURL)
                log.success("Rollback to backup completed")
            } catch {
                log.error("Rollback to backup failed: \(error.localizedDescription)")
            }

            throw error
        }

        log.success("Privileged atomic swap completed")
    }

    /// Restores the app from backup and reapplies root ownership.
    private func performRestoreFromBackup(currentURL: URL, backupBundleURL: URL) throws {
        log.info("Starting privileged restore from backup")
        log.info("Current app: \(currentURL.path)")
        log.info("Backup app: \(backupBundleURL.path)")

        if fileManager.fileExists(atPath: currentURL.path) {
            try fileManager.removeItem(at: currentURL)
            log.success("Removed current app before restore")
        }

        try fileManager.moveItem(at: backupBundleURL, to: currentURL)
        try applyRootOwnershipRecursively(at: currentURL)
        log.success("Privileged restore completed")
    }

    /// Applies root ownership recursively to a directory tree.
    private func applyRootOwnershipRecursively(at url: URL) throws {
        log.info("Applying root ownership recursively at \(url.path)")
        try applyOwnershipRecursively(at: url, uid: 0, gid: 0)
        log.success("Applied root ownership recursively at \(url.path)")
    }

    /// Applies a target uid/gid recursively to the root URL and its descendants.
    private func applyOwnershipRecursively(at rootURL: URL, uid: uid_t, gid: gid_t) throws {
        var itemCount = 0
        try applyOwnership(to: rootURL, uid: uid, gid: gid)
        itemCount += 1

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil
        ) else {
            log.success("Applied ownership to \(itemCount) items under \(rootURL.path)")
            return
        }

        while let itemURL = enumerator.nextObject() as? URL {
            try applyOwnership(to: itemURL, uid: uid, gid: gid)
            itemCount += 1
        }

        log.success("Applied ownership to \(itemCount) items under \(rootURL.path)")
    }

    /// Applies ownership to a single filesystem entry using `lchown`.
    private func applyOwnership(to itemURL: URL, uid: uid_t, gid: gid_t) throws {
        let result: Int32 = itemURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return -1
            }
            return lchown(path, uid, gid)
        }

        guard result == 0 else {
            let errorCode = errno
            throw PrivilegedHelperError.ownershipChangeFailed(url: itemURL, code: errorCode)
        }

        log.success("Applied ownership to \(itemURL.path) (uid: \(uid), gid: \(gid))")
    }
}
