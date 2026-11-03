//
//  BundleUtilities.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-23.
//

import Foundation
import Scribe

@Loggable(style: .static)
enum BundleUtilities {
    /// Required paths that must exist in a valid app bundle
    static let requiredBundlePaths = ["Contents/Info.plist", "Contents/MacOS"]

    /// Recursively searches for an app bundle (.app) within a directory
    /// - Parameter directory: The directory to search in
    /// - Returns: URL to the found app bundle
    /// - Throws: `UpdateError.installationFailed` if no app bundle is found
    static func findAppBundle(in directory: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        )

        for item in contents {
            if item.pathExtension == "app" {
                log.info("Found app bundle: \(item.lastPathComponent)")
                return item
            }

            let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])
            if resourceValues.isDirectory == true,
               let found = try? findAppBundle(in: item) {
                return found
            }
        }

        let fileList = contents.map(\.lastPathComponent).joined(separator: ", ")
        log.error("No .app bundle found in directory. Available files: \(fileList)")

        throw UpdateError.installationFailed("No .app bundle found in update package. Found files: \(fileList)")
    }

    /// Verifies that a bundle has the required structure (Info.plist and MacOS directory)
    /// - Parameter bundleURL: URL to the app bundle to verify
    /// - Throws: `UpdateError.installationFailed` if required paths are missing
    static func verifyBundleStructure(_ bundleURL: URL) throws {
        log.debug("Verifying bundle structure for: \(bundleURL.path)")

        for path in requiredBundlePaths {
            let fullPath = bundleURL.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: fullPath.path) else {
                log.error("Missing required path: \(path)")
                throw UpdateError.installationFailed("Invalid app bundle: missing \(path)")
            }
        }

        log.debug("Bundle structure verification passed")
    }

    /// Returns the path to the executable for a given bundle
    /// - Parameter bundleURL: URL to the app bundle
    /// - Returns: URL to the executable
    /// - Throws: `UpdateError.installationFailed` if executable name cannot be determined
    static func executablePath(for bundleURL: URL) throws -> URL {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")

        guard let plist = NSDictionary(contentsOf: infoPlistURL),
              let executableName = plist["CFBundleExecutable"] as? String else {
            throw UpdateError.installationFailed("Could not determine executable name from Info.plist")
        }

        return bundleURL.appendingPathComponent("Contents/MacOS/\(executableName)")
    }

    // MARK: Version Checking

    /// Version information extracted from a bundle's Info.plist
    struct VersionInfo {
        let version: String
        let build: Int

        /// Returns the normalized version string (removes dev build emoji and trims whitespace)
        var normalizedVersion: String {
            version
                .replacing(/🧪/, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Verifies that a bundle's version matches the expected manifest
    /// - Parameters:
    ///   - bundleURL: URL to the app bundle to verify
    ///   - manifest: The update manifest to compare against
    /// - Throws: `UpdateError.installationFailed` if versions don't match
    static func verifyVersionMatches(bundleURL: URL, manifest: UpdateManifest) throws {
        guard let versionInfo = readVersionInfo(from: bundleURL) else {
            throw UpdateError.installationFailed("Could not read version info from bundle at: \(bundleURL.path)")
        }

        try verifyVersionMatches(versionInfo: versionInfo, manifest: manifest)
    }

    /// Returns whether a bundle on disk already contains the manifest's version.
    ///
    /// Unlike `verifyVersionMatches(bundleURL:manifest:)`, a mismatch is an expected outcome here and is not logged as an error.
    /// - Parameters:
    ///   - manifest: The update manifest to compare against
    ///   - bundleURL: URL to the app bundle to inspect
    /// - Returns: `true` if the bundle's version (and build number, for non-stable channels) matches the manifest
    static func bundleContains(_ manifest: UpdateManifest, at bundleURL: URL) -> Bool {
        guard let versionInfo = readVersionInfo(from: bundleURL),
              versionInfo.normalizedVersion == manifest.version else {
            return false
        }

        return manifest.channel == .stable || versionInfo.build == manifest.buildNumber
    }

    /// Reads version information from a bundle's Info.plist
    /// - Parameter bundleURL: URL to the app bundle
    /// - Returns: VersionInfo if successfully read, nil otherwise
    private static func readVersionInfo(from bundleURL: URL) -> VersionInfo? {
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")

        guard let plist = NSDictionary(contentsOf: infoPlistURL),
              let version = plist["CFBundleShortVersionString"] as? String,
              let buildString = plist["CFBundleVersion"] as? String,
              let build = Int(buildString) else {
            log.error("Could not read version info from Info.plist at: \(infoPlistURL.path)")
            return nil
        }

        return VersionInfo(version: version, build: build)
    }

    /// Verifies that version info matches the expected manifest
    /// - Parameters:
    ///   - versionInfo: The version info to verify
    ///   - manifest: The update manifest to compare against
    /// - Throws: `UpdateError.installationFailed` if versions don't match
    private static func verifyVersionMatches(versionInfo: VersionInfo, manifest: UpdateManifest) throws {
        log.info("Verifying version - Bundle: \(versionInfo.version) (\(versionInfo.build)), Expected: \(manifest.version) (\(manifest.buildNumber))")

        guard versionInfo.normalizedVersion == manifest.version else {
            log.error("Version mismatch - Expected: \(manifest.version), Got: \(versionInfo.normalizedVersion)")
            throw UpdateError.installationFailed("Version mismatch: expected \(manifest.version), got \(versionInfo.normalizedVersion)")
        }

        // For non-stable channels, also verify build number
        if manifest.channel != .stable {
            guard versionInfo.build == manifest.buildNumber else {
                log.error("Build number mismatch - Expected: \(manifest.buildNumber), Got: \(versionInfo.build)")
                throw UpdateError.installationFailed("Build number mismatch: expected \(manifest.buildNumber), got \(versionInfo.build)")
            }
        }

        log.success("Version verification passed")
    }
}
