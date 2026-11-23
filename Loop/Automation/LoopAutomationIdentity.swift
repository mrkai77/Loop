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

    /// ASCII letters, digits, `-` and `_`, as Loop's settings file allows
    static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
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

    /// Each binding's config ID, or else the first id from its action that's still free
    static func ids(for bindings: [some ActionBinding]) -> [String] {
        var taken = Set(bindings.compactMap(\.configID))
        return bindings.map { binding in
            if let configID = binding.configID {
                return configID
            }

            let id = nextFreeID(idStem(binding.bindingTarget), taken: taken)
            taken.insert(id)
            return id
        }
    }

    /// A custom, stash or cycle action's name, else its action's key, like the settings file
    static func idStem(_ target: BindingTarget?) -> String {
        guard let action = target?.action else {
            return "link"
        }

        if [.custom, .stash, .cycle].contains(action.direction), let name = action.name {
            let stem = kebabCase(name)
            if !stem.isEmpty {
                return stem
            }
        }

        return action.direction.automationKey
    }

    /// Gestures that open the radial menu can't be run, so they have no id
    static func runnableGestures(_ gestures: [GestureBinding]) -> [GestureBinding] {
        gestures.filter { $0.bindingTarget != nil }
    }
}
