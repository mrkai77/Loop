//
//  WorkspaceHotKeys.swift
//  Loop
//
//  Created on 2026-10-20.
//

import Carbon.HIToolbox
import Scribe
import SwiftUI

/// 'LOWS', identifies our hot keys in the shared Carbon event stream.
/// Kept outside the class so the C callback can read it without hopping to the main actor.
private let workspaceHotKeySignature: OSType = 0x4C_4F_57_53

/// Registers ⌃⌥⌘1 to ⌃⌥⌘9 for workspaces and ⌃⌥⌘0 for restoring the display layout.
///
/// Carbon hot keys are used because they don't require any extra permission and don't
/// interfere with Loop's own event taps.
@Loggable
@MainActor
final class WorkspaceHotKeys {
    static let modifiers = UInt32(cmdKey | optionKey | controlKey)
    static let restoreLayoutHotKeyID: UInt32 = 0

    /// Indexed by hot key ID: 0 restores the display layout, 1-9 apply workspaces.
    private static let keyCodes: [Int] = [
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
    ]

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private let onPress: (UInt32) -> ()

    init(onPress: @escaping (UInt32) -> ()) {
        self.onPress = onPress
    }

    static func displayString(for id: UInt32) -> String {
        "⌃⌥⌘\(id)"
    }

    func register() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr, hotKeyID.signature == workspaceHotKeySignature else {
                    return OSStatus(eventNotHandledErr)
                }

                let hotKeys = Unmanaged<WorkspaceHotKeys>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                Task { @MainActor in
                    hotKeys.onPress(id)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        guard status == noErr else {
            log.error("Failed to install hot key handler: \(status)")
            return
        }

        for (id, keyCode) in Self.keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(
                UInt32(keyCode),
                Self.modifiers,
                EventHotKeyID(signature: workspaceHotKeySignature, id: UInt32(id)),
                GetApplicationEventTarget(),
                0,
                &ref
            )

            if result == noErr, let ref {
                hotKeyRefs.append(ref)
            } else {
                log.warn("Failed to register \(Self.displayString(for: UInt32(id))), it may be used by another app")
            }
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
