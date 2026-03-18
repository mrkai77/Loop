//
//  PrivilegedHelperService.swift
//  Loop
//
//  Created by Kai Azim on 2026-02-23.
//

import AppKit
import Darwin
import Foundation
import Scribe
import Security

@Loggable
final class PrivilegedHelperService: NSObject, NSXPCListenerDelegate {
    struct TrustedClientContext {
        let clientPID: pid_t
        let clientUID: uid_t
        let clientGID: gid_t
        let clientBundleURL: URL
        let loopSupportRoot: URL
        let stagingRoot: URL
        let rollbackRoot: URL
    }

    private let listener: NSXPCListener
    private let connectionStateLock = NSLock()
    private var activeConnectionPID: pid_t?

    init(serviceName: String) {
        self.listener = NSXPCListener(machServiceName: serviceName)
        super.init()
        listener.delegate = self
    }

    func run() {
        log.info("Starting privileged helper listener")
        listener.resume()
        log.success("Privileged helper listener is running")
        RunLoop.current.run()
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let pid = newConnection.processIdentifier
        log.info("Received new XPC connection request (pid: \(pid))")

        guard let context = trustedClientContext(for: newConnection) else {
            log.warn("Rejected XPC connection (pid: \(pid))")
            return false
        }

        guard reserveActiveConnection(for: pid) else {
            log.warn("Rejected XPC connection (pid: \(pid)) because another connection is already active")
            return false
        }

        newConnection.invalidationHandler = { [weak self] in
            self?.releaseActiveConnection(for: pid, reason: "invalidation")
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.releaseActiveConnection(for: pid, reason: "interruption")
        }
        newConnection.exportedInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        newConnection.exportedObject = PrivilegedHelper(context: context)
        newConnection.resume()
        log.success("Accepted XPC connection (pid: \(pid), uid: \(context.clientUID))")

        return true
    }

    private func trustedClientContext(for connection: NSXPCConnection) -> TrustedClientContext? {
        let pid = connection.processIdentifier
        guard pid > 0 else {
            log.warn("Rejecting client with invalid pid: \(pid)")
            return nil
        }

        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier == PrivilegedHelperConstants.appBundleIdentifier else {
            log.warn("Rejecting client pid \(pid) due to bundle identifier mismatch")
            return nil
        }

        guard validateCodeSignature(forProcessID: pid) else {
            return nil
        }

        guard let bundleURL = app.bundleURL else {
            log.warn("Rejecting client pid \(pid) because bundle URL could not be resolved")
            return nil
        }

        let clientUID = connection.effectiveUserIdentifier
        guard let accountInfo = userAccountInfo(for: clientUID) else {
            log.warn("Rejecting client pid \(pid) because home directory for uid \(clientUID) could not be resolved")
            return nil
        }

        let homeDirectory = accountInfo.homeDirectory
        let clientGID = accountInfo.primaryGroupID
        let canonicalBundleURL = LoopSupportPaths.canonical(bundleURL)
        let canonicalHomeDirectory = LoopSupportPaths.canonical(homeDirectory)
        let loopSupportRoot = LoopSupportPaths.loopDirectory(homeDirectory: canonicalHomeDirectory)
        let stagingRoot = LoopSupportPaths.stagingDirectory(homeDirectory: canonicalHomeDirectory)
        let rollbackRoot = LoopSupportPaths.rollbackDirectory(homeDirectory: canonicalHomeDirectory)

        return TrustedClientContext(
            clientPID: pid,
            clientUID: clientUID,
            clientGID: clientGID,
            clientBundleURL: canonicalBundleURL,
            loopSupportRoot: loopSupportRoot,
            stagingRoot: stagingRoot,
            rollbackRoot: rollbackRoot
        )
    }

    private func validateCodeSignature(forProcessID pid: pid_t) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
        let guestStatus = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &code)

        guard guestStatus == errSecSuccess, let code else {
            log.error("Failed to copy guest code for pid \(pid), status \(guestStatus)")
            return false
        }

        var requirement: SecRequirement?
        let requirementStatus = SecRequirementCreateWithString(
            PrivilegedHelperConstants.authorizedClientRequirement as CFString,
            SecCSFlags(),
            &requirement
        )

        guard requirementStatus == errSecSuccess, let requirement else {
            log.error("Failed creating requirement, status \(requirementStatus)")
            return false
        }

        let validationStatus = SecCodeCheckValidity(code, SecCSFlags(), requirement)
        guard validationStatus == errSecSuccess else {
            log.error("Code signature requirement check failed for pid \(pid), status \(validationStatus)")
            return false
        }

        log.success("Code signature requirement check passed for pid \(pid)")
        return true
    }

    private func userAccountInfo(for uid: uid_t) -> (homeDirectory: URL, primaryGroupID: gid_t)? {
        guard let passwdEntry = getpwuid(uid) else {
            return nil
        }

        let homePath = String(cString: passwdEntry.pointee.pw_dir)
        guard !homePath.isEmpty else {
            return nil
        }

        return (
            homeDirectory: URL(fileURLWithPath: homePath, isDirectory: true),
            primaryGroupID: passwdEntry.pointee.pw_gid
        )
    }

    private func reserveActiveConnection(for pid: pid_t) -> Bool {
        connectionStateLock.lock()
        defer { connectionStateLock.unlock() }

        guard activeConnectionPID == nil else {
            return false
        }

        activeConnectionPID = pid
        return true
    }

    private func releaseActiveConnection(for pid: pid_t, reason: String) {
        connectionStateLock.lock()
        defer { connectionStateLock.unlock() }

        guard activeConnectionPID == pid else {
            return
        }

        activeConnectionPID = nil
        log.info("Released active XPC connection state for pid \(pid) (\(reason))")
    }
}
