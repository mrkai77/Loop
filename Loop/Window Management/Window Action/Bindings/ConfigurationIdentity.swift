//
//  ConfigurationIdentity.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import CryptoKit
import Foundation

enum ConfigurationIdentity {
    private static let namespace = UUID(uuid: (0x4C, 0x4F, 0x4F, 0x50, 0x4C, 0x4F, 0x4F, 0x50, 0x4C, 0x4F, 0x4F, 0x50, 0x4C, 0x4F, 0x4F, 0x50))

    /// ASCII letters, digits, `-` and `_`.
    static func isValid(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    static func validate(_ id: String, as description: String = "id") throws {
        guard isValid(id) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid \(description) \(ConfigurationMessage.quoted(id)); use letters, digits, '-' and '_'"))
        }
    }

    /// References keep resolving to the first row. A repeated `move-to-space-1` becomes `move-to-space-1-2`.
    static func deduplicatingIDs<Binding: ActionBinding>(_ bindings: [Binding]) -> [Binding] {
        var taken = Set(bindings.compactMap(\.configID))
        var seen: Set<String> = []
        return bindings.map { binding in
            guard let id = binding.configID, !seen.insert(id).inserted else { return binding }
            let renamed = nextFreeID(id, taken: taken)
            taken.insert(renamed)
            var binding = binding
            binding.configID = renamed
            binding.deriveIdentity()
            return binding
        }
    }

    static func isGenerated(_ id: String, from stem: String) -> Bool {
        if id == stem { return true }
        guard id.hasPrefix(stem + "-"), let suffix = Int(id.dropFirst(stem.count + 1)) else { return false }
        return suffix >= 2
    }

    static func nextFreeID(_ id: String, taken: Set<String>) -> String {
        guard taken.contains(id) else { return id }
        var suffix = 2
        while taken.contains("\(id)-\(suffix)") { suffix += 1 }
        return "\(id)-\(suffix)"
    }

    /// `HTTPServer` becomes `http-server`, and `macOSCenter` becomes `macos-center`.
    static func kebabCase(_ text: String) -> String {
        let characters = Array(text.folding(options: .diacriticInsensitive, locale: nil))
        var words: [String] = []
        var word = ""
        for (index, character) in characters.enumerated() {
            guard character.isASCII, character.isLetter || character.isNumber else {
                if !word.isEmpty { words.append(word); word = "" }
                continue
            }
            let startsLowercaseRun = index + 1 < characters.count && characters[index + 1].isASCII && characters[index + 1].isLowercase
            let changesBetweenDigitsAndLetters = word.last.map { $0.isNumber != character.isNumber } ?? false
            if (character.isUppercase && startsLowercaseRun) || changesBetweenDigitsAndLetters, !word.isEmpty { words.append(word); word = "" }
            word.append(character.lowercased())
        }
        if !word.isEmpty { words.append(word) }
        return words.joined(separator: "-")
    }

    static func uuid(_ seed: String) -> UUID {
        var bytes = namespace.uuid
        let data = withUnsafeBytes(of: &bytes) { Data($0) }
        var hash = Array(Insecure.SHA1.hash(data: data + Data(seed.utf8)).prefix(16))
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return hash.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
    }
}
