//
//  LoopRoute.swift
//  Loop
//
//  Created by Kai Azim on 2026-10-13.
//

import Foundation

/// Every command the automation API accepts, so the app, the CLI and error suggestions spell routes the same way
enum LoopRoute: Hashable {
    case listWindows
    case listScreens
    case listActions(LoopActionListFilter)
    case exec(LoopActionKind, name: String)
    case execID(String)

    var components: [String] {
        switch self {
        case .listWindows:
            ["list", "windows"]
        case .listScreens:
            ["list", "screens"]
        case .listActions(.all):
            ["list", "actions"]
        case .listActions(.presetOnly):
            ["list", "actions", "preset"]
        case .listActions(.customOnly):
            ["list", "actions", "custom"]
        case let .exec(kind, name):
            ["exec", kind.rawValue, name]
        case let .execID(id):
            ["exec", "id", id]
        }
    }

    /// Unencoded, for showing to people, e.g. `loop://exec/custom/<name>`. Use `url(queryItems:)` to send a route
    var displayString: String {
        "loop://" + components.joined(separator: "/")
    }

    /// Encodes "/" too, so a name like "Left 1/3" stays one path component
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
        guard components.count >= 2 else { return nil }

        let command = components[0].lowercased()
        let subject = components[1].lowercased()
        let argument = components.count == 3 ? components[2] : nil

        switch (command, subject, argument?.lowercased()) {
        case ("list", "windows", nil) where components.count == 2:
            self = .listWindows
        case ("list", "screens", nil) where components.count == 2:
            self = .listScreens
        case ("list", "actions", nil) where components.count == 2:
            self = .listActions(.all)
        case ("list", "actions", "preset"):
            self = .listActions(.presetOnly)
        case ("list", "actions", "custom"):
            self = .listActions(.customOnly)
        case ("exec", "id", _?):
            self = .execID(components[2])
        case let ("exec", kind, _?):
            guard let kind = LoopActionKind(rawValue: kind) else { return nil }
            self = .exec(kind, name: components[2])
        default:
            return nil
        }
    }

    /// Accepts both `displayString` and encoded URLs
    init?(string: String) {
        guard let range = string.range(of: "loop://", options: [.anchored, .caseInsensitive]) else {
            return nil
        }

        let path = string[range.upperBound...].split(separator: "?", maxSplits: 1).first ?? ""
        let components = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.removingPercentEncoding ?? String($0) }

        self.init(components: components)
    }

    func commandLineInvocation(executableName: String) -> String {
        switch self {
        case .listWindows:
            "\(executableName) list windows"
        case .listScreens:
            "\(executableName) list screens"
        case .listActions(.all):
            "\(executableName) list actions"
        case .listActions(.presetOnly):
            "\(executableName) list actions --preset"
        case .listActions(.customOnly):
            "\(executableName) list actions --custom"
        case let .exec(kind, name):
            "\(executableName) exec --\(kind.rawValue) \(Self.shellQuoted(name))"
        case let .execID(id):
            "\(executableName) exec --id \(id)"
        }
    }

    private static func shellQuoted(_ string: String) -> String {
        string.contains(where: { $0.isWhitespace || "'\"\\$`".contains($0) })
            ? "'" + string.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
            : string
    }
}
