//
//  LoopAutomationModels.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-30.
//

import CoreGraphics
import Foundation

enum LoopActionKind: String, Codable {
    case direction
    case keybind
}

enum LoopActionListFilter: String, Codable {
    case all
    case directionsOnly
    case keybindsOnly
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

struct LoopExecutionTargetWindow: Codable {
    let id: UInt32
    let bundleID: String
    let appName: String
    let title: String
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
    let directionCategories: [LoopActionCategory]
    let keybindActions: [LoopActionDescriptor]
}

struct LoopExecutionResult: Codable {
    let action: LoopActionDescriptor
    let targetWindow: LoopExecutionTargetWindow?
}

enum LoopAutomationResult: Codable {
    case windowList(LoopWindowListResult)
    case screenList(LoopScreenListResult)
    case actionList(LoopActionListResult)
    case execution(LoopExecutionResult)

    private enum CodingKeys: String, CodingKey {
        case kind
        case windows
        case screens
        case filter
        case directionCategories
        case keybindActions
        case action
        case targetWindow
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(LoopAutomationResultKind.self, forKey: .kind)

        switch kind {
        case .windowList:
            self = .windowList(
                LoopWindowListResult(
                    windows: try container.decode([LoopWindowSummary].self, forKey: .windows)
                )
            )
        case .screenList:
            self = .screenList(
                LoopScreenListResult(
                    screens: try container.decode([LoopScreenSummary].self, forKey: .screens)
                )
            )
        case .actionList:
            self = .actionList(
                LoopActionListResult(
                    filter: try container.decode(LoopActionListFilter.self, forKey: .filter),
                    directionCategories: try container.decode([LoopActionCategory].self, forKey: .directionCategories),
                    keybindActions: try container.decode([LoopActionDescriptor].self, forKey: .keybindActions)
                )
            )
        case .execution:
            self = .execution(
                LoopExecutionResult(
                    action: try container.decode(LoopActionDescriptor.self, forKey: .action),
                    targetWindow: try container.decodeIfPresent(LoopExecutionTargetWindow.self, forKey: .targetWindow)
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)

        switch self {
        case let .windowList(result):
            try container.encode(result.windows, forKey: .windows)
        case let .screenList(result):
            try container.encode(result.screens, forKey: .screens)
        case let .actionList(result):
            try container.encode(result.filter, forKey: .filter)
            try container.encode(result.directionCategories, forKey: .directionCategories)
            try container.encode(result.keybindActions, forKey: .keybindActions)
        case let .execution(result):
            try container.encode(result.action, forKey: .action)
            try container.encodeIfPresent(result.targetWindow, forKey: .targetWindow)
        }
    }
}

struct LoopAutomationError: Codable {
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
