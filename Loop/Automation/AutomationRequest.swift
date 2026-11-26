//
//  AutomationRequest.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import Foundation

/// A `loop://` request, parsed and checked before anything runs.
/// Routes are `loop://list/<subject>` and `loop://run/<target>`, with `?windowID=`, `?bundleID=` and `?screenID=`.
struct AutomationRequest: Equatable {
    enum Command: Equatable {
        case route(LoopRoute)
        /// `action/<name>` and `keybind/<name>` from older versions, which matched keybinds by name
        case legacyNamedAction(String, scope: LegacyNameScope)
    }

    let command: Command
    let options: LoopTargetOptions

    init(command: Command, options: LoopTargetOptions = LoopTargetOptions()) {
        self.command = command
        self.options = options
    }

    /// Lists only read, so URLs show their output instead of only reporting failures
    var showsOutput: Bool {
        if case .route(.list) = command { true } else { false }
    }

    /// The route, such as "list windows"
    var title: String {
        switch command {
        case let .route(route):
            route.components.joined(separator: " ")
        case let .legacyNamedAction(name, _):
            name
        }
    }

    private static let listRoutes: [LoopRoute] = LoopListSubject.allCases.map { .list($0) }

    private static let exampleRunRoutes: [LoopRoute] = [
        .run(.action("right-half")),
        .run(.action("next-screen")),
        .run(.binding(.keybind, id: "<id>")),
        .run(.binding(.radialMenu, id: "<id>"))
    ]

    static func parse(_ url: URL) -> Result<Self, LoopAutomationError> {
        guard url.scheme?.lowercased() == "loop",
              let components = LoopRoute.pathComponents(of: url.absoluteString)
        else {
            return .failure(LoopAutomationError(.invalidRequest, message: "URLs must start with loop://"))
        }

        let options: LoopTargetOptions
        do {
            options = try LoopTargetOptions(queryItems: URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
        } catch {
            return .failure(error)
        }

        guard let command = LoopRoute(components: components).map(Command.route) ?? legacyCommand(from: components) else {
            return .failure(invalidRouteError(components))
        }

        let request = Self(command: command, options: options)
        if request.showsOutput, !options.isEmpty {
            return .failure(LoopAutomationError(.invalidRequest, message: "list doesn’t take windowID, bundleID or screenID"))
        }

        return .success(request)
    }

    private static func invalidRouteError(_ components: [String]) -> LoopAutomationError {
        guard let command = components.first?.lowercased() else {
            return LoopAutomationError(.invalidRequest, message: "No command given", suggesting: nil, available: listRoutes + exampleRunRoutes)
        }

        let arguments = components.dropFirst()

        switch command {
        case "list":
            return LoopAutomationError(
                .invalidRequest,
                message: arguments.isEmpty ? "No list type given" : "Unknown list type: \(arguments.joined(separator: "/"))",
                suggesting: nil,
                available: listRoutes
            )
        case "run":
            return LoopAutomationError(
                .invalidRequest,
                message: arguments.isEmpty ? "No action given" : "Invalid action: \(arguments.joined(separator: "/"))",
                suggesting: nil,
                available: exampleRunRoutes
            )
        default:
            return LoopAutomationError(.invalidRequest, message: "Unknown command: \(command)", suggesting: nil, available: listRoutes + exampleRunRoutes)
        }
    }
}
