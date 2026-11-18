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
        let destinations: [ActionTarget] = [.reference(.init(.key, "destination")), .reference(.init(.gesture, "destination")), .reference(.init(.radialMenu, "destination"))]
        for target in destinations {
            let snapshot = BindingResolutionSnapshot(
                keyBindings: [.init(configID: "destination", target: .windowAction(final)), .init(configID: "source", target: target)],
                gestureBindings: [.init(configID: "destination", target: .windowAction(final)), .init(configID: "source", target: target)],
                radialMenuBindings: [.init(configID: "destination", target: .windowAction(final)), .init(configID: "source", target: target)]
            )
            try snapshot.validate()
            for source in [ActionTarget.reference(.init(.key, "source")), .reference(.init(.gesture, "source")), .reference(.init(.radialMenu, "source"))] {
                #expect(try snapshot.resolve(source).direction == .maximize)
            }
        }
    }

    @Test func multiHopReferencesResolveRegardlessOfPhysicalInputsOrOrdering() throws {
        let key = KeyBinding(configID: "key", keys: [], target: .reference(.init(.gesture, "gesture")))
        let gesture = GestureBinding(kind: nil, configID: "gesture", target: .reference(.init(.radialMenu, "menu")))
        let menu = RadialMenuBinding(configID: "menu", target: .reference(.init(.key, "final")))
        let final = KeyBinding(configID: "final", keys: [], target: .windowAction(.init(.leftHalf)))
        for keys in [[key, final], [final, key]] {
            let snapshot = BindingResolutionSnapshot(keyBindings: keys, gestureBindings: [gesture], radialMenuBindings: [menu])
            try snapshot.validate()
            #expect(try snapshot.resolve(.reference(.init(.key, "key"))).direction == .leftHalf)
        }
    }

    @Test func missingReferencesPerformNoActionAndRemainReferences() throws {
        let target = ActionTarget.reference(.init(.gesture, "deleted"))
        let snapshot = BindingResolutionSnapshot(keyBindings: [.init(configID: "alias", target: target)], gestureBindings: [], radialMenuBindings: [])
        #expect(throws: BindingResolutionSnapshot.ResolutionError.missingReference(.init(.gesture, "deleted"))) { try snapshot.resolve(.reference(.init(.key, "alias"))) }
        #expect(throws: BindingResolutionSnapshot.ResolutionError.missingReference(.init(.gesture, "deleted"))) { try snapshot.terminal(of: target) }
        #expect(snapshot.action(for: target).direction == .noAction)
        try snapshot.validate() // Running no action isn't a problem in the graph.
        #expect(target == .reference(.init(.gesture, "deleted")))
    }

    @Test func cyclesThroughAllCategoriesAndCycleStepsAreDiagnosed() {
        let key = KeyBinding(configID: "key", target: .reference(.init(.gesture, "gesture")))
        let gesture = GestureBinding(configID: "gesture", target: .reference(.init(.radialMenu, "menu")))
        let menu = RadialMenuBinding(configID: "menu", target: .windowAction(.init(kind: .cycle(.init(steps: [.reference(.init(.key, "key"))])))))
        let snapshot = BindingResolutionSnapshot(keyBindings: [key], gestureBindings: [gesture], radialMenuBindings: [menu])
        #expect(throws: BindingResolutionSnapshot.ResolutionError.self) { try snapshot.validate() }
        #expect(snapshot.action(for: .reference(.init(.key, "key"))).direction == .noAction)
        let selfReference = BindingResolutionSnapshot(keyBindings: [.init(configID: "self", target: .reference(.init(.key, "self")))], gestureBindings: [], radialMenuBindings: [])
        #expect(throws: BindingResolutionSnapshot.ResolutionError.self) { try selfReference.validate() }
    }

    @Test func aRadialMenuGestureHasNoReferenceableAction() throws {
        let gesture = GestureBinding(kind: .radialMenu, configID: "radial")
        let snapshot = BindingResolutionSnapshot(keyBindings: [.init(configID: "link", target: .reference(.init(.gesture, "radial")))], gestureBindings: [gesture], radialMenuBindings: [])
        let error = BindingResolutionSnapshot.ResolutionError.radialMenuGestureReference(.init(.gesture, "radial"))
        #expect(throws: error) { try snapshot.resolve(.reference(.init(.gesture, "radial"))) }
        #expect(throws: error) { try snapshot.terminal(of: .reference(.init(.key, "link"))) }
        #expect(throws: error) { try snapshot.validate() }
        #expect(error.localizedDescription == "gesture 'radial' opens the radial menu, so it can't be referenced")
    }

    @Test func terminalFollowsReferencesWithoutResolvingCycleSteps() throws {
        let cycle = WindowAction(kind: .cycle(.init(steps: [.reference(.init(.key, "half"))])))
        let snapshot = BindingResolutionSnapshot(
            keyBindings: [.init(configID: "half", target: .windowAction(.init(.leftHalf))), .init(configID: "cycle", target: .windowAction(cycle))],
            gestureBindings: [.init(configID: "alias", target: .reference(.init(.key, "cycle")))],
            radialMenuBindings: []
        )
        let terminal = try snapshot.terminal(of: .reference(.init(.gesture, "alias")))
        #expect(terminal.holder == .init(.key, "cycle"))
        #expect(terminal.action == cycle)
        #expect(try snapshot.terminal(of: .windowAction(cycle)).holder == nil)
        #expect(throws: BindingResolutionSnapshot.ResolutionError.cycle([.init(.key, "loop"), .init(.key, "loop")])) {
            try BindingResolutionSnapshot(keyBindings: [.init(configID: "loop", target: .reference(.init(.key, "loop")))], gestureBindings: [], radialMenuBindings: [])
                .terminal(of: .reference(.init(.key, "loop")))
        }
    }

    @Test func cycleStepReferencesAreMaterialized() throws {
        let outer = WindowAction(kind: .cycle(.init(steps: [.reference(.init(.gesture, "half")), .windowAction(.init(.maximize))])))
        let snapshot = BindingResolutionSnapshot(keyBindings: [], gestureBindings: [.init(configID: "half", target: .windowAction(.init(.leftHalf)))], radialMenuBindings: [])
        try snapshot.validate()
        let cycle = try snapshot.resolve(.windowAction(outer))
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
        let outer = WindowAction(kind: .cycle(.init(steps: [.reference(.init(.gesture, "inner")), .reference(.init(.key, "alias")), .windowAction(.init(.maximize))])))
        let snapshot = BindingResolutionSnapshot(
            keyBindings: [.init(configID: "alias", target: .reference(.init(.gesture, "inner"))), .init(configID: "outer", target: .windowAction(outer))],
            gestureBindings: [.init(configID: "inner", target: .windowAction(inner))],
            radialMenuBindings: []
        )
        let resolved = snapshot.action(for: .reference(.init(.key, "outer")))
        #expect(resolved.resolvedCycleSteps?.map(\.direction) == [.noAction, .noAction, .maximize])
        #expect(snapshot.action(for: .reference(.init(.gesture, "inner"))).direction == .cycle)
        #expect(throws: BindingResolutionSnapshot.ResolutionError.nestedCycle(.init(.gesture, "inner"))) { try snapshot.validate() }
    }

    @Test func aCycleStepThatIsACycleInlineResolvesToNoActionAndIsReported() throws {
        let inline = WindowAction([.init(.leftHalf)])
        let outer = WindowAction(kind: .cycle(.init(steps: [.windowAction(inline), .windowAction(.init(.maximize))])))
        let snapshot = BindingResolutionSnapshot(keyBindings: [.init(configID: "outer", target: .windowAction(outer))], gestureBindings: [], radialMenuBindings: [])
        #expect(snapshot.action(for: .reference(.init(.key, "outer"))).resolvedCycleSteps?.map(\.direction) == [.noAction, .maximize])
        #expect(throws: BindingResolutionSnapshot.ResolutionError.nestedCycle(nil)) { try snapshot.validate() }
    }

    @Test func referencesToNonCycleBindingsAreNotNestedCycles() throws {
        let outer = WindowAction(kind: .cycle(.init(steps: [.reference(.init(.key, "half"))])))
        let snapshot = BindingResolutionSnapshot(keyBindings: [.init(configID: "half", target: .windowAction(.init(.leftHalf))), .init(configID: "outer", target: .windowAction(outer))], gestureBindings: [], radialMenuBindings: [])
        try snapshot.validate()
    }

    @Test func reverseCyclePolicyUsesPhysicalSourceRatherThanReferencedKeybind() throws {
        let destination = KeyBinding(configID: "destination", keys: [.kVK_Shift, .kVK_LeftArrow], target: .windowAction(.init([.init(.leftHalf), .init(.rightHalf)])))
        let source = KeyBinding(keys: [.kVK_RightArrow], target: .reference(.init(.key, "destination")))
        let snapshot = BindingResolutionSnapshot(keyBindings: [source, destination], gestureBindings: [], radialMenuBindings: [])
        #expect(try snapshot.resolve(source.target).direction == .cycle)
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
            keyBindings: [.init(configID: "stash", target: .windowAction(stash)), .init(configID: "alias", target: .reference(.init(.key, "stash")))],
            gestureBindings: [.init(configID: "gesture", target: .reference(.init(.key, "alias")))],
            radialMenuBindings: [.init(configID: "menu", target: .reference(.init(.gesture, "gesture")))]
        )
        for target in [ActionTarget.reference(.init(.key, "stash")), .reference(.init(.key, "alias")), .reference(.init(.gesture, "gesture")), .reference(.init(.radialMenu, "menu"))] {
            #expect(try snapshot.resolve(target).id == snapshot.resolve(.reference(.init(.key, "stash"))).id)
        }
    }

    @Test func cycleProgressContinuesAcrossInvocationCategories() throws {
        let cycle = WindowAction([.init(.leftHalf), .init(.rightHalf)])
        let snapshot = BindingResolutionSnapshot(
            keyBindings: [.init(configID: "cycle", target: .windowAction(cycle))],
            gestureBindings: [.init(configID: "gesture", target: .reference(.init(.key, "cycle")))],
            radialMenuBindings: [.init(configID: "menu", target: .reference(.init(.gesture, "gesture")))]
        )
        var coordinator = CycleActionCoordinator()
        var current = WindowAction(.noSelection)
        var parent: WindowAction?
        var directions: [WindowDirection] = []
        for target in [ActionTarget.reference(.init(.key, "cycle")), .reference(.init(.gesture, "gesture")), .reference(.init(.radialMenu, "menu"))] {
            let action = try snapshot.resolve(target)
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
