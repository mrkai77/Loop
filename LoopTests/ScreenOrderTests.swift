//
//  ScreenOrderTests.swift
//  LoopTests
//
//  Created by Anand Hegde on 2026-09-20.
//

import CoreGraphics
@testable import Loop
import Testing

struct ScreenOrderTests {
    /// A stand-in for a screen: a name, so that an order can be read at a glance, and the frame
    /// it occupies. Frames use Loop's screen coordinate space, where the y axis points up.
    private struct Screen {
        let name: String
        let frame: CGRect

        init(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat = 1920, height: CGFloat = 1080) {
            self.name = name
            self.frame = CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private func order(_ order: ScreenOrder, _ screens: [Screen]) -> [String] {
        order.sorted(screens, frame: \.frame).map(\.name)
    }

    // MARK: A single row

    /// Three screens side by side, the arrangement almost everybody has.
    private var row: [Screen] {
        [
            Screen("left", x: -1920, y: 0),
            Screen("middle", x: 0, y: 0),
            Screen("right", x: 1920, y: 0)
        ]
    }

    @Test func aRowIsWalkedLeftToRightClockwise() {
        #expect(order(.clockwise, row) == ["left", "middle", "right"])
    }

    @Test func aRowIsWalkedRightToLeftCounterclockwise() {
        #expect(order(.counterclockwise, row) == ["left", "right", "middle"])
    }

    @Test func aRowKeepsEveryScreenInTheCycle() {
        // A row has no inside, so the middle screen has to stay in the ring rather than being
        // treated as a screen the cycle visits later.
        #expect(order(.clockwise, row).count == row.count)
    }

    @Test func aRowOfDifferentlySizedScreensIsStillWalkedLeftToRight() {
        // A laptop display next to two larger screens: the centers no longer line up.
        let screens = [
            Screen("laptop", x: -1470, y: 0, width: 1470, height: 956),
            Screen("main", x: 0, y: 0, width: 2560, height: 1440),
            Screen("side", x: 2560, y: 200, width: 1920, height: 1080)
        ]

        #expect(order(.clockwise, screens) == ["laptop", "main", "side"])
    }

    // MARK: A column

    @Test func aColumnIsWalkedTopToBottomClockwise() {
        // Clockwise is the right hand side of the circle, which runs downwards.
        let screens = [
            Screen("top", x: 0, y: 2160),
            Screen("middle", x: 0, y: 1080),
            Screen("bottom", x: 0, y: 0)
        ]

        #expect(order(.clockwise, screens) == ["top", "middle", "bottom"])
        #expect(order(.counterclockwise, screens) == ["top", "bottom", "middle"])
    }

    // MARK: A square

    /// Four screens in a block, the arrangement the clockwise request was filed about.
    private var square: [Screen] {
        [
            Screen("topLeft", x: 0, y: 1080),
            Screen("topRight", x: 1920, y: 1080),
            Screen("bottomLeft", x: 0, y: 0),
            Screen("bottomRight", x: 1920, y: 0)
        ]
    }

    @Test func aSquareIsWalkedClockwiseFromTheTopLeft() {
        #expect(order(.clockwise, square) == ["topLeft", "topRight", "bottomRight", "bottomLeft"])
    }

    @Test func aSquareIsWalkedCounterclockwiseFromTheTopLeft() {
        #expect(order(.counterclockwise, square) == ["topLeft", "bottomLeft", "bottomRight", "topRight"])
    }

    @Test func theOrderDoesNotDependOnHowMacOSHandsOverTheScreens() {
        let shuffled = [square[2], square[0], square[3], square[1]]

        #expect(order(.clockwise, shuffled) == order(.clockwise, square))
    }

    @Test func aSquareIsWalkedRowByRowWhenZShaped() {
        #expect(order(.zShaped, square) == ["topLeft", "topRight", "bottomLeft", "bottomRight"])
    }

    // MARK: Screens with an inside

    @Test func theScreenInTheMiddleComesAfterTheOnesAroundIt() {
        // The nine screen arrangement from the feature request: the eight on the outside are
        // visited first, then the one they surround.
        var screens: [Screen] = []

        for row in 0 ..< 3 {
            for column in 0 ..< 3 {
                screens.append(
                    Screen("\(row)\(column)", x: CGFloat(column) * 1920, y: CGFloat(2 - row) * 1080)
                )
            }
        }

        #expect(
            order(.clockwise, screens) == [
                "00", "01", "02", "12", "22", "21", "20", "10", // around the outside
                "11" // and then the middle
            ]
        )
    }

    // MARK: Degenerate arrangements

    @Test func oneScreenIsItsOwnCycle() {
        let screens = [Screen("only", x: 0, y: 0)]

        for order in ScreenOrder.allCases {
            #expect(self.order(order, screens) == ["only"])
        }
    }

    @Test func twoScreensCycleTheSameWayAround() {
        let screens = [
            Screen("right", x: 1920, y: 0),
            Screen("left", x: 0, y: 0)
        ]

        for order in ScreenOrder.allCases {
            #expect(self.order(order, screens) == ["left", "right"])
        }
    }

    @Test func noScreensAreLostOrDuplicated() {
        let screens = [
            Screen("a", x: 0, y: 2160),
            Screen("b", x: 1920, y: 2160),
            Screen("c", x: 3840, y: 1080),
            Screen("d", x: 1920, y: 1080),
            Screen("e", x: 0, y: 0),
            Screen("f", x: 1920, y: 0),
            Screen("g", x: 3840, y: 0)
        ]

        for order in ScreenOrder.allCases {
            #expect(Set(self.order(order, screens)) == Set(screens.map(\.name)))
            #expect(self.order(order, screens).count == screens.count)
        }
    }

    @Test func everyScreenIsReachableByWalkingTheCycle() {
        // What next/previous screen actually relies on: starting anywhere and stepping forward
        // has to reach every screen before coming back around.
        let screens = [
            Screen("a", x: 0, y: 1080),
            Screen("b", x: 1920, y: 1080),
            Screen("c", x: 3840, y: 1080),
            Screen("d", x: 1920, y: 0),
            Screen("e", x: 0, y: 0)
        ]

        for order in ScreenOrder.allCases {
            let cycle = self.order(order, screens)

            for start in cycle.indices {
                let walked = (0 ..< cycle.count).map { cycle[(start + $0) % cycle.count] }
                #expect(Set(walked).count == screens.count)
            }
        }
    }
}
