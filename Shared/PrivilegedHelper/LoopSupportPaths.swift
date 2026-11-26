//
//  LoopSupportPaths.swift
//  Loop
//
//  Created by Kai Azim on 2026-02-23.
//

import Foundation

enum LoopSupportPaths {
    /// Returns `~/Library/Application Support` for the supplied home directory.
    static func appSupportDirectory(homeDirectory: URL) -> URL {
        canonical(homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true))
    }

    /// Returns the Loop application support root under the supplied home directory.
    static func loopDirectory(homeDirectory: URL) -> URL {
        canonical(appSupportDirectory(homeDirectory: homeDirectory).appendingPathComponent("Loop", isDirectory: true))
    }

    /// Returns the Loop backups directory under the supplied home directory.
    static func backupsDirectory(homeDirectory: URL) -> URL {
        canonical(loopDirectory(homeDirectory: homeDirectory).appendingPathComponent("Backups", isDirectory: true))
    }

    /// Returns the Loop staging directory under the supplied home directory.
    static func stagingDirectory(homeDirectory: URL) -> URL {
        canonical(loopDirectory(homeDirectory: homeDirectory).appendingPathComponent("Staging", isDirectory: true))
    }

    /// Returns the Loop rollback directory under the supplied home directory.
    static func rollbackDirectory(homeDirectory: URL) -> URL {
        canonical(loopDirectory(homeDirectory: homeDirectory).appendingPathComponent("Rollback.noindex", isDirectory: true))
    }

    /// Resolves symlinks and normalizes the URL to a standardized file URL.
    static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }
}
