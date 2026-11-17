//
//  OverlappingKeybindCycleTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-08-29.
//

import CoreGraphics
import Foundation
@testable import Loop
import Testing

struct OverlappingKeybindCycleTests {
    private let triggerKey: Set<CGKeyCode> = [.kVK_Control]
    private let firstKey: CGKeyCode = .kVK_LeftArrow
    private let secondKey: CGKeyCode = .kVK_RightArrow
    private let thirdKey: CGKeyCode = .kVK_DownArrow
    private let unrelatedKey: CGKeyCode = .kVK_UpArrow

    @Test func dualKeyCycleAdvancesWhenItsPrefixIsAlsoBound() throws {
        var fixture = makeDualKeyFixture()

        _ = try fixture.scenario.activate(pressedKeys: [firstKey])
        let firstSelection = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey])
        _ = try fixture.scenario.activate(pressedKeys: [firstKey])
        let secondSelection = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey])

        #expect(firstSelection.id == fixture.firstChordAction.id)
        #expect(secondSelection.id == fixture.secondChordAction.id)
    }

    @Test func dualKeyCycleRestartsAfterAnUnrelatedCycle() throws {
        var fixture = makeDualKeyFixture()

        _ = try fixture.scenario.activate(pressedKeys: [firstKey])
        _ = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey])
        _ = try fixture.scenario.activate(pressedKeys: [firstKey])
        let secondSelection = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey])
        _ = try fixture.scenario.activate(pressedKeys: [unrelatedKey])
        _ = try fixture.scenario.activate(pressedKeys: [firstKey])
        let restartedSelection = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey])

        #expect(secondSelection.id == fixture.secondChordAction.id)
        #expect(restartedSelection.id == fixture.firstChordAction.id)
    }

    @Test func tripleKeyCycleAdvancesWhenEachPrefixIsBound() throws {
        var fixture = makeTripleKeyFixture()

        _ = try fixture.scenario.activate(pressedKeys: [firstKey])
        _ = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey])
        let firstSelection = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey, thirdKey])
        _ = try fixture.scenario.activate(pressedKeys: [firstKey])
        _ = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey])
        let secondSelection = try fixture.scenario.activate(pressedKeys: [firstKey, secondKey, thirdKey])

        #expect(firstSelection.id == fixture.firstChordAction.id)
        #expect(secondSelection.id == fixture.secondChordAction.id)
    }

    private func makeDualKeyFixture() -> Fixture {
        let prefixCycle = WindowAction(
            cycle: [
                .init(.leftHalf),
                .init(.rightHalf)
            ]
        )
        let firstChordAction = WindowAction(.topHalf)
        let secondChordAction = WindowAction(.bottomHalf)
        let chordCycle = WindowAction(
            cycle: [
                firstChordAction,
                secondChordAction
            ]
        )
        let unrelatedCycle = WindowAction(
            cycle: [
                .init(.topLeftQuarter),
                .init(.bottomRightQuarter)
            ]
        )
        let actions: [Set<CGKeyCode>: WindowAction] = [
            [firstKey]: prefixCycle,
            [firstKey, secondKey]: chordCycle,
            [unrelatedKey]: unrelatedCycle
        ]

        return Fixture(
            scenario: Scenario(
                triggerKey: triggerKey,
                actions: actions
            ),
            firstChordAction: firstChordAction,
            secondChordAction: secondChordAction
        )
    }

    private func makeTripleKeyFixture() -> Fixture {
        let prefixCycle = WindowAction(
            cycle: [
                .init(.leftHalf),
                .init(.rightHalf)
            ]
        )
        let intermediateCycle = WindowAction(
            cycle: [
                .init(.topLeftQuarter),
                .init(.bottomRightQuarter)
            ]
        )
        let firstChordAction = WindowAction(.topHalf)
        let secondChordAction = WindowAction(.bottomHalf)
        let chordCycle = WindowAction(
            cycle: [
                firstChordAction,
                secondChordAction
            ]
        )
        let actions: [Set<CGKeyCode>: WindowAction] = [
            [firstKey]: prefixCycle,
            [firstKey, secondKey]: intermediateCycle,
            [firstKey, secondKey, thirdKey]: chordCycle
        ]

        return Fixture(
            scenario: Scenario(
                triggerKey: triggerKey,
                actions: actions
            ),
            firstChordAction: firstChordAction,
            secondChordAction: secondChordAction
        )
    }

    private struct Fixture {
        var scenario: Scenario
        let firstChordAction: WindowAction
        let secondChordAction: WindowAction
    }

    private struct Scenario {
        let triggerKey: Set<CGKeyCode>
        let actions: [Set<CGKeyCode>: WindowAction]

        let bindings: [UUID: KeyBinding]
        var resizeContext = ResizeContext()

        init(triggerKey: Set<CGKeyCode>, actions: [Set<CGKeyCode>: WindowAction]) {
            self.triggerKey = triggerKey
            self.actions = actions
            self.bindings = Dictionary(uniqueKeysWithValues: actions.map { keys, action in
                (action.id, KeyBinding(id: action.id, keys: KeyCombination(keyCodes: keys, layout: FakeLayouts.layout(FakeLayouts.us).0), target: .windowAction(action)))
            })
        }

        mutating func activate(pressedKeys: Set<CGKeyCode>) throws -> WindowAction {
            let decision = KeybindResolver.resolve(
                .init(
                    eventType: .keyDown,
                    isRepeat: false,
                    pressedKeys: pressedKeys,
                    modifierKeys: triggerKey,
                    trigger: .init(keys: triggerKey, isSideDependent: false),
                    isLoopOpen: true,
                    actionsByKeybind: actions,
                    bypassedActionsByKeybind: [:]
                )
            )
            let matchedAction = try #require(openedAction(decision.effect))

            guard matchedAction.direction == .cycle else {
                resizeContext.setAction(to: matchedAction, parent: nil, sourceBinding: bindings[matchedAction.id])
                return matchedAction
            }

            let cycleAction = matchedAction
            let proposedAction = resizeContext.proposeCycleAction(
                in: cycleAction,
                restartAtBeginningWhenInterrupted: true,
                mode: .advance(.forward),
                sourceBinding: bindings[cycleAction.id]
            )
            let proposal = try #require(proposedAction)
            let committedAction = resizeContext.commitCycleAction(proposal, in: cycleAction)
            let action = try #require(committedAction)

            resizeContext.setAction(to: action, parent: cycleAction, sourceBinding: bindings[cycleAction.id])
            return action
        }

        private func openedAction(
            _ effect: KeybindResolver.Effect
        ) -> WindowAction? {
            guard case let .open(action, _) = effect else {
                return nil
            }
            return action
        }
    }
}
