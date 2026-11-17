//
//  ConfigurationMessageTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-17.
//

import Foundation
@testable import Loop
import Testing
import TOML
import Tome

struct ConfigurationMessageTests {
    private func message<T: Decodable>(_ type: T.Type, _ value: TOMLValue) -> String? {
        do { _ = try TOMLDecoder().decodeFromValue(type, from: value) } catch let DecodingError.dataCorrupted(context) {
            return context.debugDescription
        } catch let DecodingError.typeMismatch(_, context) {
            return context.debugDescription
        } catch { return "\(error)" }
        return nil
    }

    @Test func gestureFingersNameTheCount() {
        #expect(message(GestureBinding.self, .table(["fingers": .integer(7), "action": .string("maximize")]))
            == "Fingers must be from 2 to 5, found '7'")
    }

    @Test func keyNamesNameTheEmptyEntry() {
        #expect(message(KeyCombination.self, .array([.string("a"), .string("")])) == "Key names can't be empty, found '[\"a\", \"\"]'")
    }

    @Test func targetsNameWhatIsWrong() {
        #expect(message(ActionTarget.self, .table(["action": .string("bogus")])) == "Unknown action 'bogus'")
        #expect(message(ActionTarget.self, .table(["action": .string("key:Not Valid!")]))
            == "Invalid key binding id 'Not Valid!'; use letters, digits, '-' and '_'")
    }

    @Test func payloadsNameWhatTheyFound() {
        #expect(message(ScreenLength.self, .boolean(true)) == "Expected a quoted length or a number of points, found 'true'")
        #expect(message(ScreenLength.self, .table([:])) == "Expected a quoted length or a number of points, found a table")
        #expect(message(ScreenLength.self, .string("25")) == "Expected a length ending in %, pt or px, found '25'")
        #expect(message(ActionSize.self, .table(["depth": .integer(1), "width": .string("1pt")]))
            == "Expected only 'width' and 'height' in a size table, found 'depth'")
        #expect(message(ActionPosition.self, .table(["z": .integer(1)])) == "Expected only 'x' and 'y' in a position table, found 'z'")
    }

    @Test func longValuesAreTruncated() {
        let long = String(repeating: "x", count: 60)
        #expect(message(ActionSize.self, .string(long)) == "Unknown size '\(String(repeating: "x", count: 40))…'")
    }
}
