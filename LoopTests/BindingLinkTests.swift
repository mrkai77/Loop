//
//  BindingLinkTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-22.
//

import CoreGraphics
import Foundation
@testable import Loop
import Testing

struct BindingLinkTests {
    private let maximize = Keybind(keys: [.kVK_Return], target: .action(WindowAction(.maximize)))
    private let swipe = GestureBinding(kind: .swipeUp, action: .singleAction(.action(WindowAction(.topHalf))))
    private let radialGesture = GestureBinding(kind: .radialMenu, action: .radialMenuActions)
    private let slot = RadialMenuBinding(target: .action(WindowAction(.bottomHalf)))

    private func resolver(keybinds: [Keybind] = [], gestures: [GestureBinding] = [], radialMenuActions: [RadialMenuBinding] = []) -> BindingLinkResolver {
        BindingLinkResolver(keybinds: keybinds, gestures: gestures, radialMenuActions: radialMenuActions)
    }

    private func keybind(linkingTo link: BindingLink, keys: Set<CGKeyCode> = [.kVK_ANSI_L]) -> Keybind {
        Keybind(keys: keys, target: .link(link))
    }

    private func link<Binding: ActionBinding>(to binding: Binding) -> BindingLink {
        BindingLink(Binding.bindingKind, id: binding.id.uuidString)
    }

    @Test func linksFindBindingsByTheirConfigID() {
        var named = swipe
        named.configID = "swipe-up"
        let resolver = resolver(gestures: [named])

        #expect(resolver.resolvedAction(for: BindingLink(.gesture, id: "swipe-up"))?.direction == .topHalf)
        #expect(resolver.identity(of: BindingLink(.gesture, id: "swipe-up")) == named.identity)
        #expect(resolver.resolvedAction(for: BindingLink(.keybind, id: "swipe-up")) == nil)
    }

    @Test func chainsResolveToTheBindingThatHoldsTheAction() {
        let toGesture = keybind(linkingTo: link(to: swipe))
        let toKeybind = RadialMenuBinding(target: .link(link(to: toGesture)))
        let resolver = resolver(keybinds: [toGesture], gestures: [swipe], radialMenuActions: [toKeybind])

        let terminal = resolver.terminal(of: link(to: toKeybind))
        #expect(terminal?.identity == swipe.identity)
        #expect(terminal?.action.direction == .topHalf)

        // The radial menu highlights the slot for an action from anywhere along its chain
        for action in [swipe.resolvedAction(with: resolver), toGesture.resolvedAction(with: resolver)] {
            #expect(action.map { toKeybind.runs($0, with: resolver) } == true)
        }
    }

    @Test func removedBindingsAndRadialMenuGesturesResolveToNothing() {
        let resolver = resolver(gestures: [radialGesture])

        #expect(resolver.resolvedAction(for: BindingLink(.keybind, id: UUID().uuidString)) == nil)
        #expect(resolver.resolvedAction(for: link(to: radialGesture)) == nil)
        #expect(!resolver.canBeLinked(radialGesture.identity))
    }

    @Test func linksThatLoopResolveToNothingAndCantBeMade() {
        let first = Keybind(target: .action(WindowAction(.noAction)))
        let second = keybind(linkingTo: link(to: first))
        let looped = Keybind(id: first.id, target: .link(link(to: second)))
        #expect(resolver(keybinds: [looped, second]).resolvedAction(for: link(to: looped)) == nil)

        let unlinked = Keybind(target: .action(WindowAction(.center)))
        let fixed = resolver(keybinds: [first, unlinked, maximize])
        #expect(fixed.wouldLoop(linking: first.identity, to: first.identity))
        #expect(!fixed.wouldLoop(linking: first.identity, to: maximize.identity))

        let backToFirst = resolver(keybinds: [first, second, maximize])
        #expect(backToFirst.wouldLoop(linking: first.identity, to: second.identity))
    }

    @Test func aKeybindsActionSharesItsID() {
        var keybind = Keybind(target: .action(WindowAction(.center)))
        keybind.target = .action(WindowAction(.maximize))

        #expect(keybind.target.action?.id == keybind.id)
    }

    @Test func slotsRunWhatTheBindingTheyLinkToRan() {
        let linkedSlot = RadialMenuBinding(target: .link(link(to: maximize)))
        let resolver = resolver(keybinds: [maximize], radialMenuActions: [linkedSlot, slot])
        let fromKeybind = maximize.resolvedAction(with: resolver)
        let fromSlot = linkedSlot.resolvedAction(with: resolver)

        #expect(fromSlot?.id == linkedSlot.id)
        #expect(fromKeybind.map { linkedSlot.runs($0, with: resolver) } == true)
        #expect(fromSlot.map { linkedSlot.runs($0, with: resolver) } == true)
        #expect(fromKeybind.map { slot.runs($0, with: resolver) } == false)
    }

    @Test func keybindsLinkingNowhereRunNothingUnderTheirOwnID() {
        let broken = keybind(linkingTo: BindingLink(.gesture, id: UUID().uuidString))
        let snapshot = WindowActionCache.snapshot(linkResolver: resolver(keybinds: [broken]), triggerKey: [.kVK_Function], cycleBackwardsOnShiftPressed: false)

        #expect(snapshot.actionsByKeybind[broken.keys]?.direction == .noAction)
        #expect(snapshot.actionsByKeybind[broken.keys]?.id == broken.id)
    }

    // MARK: - Cycles

    @Test func cycleStepsRunTheActionTheyLinkToUnderTheirOwnID() {
        let step = CycleStep(target: .link(link(to: swipe)))
        var cycle = WindowAction("Mixed", cycle: [WindowAction(.leftHalf)])
        cycle.cycle?.append(step)
        let resolved = resolver(gestures: [swipe]).resolvingCycle(of: cycle)

        #expect(resolved.cycleActions?.map(\.direction) == [.leftHalf, .topHalf])
        #expect(resolved.cycleActions?.last?.id == step.id)
        #expect(Keybind(target: .action(cycle)).target.editableAction(with: resolver(gestures: [swipe]))?.cycle?.last?.target.link != nil)
    }

    @Test func cycleStepsThatLeadNowhereOrToACycleAreLeftOut() {
        let halves = Keybind(target: .action(WindowAction("Halves", cycle: [WindowAction(.leftHalf)])))
        var cycle = WindowAction(cycle: [WindowAction(.center)])
        cycle.cycle? += [
            CycleStep(target: .link(link(to: halves))),
            CycleStep(target: .link(BindingLink(.gesture, id: "removed")))
        ]
        let resolver = resolver(keybinds: [halves, maximize])

        #expect(resolver.resolvingCycle(of: cycle).cycleActions?.map(\.direction) == [.center])
        #expect(!resolver.canBeLinked(fromCycle: halves.identity))
        #expect(resolver.canBeLinked(fromCycle: maximize.identity) == !WindowAction(.maximize).allowsRapidRepeat)
    }

    @Test func linkedKeybindsKeepTheirOwnKeysForCycling() {
        let cycle = Keybind(keys: [.kVK_Shift, .kVK_UpArrow], target: .action(WindowAction(.init(localized: "Top Cycle"), cycle: [.init(.topHalf), .init(.topThird)])))
        let linked = keybind(linkingTo: link(to: cycle), keys: [.kVK_ANSI_X])

        for keybinds in [[cycle, linked], [linked, cycle]] {
            let snapshot = WindowActionCache.snapshot(
                linkResolver: resolver(keybinds: keybinds),
                triggerKey: [.kVK_Function],
                cycleBackwardsOnShiftPressed: true
            )
            let linkedAction = snapshot.actionsByKeybind[[.kVK_ANSI_X]]
            let cycleAction = snapshot.actionsByKeybind[[.kVK_Shift, .kVK_UpArrow]]

            #expect(linkedAction?.direction == .cycle)
            #expect(linkedAction.flatMap { snapshot.keysByActionID[$0.id] } == [.kVK_ANSI_X])
            #expect(cycleAction.flatMap { snapshot.keysByActionID[$0.id] } == [.kVK_Shift, .kVK_UpArrow])
        }
    }

    // MARK: - Settings

    @Test func savedSettingsFromBeforeKeybindsWereSeparateStillRead() throws {
        let keybindID = UUID()
        let radial = #"{ "id" : "\#(UUID().uuidString)", "type" : { "keybindReference" : { "_0" : "\#(keybindID.uuidString)" } } }"#
        let decodedRadial = try JSONDecoder().decode(RadialMenuBinding.self, from: Data(radial.utf8))
        #expect(decodedRadial.target.link == BindingLink(.keybind, id: keybindID.uuidString))

        let keybind = #"{ "id" : "\#(keybindID.uuidString)", "direction" : "Maximize", "keybind" : [36], "bypassTriggerKey" : true }"#
        let decodedKeybind = try JSONDecoder().decode(Keybind.self, from: Data(keybind.utf8))
        #expect(decodedKeybind.id == keybindID)
        #expect(decodedKeybind.keys == [36])
        #expect(decodedKeybind.bypassTriggerKey == true)
        #expect(decodedKeybind.target.action?.direction == .maximize)
        #expect(decodedKeybind.configID == nil)
    }

    @Test func bindingsRoundTripThroughSettings() throws {
        let gestureLink = RadialMenuBinding(target: .link(BindingLink(.gesture, id: "swipe-up")))
        let decodedRadial = try JSONDecoder().decode(RadialMenuBinding.self, from: JSONEncoder().encode(gestureLink))
        #expect(decodedRadial.target.link == BindingLink(.gesture, id: "swipe-up"))

        var linked = keybind(linkingTo: BindingLink(.radialMenu, id: "bottom-half"))
        linked.configID = "my-link"
        linked.bypassTriggerKey = true
        #expect(try JSONDecoder().decode(Keybind.self, from: JSONEncoder().encode(linked)) == linked)
        #expect(try JSONDecoder().decode(Keybind.self, from: JSONEncoder().encode(maximize)) == maximize)
    }

    @Test func olderVersionsReadNewLinksAsDoingNothing() throws {
        let encoded = try JSONEncoder().encode(RadialMenuBinding(target: .link(BindingLink(.gesture, id: "swipe-up"))))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let type = try #require(object["type"] as? [String: Any])
        let custom = try #require((type["custom"] as? [String: Any])?["_0"] as? [String: Any])

        #expect(Set(type.keys) == ["custom"])
        #expect(custom["direction"] as? String == WindowDirection.noAction.rawValue)
        // Older versions require `keybind` on every action
        #expect(custom["keybind"] as? [Any] != nil)

        let keybind = try JSONEncoder().encode(keybind(linkingTo: BindingLink(.gesture, id: "swipe-up")))
        let keybindObject = try #require(JSONSerialization.jsonObject(with: keybind) as? [String: Any])
        #expect(keybindObject["direction"] as? String == WindowDirection.noAction.rawValue)
        #expect(keybindObject["keybind"] as? [Any] != nil)
    }

    @Test func linkedCycleStepsRoundTripAndReadAsDoingNothingInOlderVersions() throws {
        var cycleAction = WindowAction(cycle: [])
        cycleAction.cycle = [CycleStep(target: .link(BindingLink(.gesture, id: "swipe-up")))]
        let cycle = Keybind(keys: [.kVK_ANSI_C], target: .action(cycleAction))
        let encoded = try JSONEncoder().encode(cycle)
        #expect(try JSONDecoder().decode(Keybind.self, from: encoded) == cycle)

        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let step = try #require((object["cycle"] as? [[String: Any]])?.first)
        #expect(step["direction"] as? String == WindowDirection.noAction.rawValue)
        #expect(step["keybind"] as? [Any] != nil)
        #expect(step["link"] as? String == "gesture:swipe-up")
    }
}
