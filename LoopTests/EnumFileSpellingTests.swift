//
//  EnumFileSpellingTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

/// Only the `move-to-space` numbers differ from the old spelling.
struct EnumFileSpellingTests {
    private func check<Value: Tome.Serializable & CaseIterable & Equatable>(_ expected: [String: String], _: Value.Type) throws where Value: RawRepresentable<String> {
        #expect(Value.allCases.count == expected.count, "\(Value.self)")
        for value in Value.allCases {
            // WindowDirection prints its raw value, so its case name comes from the old camelCase raw value.
            let name = (value as? WindowDirection).flatMap { WindowDirectionLegacyCodingTests.legacy[$0.rawValue] }.map { $0.prefix(1).lowercased() + $0.dropFirst() } ?? String(describing: value)
            #expect(expected[name] == value.rawValue, "\(Value.self).\(name)")
            #expect(try value.encodeTOML() == .string(expected[name] ?? ""), "\(Value.self).\(name)")
            #expect(try Value.decodeTOML(.string(value.rawValue)) == value)
        }
    }

    @Test func everyCaseKeepsItsFileSpelling() throws {
        try check([
            "noAction": "none",
            "noSelection": "no-selection",
            "maximize": "maximize",
            "almostMaximize": "almost-maximize",
            "fullscreen": "fullscreen",
            "maximizeHeight": "maximize-height",
            "maximizeWidth": "maximize-width",
            "fillAvailableSpace": "fill-available-space",
            "undo": "undo",
            "initialFrame": "initial-frame",
            "hide": "hide",
            "minimize": "minimize",
            "minimizeOthers": "minimize-others",
            "macOSCenter": "macos-center",
            "center": "center",
            "topHalf": "top-half",
            "rightHalf": "right-half",
            "bottomHalf": "bottom-half",
            "leftHalf": "left-half",
            "horizontalCenterHalf": "horizontal-center-half",
            "verticalCenterHalf": "vertical-center-half",
            "topLeftQuarter": "top-left-quarter",
            "topRightQuarter": "top-right-quarter",
            "bottomRightQuarter": "bottom-right-quarter",
            "bottomLeftQuarter": "bottom-left-quarter",
            "rightThird": "right-third",
            "rightTwoThirds": "right-two-thirds",
            "horizontalCenterThird": "horizontal-center-third",
            "leftThird": "left-third",
            "leftTwoThirds": "left-two-thirds",
            "firstFourth": "first-fourth",
            "secondFourth": "second-fourth",
            "thirdFourth": "third-fourth",
            "fourthFourth": "fourth-fourth",
            "leftThreeFourths": "left-three-fourths",
            "rightThreeFourths": "right-three-fourths",
            "topThird": "top-third",
            "topTwoThirds": "top-two-thirds",
            "verticalCenterThird": "vertical-center-third",
            "bottomThird": "bottom-third",
            "bottomTwoThirds": "bottom-two-thirds",
            "nextScreen": "next-screen",
            "previousScreen": "previous-screen",
            "leftScreen": "left-screen",
            "rightScreen": "right-screen",
            "topScreen": "top-screen",
            "bottomScreen": "bottom-screen",
            "nextSpace": "next-space",
            "previousSpace": "previous-space",
            "moveToSpace1": "move-to-space-1",
            "moveToSpace2": "move-to-space-2",
            "moveToSpace3": "move-to-space-3",
            "moveToSpace4": "move-to-space-4",
            "moveToSpace5": "move-to-space-5",
            "moveToSpace6": "move-to-space-6",
            "moveToSpace7": "move-to-space-7",
            "moveToSpace8": "move-to-space-8",
            "moveToSpace9": "move-to-space-9",
            "moveToSpace10": "move-to-space-10",
            "moveToSpace11": "move-to-space-11",
            "moveToSpace12": "move-to-space-12",
            "moveToSpace13": "move-to-space-13",
            "moveToSpace14": "move-to-space-14",
            "moveToSpace15": "move-to-space-15",
            "moveToSpace16": "move-to-space-16",
            "larger": "larger",
            "smaller": "smaller",
            "scaleUp": "scale-up",
            "scaleDown": "scale-down",
            "shrinkTop": "shrink-top",
            "shrinkBottom": "shrink-bottom",
            "shrinkRight": "shrink-right",
            "shrinkLeft": "shrink-left",
            "shrinkHorizontal": "shrink-horizontal",
            "shrinkVertical": "shrink-vertical",
            "growTop": "grow-top",
            "growBottom": "grow-bottom",
            "growRight": "grow-right",
            "growLeft": "grow-left",
            "growHorizontal": "grow-horizontal",
            "growVertical": "grow-vertical",
            "moveUp": "move-up",
            "moveDown": "move-down",
            "moveRight": "move-right",
            "moveLeft": "move-left",
            "focusUp": "focus-up",
            "focusDown": "focus-down",
            "focusRight": "focus-right",
            "focusLeft": "focus-left",
            "focusNextInStack": "focus-next-in-stack",
            "stash": "stash",
            "unstash": "unstash",
            "custom": "custom",
            "cycle": "cycle"
        ], WindowDirection.self)
        try check([
            "system": "system",
            "wallpaper": "wallpaper",
            "custom": "custom"
        ], AccentColorOption.self)
        try check([
            "fluid": "fluid",
            "relaxed": "relaxed",
            "snappy": "snappy",
            "brisk": "brisk",
            "instant": "instant"
        ], AnimationConfiguration.self)
        try check([
            "zShaped": "z-shaped",
            "clockwise": "clockwise"
        ], ScreenOrder.self)
        try check([
            "frontmost": "active",
            "underCursor": "under-cursor"
        ], WindowSelection.self)
        try check([
            "system": "system",
            "custom": "custom"
        ], PreviewBackgroundStyle.self)
        try check([
            "screenCenter": "screen-center",
            "radialMenu": "radial-menu",
            "actionCenter": "action-center"
        ], PreviewStartingPosition.self)
        try check([
            "simple": "simple",
            "custom": "custom"
        ], PaddingConfiguration.Mode.self)
        try check([
            "none": "none",
            "topLeft": "top-left",
            "top": "top",
            "topRight": "top-right",
            "right": "right",
            "bottomRight": "bottom-right",
            "bottom": "bottom",
            "bottomLeft": "bottom-left",
            "left": "left",
            "center": "center",
            "macOSCenter": "macos-center"
        ], CustomWindowActionAnchor.self)
        try check([
            "pixels": "pixels",
            "percentage": "percentage"
        ], CustomWindowActionUnit.self)
        try check([
            "custom": "custom",
            "preserve": "preserve",
            "initial": "initial"
        ], CustomWindowActionSizeMode.self)
        try check([
            "generic": "generic",
            "coordinates": "coordinates"
        ], CustomWindowActionPositionMode.self)
        try check([
            "radialMenu": "radial-menu",
            "swipeUp": "swipe-up",
            "swipeDown": "swipe-down",
            "swipeLeft": "swipe-left",
            "swipeRight": "swipe-right",
            "magnifyOut": "pinch",
            "magnifyIn": "spread"
        ], GestureBinding.Kind.self)
        try check([
            "titlebar": "title-bar",
            "anywhere": "anywhere"
        ], GestureBinding.ActivationZone.self)
    }
}
