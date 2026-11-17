//
//  KeyNames.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import CoreGraphics
import Foundation
import TOML

/// Persisted key names: the character a key types (`"a"`, `"]"`), a fixed name, or `#<keycode>`.
enum KeyNames {
    // MARK: Fixed names

    /// These win any clash with a layout character.
    static let fixedPairs: [(code: CGKeyCode, name: String)] = [
        (.kVK_F1, "f1"), (.kVK_F2, "f2"), (.kVK_F3, "f3"), (.kVK_F4, "f4"), (.kVK_F5, "f5"),
        (.kVK_F6, "f6"), (.kVK_F7, "f7"), (.kVK_F8, "f8"), (.kVK_F9, "f9"), (.kVK_F10, "f10"),
        (.kVK_F11, "f11"), (.kVK_F12, "f12"), (.kVK_F13, "f13"), (.kVK_F14, "f14"), (.kVK_F15, "f15"),
        (.kVK_F16, "f16"), (.kVK_F17, "f17"), (.kVK_F18, "f18"), (.kVK_F19, "f19"), (.kVK_F20, "f20"),

        (.kVK_ANSI_KeypadDecimal, "pad."), (.kVK_ANSI_KeypadMultiply, "pad*"), (.kVK_ANSI_KeypadPlus, "pad+"),
        (.kVK_ANSI_KeypadDivide, "pad/"), (.kVK_ANSI_KeypadMinus, "pad-"), (.kVK_ANSI_KeypadEquals, "pad="),
        (.kVK_ANSI_Keypad0, "pad0"), (.kVK_ANSI_Keypad1, "pad1"), (.kVK_ANSI_Keypad2, "pad2"),
        (.kVK_ANSI_Keypad3, "pad3"), (.kVK_ANSI_Keypad4, "pad4"), (.kVK_ANSI_Keypad5, "pad5"),
        (.kVK_ANSI_Keypad6, "pad6"), (.kVK_ANSI_Keypad7, "pad7"), (.kVK_ANSI_Keypad8, "pad8"),
        (.kVK_ANSI_Keypad9, "pad9"), (.kVK_ANSI_KeypadClear, "pad-clear"), (.kVK_ANSI_KeypadEnter, "pad-enter"),

        (.kVK_Return, "return"), (.kVK_Tab, "tab"), (.kVK_Space, "space"), (.kVK_Delete, "delete"),
        (.kVK_Escape, "escape"), (.kVK_Help, "help"), (.kVK_Home, "home"), (.kVK_PageUp, "page-up"),
        (.kVK_ForwardDelete, "forward-delete"), (.kVK_End, "end"), (.kVK_PageDown, "page-down"),
        (.kVK_LeftArrow, "left"), (.kVK_RightArrow, "right"), (.kVK_DownArrow, "down"), (.kVK_UpArrow, "up"),

        (.kVK_Command, "cmd"), (.kVK_RightCommand, "right-cmd"), (.kVK_Shift, "shift"), (.kVK_CapsLock, "caps-lock"),
        (.kVK_Option, "alt"), (.kVK_Control, "ctrl"), (.kVK_RightShift, "right-shift"),
        (.kVK_RightOption, "right-alt"), (.kVK_RightControl, "right-ctrl"), (.kVK_Function, "fn"),

        (.kVK_JIS_Yen, "yen"), (.kVK_JIS_Underscore, "underscore"), (.kVK_JIS_KeypadComma, "pad,"),
        (.kVK_JIS_Eisu, "eisu"), (.kVK_JIS_Kana, "kana")
    ]

    private static let fixedCodesByName: [String: CGKeyCode] = Dictionary(fixedPairs.map { ($0.name, $0.code) }, uniquingKeysWith: { _, last in last })
    private static let fixedNamesByCode: [CGKeyCode: String] = Dictionary(fixedPairs.map { ($0.code, $0.name) }, uniquingKeysWith: { _, last in last })

    static func fixedCode(for name: String) -> CGKeyCode? { fixedCodesByName[name] }

    static func fixedName(for code: CGKeyCode) -> String? { fixedNamesByCode[code] }

    // MARK: Layout-dependent keys

    /// The US character of each key is its fallback name, for layouts that lack it or have no layout data.
    static let layoutDependentKeys: [(code: CGKeyCode, fallbackName: String?)] = [
        (.kVK_ANSI_A, "a"), (.kVK_ANSI_B, "b"), (.kVK_ANSI_C, "c"), (.kVK_ANSI_D, "d"), (.kVK_ANSI_E, "e"), (.kVK_ANSI_F, "f"),
        (.kVK_ANSI_G, "g"), (.kVK_ANSI_H, "h"), (.kVK_ANSI_I, "i"), (.kVK_ANSI_J, "j"), (.kVK_ANSI_K, "k"), (.kVK_ANSI_L, "l"),
        (.kVK_ANSI_M, "m"), (.kVK_ANSI_N, "n"), (.kVK_ANSI_O, "o"), (.kVK_ANSI_P, "p"), (.kVK_ANSI_Q, "q"), (.kVK_ANSI_R, "r"),
        (.kVK_ANSI_S, "s"), (.kVK_ANSI_T, "t"), (.kVK_ANSI_U, "u"), (.kVK_ANSI_V, "v"), (.kVK_ANSI_W, "w"), (.kVK_ANSI_X, "x"),
        (.kVK_ANSI_Y, "y"), (.kVK_ANSI_Z, "z"), (.kVK_ANSI_0, "0"), (.kVK_ANSI_1, "1"), (.kVK_ANSI_2, "2"), (.kVK_ANSI_3, "3"),
        (.kVK_ANSI_4, "4"), (.kVK_ANSI_5, "5"), (.kVK_ANSI_6, "6"), (.kVK_ANSI_7, "7"), (.kVK_ANSI_8, "8"), (.kVK_ANSI_9, "9"),
        (.kVK_ANSI_Grave, "`"), (.kVK_ANSI_Equal, "="), (.kVK_ANSI_Minus, "-"), (.kVK_ANSI_RightBracket, "]"),
        (.kVK_ANSI_LeftBracket, "["), (.kVK_ANSI_Quote, "'"), (.kVK_ANSI_Semicolon, ";"), (.kVK_ANSI_Backslash, "\\"),
        (.kVK_ANSI_Comma, ","), (.kVK_ANSI_Slash, "/"), (.kVK_ANSI_Period, "."), (.kVK_ISO_Section, "§"),
        (.kVK_JIS_Yen, nil), (.kVK_JIS_Underscore, nil), (.kVK_JIS_KeypadComma, nil), (.kVK_JIS_Eisu, nil), (.kVK_JIS_Kana, nil)
    ]

    static let fallbackCharacters: [(code: CGKeyCode, name: String)] = layoutDependentKeys.compactMap { key in
        key.fallbackName.map { (key.code, $0) }
    }

    private static let fallbackCodesByName: [String: CGKeyCode] = Dictionary(fallbackCharacters.map { ($0.name, $0.code) }, uniquingKeysWith: { _, last in last })
    private static let fallbackNamesByCode: [CGKeyCode: String] = Dictionary(fallbackCharacters.map { ($0.code, $0.name) }, uniquingKeysWith: { _, last in last })

    static func fallbackCode(for name: String) -> CGKeyCode? { fallbackCodesByName[name] }

    static func fallbackName(for code: CGKeyCode) -> String? { fallbackNamesByCode[code] }

    // MARK: Raw key codes

    static func rawName(for code: CGKeyCode) -> String { "#\(code)" }

    static func rawCode(for name: String) -> CGKeyCode? {
        guard name.hasPrefix("#") else { return nil }
        let digits = name.dropFirst()
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber) else { return nil }
        return UInt16(digits).map { CGKeyCode($0) }
    }

    // MARK: Validation

    /// Doesn't consult the layout. Names are stored lowercased.
    static func canonical(_ input: String) throws -> String {
        let name = input.lowercased()
        if fixedCodesByName[name] != nil || rawCode(for: name) != nil { return name }
        if input.count == 1 { return name.count == 1 ? name : input }
        throw ParseError.invalidKeyName(input)
    }

    // MARK: Modifiers and ordering

    static func isModifier(_ name: String) -> Bool { fixedCode(for: name)?.isModifier == true }

    /// `right-cmd` becomes `cmd`.
    static func baseModifier(_ name: String) -> String {
        guard let code = fixedCode(for: name), let base = fixedName(for: code.baseModifier) else { return name }
        return base
    }

    static func isRightModifier(_ name: String) -> Bool { fixedCode(for: name)?.isModifierOnRightSide == true }

    static func modifierSystemImage(_ name: String) -> String? { fixedCode(for: name)?.modifierSystemImage }

    static func displayLabel(_ name: String) -> String {
        fixedCode(for: name)?.symbol ?? name
    }

    /// Modifiers by key code, then characters, then the remaining keys by key code.
    static func components(from names: Set<String>) -> [String] {
        func rank(_ name: String) -> Int {
            if isModifier(name) { 0 } else if fixedCode(for: name) == nil, rawCode(for: name) == nil { 1 } else { 2 }
        }
        func code(_ name: String) -> CGKeyCode { fixedCode(for: name) ?? rawCode(for: name) ?? 0 }
        return names.sorted { lhs, rhs in
            let (left, right) = (rank(lhs), rank(rhs))
            if left != right { return left < right }
            return left == 1 ? lhs < rhs : code(lhs) < code(rhs)
        }
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case invalidKeyName(String)

        var errorDescription: String? {
            switch self {
            case let .invalidKeyName(name): "Unknown key name \(ConfigurationMessage.quoted(name))"
            }
        }
    }
}
