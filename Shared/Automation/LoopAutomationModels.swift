//
//  LoopAutomationModels.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import CoreGraphics
import Foundation

// Every key is always present, with `null` for missing values, so scripts can rely on the shape.
// `key`, `id`, `target` and `code` values are stable; `name`, `title`, `category`, `trigger` and `note` are display text.
// Version 1 only ever gains keys, result kinds and error codes. Anything else bumps `version`, so readers should ignore what they don't know.

enum LoopAutomationResultKind: String, Codable {
    case windowList
    case screenList
    case actionList
    case bindingList
    case run
}

struct LoopRect: Codable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }
}

struct LoopWindowSummary: Codable {
    let id: UInt32
    @NullEncoded var bundleID: String?
    @NullEncoded var appName: String?
    @NullEncoded var title: String?
    let frame: LoopRect
}

struct LoopScreenSummary: Codable {
    let id: UInt32
    let name: String
    let frame: LoopRect
    let isMain: Bool
}

/// A built-in action that `run` can trigger by its `key`
struct LoopActionSummary: Codable {
    let key: String
    let name: String
    let category: String
}

/// The action a binding runs
struct LoopBoundAction: Codable {
    /// A built-in action's key, or `custom`, `cycle` or `stash`
    let key: String
    let name: String
}

/// A keybind, gesture or radial menu action
struct LoopBindingSummary: Codable {
    let kind: LoopBindingKind
    /// `nil` for gestures that open the radial menu, as they don't run an action themselves
    @NullEncoded var id: String?
    /// What to pass to `run`, such as `keybind:portrait`
    @NullEncoded var target: String?
    @NullEncoded var action: LoopBoundAction?
    /// Set when the action comes from another binding, such as `keybind:portrait`
    @NullEncoded var linkedTarget: String?
    /// How it's triggered, such as the keys, the gesture or the radial menu slot
    @NullEncoded var trigger: String?
    /// Whether the keybind or gesture currently triggers anything. Inactive bindings can still be run.
    let isActive: Bool
    /// Why it isn't active, or why it can't be run
    @NullEncoded var note: String?
}

struct LoopWindowListResult: Codable {
    let windows: [LoopWindowSummary]
}

struct LoopScreenListResult: Codable {
    let screens: [LoopScreenSummary]
}

struct LoopActionListResult: Codable {
    let actions: [LoopActionSummary]
}

struct LoopBindingListResult: Codable {
    let bindingKind: LoopBindingKind
    let bindings: [LoopBindingSummary]
}

struct LoopRunResult: Codable {
    let target: String
    let action: LoopBoundAction
    @NullEncoded var window: LoopWindowSummary?
}

enum LoopAutomationResult: Codable {
    case windowList(LoopWindowListResult)
    case screenList(LoopScreenListResult)
    case actionList(LoopActionListResult)
    case bindingList(LoopBindingListResult)
    case run(LoopRunResult)

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    var kind: LoopAutomationResultKind {
        switch self {
        case .windowList:
            .windowList
        case .screenList:
            .screenList
        case .actionList:
            .actionList
        case .bindingList:
            .bindingList
        case .run:
            .run
        }
    }

    /// Each payload's keys sit next to `kind` in the same object
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        switch try container.decode(LoopAutomationResultKind.self, forKey: .kind) {
        case .windowList:
            self = try .windowList(LoopWindowListResult(from: decoder))
        case .screenList:
            self = try .screenList(LoopScreenListResult(from: decoder))
        case .actionList:
            self = try .actionList(LoopActionListResult(from: decoder))
        case .bindingList:
            self = try .bindingList(LoopBindingListResult(from: decoder))
        case .run:
            self = try .run(LoopRunResult(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .windowList(result):
            try result.encode(to: encoder)
        case let .screenList(result):
            try result.encode(to: encoder)
        case let .actionList(result):
            try result.encode(to: encoder)
        case let .bindingList(result):
            try result.encode(to: encoder)
        case let .run(result):
            try result.encode(to: encoder)
        }
    }
}

/// Stable reasons for a failure, so scripts don't have to match on messages
enum LoopAutomationErrorCode: String, Codable {
    /// The request isn't a valid command, or one of its values is malformed
    case invalidRequest
    /// The action, binding, window, screen or app doesn't exist
    case notFound
    /// The action needs a window, and there isn't one to act on
    case noWindow
    /// The window belongs to an app excluded in Loop's settings
    case excludedApp
    /// The window is in full screen, and Loop is set to ignore those
    case fullscreenWindow
    /// Loop can't run commands, such as when it isn't running, its command-line tool isn't set up, or it lacks Accessibility access
    case unavailable
    /// The command didn't finish in time, and may still complete
    case timeout
    /// The command ran but didn't succeed
    case failed

    /// `sysexits.h` codes, so scripts can tell bad usage and Loop being unavailable or slow apart from a failed command
    var exitCode: Int32 {
        switch self {
        case .invalidRequest: EX_USAGE
        case .unavailable: EX_UNAVAILABLE
        case .timeout: EX_TEMPFAIL
        case .notFound, .noWindow, .excludedApp, .fullscreenWindow, .failed: EXIT_FAILURE
        }
    }

    /// Reads codes from a newer Loop as `failed`, rather than failing to read the whole response
    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: rawValue) ?? .failed
    }
}

struct LoopAutomationError: Codable, Error {
    let code: LoopAutomationErrorCode
    let message: String
    /// A route to run instead, such as the list of what exists
    @NullEncoded var replacementRoute: String?
    @NullEncoded var availableRoutes: [String]?

    init(
        _ code: LoopAutomationErrorCode,
        message: String,
        replacementRoute: String? = nil,
        availableRoutes: [String]? = nil
    ) {
        self.code = code
        self.message = message
        self.replacementRoute = replacementRoute
        self.availableRoutes = availableRoutes
    }
}

struct LoopAutomationResponse: Codable {
    /// Bumped when the shape changes in a way that could break scripts
    static let currentVersion = 1

    let version: Int
    let success: Bool
    @NullEncoded var result: LoopAutomationResult?
    @NullEncoded var error: LoopAutomationError?

    init(result: LoopAutomationResult) {
        self.version = Self.currentVersion
        self.success = true
        self.result = result
        self.error = nil
    }

    init(error: LoopAutomationError) {
        self.version = Self.currentVersion
        self.success = false
        self.result = nil
        self.error = error
    }
}
