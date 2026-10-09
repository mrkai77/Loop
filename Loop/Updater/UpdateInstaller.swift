//
//  UpdateInstaller.swift
//  Loop
//
//  Created by Kami on 2026-01-22.
//

import AppKit
import Foundation
import Scribe
import Security

@Loggable
actor UpdateInstaller {
    enum InstallationPermissionState {
        case writable
        case needsElevation(reason: String)
        case notWritableNoElevationPossible(reason: String)
    }

    // MARK: - Properties

    private let backupManager: BackupManager
    private let fileManager: FileManager
    private let privilegedHelperCoordinator: PrivilegedHelperCoordinator

    private var isCancelled = false
    private var relocateToApplications = false
    private var installedAppURL: URL = Bundle.main.bundleURL
    private var installationPermissionState: InstallationPermissionState = .writable

    private var userHomeDirectory: URL {
        LoopSupportPaths.canonical(fileManager.homeDirectoryForCurrentUser)
    }

    private var stagingRootDirectory: URL {
        LoopSupportPaths.stagingDirectory(homeDirectory: userHomeDirectory)
    }

    private var rollbackRootDirectory: URL {
        LoopSupportPaths.rollbackDirectory(homeDirectory: userHomeDirectory)
    }

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.backupManager = BackupManager(fileManager: fileManager)
        self.privilegedHelperCoordinator = PrivilegedHelperCoordinator()
    }

    func installUpdate(
        from downloadURL: URL,
        manifest: UpdateManifest,
        progress: @escaping @MainActor @Sendable (UpdateProgress) -> ()
    ) async throws {
        log.info("Starting installation of update: \(manifest.version)")

        // Step 1: Pre-installation verification
        try await performPreInstallationChecks(manifest: manifest)
        await progress(UpdateProgress(phase: .checking, percentage: 1.0 / 8.0))

        // Step 2: Verify download integrity
        try await verifyDownloadIntegrity(downloadURL, manifest: manifest)
        await progress(UpdateProgress(phase: .downloading, percentage: 2.0 / 8.0))

        // Step 3: Extract and verify
        let extractedURL = try await extract(downloadURL)
        await progress(UpdateProgress(phase: .extracting, percentage: 3.0 / 8.0))

        // Step 4: Verify extraction integrity
        try await verifyExtractionIntegrity(extractedURL, manifest: manifest)
        await progress(UpdateProgress(phase: .verifying, percentage: 4.0 / 8.0))

        // Step 5: Perform safe installation
        try await performSafeInstallation(from: extractedURL, manifest: manifest)
        await progress(UpdateProgress(phase: .installing, percentage: 5.0 / 8.0))

        // Step 6: Comprehensive verification
        try await performFinalVerification(manifest: manifest)
        await progress(UpdateProgress(phase: .verifying, percentage: 6.0 / 8.0))

        // Step 7: Cleanup
        try await performSafeCleanup(extractedURL, downloadURL)
        await progress(UpdateProgress(phase: .cleaning, percentage: 7.0 / 8.0))

        try performPreRestartSafetyChecks()
        await progress(UpdateProgress(phase: .verifying, percentage: 8.0 / 8.0))

        log.success("Installation completed successfully")
    }

    func restartApplication() async {
        log.info("Preparing application restart from: \(installedAppURL.path)")

        // Verify the app exists before attempting restart
        guard fileManager.fileExists(atPath: installedAppURL.path) else {
            log.error("Application not found at path before restart: \(installedAppURL.path)")
            return
        }

        log.notice("Application will now restart. New instance will launch in 0.5 seconds.")

        let appURL = installedAppURL
        let process = Process()
        process.launchPath = "/bin/sh"
        process.arguments = ["-c", "sleep 0.5; open \"\(appURL.path)\""]
        process.launch()

        await MainActor.run {
            NSApp.terminate(nil)
        }
    }

    func cancel() async {
        log.warn("Cancelling installation")
        isCancelled = true
    }

    // MARK: - Pre-Installation Safety Checks

    private func performPreInstallationChecks(manifest: UpdateManifest) async throws {
        log.info("Performing pre-installation safety checks")

        try checkCancellation()

        let checks: [(String, () async throws -> ())] = [
            ("disk space", { try await self.verifyDiskSpace(manifest: manifest) }),
            ("current app integrity", { try await self.verifyCurrentAppIntegrity() }),
            ("installation permissions", { try await self.verifyInstallationPermissions() }),
            ("conflicting processes", { try await self.checkForConflictingRunningProcesses() }),
            ("app location", { try await self.checkAppLocationAndOfferRelocation() })
        ]

        for (checkName, check) in checks {
            do {
                try await check()
                log.debug("\(checkName) check passed")
            } catch {
                log.error("\(checkName) check failed: \(error)")
                throw error
            }
        }

        log.success("All pre-installation safety checks passed")
    }

    private func checkAppLocationAndOfferRelocation() async throws {
        let location = AppLocation.current

        switch location {
        case .systemApplications, .userApplications:
            log.info("App is in Applications folder: \(location)")
            relocateToApplications = false
        case let .other(path):
            log.warn("App is not in Applications folder: \(path)")

            let shouldRelocate = await askUserForRelocation()

            if shouldRelocate {
                log.info("User chose to install to Applications folder")
                relocateToApplications = true
            } else {
                log.info("User chose to keep current location. Update will install to: \(path)")
                relocateToApplications = false
            }
        }
    }

    @MainActor
    private func askUserForRelocation() async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Move to Applications Folder?")
        alert.informativeText = String(localized: "\(Bundle.main.appName) isn’t in your Applications folder. Would you like to install the update to your Applications folder instead?")
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Install in Applications Folder"))
        alert.addButton(withTitle: String(localized: "Keep in Current Location"))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func verifyDiskSpace(manifest _: UpdateManifest) async throws {
        log.info("Verifying disk space requirements")

        let currentAppSize = try fileManager.calculateDirectorySize(Bundle.main.bundleURL)
        let requiredSpace = currentAppSize * 3 // Current app + backup + new app

        let availableSpace = try getAvailableDiskSpace()

        guard availableSpace > requiredSpace else {
            let errorMessage =
                "Insufficient disk space. Required: \(requiredSpace.formattedBytes), Available: \(availableSpace.formattedBytes)"
            log.error("\(errorMessage)")
            throw UpdateError.installationFailed(errorMessage)
        }

        log.success("Disk space verification passed. Available: \(availableSpace.formattedBytes), Required: \(requiredSpace.formattedBytes)")
    }

    private func verifyCurrentAppIntegrity() async throws {
        try validateAppBundle(Bundle.main.bundleURL, skipVersionCheck: true)
        log.success("Current application integrity verified")
    }

    private func verifyInstallationPermissions() async throws {
        log.info("Verifying installation permissions")

        let currentAppURL = Bundle.main.bundleURL
        let parentDirectory = currentAppURL.deletingLastPathComponent()

        guard fileManager.isWritableFile(atPath: parentDirectory.path) else {
            installationPermissionState = permissionStateForRestrictedInstallLocation(
                baseReason: "No write permissions to application directory: \(parentDirectory.path)"
            )
            return
        }

        let testFile = parentDirectory.appendingPathComponent("loop_permission_test_\(UUID().uuidString)")

        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try fileManager.removeItem(at: testFile)
            installationPermissionState = .writable
            log.success("Installation permissions verified")
        } catch {
            try? fileManager.removeItem(at: testFile)

            guard isExplicitPermissionError(error) else {
                throw UpdateError.installationFailed("Cannot verify installation permissions: \(error.localizedDescription)")
            }

            installationPermissionState = permissionStateForRestrictedInstallLocation(
                baseReason: "Cannot write to application directory: \(error.localizedDescription)"
            )
        }
    }

    private func permissionStateForRestrictedInstallLocation(baseReason: String) -> InstallationPermissionState {
        switch privilegedHelperCoordinator.privilegedHelperReadiness() {
        case .available:
            .needsElevation(reason: baseReason)
        case let .unavailable(helperReason):
            .notWritableNoElevationPossible(reason: "\(baseReason). \(helperReason)")
        }
    }

    private func isExplicitPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            let cocoaPermissionCodes: Set<Int> = [
                NSFileReadNoPermissionError,
                NSFileWriteNoPermissionError,
                NSFileWriteVolumeReadOnlyError
            ]
            return cocoaPermissionCodes.contains(nsError.code)
        }

        if nsError.domain == NSPOSIXErrorDomain,
           let code = POSIXErrorCode(rawValue: Int32(nsError.code)) {
            return code == .EACCES || code == .EPERM || code == .EROFS
        }

        return false
    }

    private func checkForConflictingRunningProcesses() async throws {
        log.info("Checking for interfering processes")

        // Check if any other updater processes are running
        let runningApps = NSWorkspace.shared.runningApplications
        let interferingApps = runningApps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return bundleId.contains("updater") || bundleId.contains("installer")
        }

        if !interferingApps.isEmpty {
            let appNames = interferingApps.compactMap(\.localizedName).joined(separator: ", ")
            log.warn("Found potentially interfering processes: \(appNames)")
        }

        log.success("Process interference check completed")
    }

    // MARK: - Download Verification

    private func verifyDownloadIntegrity(_ downloadURL: URL, manifest: UpdateManifest) async throws {
        try checkCancellation()
        log.info("Performing comprehensive download verification")

        // Basic file existence and readability
        guard fileManager.fileExists(atPath: downloadURL.path) else {
            throw UpdateError.installationFailed("Download file does not exist: \(downloadURL.path)")
        }

        guard fileManager.isReadableFile(atPath: downloadURL.path) else {
            throw UpdateError.installationFailed("Download file is not readable: \(downloadURL.path)")
        }

        // File size verification
        let attributes = try fileManager.attributesOfItem(atPath: downloadURL.path)
        let fileSize = attributes[.size] as? Int64 ?? 0

        guard fileSize > 0 else {
            throw UpdateError.installationFailed("Download file is empty")
        }

        // Minimum reasonable size check (1KB)
        guard fileSize > 1024 else {
            throw UpdateError.installationFailed("Download file is suspiciously small: \(fileSize) bytes")
        }

        log.info("Download file size: \(fileSize.formattedBytes)")

        // Checksum verification
        try await ChecksumVerifier.verifyFile(
            downloadURL,
            expectedChecksum: manifest.checksums.zip
        )

        log.success("Download integrity verification completed")
    }

    // MARK: - Extraction

    private func extract(_ downloadURL: URL) async throws -> URL {
        try checkCancellation()
        return try ZipExtractor.extract(from: downloadURL, cancellationCheck: checkCancellation)
    }

    // MARK: - Extraction Integrity Verification

    private func verifyExtractionIntegrity(_ extractedURL: URL, manifest: UpdateManifest) async throws {
        try checkCancellation()
        log.info("Performing extraction integrity verification")

        // Find and verify app bundle
        let appBundle = try BundleUtilities.findAppBundle(in: extractedURL)

        // Comprehensive bundle validation
        try validateAppBundle(appBundle, manifest: manifest)

        // Code signature validation
        try await validateAppCodeSignature(appBundle)

        log.success("Extraction integrity verification completed")
    }

    private func validateAppBundle(_ appBundle: URL, skipVersionCheck: Bool = false, manifest: UpdateManifest? = nil) throws {
        log.info("Validating app bundle: \(appBundle.lastPathComponent)")

        // Check bundle structure
        try BundleUtilities.verifyBundleStructure(appBundle)

        // Check Info.plist
        let infoPlistURL = appBundle.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: infoPlistURL) else {
            throw UpdateError.installationFailed("Could not read Info.plist")
        }

        // Validate basic bundle properties
        guard let bundleIdentifier = plist["CFBundleIdentifier"] as? String, !bundleIdentifier.isEmpty else {
            throw UpdateError.installationFailed("Invalid CFBundleIdentifier")
        }

        guard let packageType = plist["CFBundlePackageType"] as? String, packageType == "APPL" else {
            throw UpdateError.installationFailed("Invalid CFBundlePackageType")
        }

        // Validate executable
        guard let executableName = plist["CFBundleExecutable"] as? String, !executableName.isEmpty else {
            throw UpdateError.installationFailed("Missing CFBundleExecutable")
        }

        let executablePath = appBundle.appendingPathComponent("Contents/MacOS/\(executableName)")
        guard fileManager.fileExists(atPath: executablePath.path) else {
            throw UpdateError.installationFailed("Executable not found: \(executableName)")
        }

        let executableAttributes = try fileManager.attributesOfItem(atPath: executablePath.path)
        guard let permissions = executableAttributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o111 != 0 else {
            throw UpdateError.installationFailed("Executable lacks execute permissions")
        }

        // Version validation for extracted apps
        if !skipVersionCheck, let manifest {
            try BundleUtilities.verifyVersionMatches(bundleURL: appBundle, manifest: manifest)
        }

        // System compatibility check
        try validateSystemCompatibility(plist)

        log.success("App bundle validation completed")
    }

    private func validateSystemCompatibility(_ plist: NSDictionary) throws {
        // Check minimum OS version from plist
        if let minOSString = plist["LSMinimumSystemVersion"] as? String {
            let components = minOSString.split(separator: ".").compactMap { Int($0) }
            if components.count >= 2 {
                let minOSVersion = OperatingSystemVersion(
                    majorVersion: components[0],
                    minorVersion: components[1],
                    patchVersion: components.count > 2 ? components[2] : 0
                )

                guard ProcessInfo.processInfo.isOperatingSystemAtLeast(minOSVersion) else {
                    throw UpdateError.installationFailed("App manifest inconsistency: app actually requires macOS \(minOSString) or later.")
                }
            }
        }

        // Check supported architectures – plist value is an array of strings
        if let archStrings = plist["LSArchitecturePriority"] as? [String] {
            // Map string representations to our internal Architecture enum
            let supportedArchitectures: [SystemInfo.Architecture] = archStrings.compactMap { arch in
                switch arch.lowercased() {
                case "arm64": .arm64
                case "x86_64", "x86-64", "x86": .x86_64
                default: nil
                }
            }

            guard !supportedArchitectures.isEmpty else {
                // No recognized architectures, assume compatible
                return
            }

            guard supportedArchitectures.contains(SystemInfo.architecture) else {
                throw UpdateError.installationFailed("App does not support current architecture")
            }
        }
    }

    private func validateAppCodeSignature(_ appBundle: URL) async throws {
        log.info("Validating app code signature")

        let creationFlags = SecCSFlags()
        let validationFlags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appBundle as CFURL, creationFlags, &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            let message = securityErrorMessage(for: createStatus)
            throw UpdateError.installationFailed("Code signature object creation failed: \(message)")
        }

        let validationStatus = SecStaticCodeCheckValidity(staticCode, validationFlags, nil)
        guard validationStatus == errSecSuccess else {
            let message = securityErrorMessage(for: validationStatus)
            throw UpdateError.installationFailed("Code signature validation failed: \(message)")
        }

        log.success("Code signature validation passed")
    }

    private func securityErrorMessage(for status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(message) (OSStatus \(status))"
        }
        return "OSStatus \(status)"
    }

    // MARK: - Safe Installation

    private func performSafeInstallation(from extractedURL: URL, manifest: UpdateManifest) async throws {
        try checkCancellation()
        log.info("Performing safe installation")

        let appBundle = try BundleUtilities.findAppBundle(in: extractedURL)

        if relocateToApplications {
            try await performRelocationInstall(from: appBundle, manifest: manifest)
        } else {
            // Pre-installation verification (checks current running app)
            try await verifyPreInstallationState()

            // Perform atomic installation to current location
            let currentAppURL = Bundle.main.bundleURL

            switch installationPermissionState {
            case .writable:
                try await performAtomicInstallationNonPrivileged(from: appBundle, to: currentAppURL, manifest: manifest)
            case .needsElevation:
                log.info("Requesting administrator authorization for privileged installation")
                var enteredPrivilegedSession = false
                do {
                    try await privilegedHelperCoordinator.withPrivilegedSession(
                        prompt: String(localized: "\(Bundle.main.appName) is trying to install an update.")
                    ) { session in
                        enteredPrivilegedSession = true
                        log.success("Administrator authorization granted; privileged session established")

                        do {
                            try await performAtomicInstallationPrivilegedWithSession(
                                from: appBundle,
                                to: currentAppURL,
                                manifest: manifest,
                                session: session
                            )
                        } catch {
                            if await askUserForApplicationsFallback(
                                failedTargetPath: currentAppURL.path,
                                after: error.localizedDescription
                            ) {
                                try await performRelocationInstall(
                                    from: appBundle,
                                    manifest: manifest,
                                    cleanupSession: session
                                )
                            } else {
                                throw UpdateError.installationFailed("Update requires administrator authorization to modify \(currentAppURL.path).")
                            }
                        }
                    }
                } catch {
                    guard !enteredPrivilegedSession else {
                        throw error
                    }

                    if await askUserForApplicationsFallback(
                        failedTargetPath: currentAppURL.path,
                        after: error.localizedDescription
                    ) {
                        try await performRelocationInstall(from: appBundle, manifest: manifest)
                    } else {
                        throw UpdateError.installationFailed("Update requires administrator authorization to modify \(currentAppURL.path).")
                    }
                }
            case let .notWritableNoElevationPossible(reason):
                if await askUserForApplicationsFallback(
                    failedTargetPath: currentAppURL.path,
                    after: reason
                ) {
                    try await performRelocationInstall(from: appBundle, manifest: manifest)
                } else {
                    throw UpdateError.installationFailed("Cannot modify current application location: \(reason)")
                }
            }
        }

        // Post-installation verification
        try await verifyPostInstallationState(manifest: manifest)

        log.success("Safe installation completed")
    }

    private func performRelocationInstall(
        from appBundle: URL,
        manifest: UpdateManifest,
        cleanupSession: PrivilegedHelperCoordinator.PrivilegedSession? = nil
    ) async throws {
        log.info("Installing to Applications folder")

        let sourceAppURL = LoopSupportPaths.canonical(Bundle.main.bundleURL)
        let userAppsURL = LoopSupportPaths.canonical(
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        )
        let destinationURL = LoopSupportPaths.canonical(
            userAppsURL.appendingPathComponent("Loop.app", isDirectory: true)
        )

        // Create ~/Applications if needed
        try fileManager.createDirectory(at: userAppsURL, withIntermediateDirectories: true)

        // Reuse the same staging + swap path used for regular updates so only swap
        // operations touch locations outside Loop's support directory.
        try await performAtomicInstallationNonPrivileged(
            from: appBundle,
            to: destinationURL,
            manifest: manifest
        )

        // Verify the installation
        try BundleUtilities.verifyBundleStructure(destinationURL)
        try BundleUtilities.verifyVersionMatches(bundleURL: destinationURL, manifest: manifest)

        // Store the new location for restart
        installedAppURL = destinationURL

        await cleanupOldRelocatedCopyIfNeeded(
            source: sourceAppURL,
            destination: destinationURL,
            cleanupSession: cleanupSession
        )

        log.success("Successfully installed to Applications folder")
    }

    private func cleanupOldRelocatedCopyIfNeeded(
        source sourceAppURL: URL,
        destination destinationURL: URL,
        cleanupSession: PrivilegedHelperCoordinator.PrivilegedSession?
    ) async {
        let canonicalSource = LoopSupportPaths.canonical(sourceAppURL)
        let canonicalDestination = LoopSupportPaths.canonical(destinationURL)

        guard canonicalSource != canonicalDestination else {
            log.debug("Skipping relocation cleanup because source and destination are identical")
            return
        }

        guard fileManager.fileExists(atPath: canonicalSource.path) else {
            log.debug("Skipping relocation cleanup because source app copy no longer exists at \(canonicalSource.path)")
            return
        }

        do {
            try fileManager.trashItem(at: canonicalSource, resultingItemURL: nil)
            log.info("Moved previous app copy to Trash after relocation: \(canonicalSource.path)")
            return
        } catch {
            guard isExplicitPermissionError(error) else {
                log.warn("Failed to remove previous app copy after relocation at \(canonicalSource.path): \(error.localizedDescription)")
                return
            }

            guard let cleanupSession else {
                log.debug("No pre-existing privileged session available for relocation cleanup; previous app copy remains at \(canonicalSource.path)")
                return
            }

            log.info("Could not move previous app copy to Trash due to permissions; attempting privileged cleanup with existing session")
            do {
                try await cleanupSession.removeCurrentBundle()
                log.info("Privileged cleanup removed previous app copy after relocation")
            } catch {
                log.debug("Existing privileged session could not remove previous app copy: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func askUserForApplicationsFallback(
        failedTargetPath: String,
        after failureReason: String
    ) async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Administrator Authorization Required")
        alert.informativeText = String(
            localized: "\(Bundle.main.appName) couldn’t install the update at \(failedTargetPath) (\(failureReason)). Would you like to install this update in your Applications folder instead?"
        )
        alert.alertStyle = .warning
        alert.addButton(
            withTitle: String(localized: "Install in Applications Folder")
        )
        alert.addButton(
            withTitle: String(localized: "Cancel Update")
        )

        return alert.runModal() == .alertFirstButtonReturn
    }

    private func verifyPreInstallationState() async throws {
        log.info("Verifying pre-installation state")

        let currentAppURL = Bundle.main.bundleURL
        guard fileManager.fileExists(atPath: currentAppURL.path) else {
            throw UpdateError.installationFailed("Current application no longer exists before installation")
        }

        try validateAppBundle(currentAppURL, skipVersionCheck: true)
        log.success("Pre-installation state verified")
    }

    private func verifyPostInstallationState(manifest: UpdateManifest) async throws {
        log.info("Verifying post-installation state")

        guard fileManager.fileExists(atPath: installedAppURL.path) else {
            throw UpdateError.installationFailed("Application missing after installation - CRITICAL ERROR")
        }

        try validateAppBundle(installedAppURL, manifest: manifest)
        log.success("Post-installation state verified")
    }

    // MARK: - Atomic Installation

    private func performAtomicInstallationNonPrivileged(
        from sourceURL: URL,
        to destinationURL: URL,
        manifest: UpdateManifest
    ) async throws {
        log.info("Performing atomic installation")

        let stagingURL = stagingRootDirectory
            .appendingPathComponent("\(destinationURL.lastPathComponent).staging", isDirectory: true)

        do {
            try await executeAtomicInstallationSteps(
                source: sourceURL,
                staging: stagingURL,
                destination: destinationURL,
                manifest: manifest
            )
            log.info("Atomic installation completed successfully")
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func performAtomicInstallationPrivilegedWithSession(
        from sourceURL: URL,
        to destinationURL: URL,
        manifest: UpdateManifest,
        session: PrivilegedHelperCoordinator.PrivilegedSession
    ) async throws {
        let stagingURL = stagingRootDirectory
            .appendingPathComponent("\(destinationURL.lastPathComponent).staging", isDirectory: true)

        do {
            try copyToStaging(from: sourceURL, to: stagingURL)
            log.info("Verifying staged application immediately before privileged swap")
            try await verifyStaged(stagingURL, manifest: manifest)
            try await atomicSwapPrivileged(
                staged: stagingURL,
                current: destinationURL,
                session: session
            )
            log.success("Privileged atomic installation completed successfully")
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func executeAtomicInstallationSteps(
        source: URL,
        staging: URL,
        destination: URL,
        manifest: UpdateManifest
    ) async throws {
        try copyToStaging(from: source, to: staging)
        try await verifyStaged(staging, manifest: manifest)
        try await atomicSwap(staged: staging, current: destination)
    }

    private func copyToStaging(from sourceURL: URL, to stagingURL: URL) throws {
        try checkCancellation()

        log.debug("Copying application to staging area")

        try fileManager.createDirectory(
            at: stagingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.copyItem(at: sourceURL, to: stagingURL)
    }

    private func verifyStaged(_ stagingURL: URL, manifest: UpdateManifest) async throws {
        try checkCancellation()

        log.debug("Verifying staged application")

        try BundleUtilities.verifyBundleStructure(stagingURL)
        try BundleUtilities.verifyVersionMatches(bundleURL: stagingURL, manifest: manifest)
        try await testStagedApplication(stagingURL)
    }

    private func testStagedApplication(_ bundleURL: URL) async throws {
        log.debug("Testing staged application")

        let executablePath = bundleURL.appendingPathComponent("Contents/MacOS")
        let contents = try fileManager.contentsOfDirectory(
            at: executablePath,
            includingPropertiesForKeys: nil
        )

        guard !contents.isEmpty else {
            log.error("No executable found in MacOS directory")
            throw UpdateError.installationFailed("No executable found in app bundle")
        }

        log.debug("Application testing passed")
    }

    private func atomicSwap(staged stagingURL: URL, current currentURL: URL) async throws {
        try checkCancellation()

        log.info("Starting atomic swap")
        log.info("Current app: \(currentURL.path)")
        log.info("Staged app: \(stagingURL.path)")

        let rollbackID = try createTransientRollbackID()
        let rollbackContainerURL = rollbackRootDirectory.appendingPathComponent(rollbackID, isDirectory: true)
        let backupBundleURL = rollbackContainerURL.appendingPathComponent(
            currentURL.lastPathComponent,
            isDirectory: true
        )

        try await performSwapOperation(
            current: currentURL,
            staged: stagingURL,
            backupBundle: backupBundleURL
        )

        await archiveRollbackSnapshotIfPresent(at: rollbackContainerURL)
    }

    private func atomicSwapPrivileged(
        staged stagingURL: URL,
        current currentURL: URL,
        session: PrivilegedHelperCoordinator.PrivilegedSession
    ) async throws {
        try checkCancellation()

        log.info("Starting privileged atomic swap")
        log.info("Current app: \(currentURL.path)")
        log.info("Staged app: \(stagingURL.path)")

        let rollbackID = try createTransientRollbackID()
        let rollbackContainerURL = rollbackRootDirectory.appendingPathComponent(rollbackID, isDirectory: true)
        let backupBundleURL = rollbackContainerURL.appendingPathComponent(
            currentURL.lastPathComponent,
            isDirectory: true
        )

        do {
            log.info("Invoking privileged helper atomic swap")
            try await session.atomicSwap(rollbackID: rollbackID)

            try verifyPrivilegedSwapCompletion(current: currentURL, backupBundle: backupBundleURL, staged: stagingURL)
        } catch {
            log.error("Privileged atomic swap failed: \(error.localizedDescription)")
            try await reconcilePrivilegedSwapFailure(
                current: currentURL,
                staged: stagingURL,
                rollbackID: rollbackID,
                originalError: error,
                session: session
            )
        }

        await archiveRollbackSnapshotIfPresent(at: rollbackContainerURL)
    }

    private func reconcilePrivilegedSwapFailure(
        current currentURL: URL,
        staged stagingURL: URL,
        rollbackID: String,
        originalError: Error,
        session: PrivilegedHelperCoordinator.PrivilegedSession
    ) async throws {
        let rollbackContainerURL = rollbackRootDirectory.appendingPathComponent(rollbackID, isDirectory: true)
        let backupBundleURL = rollbackContainerURL.appendingPathComponent(
            currentURL.lastPathComponent,
            isDirectory: true
        )
        let currentExists = fileManager.fileExists(atPath: currentURL.path)
        let backupExists = fileManager.fileExists(atPath: backupBundleURL.path)

        if currentExists, backupExists {
            do {
                try verifyPrivilegedSwapCompletion(current: currentURL, backupBundle: backupBundleURL, staged: stagingURL)
                log.notice("Privileged swap and ownership validation completed despite transport failure; continuing installation")
                return
            } catch {
                log.warn("Privileged swap state or ownership check failed after transport error; attempting recovery restore: \(error.localizedDescription)")
            }
        }

        guard backupExists else {
            guard currentExists else {
                throw UpdateError.installationFailed(
                    "Privileged atomic swap failed and no backup was available for recovery: \(originalError.localizedDescription)"
                )
            }

            do {
                try validateAppBundle(currentURL, skipVersionCheck: true)
                try verifyPrivilegedInstalledOwnership(current: currentURL)
            } catch {
                throw UpdateError.installationFailed(
                    "Privileged atomic swap failed, backup snapshot was unavailable, and restored app verification failed: \(originalError.localizedDescription). Verification error: \(error.localizedDescription)"
                )
            }

            throw UpdateError.installationFailed(
                "Privileged atomic swap failed. The previous app version was restored successfully."
            )
        }

        do {
            log.notice("Attempting privileged rollback recovery using the existing authorized session")
            try await session.restoreFromBackup(rollbackID: rollbackID)

            guard fileManager.fileExists(atPath: currentURL.path) else {
                throw UpdateError.installationFailed("Privileged restore failed: restored app not found at \(currentURL.path)")
            }

            try validateAppBundle(currentURL, skipVersionCheck: true)
        } catch {
            throw UpdateError.installationFailed(
                "Privileged atomic swap failed and restore was unsuccessful: \(originalError.localizedDescription). Recovery error: \(error.localizedDescription)"
            )
        }

        throw UpdateError.installationFailed(
            "Privileged atomic swap failed. The previous app version was restored successfully."
        )
    }

    private func performSwapOperation(current: URL, staged: URL, backupBundle: URL) async throws {
        let currentExists = fileManager.fileExists(atPath: current.path)

        do {
            if currentExists {
                log.info("Moving current app to backup...")

                // Ensure the backup directory exists
                let backupParent = backupBundle.deletingLastPathComponent()
                try fileManager.createDirectory(at: backupParent, withIntermediateDirectories: true)

                // Check if backup already exists and remove it if necessary
                if fileManager.fileExists(atPath: backupBundle.path) {
                    log.warn("Backup already exists at \(backupBundle.path), removing it first")
                    try fileManager.removeItem(at: backupBundle)
                }

                try fileManager.moveItem(at: current, to: backupBundle)
                log.info("Current app backed up to: \(backupBundle.path)")
            } else {
                log.info("No existing app at destination, installing staged app directly")
            }

            log.info("Moving staged app to current location...")
            try fileManager.moveItem(at: staged, to: current)
            log.info("New app installed at: \(current.path)")

            // Verify the atomic swap was successful
            try verifySwapSuccess(current: current, backupBundle: backupBundle, staged: staged, expectBackup: currentExists)
            log.success("Atomic swap completed and verified successfully!")
        } catch {
            log.error("Atomic swap failed: \(error)")
            log.error("Current: \(current.path), Staged: \(staged.path), Backup: \(backupBundle.path)")
            log.error("Current exists: \(fileManager.fileExists(atPath: current.path))")
            log.error("Staged exists: \(fileManager.fileExists(atPath: staged.path))")
            log.error("Backup exists: \(fileManager.fileExists(atPath: backupBundle.path))")

            if currentExists, fileManager.fileExists(atPath: backupBundle.path) {
                try restoreFromRollbackSnapshot(currentURL: current, backupBundleURL: backupBundle)
            }
            throw error
        }
    }

    private func restoreFromRollbackSnapshot(currentURL: URL, backupBundleURL: URL) throws {
        log.info("Attempting to restore from rollback snapshot")

        guard fileManager.fileExists(atPath: backupBundleURL.path) else {
            log.warn("Rollback snapshot not found at \(backupBundleURL.path)")
            return
        }

        if fileManager.fileExists(atPath: currentURL.path) {
            try fileManager.removeItem(at: currentURL)
        }

        try fileManager.moveItem(at: backupBundleURL, to: currentURL)
        try BundleUtilities.verifyBundleStructure(currentURL)
        log.success("Restored application from rollback snapshot")
    }

    private func verifySwapSuccess(current: URL, backupBundle: URL, staged: URL, expectBackup: Bool = true) throws {
        log.debug("Verifying atomic swap success...")

        if expectBackup {
            // 1. Verify backup was created successfully
            guard fileManager.fileExists(atPath: backupBundle.path) else {
                throw UpdateError.installationFailed("Atomic swap verification failed: Backup not found at expected location: \(backupBundle.path)")
            }

            // Verify backup has correct bundle structure
            try BundleUtilities.verifyBundleStructure(backupBundle)
            log.debug("Backup bundle structure verified")

            // Verify backup has a valid Info.plist and version
            let backupInfoPlistURL = backupBundle.appendingPathComponent("Contents/Info.plist")
            guard fileManager.fileExists(atPath: backupInfoPlistURL.path) else {
                throw UpdateError.installationFailed("Atomic swap verification failed: Backup app Info.plist not found")
            }

            guard let backupPlist = NSDictionary(contentsOf: backupInfoPlistURL),
                  let backupVersion = backupPlist["CFBundleShortVersionString"] as? String,
                  !backupVersion.isEmpty else {
                throw UpdateError.installationFailed("Atomic swap verification failed: Backup app version information is invalid")
            }

            log.debug("Backup version verified: \(backupVersion)")
        } else {
            log.debug("No existing destination app to back up before swap")
        }

        // 2. Verify new app was installed successfully
        guard fileManager.fileExists(atPath: current.path) else {
            throw UpdateError.installationFailed("Atomic swap verification failed: New app not found at expected location: \(current.path)")
        }

        // Verify new app has correct bundle structure
        try BundleUtilities.verifyBundleStructure(current)
        log.debug("New app bundle structure verified")

        // Verify new app has a valid Info.plist and version
        let infoPlistURL = current.appendingPathComponent("Contents/Info.plist")
        guard fileManager.fileExists(atPath: infoPlistURL.path) else {
            throw UpdateError.installationFailed("Atomic swap verification failed: New app Info.plist not found")
        }

        guard let plist = NSDictionary(contentsOf: infoPlistURL),
              let version = plist["CFBundleShortVersionString"] as? String,
              !version.isEmpty else {
            throw UpdateError.installationFailed("Atomic swap verification failed: New app version information is invalid")
        }

        log.debug("New app version verified: \(version)")

        // 3. Verify staging area is clean (should be empty after move)
        if fileManager.fileExists(atPath: staged.path) {
            log.warn("Staging area still exists (this is usually fine): \(staged.path)")
        }

        // 4. Verify file sizes are reasonable (basic sanity check)
        let currentSize = try fileManager.calculateDirectorySize(current)

        if expectBackup {
            let backupSize = try fileManager.calculateDirectorySize(backupBundle)
            guard backupSize > 0 else {
                throw UpdateError.installationFailed("Atomic swap verification failed: Backup appears to be empty or invalid")
            }
            log.debug("Backup size verified: \(backupSize.formattedBytes)")
        }

        guard currentSize > 0 else {
            throw UpdateError.installationFailed("Atomic swap verification failed: New app appears to be empty or invalid")
        }

        log.debug("New app size verified: \(currentSize.formattedBytes)")
        log.debug("Atomic swap verification completed")
    }

    private func verifyPrivilegedSwapCompletion(current: URL, backupBundle: URL, staged: URL) throws {
        try verifySwapSuccess(current: current, backupBundle: backupBundle, staged: staged)
        try verifyPrivilegedInstalledOwnership(current: current)
    }

    private func verifyPrivilegedInstalledOwnership(current currentURL: URL) throws {
        let attributes = try fileManager.attributesOfItem(atPath: currentURL.path)

        guard let ownerID = attributes[.ownerAccountID] as? NSNumber else {
            throw UpdateError.installationFailed(
                "Privileged install verification failed: could not read owner for \(currentURL.path)"
            )
        }

        guard ownerID.intValue == 0 else {
            throw UpdateError.installationFailed(
                "Privileged install verification failed: expected root ownership at \(currentURL.path), found uid \(ownerID.intValue)"
            )
        }
    }

    /// Generates a unique rollback token and verifies its destination does not already exist.
    private func createTransientRollbackID() throws -> String {
        let rollbackRoot = rollbackRootDirectory
        try fileManager.createDirectory(at: rollbackRoot, withIntermediateDirectories: true)

        let timestampFormatter = DateFormatter()
        timestampFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = timestampFormatter.string(from: Date())
        let currentVersion = Bundle.main.appVersion ?? "unknown"
        let rollbackID = "rollback_\(currentVersion)_\(timestamp)_\(UUID().uuidString.lowercased())"
        let rollbackURL = rollbackRootDirectory.appendingPathComponent(rollbackID, isDirectory: true)

        guard !fileManager.fileExists(atPath: rollbackURL.path) else {
            throw UpdateError.installationFailed(
                "Rollback path already exists for generated ID \(rollbackID)"
            )
        }

        return rollbackID
    }

    private func archiveRollbackSnapshotIfPresent(at rollbackURL: URL) async {
        guard fileManager.fileExists(atPath: rollbackURL.path) else {
            return
        }

        do {
            _ = try await backupManager.backup(fileURL: rollbackURL)
        } catch {
            log.warn("Could not archive rollback snapshot at \(rollbackURL.path): \(error.localizedDescription)")
        }
    }

    // MARK: - Final Verification

    private func performFinalVerification(manifest: UpdateManifest) async throws {
        try checkCancellation()
        log.info("Performing comprehensive installation verification")

        // Verify app can be read
        guard fileManager.isReadableFile(atPath: installedAppURL.path) else {
            throw UpdateError.installationFailed("Installed application is not readable")
        }

        // Comprehensive bundle validation
        try validateAppBundle(installedAppURL, manifest: manifest)

        log.success("Comprehensive verification completed")
    }

    // MARK: - Pre-Restart Verification

    private func performPreRestartSafetyChecks() throws {
        log.info("Performing pre-restart verification")

        // Final check that app exists
        guard fileManager.fileExists(atPath: installedAppURL.path) else {
            throw UpdateError.installationFailed("Application missing before restart")
        }

        // Final structure check
        try BundleUtilities.verifyBundleStructure(installedAppURL)

        // Check executable exists and has permissions
        let executablePath = try BundleUtilities.executablePath(for: installedAppURL)
        guard fileManager.fileExists(atPath: executablePath.path) else {
            throw UpdateError.installationFailed("Application executable missing before restart")
        }

        let attributes = try fileManager.attributesOfItem(atPath: executablePath.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        guard let permissions, permissions.intValue & 0o111 != 0 else {
            throw UpdateError.installationFailed("Application executable lacks execute permissions before restart")
        }

        log.success("Pre-restart verification passed")
    }

    // MARK: - Standard Methods

    private func performSafeCleanup(_ extractedURL: URL, _ downloadURL: URL) async throws {
        log.info("Performing safe cleanup of temporary files")

        let cleanupOperations = [
            (extractedURL, "extraction directory"),
            (downloadURL, "download file")
        ]

        for (url, description) in cleanupOperations {
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                    log.debug("Removed \(description): \(url.path)")
                } catch {
                    log.warn("Failed to clean up \(description): \(error)")
                    // Don't fail installation for cleanup issues
                }
            }
        }

        log.success("Safe cleanup completed")
    }

    // MARK: - Utility Methods

    private func checkCancellation() throws {
        guard !isCancelled else {
            throw UpdateError.installationFailed("Installation cancelled")
        }
    }

    private func getAvailableDiskSpace() throws -> Int64 {
        let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
        return attributes[.systemFreeSize] as? Int64 ?? 0
    }
}

// MARK: - AppLocation

enum AppLocation: CustomStringConvertible {
    case systemApplications
    case userApplications
    case other(String)

    static var current: AppLocation {
        let bundlePath = Bundle.main.bundlePath
        let userAppsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        let systemAppsPath = "/Applications"

        if bundlePath.hasPrefix(systemAppsPath) {
            return .systemApplications
        } else if bundlePath.hasPrefix(userAppsPath) {
            return .userApplications
        } else {
            return .other(bundlePath)
        }
    }

    var description: String {
        switch self {
        case .systemApplications: "/Applications"
        case .userApplications: "~/Applications"
        case let .other(path): path
        }
    }
}
