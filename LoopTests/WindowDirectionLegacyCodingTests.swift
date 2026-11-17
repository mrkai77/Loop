//
//  WindowDirectionLegacyCodingTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

struct WindowDirectionLegacyCodingTests {
    /// The PascalCase names older versions stored in Defaults and JSON, one per case, by raw value.
    static let legacy: [String: String] = [
        "none": "NoAction",
        "no-selection": "NoSelection",
        "maximize": "Maximize",
        "almost-maximize": "AlmostMaximize",
        "fullscreen": "Fullscreen",
        "maximize-height": "MaximizeHeight",
        "maximize-width": "MaximizeWidth",
        "fill-available-space": "FillAvailableSpace",
        "undo": "Undo",
        "initial-frame": "InitialFrame",
        "hide": "Hide",
        "minimize": "Minimize",
        "minimize-others": "MinimizeOthers",
        "macos-center": "MacOSCenter",
        "center": "Center",
        "top-half": "TopHalf",
        "right-half": "RightHalf",
        "bottom-half": "BottomHalf",
        "left-half": "LeftHalf",
        "horizontal-center-half": "HorizontalCenterHalf",
        "vertical-center-half": "VerticalCenterHalf",
        "top-left-quarter": "TopLeftQuarter",
        "top-right-quarter": "TopRightQuarter",
        "bottom-right-quarter": "BottomRightQuarter",
        "bottom-left-quarter": "BottomLeftQuarter",
        "right-third": "RightThird",
        "right-two-thirds": "RightTwoThirds",
        "horizontal-center-third": "HorizontalCenterThird",
        "left-third": "LeftThird",
        "left-two-thirds": "LeftTwoThirds",
        "first-fourth": "FirstFourth",
        "second-fourth": "SecondFourth",
        "third-fourth": "ThirdFourth",
        "fourth-fourth": "FourthFourth",
        "left-three-fourths": "LeftThreeFourths",
        "right-three-fourths": "RightThreeFourths",
        "top-third": "TopThird",
        "top-two-thirds": "TopTwoThirds",
        "vertical-center-third": "VerticalCenterThird",
        "bottom-third": "BottomThird",
        "bottom-two-thirds": "BottomTwoThirds",
        "next-screen": "NextScreen",
        "previous-screen": "PreviousScreen",
        "left-screen": "LeftScreen",
        "right-screen": "RightScreen",
        "top-screen": "TopScreen",
        "bottom-screen": "BottomScreen",
        "next-space": "NextSpace",
        "previous-space": "PreviousSpace",
        "move-to-space-1": "MoveToSpace1",
        "move-to-space-2": "MoveToSpace2",
        "move-to-space-3": "MoveToSpace3",
        "move-to-space-4": "MoveToSpace4",
        "move-to-space-5": "MoveToSpace5",
        "move-to-space-6": "MoveToSpace6",
        "move-to-space-7": "MoveToSpace7",
        "move-to-space-8": "MoveToSpace8",
        "move-to-space-9": "MoveToSpace9",
        "move-to-space-10": "MoveToSpace10",
        "move-to-space-11": "MoveToSpace11",
        "move-to-space-12": "MoveToSpace12",
        "move-to-space-13": "MoveToSpace13",
        "move-to-space-14": "MoveToSpace14",
        "move-to-space-15": "MoveToSpace15",
        "move-to-space-16": "MoveToSpace16",
        "larger": "Larger",
        "smaller": "Smaller",
        "scale-up": "ScaleUp",
        "scale-down": "ScaleDown",
        "shrink-top": "ShrinkTop",
        "shrink-bottom": "ShrinkBottom",
        "shrink-right": "ShrinkRight",
        "shrink-left": "ShrinkLeft",
        "shrink-horizontal": "ShrinkHorizontal",
        "shrink-vertical": "ShrinkVertical",
        "grow-top": "GrowTop",
        "grow-bottom": "GrowBottom",
        "grow-right": "GrowRight",
        "grow-left": "GrowLeft",
        "grow-horizontal": "GrowHorizontal",
        "grow-vertical": "GrowVertical",
        "move-up": "MoveUp",
        "move-down": "MoveDown",
        "move-right": "MoveRight",
        "move-left": "MoveLeft",
        "focus-up": "FocusUp",
        "focus-down": "FocusDown",
        "focus-right": "FocusRight",
        "focus-left": "FocusLeft",
        "focus-next-in-stack": "FocusNextInStack",
        "stash": "Stash",
        "unstash": "Unstash",
        "custom": "Custom",
        "cycle": "Cycle"
    ]

    @Test func everyCaseCodesAsItsRawValue() throws {
        for direction in WindowDirection.allCases {
            let data = try JSONEncoder().encode([direction])
            #expect(String(data: data, encoding: .utf8) == "[\"\(direction.rawValue)\"]")
            #expect(try JSONDecoder().decode([WindowDirection].self, from: data) == [direction])
        }
    }

    @Test func everyLegacyNameReadsAsItsDirection() throws {
        #expect(Self.legacy.count == WindowDirection.allCases.count)
        for (raw, legacyName) in Self.legacy {
            #expect(try legacyAction(named: legacyName).direction.rawValue == raw, "\(legacyName)")
        }
    }

    @Test func unknownLegacyNamesAreRejected() {
        for name in ["left-half", "None", "Nope", "leftHalf", ""] {
            #expect(throws: (any Error).self) { try legacyAction(named: name) }
        }
    }

    private func legacyAction(named name: String) throws -> WindowAction {
        try JSONDecoder().decode(LegacyWindowAction.self, from: Data("{\"direction\":\"\(name)\",\"keybind\":[]}".utf8)).convertToWindowAction()
    }

    @Test func theFileFormUsesTheRawValue() throws {
        for direction in WindowDirection.allCases where direction != .custom && direction != .stash && direction != .cycle {
            #expect(try TargetCoding.encode(.windowAction(WindowAction(direction))) == ["action": .string(direction.rawValue)])
        }
    }
}
