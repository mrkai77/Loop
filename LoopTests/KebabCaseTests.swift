//
//  KebabCaseTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

struct KebabCaseTests {
    @Test func wordsSplitAtCapitalsAndAcronymsStayWhole() {
        let cases: [(String, String)] = [
            ("leftHalf", "left-half"),
            ("topTwoThirds", "top-two-thirds"),
            ("macOSCenter", "macos-center"),
            ("iOS", "ios"),
            ("HTTPServer", "http-server"),
            ("moveToSpace16", "move-to-space-16"),
            ("moveToSpace1", "move-to-space-1"),
            ("move-to-space-1", "move-to-space-1"),
            ("h264Codec", "h-264-codec"),
            ("maximize", "maximize"),
            ("already-kebab", "already-kebab"),
            ("snake_case words", "snake-case-words"),
            ("UPPER", "upper"),
            ("", ""),
            ("\u{1F680}!!", "")
        ]
        for (input, expected) in cases {
            #expect(ConfigurationIdentity.kebabCase(input) == expected, "\(input)")
        }
    }

    @Test func conversionIsIdempotent() {
        for direction in WindowDirection.allCases {
            let name = direction.rawValue
            #expect(ConfigurationIdentity.kebabCase(name) == name)
        }
    }
}
