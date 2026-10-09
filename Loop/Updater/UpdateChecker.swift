//
//  UpdateChecker.swift
//  Loop
//
//  Created by Kami on 2026-01-22.
//

import Foundation
import Scribe

@Loggable
actor UpdateChecker {
    private let httpClient: HTTPClient = .init()

    private static let minimumOSRegex = /Minimum macOS version:\s*(?<major>\d+)(?:\.(?<minor>\d+))?(?:\.(?<patch>\d+))?/
        .ignoresCase()
    private static let maximumOSRegex = /Maximum macOS version:\s*(?<major>\d+)(?:\.(?<minor>\d+))?(?:\.(?<patch>\d+))?/
        .ignoresCase()
    private static let supportedArchitecturesRegex = /Supported architectures:\s*(?<archs>.+)/
        .ignoresCase()

    func checkForUpdate(
        currentVersion: String,
        currentBuild: Int = 0,
        channel: UpdateChannel
    ) async throws -> UpdateManifest? {
        log.info("Checking for updates: \(currentVersion) build \(currentBuild) [\(channel.rawValue)]")

        let endpoint = URL(string: channel.githubReleasesEndpoint)!
        var candidateRelease: GitHubRelease?

        let manifestData = try await httpClient.fetchData(from: endpoint)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        switch channel {
        case .stable:
            // Single release
            candidateRelease = try decoder.decode(GitHubRelease.self, from: manifestData)
        case .development:
            // Multiple releases for dev channel
            let releases = try decoder.decode([GitHubRelease].self, from: manifestData)
            candidateRelease = releases.first(where: { $0.prerelease })
        }

        if let candidateRelease {
            return try processRelease(
                candidateRelease,
                currentVersion: currentVersion,
                currentBuild: currentBuild
            )
        }

        log.info("No update available")
        return nil
    }

    private func processRelease(
        _ release: GitHubRelease,
        currentVersion: String,
        currentBuild: Int
    ) throws -> UpdateManifest? {
        log.debug("Processing release: tagName='\(release.tagName)', name='\(release.name)', prerelease=\(release.prerelease)")

        // Extract version and build number from release
        let (version, buildNumber) = extractVersionInfo(from: release)

        // Check if this is actually a newer version
        log.debug("Checking version: current='\(currentVersion) (\(currentBuild))', available='\(version) (\(buildNumber))'")
        guard isNewerVersion(
            version,
            buildNumber: buildNumber,
            than: currentVersion,
            currentBuild: currentBuild
        ) else {
            log.info("No newer version available")
            return nil
        }

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            log.error("No ZIP asset found in release")
            return nil
        }

        // Extract checksum from asset digest (format: "sha256:checksum")
        let zipChecksum = asset.digest?.replacing(/sha256:/, with: "") ?? ""
        log.debug("Asset digest: \(asset.digest ?? "none"), extracted checksum: \(zipChecksum)")

        let compatibility = extractCompatibilityRequirements(from: release.body)

        let manifest = UpdateManifest(
            version: version,
            buildNumber: buildNumber,
            downloadUrl: asset.browserDownloadURL.absoluteString,
            releaseNotes: UpdateManifest.ReleaseNotes(
                title: release.name,
                body: release.body
            ),
            checksums: UpdateManifest.Checksums(
                zip: zipChecksum
            ),
            compatibility: UpdateManifest.Compatibility(
                minimumOS: compatibility.minimumOS,
                maximumOS: compatibility.maximumOS,
                supportedArchitectures: compatibility.architectures
            ),
            channel: release.prerelease ? .development : .stable,
            publishedAt: release.createdAt,
            size: Int64(asset.size)
        )

        // Verify system requirements before returning the manifest
        try verifySystemRequirements(manifest: manifest)

        log.info("Found update: \(manifest.version) (\(manifest.buildNumber))")
        return manifest
    }

    private func extractVersionInfo(from release: GitHubRelease) -> (version: String, buildNumber: Int) {
        if release.prerelease {
            // Parse from name field like "🧪 1.4.1 (1683)"
            let regex = /🧪\s+(\d+\.\d+\.\d+)\s+\((\d+)\)/
            if let match = release.name.firstMatch(of: regex) {
                let version = String(match.1)
                let build = Int(String(match.2)) ?? 0
                log.debug("Parsed prerelease: version=\(version), build=\(build)")
                return (version, build)
            }

            log.warn("Could not parse prerelease version from: '\(release.name)'")
            return ("0.0.0", 0)
        } else {
            // Stable release: tagName is the version
            return (release.tagName, 0)
        }
    }

    private func isNewerVersion(_ newVersion: String, buildNumber: Int, than currentVersion: String, currentBuild: Int) -> Bool {
        let versionComparison = newVersion.compare(currentVersion, options: .numeric)

        if versionComparison == .orderedDescending {
            return true
        } else if versionComparison == .orderedSame {
            // For same version, only consider it newer if:
            // 1. The release has a meaningful build number (> 0), AND
            // 2. That build number is actually higher than current
            // This prevents stable releases with build=0 from triggering updates for dev builds
            return buildNumber > 0 && buildNumber > currentBuild
        }

        return false
    }

    private func extractCompatibilityRequirements(
        from body: String
    ) -> (minimumOS: OperatingSystemVersion?, maximumOS: OperatingSystemVersion?, architectures: [SystemInfo.Architecture]) {
        var minimumOS: OperatingSystemVersion?
        var maximumOS: OperatingSystemVersion?
        var architectures: [SystemInfo.Architecture]?

        for line in body.split(whereSeparator: \.isNewline).reversed() {
            let lineStr = String(line)

            // Extract minimum OS version
            if minimumOS == nil,
               let match = lineStr.firstMatch(of: Self.minimumOSRegex),
               let major = Int(match.major) {
                let minor = match.minor.flatMap { Int($0) } ?? 0
                let patch = match.patch.flatMap { Int($0) } ?? 0
                minimumOS = OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
            }

            // Extract maximum OS version
            if maximumOS == nil,
               let match = lineStr.firstMatch(of: Self.maximumOSRegex),
               let major = Int(match.major) {
                let minor = match.minor.flatMap { Int($0) } ?? 0
                let patch = match.patch.flatMap { Int($0) } ?? 0
                maximumOS = OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: patch)
            }

            // Extract supported architectures
            if architectures == nil,
               let match = lineStr.firstMatch(of: Self.supportedArchitecturesRegex) {
                let archsString = String(match.archs)
                var archs: [SystemInfo.Architecture] = []

                if archsString.contains("arm64") {
                    archs.append(.arm64)
                }
                if archsString.contains("x86_64") {
                    archs.append(.x86_64)
                }

                if !archs.isEmpty {
                    architectures = archs
                }
            }

            // Early exit if all values found
            if minimumOS != nil, maximumOS != nil, architectures != nil {
                break
            }
        }

        let finalArchitectures = architectures ?? SystemInfo.Architecture.allCases

        log.debug("Extracted compatibility: minOS=\(minimumOS?.description ?? "none"), maxOS=\(maximumOS?.description ?? "none"), archs=\(finalArchitectures.map(\.rawValue))")

        return (minimumOS, maximumOS, finalArchitectures)
    }

    private func verifySystemRequirements(manifest: UpdateManifest) throws {
        log.info("Verifying system requirements")

        if let minimumOS = manifest.compatibility.minimumOS {
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumOS) else {
                throw UpdateError.incompatibleSystem(String(localized: "This update requires macOS \(minimumOS.description) or later."))
            }
            log.debug("Minimum OS requirement check passed for version: \(minimumOS.description)")
        }

        if let maximumOS = manifest.compatibility.maximumOS {
            // Maximum OS is inclusive
            // e.g. a max OS of 15.6.1 should allow Loop to be installed on 15.6.1, but not on 15.6.2
            let actualMaximumOS = OperatingSystemVersion(
                majorVersion: maximumOS.majorVersion,
                minorVersion: maximumOS.minorVersion,
                patchVersion: maximumOS.patchVersion + 1
            )

            guard !ProcessInfo.processInfo.isOperatingSystemAtLeast(actualMaximumOS) else {
                throw UpdateError.incompatibleSystem(String(localized: "This update requires macOS \(maximumOS.description) or earlier."))
            }

            log.debug("Maximum OS requirement check passed for version: \(maximumOS.description)")
        }

        let supportedArchitectures = manifest.compatibility.supportedArchitectures
        guard supportedArchitectures.contains(SystemInfo.architecture) else {
            let supported = supportedArchitectures.map(\.rawValue).joined(separator: ", ")
            log.error("Update requires \(supported) architecture")
            throw UpdateError.incompatibleSystem(String(localized: "This update isn’t available for this Mac."))
        }
        log.debug("Supported architectures check passed")

        log.success("All system requirement checks passed")
    }
}
