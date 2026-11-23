//
//  LoopRoute.swift
//  Loop
//
//  Created by Kai Azim on 2026-10-13.
//

import Foundation

/// What `list` can show
enum LoopListSubject: String, CaseIterable, Codable {
    case windows
    case screens
    case actions
    case keybinds
    case gestures
    case radialMenu = "radial-menu"

    /// As in "No windows"
    var pluralNoun: String {
        switch self {
        case .windows: "windows"
        case .screens: "screens"
        case .actions: "actions"
        case .keybinds: "keybinds"
        case .gestures: "gestures"
        case .radialMenu: "radial menu actions"
        }
    }
}

/// Every command the automation API accepts, so the app, the CLI and error suggestions spell routes the same way
enum LoopRoute: Hashable {
    case list(LoopListSubject)
    case run(LoopTarget)

    var components: [String] {
        switch self {
        case let .list(subject):
            ["list", subject.rawValue]
        case let .run(target):
            ["run", target.description]
        }
    }

    /// Unencoded, for showing to people, e.g. `loop://run/keybind:portrait`. Use `url(queryItems:)` to send a route
    var displayString: String {
        "loop://" + components.joined(separator: "/")
    }

    /// Encodes "/" too, so an id stays one path component
    func url(queryItems: [URLQueryItem] = []) -> URL {
        var allowedCharacters = CharacterSet.urlPathAllowed
        allowedCharacters.remove("/")

        var urlComponents = URLComponents()
        urlComponents.scheme = "loop"
        urlComponents.host = components[0]
        urlComponents.percentEncodedPath = "/" + components.dropFirst()
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? $0 }
            .joined(separator: "/")
        urlComponents.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = urlComponents.url else {
            preconditionFailure("Couldn’t build a URL for \(components)")
        }

        return url
    }

    init?(components: [String]) {
        guard components.count == 2 else {
            return nil
        }

        switch components[0].lowercased() {
        case "list":
            guard let subject = LoopListSubject(rawValue: components[1].lowercased()) else {
                return nil
            }
            self = .list(subject)
        case "run":
            guard let target = LoopTarget(components[1]) else {
                return nil
            }
            self = .run(target)
        default:
            return nil
        }
    }

    /// Accepts both `displayString` and encoded URLs
    init?(string: String) {
        guard let components = Self.pathComponents(of: string) else {
            return nil
        }

        self.init(components: components)
    }

    /// Splits before decoding, so an encoded "/" stays inside its component
    static func pathComponents(of string: String) -> [String]? {
        guard let range = string.range(of: "loop://", options: [.anchored, .caseInsensitive]) else {
            return nil
        }

        let path = string[range.upperBound...].split(separator: "?", maxSplits: 1).first ?? ""
        return path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.removingPercentEncoding ?? String($0) }
    }

    func commandLineInvocation(executableName: String) -> String {
        ([executableName] + components.map(Self.shellQuoted)).joined(separator: " ")
    }

    private static func shellQuoted(_ string: String) -> String {
        string.contains(where: { $0.isWhitespace || "'\"\\$`".contains($0) })
            ? "'" + string.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
            : string
    }
}

extension LoopAutomationError {
    init(_ code: LoopAutomationErrorCode, message: String, suggesting replacement: LoopRoute?, available: [LoopRoute] = []) {
        self.init(
            code,
            message: message,
            replacementRoute: replacement?.displayString,
            availableRoutes: available.isEmpty ? nil : available.map(\.displayString)
        )
    }
}
