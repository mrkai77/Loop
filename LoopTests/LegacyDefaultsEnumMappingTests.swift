//
//  LegacyDefaultsEnumMappingTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

struct LegacyDefaultsEnumMappingTests {
    @Test func previewSettingsStoredBeforeTheRawValuesChangedStillRead() {
        #expect(LegacyPreviewStartingPosition.screenCenter.current == .screenCenter)
        #expect(LegacyPreviewStartingPosition.radialMenu.current == .radialMenu)
        #expect(LegacyPreviewStartingPosition.actionCenter.current == .actionCenter)
        #expect(LegacyPreviewBackgroundStyle.custom.current == .custom)
        #expect(LegacyPreviewBackgroundStyle.system.current == .system)
        #expect(LegacyPreviewStartingPosition(rawValue: "screenCenter") == .screenCenter)
    }
}
