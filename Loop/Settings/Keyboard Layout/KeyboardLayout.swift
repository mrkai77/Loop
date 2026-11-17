//
//  KeyboardLayout.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-16.
//

import Carbon
import Cocoa
import Foundation
import Scribe

/// Tests use a fake source.
protocol KeyLayoutSource: AnyObject, Sendable {
    /// Without layout data, a hardcoded US set is used.
    var hasLayoutData: Bool { get }
    /// Unshifted, without dead keys, reduced to its first UTF-16 unit.
    func character(forKeyCode code: CGKeyCode) -> String?
}

struct KeyLayoutTable: Sendable {
    let codesByName: [String: CGKeyCode]
    let namesByCode: [CGKeyCode: String]

    /// Fixed names are added last, so they win any clash.
    init(source: any KeyLayoutSource) {
        var pairs: [(code: CGKeyCode, name: String)] = []
        if source.hasLayoutData {
            for (code, _) in KeyNames.layoutDependentKeys {
                // macOS 12 started including key codes 93 and 94 in the layout data
                guard code != 93, code != 94, let character = source.character(forKeyCode: code) else { continue }
                pairs.append((code, character))
            }
        } else {
            pairs = KeyNames.fallbackCharacters
        }
        pairs += KeyNames.fixedPairs
        self.codesByName = Dictionary(pairs.map { ($0.name, $0.code) }, uniquingKeysWith: { _, last in last })
        self.namesByCode = Dictionary(pairs.map { ($0.code, $0.name) }, uniquingKeysWith: { _, last in last })
    }
}

/// Rebuilds its map whenever the input source changes.
@Loggable
final class KeyboardLayout: @unchecked Sendable {
    /// Tests override it with ``withLayout(_:operation:)``.
    static var shared: KeyboardLayout { override ?? live }
    private static let live: KeyboardLayout = {
        let source = LiveKeyLayoutSource.make()
        let layout = KeyboardLayout(source: source)
        source.onChange = { [weak layout] in layout?.invalidate() }
        return layout
    }()

    @TaskLocal private static var override: KeyboardLayout?

    static func withLayout<T>(_ layout: KeyboardLayout, operation: () throws -> T) rethrows -> T {
        try $override.withValue(layout, operation: operation)
    }

    /// Posted on the main queue.
    static let didChange = Notification.Name("KeyboardLayout.didChange")

    private let source: any KeyLayoutSource
    private let lock = NSLock()
    private var cachedTable: KeyLayoutTable?

    init(source: any KeyLayoutSource) {
        self.source = source
    }

    private var table: KeyLayoutTable {
        lock.lock()
        defer { lock.unlock() }
        if let cachedTable { return cachedTable }
        let built = KeyLayoutTable(source: source)
        cachedTable = built
        return built
    }

    func invalidate() {
        lock.lock()
        cachedTable = nil
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: self) }
    }

    /// Tries `#<code>`, then the active map, then the fallback names.
    func keyCode(forName name: String) -> CGKeyCode? {
        let name = name.lowercased()
        if let raw = KeyNames.rawCode(for: name) { return raw }
        if let code = table.codesByName[name] { return code }
        if let code = KeyNames.fallbackCode(for: name) {
            log.warn("Key '\(name)' not found in the active layout; using its fallback key")
            return code
        }
        return nil
    }

    /// Like ``keyCode(forName:)``, without logging.
    func resolves(_ name: String) -> Bool {
        let name = name.lowercased()
        return KeyNames.rawCode(for: name) != nil || table.codesByName[name] != nil || KeyNames.fallbackCode(for: name) != nil
    }

    /// Falls back to `#<code>`, so it is never empty.
    func name(forKeyCode code: CGKeyCode) -> String {
        if let name = table.namesByCode[code] { return name }
        if let name = KeyNames.fallbackName(for: code) { return name }
        return KeyNames.rawName(for: code)
    }

    func keyCodes(for names: Set<String>) -> Set<CGKeyCode>? {
        var codes: Set<CGKeyCode> = []
        for name in names {
            guard let code = keyCode(forName: name) else { return nil }
            codes.insert(code)
        }
        return codes
    }
}

/// Text Input Sources must be used on the main thread, so the layout data is copied there and read from any thread.
final class LiveKeyLayoutSource: KeyLayoutSource, @unchecked Sendable {
    private let lock = NSLock()
    private var layoutData: Data?
    private var observer: (any NSObjectProtocol)?
    var onChange: (() -> ())?

    static func make() -> LiveKeyLayoutSource {
        let source = LiveKeyLayoutSource()
        source.start()
        return source
    }

    private func start() {
        if Thread.isMainThread { refresh() } else { DispatchQueue.main.async { [self] in refresh(); onChange?() } }
        observer = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
            self?.onChange?()
        }
    }

    /// Must run on the main thread.
    private func refresh() {
        // `TISCopyCurrentKeyboardInputSource` can return NULL.
        let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        let data = source
            .flatMap { TISGetInputSourceProperty($0, kTISPropertyUnicodeKeyLayoutData) }
            .map { Unmanaged<CFData>.fromOpaque($0).takeUnretainedValue() as Data }
        lock.lock()
        layoutData = data
        lock.unlock()
    }

    var hasLayoutData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return layoutData != nil
    }

    /// Big thanks to https://github.com/sindresorhus/KeyboardShortcuts/
    func character(forKeyCode code: CGKeyCode) -> String? {
        lock.lock()
        let data = layoutData
        lock.unlock()
        guard let data else { return nil }
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout,
                UInt16(code),
                UInt16(kUCKeyActionDown),
                0, // no modifiers
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: [characters[0]], count: 1)
    }
}
