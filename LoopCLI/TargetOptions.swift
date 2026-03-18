//
//  TargetOptions.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import ArgumentParser
import Foundation

struct TargetOptions: ParsableArguments {
    @Option(name: .customLong("window-id"), help: "Target a specific window by ID (from `list windows`)")
    var windowID: UInt32?

    @Option(name: .customLong("bundle-id"), help: "Target an app by bundle identifier (launches if needed)")
    var bundleID: String?

    @Option(name: .customLong("screen-id"), help: "Target a specific screen by ID (from `list screens`)")
    var screenID: UInt32?

    func validate() throws {
        if windowID != nil, bundleID != nil {
            throw ValidationError("--window-id and --bundle-id are mutually exclusive")
        }
    }

    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []

        if let windowID {
            items.append(URLQueryItem(name: "windowID", value: String(windowID)))
        }

        if let bundleID {
            items.append(URLQueryItem(name: "bundleID", value: bundleID))
        }

        if let screenID {
            items.append(URLQueryItem(name: "screenID", value: String(screenID)))
        }

        return items
    }
}
