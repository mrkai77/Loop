//
//  BindingResolutionSnapshotTests.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-14.
//

import Foundation
@testable import Loop
import Testing

struct BindingResolutionSnapshotTests {
    @Test func everyReferenceCategoryResolvesAcrossEveryDestination() throws {
        let final = WindowAction(.maximize)
        let destinations: [ActionTarget] = [.keyBinding("destination"), .gestureBinding("destination"), .radialMenuBinding("destination")]
        for target in destinations {
            let snapshot = BindingResolutionSnapshot(
                keyBindings: [.init(configID: "destination", target: .windowAction(final)), .init(configID: "source", target: target)],
                gestures: [.init(configID: "destination", target: .windowAction(final)), .init(configID: "source", target: target)],
                radialMenuBindings: [.init(configID: "destination", target: .windowAction(final)), .init(configID: "source", target: target)]
            )
            try snapshot.validate()
            for source in [ActionTarget.keyBinding("source"), .gestureBinding("source"), .radialMenuBinding("source")] {
                #expect(try snapshot.resolve(source)?.direction == .maximize)
            }
        }
    }

    @Test func multiHopReferencesResolveRegardlessOfPhysicalInputsOrOrdering() throws {
        let key = KeyBinding(configID: "key", keys: [], target: .gestureBinding("gesture"))
        let gesture = GestureBinding(kind: nil, configID: "gesture", target: .radialMenuBinding("menu"))
        let menu = RadialMenuBinding(configID: "menu", target: .keyBinding("final"))
        let final = KeyBinding(configID: "final", keys: [], target: .windowAction(.init(.leftHalf)))
        for keys in [[key, final], [final, key]] {
            let snapshot = BindingResolutionSnapshot(keyBindings: keys, gestures: [gesture], radialMenuBindings: [menu])
            try snapshot.validate()
            #expect(try snapshot.resolve(.keyBinding("key"))?.direction == .leftHalf)
        }
    }

    @Test func missingReferencesPerformNoActionAndRemainReferences() throws {
        let target = ActionTarget.gestureBinding("deleted")
        let snapshot = BindingResolutionSnapshot(keyBindings: [], gestures: [], radialMenuBindings: [])
        #expect(try snapshot.resolve(target)?.direction == .noAction)
        #expect(target == .gestureBinding("deleted"))
    }

    @Test func cyclesThroughAllCategoriesAndCycleStepsAreDiagnosed() {
        let key = KeyBinding(configID: "key", target: .gestureBinding("gesture"))
        let gesture = GestureBinding(configID: "gesture", target: .radialMenuBinding("menu"))
        let menu = RadialMenuBinding(configID: "menu", target: .windowAction(.init(kind: .cycle(.init(steps: [.keyBinding("key")])))))
        let snapshot = BindingResolutionSnapshot(keyBindings: [key], gestures: [gesture], radialMenuBindings: [menu])
        #expect(throws: BindingResolutionSnapshot.ResolutionError.self) { try snapshot.validate() }
        #expect(snapshot.action(for: .keyBinding("key"))?.direction == .noAction)
        let selfReference = BindingResolutionSnapshot(keyBindings: [.init(configID: "self", target: .keyBinding("self"))], gestures: [], radialMenuBindings: [])
        #expect(throws: BindingResolutionSnapshot.ResolutionError.self) { try selfReference.validate() }
    }

    @Test func radialMenuGestureModeHasNoSingleReferenceableAction() throws {
        let gesture = GestureBinding(kind: .radialMenu, configID: "radial", target: .radialMenuMode)
        let snapshot = BindingResolutionSnapshot(keyBindings: [], gestures: [gesture], radialMenuBindings: [])
        #expect(try snapshot.resolve(.radialMenuMode) == nil)
        try snapshot.validate() // A named mode gesture is harmless until referenced.
        #expect(throws: BindingResolutionSnapshot.ResolutionError.self) { try snapshot.resolve(.gestureBinding("radial")) }
    }

    @Test func cycleStepReferencesAreMaterialized() throws {
        let outer = WindowAction(kind: .cycle(.init(steps: [.gestureBinding("half"), .windowAction(.init(.maximize))])))
        let snapshot = BindingResolutionSnapshot(keyBindings: [], gestures: [.init(configID: "half", target: .windowAction(.init(.leftHalf)))], radialMenuBindings: [])
        try snapshot.validate()
        let resolvedCycle = try snapshot.resolve(.windowAction(outer))
        let cycle = try #require(resolvedCycle)
        #expect(cycle.resolvedCycleSteps?.map(\.direction) == [.leftHalf, .maximize])
        var coordinator = CycleActionCoordinator()
        var current = WindowAction(.noSelection)
        var parent: WindowAction?
        var directions: [WindowDirection] = []
        for _ in 0 ..< 3 {
            let proposed = coordinator.proposeAction(
                for: 1,
                in: cycle,
                currentAction: current,
                currentParentAction: parent,
                recordedAction: current,
                restartAtBeginningWhenInterrupted: true,
                mode: .advance(.forward)
            )
            let proposal = try #require(proposed)
            let committed = coordinator.commit(proposal, for: 1, in: cycle)
            current = try #require(committed)
            parent = cycle
            directions.append(current.direction)
        }
        #expect(directions == [.leftHalf, .maximize, .leftHalf])
    }

    @Test func aCycleStepReferencingACycleResolvesToNoActionAndIsReported() throws {
        let inner = WindowAction([.init(.leftHalf), .init(.rightHalf)])
        let outer = WindowAction(kind: .cycle(.init(steps: [.gestureBinding("inner"), .keyBinding("alias"), .windowAction(.init(.maximize))])))
        let snapshot = BindingResolutionSnapshot(
            keyBindings: [.init(configID: "alias", target: .gestureBinding("inner")), .init(configID: "outer", target: .windowAction(outer))],
            gestures: [.init(configID: "inner", target: .windowAction(inner))],
            radialMenuBindings: []
        )
        let resolved = try #require(snapshot.action(for: .keyBinding("outer")))
        #expect(resolved.resolvedCycleSteps?.map(\.direction) == [.noAction, .noAction, .maximize])
        #expect(snapshot.action(for: .gestureBinding("inner"))?.direction == .cycle)
        #expect(throws: BindingResolutionSnapshot.ResolutionError.nestedCycle(.gesture("inner"))) { try snapshot.validate() }
    }

    @Test func aCycleStepThatIsACycleInlineResolvesToNoActionAndIsReported() throws {
        let inline = WindowAction([.init(.leftHalf)])
        let outer = WindowAction(kind: .cycle(.init(steps: [.windowAction(inline), .windowAction(.init(.maximize))])))
        let snapshot = BindingResolutionSnapshot(keyBindings: [.init(configID: "outer", target: .windowAction(outer))], gestures: [], radialMenuBindings: [])
        #expect(snapshot.action(for: .keyBinding("outer"))?.resolvedCycleSteps?.map(\.direction) == [.noAction, .maximize])
        #expect(throws: BindingResolutionSnapshot.ResolutionError.nestedCycle(nil)) { try snapshot.validate() }
    }

    @Test func referencesToNonCycleBindingsAreNotNestedCycles() throws {
        let outer = WindowAction(kind: .cycle(.init(steps: [.keyBinding("half")])))
        let snapshot = BindingResolutionSnapshot(keyBindings: [.init(configID: "half", target: .windowAction(.init(.leftHalf))), .init(configID: "outer", target: .windowAction(outer))], gestures: [], radialMenuBindings: [])
        try snapshot.validate()
    }

    @Test func reverseCyclePolicyUsesPhysicalSourceRatherThanReferencedKeybind() throws {
        let destination = KeyBinding(configID: "destination", keys: [.kVK_Shift, .kVK_LeftArrow], target: .windowAction(.init([.init(.leftHalf), .init(.rightHalf)])))
        let source = KeyBinding(keys: [.kVK_RightArrow], target: .keyBinding("destination"))
        let snapshot = BindingResolutionSnapshot(keyBindings: [source, destination], gestures: [], radialMenuBindings: [])
        #expect(try snapshot.resolve(source.target)?.direction == .cycle)
        #expect(CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: source, triggerKeys: [], enabled: true))
        #expect(!CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: destination, triggerKeys: [], enabled: true))
        #expect(CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: nil, triggerKeys: [], enabled: true))
        #expect(!CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: nil, triggerKeys: [], enabled: false))
        #expect(!CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: nil, triggerKeys: [.kVK_Shift], enabled: true))
        #expect(!CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: source, triggerKeys: [.kVK_Shift], enabled: true))
    }

    @Test func shiftDoesNotReverseWhenTheBindingItselfContainsShift() {
        let shifted = KeyBinding(keys: [.kVK_Shift, .kVK_LeftArrow], target: .windowAction(.init([.init(.leftHalf), .init(.rightHalf)])))
        let plain = KeyBinding(keys: [.kVK_LeftArrow], target: .windowAction(.init([.init(.leftHalf), .init(.rightHalf)])))
        #expect(!CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: shifted, triggerKeys: [], enabled: true))
        #expect(CycleActionCoordinator.allowsShiftReverseCycle(sourceBinding: plain, triggerKeys: [], enabled: true))
    }

    @Test func sourceBindingSurvivesAChangeWithoutAKeybind() {
        let binding = KeyBinding(keys: [.kVK_LeftArrow], target: .windowAction(.init(.leftHalf)))
        let context = ResizeContext()
        context.setAction(to: .init(.leftHalf), parent: nil, sourceBinding: binding)
        context.setAction(to: .init(.rightHalf), parent: nil)
        #expect(context.sourceBinding?.id == binding.id)

        let other = KeyBinding(keys: [.kVK_RightArrow], target: .windowAction(.init(.rightHalf)))
        context.setAction(to: .init(.rightHalf), parent: nil, sourceBinding: other)
        #expect(context.sourceBinding?.id == other.id)
    }

    @Test func aliasesShareTerminalStashIdentity() throws {
        let stash = WindowAction(.stash)
        let snapshot = BindingResolutionSnapshot(
            keyBindings: [.init(configID: "stash", target: .windowAction(stash)), .init(configID: "alias", target: .keyBinding("stash"))],
            gestures: [.init(configID: "gesture", target: .keyBinding("alias"))],
            radialMenuBindings: [.init(configID: "menu", target: .gestureBinding("gesture"))]
        )
        for target in [ActionTarget.keyBinding("stash"), .keyBinding("alias"), .gestureBinding("gesture"), .radialMenuBinding("menu")] {
            #expect(try snapshot.resolve(target)?.id == snapshot.resolve(.keyBinding("stash"))?.id)
        }
    }

    @Test func cycleProgressContinuesAcrossInvocationCategories() throws {
        let cycle = WindowAction([.init(.leftHalf), .init(.rightHalf)])
        let snapshot = BindingResolutionSnapshot(
            keyBindings: [.init(configID: "cycle", target: .windowAction(cycle))],
            gestures: [.init(configID: "gesture", target: .keyBinding("cycle"))],
            radialMenuBindings: [.init(configID: "menu", target: .gestureBinding("gesture"))]
        )
        var coordinator = CycleActionCoordinator()
        var current = WindowAction(.noSelection)
        var parent: WindowAction?
        var directions: [WindowDirection] = []
        for target in [ActionTarget.keyBinding("cycle"), .gestureBinding("gesture"), .radialMenuBinding("menu")] {
            let resolved = try snapshot.resolve(target)
            let action = try #require(resolved)
            let proposed = coordinator.proposeAction(
                for: 1,
                in: action,
                currentAction: current,
                currentParentAction: parent,
                recordedAction: current,
                restartAtBeginningWhenInterrupted: true,
                mode: .advance(.forward)
            )
            let proposal = try #require(proposed)
            let committed = coordinator.commit(proposal, for: 1, in: action)
            current = try #require(committed)
            parent = action
            directions.append(current.direction)
        }
        #expect(directions == [.leftHalf, .rightHalf, .leftHalf])
    }
}
