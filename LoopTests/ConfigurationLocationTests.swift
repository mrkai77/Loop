//
//  ConfigurationLocationTests.swift
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

struct ConfigurationLocationTests {
    @Test func resolvesXDGOnlyWhenAbsolute() {
        let home = URL(fileURLWithPath: "/test/home")
        #expect(ConfigurationManager.fileURL(environment: [:], home: home).path == "/test/home/.config/loop/config.toml")
        #expect(ConfigurationManager.fileURL(environment: ["XDG_CONFIG_HOME": "relative"], home: home).path == "/test/home/.config/loop/config.toml")
        #expect(ConfigurationManager.fileURL(environment: ["XDG_CONFIG_HOME": "/custom"], home: home).path == "/custom/loop/config.toml")
    }
}
