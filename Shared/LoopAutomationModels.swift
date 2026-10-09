//
//  LoopAutomationModels.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import CoreGraphics
import Foundation

enum LoopActionKind: String, Codable {
    case preset
    case custom
}

enum LoopActionListFilter: String, Codable {
    case all
    case presetOnly
    case customOnly
}

enum LoopAutomationResultKind: String, Codable {
    case windowList
    case screenList
    case actionList
    case execution
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
    let bundleID: String
    let appName: String
    let title: String
    let frame: LoopRect
}

struct LoopScreenSummary: Codable {
    let id: UInt32
    let name: String
    let frame: LoopRect
    let isMain: Bool
}

struct LoopActionDescriptor: Codable {
    let id: UUID?
    let kind: LoopActionKind
    let title: String
    let name: String
    let route: String
    let idRoute: String?

    var idString: String? {
        id?.uuidString.lowercased()
    }
}

struct LoopActionCategory: Codable {
    let name: String
    let actions: [LoopActionDescriptor]
}

struct LoopWindowListResult: Codable {
    let windows: [LoopWindowSummary]
}

struct LoopScreenListResult: Codable {
    let screens: [LoopScreenSummary]
}

struct LoopActionListResult: Codable {
    let filter: LoopActionListFilter
    let presetCategories: [LoopActionCategory]
    let customActions: [LoopActionDescriptor]
}

struct LoopExecutionResult: Codable {
    let action: LoopActionDescriptor
    let targetWindow: LoopWindowSummary?
}

enum LoopAutomationResult: Codable {
    case windowList(LoopWindowListResult)
    case screenList(LoopScreenListResult)
    case actionList(LoopActionListResult)
    case execution(LoopExecutionResult)

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
        case .execution:
            .execution
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
        case .execution:
            self = try .execution(LoopExecutionResult(from: decoder))
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
        case let .execution(result):
            try result.encode(to: encoder)
        }
    }
}

struct LoopAutomationError: Codable, Error {
    let message: String
    let replacementRoute: String?
    let availableRoutes: [String]?

    init(
        message: String,
        replacementRoute: String? = nil,
        availableRoutes: [String]? = nil
    ) {
        self.message = message
        self.replacementRoute = replacementRoute
        self.availableRoutes = availableRoutes
    }
}

struct LoopAutomationResponse: Codable {
    let success: Bool
    let result: LoopAutomationResult?
    let error: LoopAutomationError?

    init(result: LoopAutomationResult) {
        self.success = true
        self.result = result
        self.error = nil
    }

    init(error: LoopAutomationError) {
        self.success = false
        self.result = nil
        self.error = error
    }
}
