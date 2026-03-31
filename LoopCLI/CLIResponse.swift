//
//  CLIResponse.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-29.
//

import Foundation

struct CLIActionDescriptor {
    let id: UUID
    let kind: String
    let name: String
    let slug: String
    let urlPath: String
    let idPath: String

    var idString: String {
        id.uuidString.lowercased()
    }
}

struct CLIResponse {
    let rawOutput: String
    let jsonBody: [String: Any]?
    let isSuccess: Bool
    let errorMessage: String?
    let replacement: String?
    let availableCommands: [String]
    let availableRoutes: [String]
    let keybindActions: [CLIActionDescriptor]

    init(rawOutput: String) {
        let trimmedOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawOutput = trimmedOutput

        if let data = trimmedOutput.data(using: .utf8),
           let jsonBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            self.jsonBody = jsonBody
            self.isSuccess = jsonBody["success"] as? Bool ?? false
            self.errorMessage = jsonBody["error"] as? String
            self.replacement = jsonBody["replacement"] as? String
            self.availableCommands = Self.stringArray(from: jsonBody["availableCommands"])
            self.availableRoutes = Self.stringArray(from: jsonBody["availableRoutes"])
            self.keybindActions = Self.actionDescriptors(from: jsonBody["keybindActions"])
        } else {
            self.jsonBody = nil
            self.isSuccess = false
            self.errorMessage = nil
            self.replacement = nil
            self.availableCommands = []
            self.availableRoutes = []
            self.keybindActions = []
        }
    }

    private static func stringArray(from value: Any?) -> [String] {
        (value as? [Any])?.compactMap { $0 as? String } ?? []
    }

    private static func actionDescriptors(from value: Any?) -> [CLIActionDescriptor] {
        guard let objects = value as? [[String: Any]] else {
            return []
        }

        return objects.compactMap { object in
            guard
                let idValue = object["id"] as? String,
                let id = UUID(uuidString: idValue),
                let kind = object["kind"] as? String,
                let name = object["name"] as? String,
                let slug = object["slug"] as? String,
                let urlPath = object["urlPath"] as? String,
                let idPath = object["idPath"] as? String
            else {
                return nil
            }

            return CLIActionDescriptor(
                id: id,
                kind: kind,
                name: name,
                slug: slug,
                urlPath: urlPath,
                idPath: idPath
            )
        }
    }
}
