//
//  CLIRequest.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import ArgumentParser
import Foundation

protocol CLIRequestCommand: ParsableCommand {
    var outputMode: CLIOutputMode { get }
    func makeRequest(using application: LoopCLIApplication) throws -> CLIRequest
}

extension CLIRequestCommand {
    func run() throws {
        try LoopCLIApplication.shared.execute(
            makeRequest(using: .shared),
            outputMode: outputMode
        )
    }
}

struct CLIRequest {
    let url: URL

    init(routeComponents: [String], queryItems: [URLQueryItem] = []) {
        precondition(!routeComponents.isEmpty, "CLIRequest requires at least one route component")

        var components = URLComponents()
        components.scheme = "loop"
        components.host = routeComponents[0]

        if routeComponents.count > 1 {
            components.path = "/" + routeComponents.dropFirst().joined(separator: "/")
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            preconditionFailure("Failed to construct loop:// request for \(routeComponents)")
        }

        self.url = url
    }

    var serializedRequest: String {
        url.absoluteString
    }
}
