//
//  UpdaterModels.swift
//  Loop
//
//  Created by Kami on 2026-01-22.
//

import Foundation

// MARK: - UpdateChannel

enum UpdateChannel: String, CaseIterable {
    case stable
    case development

    var displayName: String {
        switch self {
        case .stable: "Stable"
        case .development: "Development"
        }
    }

    var isDevelopmentChannel: Bool {
        switch self {
        case .stable: false
        case .development: true
        }
    }

    var githubReleasesEndpoint: String {
        switch self {
        case .stable: "https://api.github.com/repos/MrKai77/Loop/releases/latest"
        case .development: "https://api.github.com/repos/MrKai77/Loop/releases"
        }
    }
}

// MARK: - UpdateManifest

struct UpdateManifest {
    let version: String
    let buildNumber: Int
    let downloadUrl: String
    let releaseNotes: ReleaseNotes
    let checksums: Checksums
    let compatibility: Compatibility
    let channel: UpdateChannel
    let publishedAt: Date
    let size: Int64

    struct ReleaseNotes {
        let title: String
        let body: String
    }

    struct Compatibility {
        let minimumOS: OperatingSystemVersion?
        let maximumOS: OperatingSystemVersion?
        let supportedArchitectures: [SystemInfo.Architecture]
    }

    struct Checksums {
        let zip: String
    }
}

// MARK: - UpdateProgress

struct UpdateProgress {
    let phase: UpdatePhase
    let percentage: Double
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let estimatedTimeRemaining: TimeInterval?
    let downloadSpeed: Double?

    enum UpdatePhase: String {
        case checking, downloading, extracting, verifying, installing, cleaning, completed, failed
    }

    init(
        phase: UpdatePhase,
        percentage: Double,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0,
        estimatedTimeRemaining: TimeInterval? = nil,
        downloadSpeed: Double? = nil
    ) {
        self.phase = phase
        self.percentage = percentage
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.downloadSpeed = downloadSpeed
    }
}

// MARK: - UpdateError

enum UpdateError: LocalizedError {
    case network(Error)
    case invalidManifest(String? = nil)
    case checksumMismatch
    case installationFailed(String)
    case incompatibleSystem(String)
    case security(String)
    case timeout
    case http(Int)

    var errorDescription: String? {
        switch self {
        case let .network(error):
            "Network error: \(error.localizedDescription)"
        case let .invalidManifest(details):
            details.map { "Invalid update manifest: \($0)" } ?? "Invalid update manifest"
        case .checksumMismatch:
            "File integrity check failed"
        case let .installationFailed(reason):
            "Installation failed: \(reason)"
        case let .incompatibleSystem(reason):
            reason
        case let .security(reason):
            "Security error: \(reason)"
        case .timeout:
            "Request timed out"
        case let .http(code):
            "HTTP error (\(code))"
        }
    }

    var isRetryable: Bool {
        switch self {
        case let .network(error):
            if let urlError = error as? URLError {
                return [.timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .dnsLookupFailed].contains(urlError.code)
            }
            return false
        case .timeout:
            return true
        case let .http(code) where code >= 500:
            return true
        default:
            return false
        }
    }
}

// MARK: - GitHubRelease Model

struct GitHubRelease: Codable {
    var id: Int
    var tagName: String
    var name: String
    var body: String
    var assets: [Asset]
    var prerelease: Bool
    var createdAt: Date
    var updatedAt: Date
    var publishedAt: Date

    var buildNumber: Int?

    enum CodingKeys: String, CodingKey {
        case id, tagName = "tag_name", name, body, assets, prerelease, createdAt = "created_at", updatedAt = "updated_at", publishedAt = "published_at"
    }

    struct Asset: Codable {
        var name: String
        var browserDownloadURL: URL
        var size: Int
        var digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
            case size
            case digest
        }
    }
}

// MARK: - InstallState

enum InstallState: Equatable {
    case ready
    case installing
    case readyToRestart
    case failed(any Error)

    static func == (lhs: InstallState, rhs: InstallState) -> Bool {
        switch (lhs, rhs) {
        case (.ready, .ready),
             (.installing, .installing),
             (.readyToRestart, .readyToRestart):
            true
        case let (.failed(lhsErr), .failed(rhsErr)):
            lhsErr.localizedDescription == rhsErr.localizedDescription
        default:
            false
        }
    }

    var label: String {
        switch self {
        case .ready:
            String(localized: "Install")
        case .installing:
            "          " // Helps with alignment for the animation once the update finishes
        case .readyToRestart:
            String(localized: "Relaunch to Complete")
        case .failed:
            String(localized: "Install Failed")
        }
    }

    var isUpdateButtonInteractive: Bool {
        switch self {
        case .ready, .readyToRestart:
            true
        case .installing, .failed:
            false
        }
    }

    var isCancelButtonInteractive: Bool {
        switch self {
        case .ready, .failed:
            true
        case .readyToRestart, .installing:
            false
        }
    }

    var errorDescription: String? {
        if case let .failed(error) = self {
            error.localizedDescription
        } else {
            nil
        }
    }

    var isFailure: Bool {
        if case .failed = self {
            true
        } else {
            false
        }
    }
}

// MARK: - UpdateAvailability

enum UpdateAvailability {
    case available
    case unavailable
    case osNotSupported

    var text: String {
        switch self {
        case .unavailable:
            String(localized: "Check for Updates…")
        case .available:
            String(localized: "Update…")
        case .osNotSupported:
            String(localized: "This macOS version is no longer supported.")
        }
    }
}
