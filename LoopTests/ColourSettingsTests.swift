//
//  ColourSettingsTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import SwiftUI
import Testing
import Tome
import TOML

extension StoreTests {
    struct ColourSettingsTests {
        @Test func coloursReadSixOrEightDigitHexAndWriteSixWhenOpaque() throws {
            let profile = try Profile("[accent-color]\ncolor = \"#11223344\"\n")
            defer { Tome.reset(\.customAccentColor) }
            Tome.refresh(\.customAccentColor)
            #expect(try Color.tomeBridge.serialize(Tome.customAccentColor) == .string("#11223344"))
            #expect(!profile.issues.contains { $0.path == "accent-color.color" })
            Tome.customAccentColor = Color(.sRGB, red: 1, green: 0, blue: 0)
            #expect(profile.value(at: ["accent-color", "color"]) == .string("#FF0000"))
            try profile.install("[accent-color]\ncolor = \"#336699\"\n")
            Tome.refresh(\.customAccentColor)
            #expect(try Color.tomeBridge.serialize(Tome.customAccentColor) == .string("#336699"))
            #expect(!profile.issues.contains { $0.path == "accent-color.color" })
        }
    }
}
