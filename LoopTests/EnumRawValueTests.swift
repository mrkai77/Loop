//
//  EnumRawValueTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

struct EnumRawValueTests {
    @Test func oldCamelCaseSpellingsAreRejected() {
        for old in ["leftHalf", "noAction", "macOSCenter", "left_half"] {
            #expect(throws: (any Error).self) { try WindowDirection.decodeTOML(.string(old)) }
        }
        #expect(throws: (any Error).self) { try ScreenOrder.decodeTOML(.string("zShaped")) }
        #expect(throws: (any Error).self) { try WindowSelection.decodeTOML(.string("underCursor")) }
        #expect(throws: (any Error).self) { try GestureBinding.Kind.decodeTOML(.string("swipeUp")) }
        #expect(throws: (any Error).self) { try GestureBinding.ActivationZone.decodeTOML(.string("titleBar")) }
    }

    @Test func multiWordKeysAndKeyNamesAreKebabCase() throws {
        let frame = FrameAction(size: .initial, position: .anchor(.center), fallbackSize: .init(width: ScreenLength(40), height: nil))
        let table = try TOMLCodecs.decodeTable(TOMLEncoder().encodeToValue(frame))
        #expect(table["fallback-size"] != nil)
        #expect(table["fallbackSize"] == nil)
        #expect(throws: (any Error).self) { try KeyNames.canonical("rightcmd") }
        for name in ["right-cmd", "right-shift", "right-alt", "right-ctrl", "caps-lock", "page-up", "page-down", "forward-delete", "pad-clear", "pad-enter"] {
            #expect(try KeyNames.canonical(name) == name)
        }
    }

    @Test func theGestureMarkerAndPositionAnchorsAreKebabCase() throws {
        #expect(throws: (any Error).self) { try [GestureBinding].decodeTOML(.array([.table(["action": .string("radialMenu")])])) }
        let action = try TargetCoding.decodeAction(["action": .string("stash"), "position": .string("bottom-right")])
        #expect(action.position == .anchor(.bottomRight))
        #expect(try TargetCoding.encode(.windowAction(action))["position"] == .string("bottom-right"))
        #expect(throws: (any Error).self) { try TargetCoding.decodeAction(["action": .string("stash"), "position": .string("bottomRight")]) }
        #expect(try TargetCoding.encode(.windowAction(WindowAction(.noAction))) == ["action": .string("none")])
    }
}
