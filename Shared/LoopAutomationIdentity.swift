//
//  LoopAutomationIdentity.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import Foundation

/// How the CLI and URLs name actions and bindings.
/// These match the ids Loop will write to its settings file, so a handle like `keybind:portrait` keeps working after the move.
enum LoopAutomationIdentity {
    /// `HTTPServer` becomes `http-server`, and `macOSCenter` becomes `macos-center`
    static func kebabCase(_ text: String) -> String {
        let characters = Array(text.folding(options: .diacriticInsensitive, locale: nil))
        var words: [String] = []
        var word = ""

        for (index, character) in characters.enumerated() {
            guard character.isASCII, character.isLetter || character.isNumber else {
                if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
                continue
            }

            let startsLowercaseRun = index + 1 < characters.count && characters[index + 1].isASCII && characters[index + 1].isLowercase
            let changesBetweenDigitsAndLetters = word.last.map { $0.isNumber != character.isNumber } ?? false
            if (character.isUppercase && startsLowercaseRun) || changesBetweenDigitsAndLetters, !word.isEmpty {
                words.append(word)
                word = ""
            }

            word.append(character.lowercased())
        }

        if !word.isEmpty {
            words.append(word)
        }

        return words.joined(separator: "-")
    }

    /// A repeated `halves` becomes `halves-2`
    static func nextFreeID(_ id: String, taken: Set<String>) -> String {
        guard taken.contains(id) else {
            return id
        }

        var suffix = 2
        while taken.contains("\(id)-\(suffix)") {
            suffix += 1
        }
        return "\(id)-\(suffix)"
    }

    /// Gives each stem the first free id, in order, so earlier rows keep the plain stem
    static func uniqueIDs(for stems: [String]) -> [String] {
        var taken: Set<String> = []
        return stems.map { stem in
            let id = nextFreeID(stem, taken: taken)
            taken.insert(id)
            return id
        }
    }
}
