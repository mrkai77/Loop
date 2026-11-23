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
    private let maximize = WindowAction(.maximize, keybind: [.kVK_Return])
    private let swipe = GestureBinding(kind: .swipeUp, action: .singleAction(.custom(WindowAction(.topHalf))))
    private let radialGesture = GestureBinding(kind: .radialMenu, action: .radialMenuActions)
    private let slot = RadialMenuAction.custom(WindowAction(.bottomHalf))

    private func resolver(keybinds: [WindowAction] = [], gestures: [GestureBinding] = [], radialMenuActions: [RadialMenuAction] = []) -> BindingLinkResolver {
        BindingLinkResolver(keybinds: keybinds, gestures: gestures, radialMenuActions: radialMenuActions)
    }

    private func keybind(linkingTo link: BindingLink, keys: Set<CGKeyCode> = [.kVK_ANSI_L]) -> WindowAction {
        var keybind = WindowAction(.noAction, keybind: keys)
        keybind.link = link
        return keybind
    }

    @Test func linksOfEveryKindResolveToTheirAction() {
        let resolver = resolver(keybinds: [maximize], gestures: [swipe], radialMenuActions: [slot])

        #expect(resolver.action(for: BindingLink(.keybind, id: maximize.id))?.direction == .maximize)
        #expect(resolver.action(for: BindingLink(.gesture, id: swipe.id))?.direction == .topHalf)
        #expect(resolver.action(for: BindingLink(.radialMenu, id: slot.id))?.direction == .bottomHalf)
    }

    @Test func chainsResolveToTheBindingThatHoldsTheAction() {
        let toGesture = keybind(linkingTo: BindingLink(.gesture, id: swipe.id))
        let toKeybind = RadialMenuAction.keybindReference(toGesture.id)
        let resolver = resolver(keybinds: [toGesture], gestures: [swipe], radialMenuActions: [toKeybind])

        let terminal = resolver.terminal(of: BindingLink(.radialMenu, id: toKeybind.id))
        #expect(terminal?.link == BindingLink(.gesture, id: swipe.id))
        #expect(terminal?.action.direction == .topHalf)
    }

    @Test func removedBindingsAndRadialMenuGesturesResolveToNothing() {
        let resolver = resolver(gestures: [radialGesture])

        #expect(resolver.action(for: BindingLink(.keybind, id: UUID())) == nil)
        #expect(resolver.action(for: BindingLink(.gesture, id: radialGesture.id)) == nil)
        #expect(!resolver.canBeLinked(BindingLink(.gesture, id: radialGesture.id)))
    }

    @Test func linksThatLoopResolveToNothingAndCantBeMade() {
        let first = WindowAction(.noAction)
        var second = keybind(linkingTo: BindingLink(.keybind, id: first.id))
        var looped = first
        looped.link = BindingLink(.keybind, id: second.id)
        let resolver = resolver(keybinds: [looped, second])

        #expect(resolver.action(for: BindingLink(.keybind, id: looped.id)) == nil)

        second.link = nil
        let fixed = self.resolver(keybinds: [first, second, maximize])
        let firstLink = BindingLink(.keybind, id: first.id)
        #expect(fixed.wouldLoop(linking: firstLink, to: firstLink))
        #expect(!fixed.wouldLoop(linking: firstLink, to: BindingLink(.keybind, id: maximize.id)))

        let backToFirst = self.resolver(keybinds: [first, keybind(linkingTo: firstLink), maximize])
        #expect(backToFirst.wouldLoop(linking: firstLink, to: BindingLink(.keybind, id: backToFirst.keybinds[1].id)))
    }

    @Test func linkedKeybindsKeepTheirOwnKeys() {
        let linked = keybind(linkingTo: BindingLink(.gesture, id: swipe.id), keys: [.kVK_ANSI_K])
        let resolved = linked.resolvingLink(with: resolver(gestures: [swipe]))

        #expect(resolved.direction == .topHalf)
        #expect(resolved.keybind == [.kVK_ANSI_K])
        #expect(WindowAction(.center).resolvingLink(with: resolver()).direction == .center)
    }

    @Test func unlinkingKeepsTheActionAsABindingOfItsOwn() {
        let cycle = WindowAction("Halves", cycle: [WindowAction(.leftHalf), WindowAction(.rightHalf)], keybind: [.kVK_ANSI_H])
        let ownID = UUID()
        let copy = cycle.detached(id: ownID, keybind: [.kVK_ANSI_J])

        #expect(copy.id == ownID)
        #expect(copy.keybind == [.kVK_ANSI_J])
        #expect(copy.link == nil)
        #expect(copy.name == "Halves")
        #expect(copy.cycle?.map(\.direction) == [.leftHalf, .rightHalf])
        let copiedStepIDs = Set((copy.cycle ?? []).map(\.id))
        #expect(copiedStepIDs.isDisjoint(with: (cycle.cycle ?? []).map(\.id)))
    }

    @Test func savedSettingsFromBeforeLinksStillRead() throws {
        let keybindID = UUID()
        let saved = #"{ "id" : "\#(UUID().uuidString)", "type" : { "keybindReference" : { "_0" : "\#(keybindID.uuidString)" } } }"#
        let decoded = try JSONDecoder().decode(RadialMenuAction.self, from: Data(saved.utf8))
        #expect(decoded.type.link == BindingLink(.keybind, id: keybindID))

        let oldKeybind = try JSONEncoder().encode(WindowAction(.maximize))
        #expect(try JSONDecoder().decode(WindowAction.self, from: oldKeybind).link == nil)
    }

    @Test func linksRoundTripThroughSettings() throws {
        let gestureLink = RadialMenuAction.link(BindingLink(.gesture, id: swipe.id))
        let decoded = try JSONDecoder().decode(RadialMenuAction.self, from: JSONEncoder().encode(gestureLink))
        #expect(decoded.type.link == BindingLink(.gesture, id: swipe.id))

        let linked = keybind(linkingTo: BindingLink(.radialMenu, id: slot.id))
        #expect(try JSONDecoder().decode(WindowAction.self, from: JSONEncoder().encode(linked)).link == linked.link)
    }

    @Test func olderVersionsReadNewLinksAsDoingNothing() throws {
        let encoded = try JSONEncoder().encode(RadialMenuAction.link(BindingLink(.gesture, id: swipe.id)))
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let type = try #require(object["type"] as? [String: Any])
        let custom = try #require((type["custom"] as? [String: Any])?["_0"] as? [String: Any])

        #expect(Set(type.keys) == ["custom"])
        #expect(custom["direction"] as? String == WindowDirection.noAction.rawValue)
    }

    @Test @MainActor func theCLIShowsLinksBetweenEveryKind() {
        let toGesture = keybind(linkingTo: BindingLink(.gesture, id: swipe.id))
        let catalog = LoopAutomationCatalog(
            keybinds: [toGesture],
            radialMenuActions: [.keybindReference(toGesture.id), .link(BindingLink(.gesture, id: UUID()))],
            gestures: [swipe]
        )

        let keybind = catalog.keyBindings[0]
        #expect(keybind.id == "link")
        #expect(keybind.linkedTarget == .binding(.gesture, id: "top-half"))
        #expect(keybind.action?.direction == .topHalf)

        let radial = catalog.radialMenuBindings
        #expect(radial[0].linkedTarget == .binding(.keybind, id: "link"))
        #expect(radial[0].action?.direction == .topHalf)
        #expect(radial[1].note == "Links to a gesture that was removed")
    }
}
