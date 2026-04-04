//
//  PrivilegedHelperCoordinator.swift
//  Loop
//
//  Created by Kai Azim on 2026-02-23.
//

import Foundation
import Scribe
import Security
import ServiceManagement

private struct PrivilegedHelperCoordinatorError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

@Loggable
final class PrivilegedHelperCoordinator {
    enum PrivilegedHelperReadiness {
        case available
        case unavailable(reason: String)
    }

    final class PrivilegedSession {
        private unowned let coordinator: PrivilegedHelperCoordinator
        private let connection: NSXPCConnection

        fileprivate init(coordinator: PrivilegedHelperCoordinator, connection: NSXPCConnection) {
            self.coordinator = coordinator
            self.connection = connection
        }

        func atomicSwap(rollbackID: String) async throws {
            let operation = PrivilegedOperation.atomicSwap(rollbackID: rollbackID)
            try await coordinator.performXPCOperation(connection: connection, operation: operation)
        }

        func restoreFromBackup(rollbackID: String) async throws {
            let operation = PrivilegedOperation.restore(rollbackID: rollbackID)
            try await coordinator.performXPCOperation(connection: connection, operation: operation)
        }

        func removeCurrentBundle() async throws {
            let operation = PrivilegedOperation.removeCurrentBundle
            try await coordinator.performXPCOperation(connection: connection, operation: operation)
        }

        func installCommandLineTool() async throws {
            let operation = PrivilegedOperation.installCommandLineTool
            try await coordinator.performXPCOperation(connection: connection, operation: operation)
        }

        func reinstallCommandLineTool() async throws {
            let operation = PrivilegedOperation.reinstallCommandLineTool
            try await coordinator.performXPCOperation(connection: connection, operation: operation)
        }
    }

    private final class ContinuationCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var didComplete = false

        func tryComplete() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !didComplete else { return false }
            didComplete = true
            return true
        }
    }

    private let fileManager: FileManager
    private let operationTimeout: Duration = .seconds(90)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func privilegedHelperReadiness() -> PrivilegedHelperReadiness {
        do {
            _ = try helperExecutableURL()
            return .available
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
    }

    func withPrivilegedSession<T>(
        prompt: String = "\(Bundle.main.appName) needs administrator permission to perform this action.",
        _ body: (PrivilegedSession) async throws -> T
    ) async throws -> T {
        let helperURL = try helperExecutableURL()

        var authRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authRef)

        guard createStatus == errAuthorizationSuccess, let authRef else {
            throw operationFailed(
                "Could not request administrator authorization: \(authorizationErrorMessage(for: createStatus))"
            )
        }

        defer {
            AuthorizationFree(authRef, [.destroyRights])
        }

        try requestPrivilegedHelperAuthorizationRight(authRef, prompt: prompt)

        let serviceName = PrivilegedHelperConstants.serviceName
        let jobDictionary = makeJobDictionary(serviceName: serviceName, helperPath: helperURL.path)

        try submit(jobDictionary, authRef: authRef)
        defer {
            removeSubmittedJob(serviceName: serviceName, authRef: authRef)
        }

        try await Task.sleep(for: .milliseconds(250))

        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: PrivilegedHelperProtocol.self)
        connection.resume()

        defer {
            connection.invalidationHandler = nil
            connection.interruptionHandler = nil
            connection.invalidate()
        }

        let session = PrivilegedSession(coordinator: self, connection: connection)
        return try await body(session)
    }

    private func performXPCOperation(connection: NSXPCConnection, operation: PrivilegedOperation) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let completion = ContinuationCompletion()
            var timeoutTask: Task<(), Never>?

            let finish: (Result<(), Error>) -> () = { result in
                guard completion.tryComplete() else { return }
                timeoutTask?.cancel()
                connection.interruptionHandler = nil
                connection.invalidationHandler = nil
                switch result {
                case .success:
                    continuation.resume(returning: ())
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }

            connection.interruptionHandler = {
                self.log.warn("Privileged helper \(operation.name) interrupted during shared session")
                finish(.failure(self.operationFailed("Privileged helper \(operation.name) interrupted")))
            }
            connection.invalidationHandler = {
                self.log.warn("Privileged helper \(operation.name) invalidated during shared session")
                finish(.failure(self.operationFailed("Privileged helper \(operation.name) invalidated")))
            }

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                self.log.warn("Privileged helper \(operation.name) transport failed during shared session: \(error.localizedDescription)")
                finish(.failure(self.operationFailed("Privileged helper \(operation.name) transport failed: \(error.localizedDescription)")))
            }) as? PrivilegedHelperProtocol else {
                self.log.warn("Failed to connect to privileged helper for \(operation.name)")
                finish(.failure(self.operationFailed("Failed to connect to privileged helper")))
                return
            }

            operation.invoke(on: proxy) { error in
                if let error {
                    finish(.failure(self.operationFailed(error.localizedDescription)))
                } else {
                    finish(.success(()))
                }
            }

            timeoutTask = Task {
                do {
                    try await Task.sleep(for: self.operationTimeout)
                } catch {
                    return
                }

                self.log.warn("Privileged helper \(operation.name) timed out during shared session")
                finish(.failure(self.operationFailed("Privileged helper \(operation.name) timed out")))
            }
        }
    }

    private func helperExecutableURL() throws -> URL {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LaunchServices", isDirectory: true)
            .appendingPathComponent(PrivilegedHelperConstants.helperExecutableName, isDirectory: false)

        let canonicalHelperURL = helperURL.resolvingSymlinksInPath().standardizedFileURL
        let helperPath = canonicalHelperURL.path

        guard fileManager.fileExists(atPath: helperPath) else {
            throw operationFailed("Privileged helper executable was not found at \(helperPath)")
        }

        guard fileManager.isExecutableFile(atPath: helperPath) else {
            throw operationFailed("Privileged helper executable is not executable at \(helperPath)")
        }

        return canonicalHelperURL
    }

    private func requestPrivilegedHelperAuthorizationRight(_ authRef: AuthorizationRef, prompt: String) throws {
        let rightName = privilegedHelperAuthorizationRightName()

        let getStatus = rightName.withCString { AuthorizationRightGet($0, nil) }
        if getStatus == errAuthorizationDenied {
            let setStatus = rightName.withCString { rightNameCString in
                AuthorizationRightSet(
                    authRef,
                    rightNameCString,
                    kAuthorizationRuleAuthenticateAsAdmin as CFTypeRef,
                    prompt as CFString,
                    nil,
                    nil
                )
            }

            if setStatus != errAuthorizationSuccess {
                log.warn("Failed to set privileged helper authorization right \(rightName): \(authorizationErrorMessage(for: setStatus))")
            }
        } else if getStatus != errAuthorizationSuccess {
            log.warn("Failed to retrieve privileged helper authorization right \(rightName): \(authorizationErrorMessage(for: getStatus))")
        }

        let rightsStatus: OSStatus = rightName.withCString { rightNameCString in
            var requestedRight = AuthorizationItem(
                name: rightNameCString,
                valueLength: 0,
                value: nil,
                flags: 0
            )

            return withUnsafeMutablePointer(to: &requestedRight) { rightPtr in
                var requestedRights = AuthorizationRights(count: 1, items: rightPtr)
                return AuthorizationCopyRights(
                    authRef,
                    &requestedRights,
                    nil,
                    [.interactionAllowed, .extendRights],
                    nil
                )
            }
        }

        guard rightsStatus == errAuthorizationSuccess else {
            throw operationFailed(
                "Authorization rights request failed: \(authorizationErrorMessage(for: rightsStatus))"
            )
        }

        log.info("Authorization rights granted for one-shot privileged helper")
    }

    private func privilegedHelperAuthorizationRightName() -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? PrivilegedHelperConstants.appBundleIdentifier
        return "\(bundleIdentifier).privileged-helper-auth"
    }

    private func makeJobDictionary(serviceName: String, helperPath: String) -> [String: Any] {
        [
            "Label": serviceName,
            "ProgramArguments": [
                helperPath
            ],
            "MachServices": [
                serviceName: true
            ],
            "RunAtLoad": true,
            "LaunchOnlyOnce": true
        ]
    }

    private func submit(_ jobDictionary: [String: Any], authRef: AuthorizationRef) throws {
        var error: Unmanaged<CFError>?
        let success = SMJobSubmit(
            kSMDomainSystemLaunchd,
            jobDictionary as CFDictionary,
            authRef,
            &error
        )

        guard success else {
            let details = error?.takeRetainedValue().localizedDescription ?? "Unknown privileged submission failure"
            throw operationFailed("Privileged helper submission failed: \(details)")
        }
    }

    private func removeSubmittedJob(serviceName: String, authRef: AuthorizationRef) {
        var error: Unmanaged<CFError>?
        let removed = SMJobRemove(
            kSMDomainSystemLaunchd,
            serviceName as CFString,
            authRef,
            true,
            &error
        )

        guard !removed else {
            return
        }

        let details = error?.takeRetainedValue().localizedDescription ?? "Unknown cleanup failure"
        log.warn("Failed to remove privileged helper job \(serviceName): \(details)")
    }

    private func authorizationErrorMessage(for status: OSStatus) -> String {
        if status == errAuthorizationCanceled {
            return "User canceled administrator authorization (OSStatus \(status))"
        }

        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (OSStatus \(status))"
        }

        return "OSStatus \(status)"
    }

    private func operationFailed(_ message: String) -> Error {
        PrivilegedHelperCoordinatorError(message: message)
    }
}

private enum PrivilegedOperation {
    case atomicSwap(rollbackID: String)
    case restore(rollbackID: String)
    case removeCurrentBundle
    case installCommandLineTool
    case reinstallCommandLineTool

    var name: String {
        switch self {
        case .atomicSwap:
            "atomic swap"
        case .restore:
            "restore"
        case .removeCurrentBundle:
            "remove current bundle"
        case .installCommandLineTool:
            "install command-line tool"
        case .reinstallCommandLineTool:
            "reinstall command-line tool"
        }
    }

    func invoke(on proxy: PrivilegedHelperProtocol, reply: @escaping (NSError?) -> ()) {
        switch self {
        case let .atomicSwap(rollbackID):
            proxy.atomicSwap(rollbackID: rollbackID, withReply: reply)
        case let .restore(rollbackID):
            proxy.restoreFromBackup(rollbackID: rollbackID, withReply: reply)
        case .removeCurrentBundle:
            proxy.removeCurrentBundle(withReply: reply)
        case .installCommandLineTool:
            proxy.installCommandLineTool(withReply: reply)
        case .reinstallCommandLineTool:
            proxy.reinstallCommandLineTool(withReply: reply)
        }
    }
}
