//
//  CLIOutputFormatter.swift
//  LoopCLI
//
//  Created by Kai Azim on 2026-03-30.
//

import Foundation

struct CLIOutputFormatter {
    func format(_ response: CLIResponse, mode: CLIOutputMode) -> String {
        switch mode {
        case .json:
            return response.rawOutput
        case .human:
            guard let jsonBody = response.jsonBody else {
                return response.rawOutput
            }

            return formatHuman(jsonBody) ?? formatGenericValue(jsonBody, indentLevel: 0)
        }
    }

    private func formatHuman(_ body: [String: Any]) -> String? {
        guard let command = stringValue(body["command"])?.lowercased() else {
            return nil
        }

        switch command {
        case "list":
            return formatList(body)
        case "direction", "keybind", "id":
            return formatExecution(body)
        default:
            return nil
        }
    }

    private func formatList(_ body: [String: Any]) -> String? {
        guard let type = stringValue(body["type"])?.lowercased() else {
            return nil
        }

        switch type {
        case "windows":
            return formatWindows(body)
        case "screens":
            return formatScreens(body)
        case "actions":
            return formatActions(body)
        default:
            return nil
        }
    }

    private func formatWindows(_ body: [String: Any]) -> String {
        let windows = dictionaryArray(body["windows"])
        var lines = ["Windows (\(windows.count))"]

        guard !windows.isEmpty else {
            return lines[0]
        }

        for (index, window) in windows.enumerated() {
            lines.append("")
            lines.append("\(index + 1). \(windowHeading(window, fallback: "Window \(index + 1)"))")

            if let title = nonEmptyString(window["windowTitle"]) {
                lines.append("   Title: \(sanitizeInline(title))")
            }

            if let bundleID = nonEmptyString(window["bundleID"]) {
                lines.append("   Bundle ID: \(bundleID)")
            }

            if let windowID = integerString(window["windowID"]) {
                lines.append("   Window ID: \(windowID)")
            }

            if let frame = frameString(from: dictionaryValue(window["frame"])) {
                lines.append("   Frame: \(frame)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatScreens(_ body: [String: Any]) -> String {
        let screens = dictionaryArray(body["screens"])
        var lines = ["Screens (\(screens.count))"]

        guard !screens.isEmpty else {
            return lines[0]
        }

        for (index, screen) in screens.enumerated() {
            let name = nonEmptyString(screen["name"]) ?? "Screen \(index + 1)"
            let isMain = booleanValue(screen["isMain"]) ?? false
            let suffix = isMain ? " [main]" : ""

            lines.append("")
            lines.append("\(index + 1). \(sanitizeInline(name))\(suffix)")

            if let screenID = integerString(screen["screenID"]) {
                lines.append("   Screen ID: \(screenID)")
            }

            if let frame = frameString(from: dictionaryValue(screen["frame"])) {
                lines.append("   Frame: \(frame)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatActions(_ body: [String: Any]) -> String {
        let subtype = stringValue(body["subtype"])?.lowercased()
        var sections: [String] = []

        if subtype == nil || subtype == "directions" {
            sections.append(formatDirectionSections(dictionaryArray(body["directionActions"])))
        }

        if subtype == nil || subtype == "keybinds" {
            sections.append(formatKeybindSection(dictionaryArray(body["keybindActions"])))
        }

        let nonEmptySections = sections.filter { !$0.isEmpty }
        if nonEmptySections.isEmpty {
            return "Actions\n\nNone"
        }

        return nonEmptySections.joined(separator: "\n\n")
    }

    private func formatDirectionSections(_ categories: [[String: Any]]) -> String {
        guard !categories.isEmpty else {
            return "Direction Actions\n\nNone"
        }

        var lines = ["Direction Actions"]

        for category in categories {
            let categoryName = nonEmptyString(category["category"]) ?? "Actions"
            let actions = dictionaryArray(category["actions"])
            let rows = actions.compactMap(directionRow)

            guard !rows.isEmpty else {
                continue
            }

            lines.append("")
            lines.append(sanitizeInline(categoryName))
            lines.append(contentsOf: formatAlignedRows(rows, indent: "  "))
        }

        return lines.joined(separator: "\n")
    }

    private func formatKeybindSection(_ keybinds: [[String: Any]]) -> String {
        var lines = ["Keybind Actions (\(keybinds.count))"]

        guard !keybinds.isEmpty else {
            lines.append("")
            lines.append("None")
            return lines.joined(separator: "\n")
        }

        let duplicateNames = duplicateNameSet(for: keybinds)
        lines.append("")
        let rows = keybinds.compactMap(keybindRow)
        let width = rows.map(\.0.count).max() ?? 0

        for keybind in keybinds {
            guard let row = keybindRow(from: keybind) else {
                continue
            }

            lines.append(formatAlignedRow(row, width: width, indent: "  "))

            guard
                let name = nonEmptyString(keybind["name"]),
                duplicateNames.contains(name.caseInsensitiveCompareKey),
                let id = nonEmptyString(keybind["id"])
            else {
                continue
            }

            lines.append("    id: \(id.lowercased())")
        }

        return lines.joined(separator: "\n")
    }

    private func formatExecution(_ body: [String: Any]) -> String {
        let name = nonEmptyString(body["name"]) ?? "Action"
        var lines = ["Executed \(sanitizeInline(name))"]

        if let kind = nonEmptyString(body["kind"]) {
            lines.append("Kind: \(sanitizeInline(kind))")
        }

        if let slug = nonEmptyString(body["slug"]) {
            lines.append("Slug: \(sanitizeInline(slug))")
        }

        if let id = nonEmptyString(body["id"]) {
            lines.append("ID: \(id.lowercased())")
        }

        if let window = dictionaryValue(body["window"]) {
            lines.append("")
            lines.append("Target Window")
            lines.append(contentsOf: formatWindowDetails(window, indent: "  "))
        }

        return lines.joined(separator: "\n")
    }

    private func formatWindowDetails(_ window: [String: Any], indent: String) -> [String] {
        var lines = ["\(indent)App: \(windowHeading(window, fallback: "Unknown"))"]

        if let title = nonEmptyString(window["windowTitle"]) {
            lines.append("\(indent)Title: \(sanitizeInline(title))")
        }

        if let bundleID = nonEmptyString(window["bundleID"]) {
            lines.append("\(indent)Bundle ID: \(bundleID)")
        }

        if let windowID = integerString(window["windowID"]) {
            lines.append("\(indent)Window ID: \(windowID)")
        }

        if let frame = frameString(from: dictionaryValue(window["frame"])) {
            lines.append("\(indent)Frame: \(frame)")
        }

        return lines
    }

    private func formatAlignedRows(_ rows: [(String, String)], indent: String) -> [String] {
        let width = rows.map(\.0.count).max() ?? 0

        return rows.map { primary, secondary in
            formatAlignedRow((primary, secondary), width: width, indent: indent)
        }
    }

    private func formatAlignedRow(_ row: (String, String), width: Int, indent: String) -> String {
        let (primary, secondary) = row
        guard !secondary.isEmpty else {
            return "\(indent)\(primary)"
        }

        let padding = String(repeating: " ", count: max(2, width - primary.count + 2))
        return "\(indent)\(primary)\(padding)\(secondary)"
    }

    private func directionRow(from action: [String: Any]) -> (String, String)? {
        guard let slug = nonEmptyString(action["slug"]) else {
            return nil
        }

        let name = nonEmptyString(action["name"]) ?? slug
        return (sanitizeInline(slug), sanitizeInline(name))
    }

    private func keybindRow(from action: [String: Any]) -> (String, String)? {
        guard let slug = nonEmptyString(action["slug"]) else {
            return nil
        }

        let name = nonEmptyString(action["name"]) ?? slug
        return (sanitizeInline(slug), sanitizeInline(name))
    }

    private func duplicateNameSet(for keybinds: [[String: Any]]) -> Set<String> {
        var counts: [String: Int] = [:]

        for keybind in keybinds {
            guard let name = nonEmptyString(keybind["name"]) else {
                continue
            }

            counts[name.caseInsensitiveCompareKey, default: 0] += 1
        }

        return Set(counts.compactMap { key, value in
            value > 1 ? key : nil
        })
    }

    private func windowHeading(_ window: [String: Any], fallback: String) -> String {
        if let appName = nonEmptyString(window["appName"]) {
            return sanitizeInline(appName)
        }

        if let title = nonEmptyString(window["windowTitle"]) {
            return sanitizeInline(title)
        }

        return fallback
    }

    private func frameString(from frame: [String: Any]?) -> String? {
        guard
            let frame,
            let width = integerString(frame["width"]),
            let height = integerString(frame["height"]),
            let x = integerString(frame["x"]),
            let y = integerString(frame["y"])
        else {
            return nil
        }

        return "\(width)x\(height) @ \(x),\(y)"
    }

    private func dictionaryValue(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private func dictionaryArray(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty
        else {
            return nil
        }

        return string
    }

    private func booleanValue(_ value: Any?) -> Bool? {
        switch value {
        case let bool as Bool:
            return bool
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            return nil
        default:
            return nil
        }
    }

    private func integerString(_ value: Any?) -> String? {
        switch value {
        case let int as Int:
            return String(int)
        case let int32 as Int32:
            return String(int32)
        case let int64 as Int64:
            return String(int64)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return nil
            }
            return String(number.int64Value)
        default:
            return nil
        }
    }

    private func sanitizeInline(_ string: String) -> String {
        string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func formatGenericValue(_ value: Any, indentLevel: Int) -> String {
        if let dictionary = value as? [String: Any] {
            return formatGenericDictionary(dictionary, indentLevel: indentLevel)
        }

        if let array = value as? [Any] {
            return formatGenericArray(array, indentLevel: indentLevel)
        }

        return formatGenericScalar(value)
    }

    private func formatGenericDictionary(_ dictionary: [String: Any], indentLevel: Int) -> String {
        if dictionary.isEmpty {
            return "{}"
        }

        let indent = String(repeating: "  ", count: indentLevel)
        let sortedKeys = dictionary.keys.sorted()

        return sortedKeys.map { key in
            let value = dictionary[key]!
            if isCollection(value) {
                let renderedValue = formatGenericValue(value, indentLevel: indentLevel + 1)
                if renderedValue == "{}" || renderedValue == "[]" {
                    return "\(indent)\(key): \(renderedValue)"
                }
                return "\(indent)\(key):\n\(renderedValue)"
            }

            return "\(indent)\(key): \(formatGenericScalar(value))"
        }.joined(separator: "\n")
    }

    private func formatGenericArray(_ array: [Any], indentLevel: Int) -> String {
        if array.isEmpty {
            return "[]"
        }

        let indent = String(repeating: "  ", count: indentLevel)
        let childIndentLevel = indentLevel + 1

        return array.map { item in
            if isCollection(item) {
                let renderedValue = formatGenericValue(item, indentLevel: childIndentLevel)
                if renderedValue == "{}" || renderedValue == "[]" {
                    return "\(indent)- \(renderedValue)"
                }

                return "\(indent)-\n\(renderedValue)"
            }

            return "\(indent)- \(formatGenericScalar(item))"
        }.joined(separator: "\n")
    }

    private func formatGenericScalar(_ value: Any) -> String {
        switch value {
        case let string as String:
            return formatGenericString(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case _ as NSNull:
            return "null"
        default:
            return formatGenericString(String(describing: value))
        }
    }

    private func formatGenericString(_ string: String) -> String {
        guard requiresQuoting(string) else {
            return string
        }

        return "\"\(escape(string))\""
    }

    private func requiresQuoting(_ string: String) -> Bool {
        if string.isEmpty {
            return true
        }

        if string.trimmingCharacters(in: .whitespacesAndNewlines) != string {
            return true
        }

        if string.contains("\n") || string.contains("\r") {
            return true
        }

        if string.contains(": ") || string.contains("#") {
            return true
        }

        if string.contains("{") || string.contains("}") || string.contains("[") || string.contains("]") {
            return true
        }

        return false
    }

    private func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private func isCollection(_ value: Any) -> Bool {
        value is [String: Any] || value is [Any]
    }
}

private extension String {
    var caseInsensitiveCompareKey: String {
        lowercased()
    }
}
