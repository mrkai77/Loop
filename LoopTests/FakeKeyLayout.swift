//
//  FakeKeyLayout.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-16.
//

import CoreGraphics
import Foundation
@testable import Loop

/// Keeps tests independent of the machine's input source.
final class FakeKeyLayoutSource: KeyLayoutSource, @unchecked Sendable {
    private let lock = NSLock()
    private var characters: [CGKeyCode: String]
    private var hasData: Bool

    init(characters: [CGKeyCode: String], hasLayoutData: Bool = true) {
        self.characters = characters
        self.hasData = hasLayoutData
    }

    var hasLayoutData: Bool { lock.withLock { hasData } }

    func character(forKeyCode code: CGKeyCode) -> String? { lock.withLock { characters[code] } }

    func switchTo(_ characters: [CGKeyCode: String], hasLayoutData: Bool = true) {
        lock.withLock {
            self.characters = characters
            self.hasData = hasLayoutData
        }
    }
}

enum FakeLayouts {
    static let us: [CGKeyCode: String] = Dictionary(KeyNames.fallbackCharacters.map { ($0.code, $0.name) }, uniquingKeysWith: { _, last in last })

    /// QWERTZ: Y and Z swap, and a few punctuation keys differ.
    static let german: [CGKeyCode: String] = us.merging([
        .kVK_ANSI_Y: "z", .kVK_ANSI_Z: "y", .kVK_ANSI_Minus: "ß", .kVK_ANSI_RightBracket: "+", .kVK_ANSI_Slash: "-"
    ]) { _, new in new }

    static let russian: [CGKeyCode: String] = us.merging([
        .kVK_ANSI_A: "ф", .kVK_ANSI_S: "ы", .kVK_ANSI_Z: "я", .kVK_ANSI_Q: "й", .kVK_ANSI_Y: "н"
    ]) { _, new in new }

    static func layout(_ characters: [CGKeyCode: String]) -> (KeyboardLayout, FakeKeyLayoutSource) {
        let source = FakeKeyLayoutSource(characters: characters)
        return (KeyboardLayout(source: source), source)
    }
}
