//
//  WindowActionCacheTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import CoreGraphics
import Foundation
@testable import Loop
import Testing
import Tome

extension StoreTests {
    struct WindowActionCacheTests {
        @Test func buildsInitialSnapshotAndRebuildsAfterSettingsChange() async throws {
            let settings = try Profile()
            let leftKey = CGKeyCode.kVK_LeftArrow
            let rightKey = CGKeyCode.kVK_RightArrow
            let initial = KeyBinding(.leftHalf, keybind: [.kVK_LeftArrow])
                .withConfigurationID("cache-test")
            try settings.set([initial], for: \.keyBindings)

            let initialPersistedBinding = try #require(settings[\.keyBindings].first)
            let cache = WindowActionCache(layout: FakeLayouts.layout(FakeLayouts.us).0)
            let initialAction = try #require(cache.actionsByKeybind[[leftKey]])
            #expect(initialAction.direction == .leftHalf)
            #expect(initialAction.semanticKey == directAction(in: initial.target)?.semanticKey)
            #expect(cache.keyBinding(for: initialAction)?.id == initialPersistedBinding.id)
            #expect(cache.keyBinding(for: initialAction)?.keys == [.kVK_LeftArrow])

            var updated = initialPersistedBinding
            updated.keys = [.kVK_RightArrow]
            updated.target = .windowAction(.init(.rightHalf))
            try settings.set([updated], for: \.keyBindings)

            for _ in 0 ..< 80 {
                if cache.actionsByKeybind[[rightKey]]?.direction == .rightHalf { break }
                try await Task.sleep(for: .milliseconds(10))
            }

            #expect(cache.actionsByKeybind[[leftKey]] == nil)
            let updatedPersistedBinding = try #require(settings[\.keyBindings].first)
            let updatedAction = try #require(cache.actionsByKeybind[[rightKey]])
            #expect(updatedAction.direction == .rightHalf)
            #expect(updatedAction.semanticKey == directAction(in: updated.target)?.semanticKey)
            #expect(cache.keyBinding(for: updatedAction)?.id == updatedPersistedBinding.id)
            #expect(cache.keyBinding(for: updatedAction)?.keys == [.kVK_RightArrow])
            #expect(updatedPersistedBinding.id == initialPersistedBinding.id)
        }

        @Test func rebuildsAcrossReferenceCollectionsAndReportsAnInvalidGraph() async throws {
            let settings = try Profile()
            let url = settings.url
            let binding = KeyBinding(configID: "key", keys: [.kVK_LeftArrow], target: .gestureBinding("gesture"))
            try settings.set([binding], for: \.keyBindings)
            try settings.set([GestureBinding(configID: "gesture", target: .radialMenuBinding("menu"))], for: \.gestures)
            try settings.set([RadialMenuBinding(configID: "menu", target: .windowAction(.init(.leftHalf)))], for: \.radialMenuActions)
            let cache = WindowActionCache(layout: FakeLayouts.layout(FakeLayouts.us).0)
            #expect(cache.actionsByKeybind[[.kVK_LeftArrow]]?.direction == .leftHalf)

            try settings.set([RadialMenuBinding(configID: "menu", target: .windowAction(.init(.rightHalf)))], for: \.radialMenuActions)
            for _ in 0 ..< 80 {
                if cache.actionsByKeybind[[.kVK_LeftArrow]]?.direction == .rightHalf { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(cache.actionsByKeybind[[.kVK_LeftArrow]]?.direction == .rightHalf)

            try settings.flush()
            try """
            [[key.bindings]]
            id = "key"
            keys = "left"
            action = "key:key"
            [[gestures.bindings]]
            id = "gesture"
            fingers = 3
            action = "maximize"
            [[radial-menu.bindings]]
            id = "menu"
            action = "maximize"
            """.write(to: url, atomically: true, encoding: .utf8)
            try settings.reload()
            for _ in 0 ..< 80 {
                if cache.graphIssue != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(cache.actionsByKeybind[[.kVK_LeftArrow]]?.direction == .noAction)
            let gestureID = try #require(settings[\.gestures].first?.id)
            let menuID = try #require(settings[\.radialMenuActions].first?.id)
            #expect(cache.resolve(gestureID: gestureID)?.direction == .maximize)
            #expect(cache.resolve(radialMenuBindingID: menuID)?.direction == .maximize)
            #expect(cache.graphIssue != nil)
        }

        @Test func aReferenceCycleOnlyDisablesItsOwnBindingsAndShowsAsAnIssue() async throws {
            let settings = try Profile()
            try settings.set([
                KeyBinding(configID: "a", keys: KeyCombination(names: ["a"]), target: .keyBinding("b")),
                KeyBinding(configID: "b", keys: KeyCombination(names: ["b"]), target: .keyBinding("a")),
                KeyBinding(.leftHalf, keybind: [.kVK_LeftArrow])
            ], for: \.keyBindings)
            let cache = WindowActionCache(layout: FakeLayouts.layout(FakeLayouts.us).0)
            #expect(cache.graphIssue != nil)
            #expect(cache.actionsByKeybind[[.kVK_LeftArrow]]?.direction == .leftHalf)
            #expect(cache.actionsByKeybind[[.kVK_ANSI_A]]?.direction == .noAction)
            #expect(settings.issues.isEmpty)

            try settings.set([KeyBinding(configID: "a", keys: KeyCombination(names: ["a"]), target: .windowAction(.init(.maximize)))], for: \.keyBindings)
            for _ in 0 ..< 80 {
                if cache.graphIssue == nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(cache.graphIssue == nil)
        }

        @Test func anUnresolvedKeyNameIsInactiveAndReportedInTheBanner() throws {
            let settings = try Profile()
            try settings.set([
                KeyBinding(.leftHalf, keybind: [.kVK_LeftArrow]),
                KeyBinding(.rightHalf, keybind: KeyCombination(names: ["ф"]))
            ], for: \.keyBindings)
            let cache = WindowActionCache(layout: FakeLayouts.layout(FakeLayouts.us).0)
            #expect(cache.actionsByKeybind[[.kVK_LeftArrow]]?.direction == .leftHalf)
            #expect(cache.actionsByKeybind.count == 1)
            #expect(cache.issues.map(\.path) == ["key.bindings"])
        }

        @Test func bindingsAreResolvedAgainWhenTheInputSourceChanges() async throws {
            let settings = try Profile()
            try settings.set([KeyBinding(.leftHalf, keybind: KeyCombination(names: ["z"]))], for: \.keyBindings)
            let (layout, source) = FakeLayouts.layout(FakeLayouts.us)
            let cache = WindowActionCache(layout: layout)
            #expect(cache.actionsByKeybind[[.kVK_ANSI_Z]]?.direction == .leftHalf)

            source.switchTo(FakeLayouts.german)
            layout.invalidate()
            for _ in 0 ..< 80 {
                if cache.actionsByKeybind[[.kVK_ANSI_Y]] != nil { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(cache.actionsByKeybind[[.kVK_ANSI_Y]]?.direction == .leftHalf)
            #expect(cache.actionsByKeybind[[.kVK_ANSI_Z]] == nil)
        }

        @Test func aReferencedActionBelongsToTheKeybindThatDefinesIt() throws {
            let settings = try Profile()
            let defining = KeyBinding(configID: "defining", keys: [.kVK_LeftArrow], target: .windowAction(.init(.leftHalf)))
            let referencing = KeyBinding(configID: "referencing", keys: [.kVK_RightArrow], target: .keyBinding("defining"))
            try settings.set([referencing, defining], for: \.keyBindings)
            let cache = WindowActionCache(layout: FakeLayouts.layout(FakeLayouts.us).0)
            let action = try #require(cache.actionsByKeybind[[.kVK_RightArrow]])
            #expect(action.id == cache.actionsByKeybind[[.kVK_LeftArrow]]?.id)
            #expect(cache.keyBinding(for: action)?.keys == [.kVK_LeftArrow])
        }
    }
}

private func directAction(in target: ActionTarget) -> WindowAction? {
    if case let .windowAction(action) = target { action } else { nil }
}
