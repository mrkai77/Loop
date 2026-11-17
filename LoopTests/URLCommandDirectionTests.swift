//
//  URLCommandDirectionTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import Foundation
@testable import Loop
import Testing
import Tome
import TOML

struct URLCommandDirectionTests {
    @Test func multiWordDirectionsMatchWithOrWithoutHyphens() {
        let cases: [(String, WindowDirection)] = [
            ("lefthalf", .leftHalf), ("left-half", .leftHalf), ("LeftHalf", .leftHalf),
            ("macoscenter", .macOSCenter), ("macos-center", .macOSCenter),
            ("toptwothirds", .topTwoThirds), ("movetospace12", .moveToSpace12), ("movetospace1", .moveToSpace1), ("move-to-space12", .moveToSpace12),
            ("focusnextinstack", .focusNextInStack), ("noaction", .noAction), ("none", .noAction),
            ("maximize", .maximize), ("bottomrightquarter", .bottomRightQuarter)
        ]
        for (input, expected) in cases {
            #expect(URLCommandHandler.direction(named: input) == expected, "\(input)")
        }
        #expect(URLCommandHandler.direction(named: "sideways") == nil)
    }

    @Test func urlsWrittenForOlderVersionsStillMatch() throws {
        let cases: [(String, WindowDirection)] = [
            ("loop://direction/noaction", .noAction), ("loop://direction/NoAction", .noAction),
            ("loop://direction/LeftHalf", .leftHalf), ("loop://direction/MacOSCenter", .macOSCenter),
            ("loop://direction/TopRightQuarter", .topRightQuarter), ("loop://direction/MoveToSpace3", .moveToSpace3),
            ("loop://direction/FocusNextInStack", .focusNextInStack)
        ]
        for (url, expected) in cases {
            let name = try #require(URL(string: url)).lastPathComponent
            #expect(URLCommandHandler.direction(forDirectionCommand: name) == expected, "\(url)")
        }
    }

    @Test func directionCommandKeepsItsAliases() {
        #expect(URLCommandHandler.direction(forDirectionCommand: "left") == .leftHalf)
        #expect(URLCommandHandler.direction(forDirectionCommand: "right") == .rightHalf)
        #expect(URLCommandHandler.direction(forDirectionCommand: "top") == .topHalf)
        #expect(URLCommandHandler.direction(forDirectionCommand: "bottom") == .bottomHalf)
        #expect(URLCommandHandler.direction(forDirectionCommand: "horizontalcenterhalf") == .horizontalCenterHalf)
    }
}
