//
//  ActionPositionMemoryTests.swift
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

struct ActionPositionMemoryTests {
    @Test func switchingPositionModesKeepsTheInactiveModesValues() {
        var memory = ActionPositionMemory()
        let coordinates = ActionPosition.coordinates(x: ScreenLength(25), y: ScreenLength(30, unit: .points))
        #expect(memory.switched(from: .anchor(.bottomRight), toCoordinates: true) == .coordinates(x: ScreenLength(0), y: ScreenLength(0)))
        #expect(memory.switched(from: coordinates, toCoordinates: false) == .anchor(.bottomRight))
        #expect(memory.switched(from: .anchor(.bottomRight), toCoordinates: true) == coordinates)
        #expect(memory.switched(from: coordinates, toCoordinates: false) == .anchor(.bottomRight))
    }

    @Test func anAnchorlessActionFallsBackToCenter() {
        var memory = ActionPositionMemory()
        #expect(memory.switched(from: .coordinates(x: ScreenLength(5), y: nil), toCoordinates: false) == .anchor(.center))
        #expect(memory.switched(from: .anchor(.center), toCoordinates: true) == .coordinates(x: ScreenLength(5), y: nil))
    }
}
