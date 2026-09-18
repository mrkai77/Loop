//
//  SystemGestureManager.swift
//  Loop
//
//  Created by Kai Azim on 2026-05-15.
//

import Defaults
import Foundation
import Scribe

enum SystemGesturePreferenceValue: Codable, Hashable, Defaults.Serializable {
    case bool(Bool)
    case int(Int)
    case missing
}

@Loggable
final class SystemGestureManager {
    private let restartDock: () -> ()
    private let activateSettings: () -> ()

    init(
        restartDock: @escaping () -> () = SystemGestureManager.restartDock,
        activateSettings: @escaping () -> () = SystemGestureManager.activateSettings
    ) {
        self.restartDock = restartDock
        self.activateSettings = activateSettings
    }

    enum BuiltInTrackpad: String {
        fileprivate static let domain = "com.apple.AppleMultitouchTrackpad"
        fileprivate static let defaults = UserDefaults(suiteName: domain)

        case threeFingerHorizontalSwipeGesture = "TrackpadThreeFingerHorizSwipeGesture"
        case fourFingerHorizontalSwipeGesture = "TrackpadFourFingerHorizSwipeGesture"
        case threeFingerVerticalSwipeGesture = "TrackpadThreeFingerVertSwipeGesture"
        case fourFingerVerticalSwipeGesture = "TrackpadFourFingerVertSwipeGesture"
        case fourFingerPinchGesture = "TrackpadFourFingerPinchGesture"
        case threeFingerDrag = "TrackpadThreeFingerDrag"
        case threeFingerTapGesture = "TrackpadThreeFingerTapGesture"

        fileprivate var identifier: SystemGesturePreferenceIdentifier {
            SystemGesturePreferenceIdentifier(domain: Self.domain, key: rawValue)
        }

        func get() -> SystemGesturePreferenceValue {
            identifier.get()
        }

        func set(_ value: SystemGesturePreferenceValue) {
            identifier.set(value)
            identifier.synchronize()
        }
    }

    enum BluetoothTrackpad: String {
        fileprivate static let domain = "com.apple.driver.AppleBluetoothMultitouch.trackpad"
        fileprivate static let defaults = UserDefaults(suiteName: domain)

        case threeFingerHorizontalSwipeGesture = "TrackpadThreeFingerHorizSwipeGesture"
        case fourFingerHorizontalSwipeGesture = "TrackpadFourFingerHorizSwipeGesture"
        case threeFingerVerticalSwipeGesture = "TrackpadThreeFingerVertSwipeGesture"
        case fourFingerVerticalSwipeGesture = "TrackpadFourFingerVertSwipeGesture"
        case fourFingerPinchGesture = "TrackpadFourFingerPinchGesture"
        case threeFingerDrag = "TrackpadThreeFingerDrag"
        case threeFingerTapGesture = "TrackpadThreeFingerTapGesture"

        fileprivate var identifier: SystemGesturePreferenceIdentifier {
            SystemGesturePreferenceIdentifier(domain: Self.domain, key: rawValue)
        }

        func get() -> SystemGesturePreferenceValue {
            identifier.get()
        }

        func set(_ value: SystemGesturePreferenceValue) {
            identifier.set(value)
            identifier.synchronize()
        }
    }

    enum CurrentHostTrackpad: String {
        fileprivate static let domain = "NSGlobalDomain.currentHost"

        case threeFingerHorizontalSwipeGesture = "com.apple.trackpad.threeFingerHorizSwipeGesture"
        case fourFingerHorizontalSwipeGesture = "com.apple.trackpad.fourFingerHorizSwipeGesture"
        case threeFingerVerticalSwipeGesture = "com.apple.trackpad.threeFingerVertSwipeGesture"
        case fourFingerVerticalSwipeGesture = "com.apple.trackpad.fourFingerVertSwipeGesture"
        case fourFingerPinchGesture = "com.apple.trackpad.fourFingerPinchSwipeGesture"
        case threeFingerDrag = "com.apple.trackpad.threeFingerDragGesture"
        case threeFingerTapGesture = "com.apple.trackpad.threeFingerTapGesture"

        fileprivate var identifier: SystemGesturePreferenceIdentifier {
            SystemGesturePreferenceIdentifier(domain: Self.domain, key: rawValue)
        }

        func get() -> SystemGesturePreferenceValue {
            identifier.get()
        }

        func set(_ value: SystemGesturePreferenceValue) {
            identifier.set(value)
            identifier.synchronize()
        }
    }

    enum Dock: String {
        fileprivate static let domain = "com.apple.dock"
        fileprivate static let defaults = UserDefaults(suiteName: domain)

        case showMissionControlGestureEnabled
        case showAppExposeGestureEnabled

        fileprivate var identifier: SystemGesturePreferenceIdentifier {
            SystemGesturePreferenceIdentifier(domain: Self.domain, key: rawValue)
        }

        func get() -> SystemGesturePreferenceValue {
            identifier.get()
        }

        func set(_ value: SystemGesturePreferenceValue) {
            identifier.set(value)
            identifier.synchronize()
        }
    }

    enum SystemPreferences: String {
        fileprivate static let domain = "com.apple.systempreferences"
        fileprivate static let defaults = UserDefaults(suiteName: domain)

        case threeFingerDragFourFingerNavigate = "com.apple.preference.trackpad.3fdrag-4fNavigate"

        fileprivate var identifier: SystemGesturePreferenceIdentifier {
            SystemGesturePreferenceIdentifier(domain: Self.domain, key: rawValue)
        }

        func get() -> SystemGesturePreferenceValue {
            identifier.get()
        }

        func set(_ value: SystemGesturePreferenceValue) {
            identifier.set(value)
            identifier.synchronize()
        }
    }

    fileprivate enum TrackpadGesture: String {
        case threeFingerHorizontalSwipeGesture = "TrackpadThreeFingerHorizSwipeGesture"
        case fourFingerHorizontalSwipeGesture = "TrackpadFourFingerHorizSwipeGesture"
        case threeFingerVerticalSwipeGesture = "TrackpadThreeFingerVertSwipeGesture"
        case fourFingerVerticalSwipeGesture = "TrackpadFourFingerVertSwipeGesture"
        case fourFingerPinchGesture = "TrackpadFourFingerPinchGesture"
        case threeFingerDrag = "TrackpadThreeFingerDrag"
        case threeFingerTapGesture = "TrackpadThreeFingerTapGesture"

        init?(preferenceKey: String) {
            if let gesture = Self(rawValue: preferenceKey) {
                self = gesture
                return
            }

            switch preferenceKey {
            case SystemGestureManager.CurrentHostTrackpad.threeFingerHorizontalSwipeGesture.rawValue:
                self = .threeFingerHorizontalSwipeGesture
            case SystemGestureManager.CurrentHostTrackpad.fourFingerHorizontalSwipeGesture.rawValue:
                self = .fourFingerHorizontalSwipeGesture
            case SystemGestureManager.CurrentHostTrackpad.threeFingerVerticalSwipeGesture.rawValue:
                self = .threeFingerVerticalSwipeGesture
            case SystemGestureManager.CurrentHostTrackpad.fourFingerVerticalSwipeGesture.rawValue:
                self = .fourFingerVerticalSwipeGesture
            case SystemGestureManager.CurrentHostTrackpad.fourFingerPinchGesture.rawValue:
                self = .fourFingerPinchGesture
            case SystemGestureManager.CurrentHostTrackpad.threeFingerDrag.rawValue:
                self = .threeFingerDrag
            case SystemGestureManager.CurrentHostTrackpad.threeFingerTapGesture.rawValue:
                self = .threeFingerTapGesture
            default:
                return nil
            }
        }
    }

    struct PreferenceLedger {
        var backups: [String: SystemGesturePreferenceValue]
        var managedValues: [String: SystemGesturePreferenceValue]

        var hasDisabledSystemGestures: Bool {
            managedValues.contains { key, managedValue in
                guard let identifier = SystemGesturePreferenceIdentifier(compositeKey: key),
                      identifier.isTrackpadDomain || identifier.isDockDomain,
                      let backup = backups[key]
                else { return false }

                switch (identifier.normalized(backup), identifier.normalized(managedValue)) {
                case (.bool(true), .bool(false)):
                    return true
                case let (.int(previous), .int(current)):
                    return previous > 0 && current == 0
                default:
                    return false
                }
            }
        }
    }

    static func restore() {
        var ledger = PreferenceLedger(
            backups: Defaults[.systemGesturePreferenceBackups],
            managedValues: Defaults[.systemGestureManagedValues]
        )

        Self().restoreAll(&ledger)

        Defaults[.systemGesturePreferenceBackups] = ledger.backups
        Defaults[.systemGestureManagedValues] = ledger.managedValues
    }

    static func reconcile(
        enableGestures: Bool,
        disableConflicts: Bool,
        gestures: [GestureBinding]
    ) {
        var ledger = PreferenceLedger(
            backups: Defaults[.systemGesturePreferenceBackups],
            managedValues: Defaults[.systemGestureManagedValues]
        )

        Self().reconcile(
            enableGestures: enableGestures,
            disableConflicts: disableConflicts,
            gestures: gestures,
            ledger: &ledger
        )

        Defaults[.systemGesturePreferenceBackups] = ledger.backups
        Defaults[.systemGestureManagedValues] = ledger.managedValues
    }

    func reconcile(
        enableGestures: Bool,
        disableConflicts: Bool,
        gestures: [GestureBinding],
        ledger: inout PreferenceLedger
    ) {
        normalizeStoredValues(&ledger.backups)
        normalizeStoredValues(&ledger.managedValues)

        guard enableGestures, disableConflicts else {
            restoreAll(&ledger)
            return
        }

        let desiredValues = desiredValues(for: gestures, backups: ledger.backups, managedValues: ledger.managedValues)
        guard !desiredValues.isEmpty else {
            restoreAll(&ledger)
            return
        }

        restoreNoLongerManagedValues(
            desiredValues: desiredValues,
            ledger: &ledger
        )

        var touchedDomains = Set<String>()
        var touchedDock = false
        var touchedTrackpad = false
        for (identifier, desiredValue) in desiredValues {
            let currentValue = identifier.get()
            let desiredValue = identifier.normalized(desiredValue)
            let lastManagedValue = ledger.managedValues[identifier.compositeKey].map(identifier.normalized)

            if currentValue != lastManagedValue, currentValue != desiredValue {
                ledger.backups[identifier.compositeKey] = currentValue
            }

            let backupValue = ledger.backups[identifier.compositeKey].map(identifier.normalized)
            guard currentValue != desiredValue else {
                if backupValue != nil {
                    ledger.managedValues[identifier.compositeKey] = desiredValue
                } else {
                    ledger.managedValues.removeValue(forKey: identifier.compositeKey)
                }
                continue
            }

            guard backupValue != nil else {
                ledger.managedValues.removeValue(forKey: identifier.compositeKey)
                continue
            }

            identifier.set(desiredValue)
            ledger.managedValues[identifier.compositeKey] = desiredValue
            touchedDomains.insert(identifier.domain)
            touchedDock = touchedDock || identifier.isDockDomain
            touchedTrackpad = touchedTrackpad || identifier.isTrackpadDomain
        }

        synchronize(domains: touchedDomains)
        if touchedTrackpad {
            activateSettings()
        }
        if touchedDock {
            restartDock()
        }
    }

    private func restoreAll(_ ledger: inout PreferenceLedger) {
        normalizeStoredValues(&ledger.backups)
        normalizeStoredValues(&ledger.managedValues)

        let identifiers = Set(ledger.backups.keys)
            .union(ledger.managedValues.keys)
            .compactMap(SystemGesturePreferenceIdentifier.init(compositeKey:))
        restore(identifiers, ledger: &ledger)
        ledger.backups.removeAll()
        ledger.managedValues.removeAll()
    }

    private func restoreNoLongerManagedValues(
        desiredValues: [SystemGesturePreferenceIdentifier: SystemGesturePreferenceValue],
        ledger: inout PreferenceLedger
    ) {
        let desiredKeys = Set(desiredValues.keys.map(\.compositeKey))
        let staleIdentifiers = ledger.managedValues.keys
            .filter { !desiredKeys.contains($0) }
            .compactMap(SystemGesturePreferenceIdentifier.init(compositeKey:))

        restore(staleIdentifiers, ledger: &ledger)
    }

    private func restore(
        _ identifiers: [SystemGesturePreferenceIdentifier],
        ledger: inout PreferenceLedger
    ) {
        guard !identifiers.isEmpty else { return }

        var touchedDomains = Set<String>()
        var touchedDock = false
        var touchedTrackpad = false

        for identifier in identifiers {
            guard let backupValue = ledger.backups[identifier.compositeKey].map(identifier.normalized) else {
                ledger.managedValues.removeValue(forKey: identifier.compositeKey)
                continue
            }

            let currentValue = identifier.normalized(identifier.get())
            let lastManagedValue = ledger.managedValues[
                identifier.compositeKey
            ].map(identifier.normalized)

            if let lastManagedValue, currentValue != lastManagedValue {
                // the user or another process changed this while Loop managed it
                ledger.backups.removeValue(forKey: identifier.compositeKey)
                ledger.managedValues.removeValue(forKey: identifier.compositeKey)
                continue
            }

            identifier.set(backupValue)
            ledger.backups.removeValue(forKey: identifier.compositeKey)
            ledger.managedValues.removeValue(forKey: identifier.compositeKey)
            touchedDomains.insert(identifier.domain)
            touchedDock = touchedDock || identifier.isDockDomain
            touchedTrackpad = touchedTrackpad || identifier.isTrackpadDomain
        }

        synchronize(domains: touchedDomains)
        if touchedTrackpad {
            activateSettings()
        }
        if touchedDock {
            restartDock()
        }
    }

    private func normalizeStoredValues(_ values: inout [String: SystemGesturePreferenceValue]) {
        for (key, value) in values {
            guard let identifier = SystemGesturePreferenceIdentifier(compositeKey: key) else { continue }
            values[key] = identifier.normalized(value)
        }
    }

    private func desiredValues(
        for gestures: [GestureBinding],
        backups: [String: SystemGesturePreferenceValue],
        managedValues: [String: SystemGesturePreferenceValue]
    ) -> [SystemGesturePreferenceIdentifier: SystemGesturePreferenceValue] {
        let hasThreeFingerGesture = gestures.contains { $0.fingerCount == 3 }
        let hasFourFingerGesture = gestures.contains { $0.fingerCount == 4 }

        guard hasThreeFingerGesture || hasFourFingerGesture else { return [:] }

        var desiredValues: [SystemGesturePreferenceIdentifier: SystemGesturePreferenceValue] = [:]

        if hasThreeFingerGesture {
            setTrackpadValue(
                .int(0),
                for: .threeFingerHorizontalSwipeGesture,
                .threeFingerHorizontalSwipeGesture,
                .threeFingerHorizontalSwipeGesture,
                in: &desiredValues
            )
            setTrackpadValue(
                .int(0),
                for: .threeFingerVerticalSwipeGesture,
                .threeFingerVerticalSwipeGesture,
                .threeFingerVerticalSwipeGesture,
                in: &desiredValues
            )
            setTrackpadValue(
                .bool(false),
                for: .threeFingerDrag,
                .threeFingerDrag,
                .threeFingerDrag,
                in: &desiredValues
            )
            setTrackpadValue(
                .int(0),
                for: .threeFingerTapGesture,
                .threeFingerTapGesture,
                .threeFingerTapGesture,
                in: &desiredValues
            )

            if !hasFourFingerGesture {
                let didUpgradeHorizontal = upgradeSystemGestureIfNeeded(
                    from: [
                        BuiltInTrackpad.threeFingerHorizontalSwipeGesture.identifier,
                        BluetoothTrackpad.threeFingerHorizontalSwipeGesture.identifier,
                        CurrentHostTrackpad.threeFingerHorizontalSwipeGesture.identifier
                    ],
                    to: [
                        BuiltInTrackpad.fourFingerHorizontalSwipeGesture.identifier,
                        BluetoothTrackpad.fourFingerHorizontalSwipeGesture.identifier,
                        CurrentHostTrackpad.fourFingerHorizontalSwipeGesture.identifier
                    ],
                    backups: backups,
                    managedValues: managedValues,
                    desiredValues: &desiredValues
                )

                if didUpgradeHorizontal {
                    desiredValues[SystemPreferences.threeFingerDragFourFingerNavigate.identifier] = .missing
                }

                let didUpgradeVertical = upgradeSystemGestureIfNeeded(
                    from: [
                        BuiltInTrackpad.threeFingerVerticalSwipeGesture.identifier,
                        BluetoothTrackpad.threeFingerVerticalSwipeGesture.identifier,
                        CurrentHostTrackpad.threeFingerVerticalSwipeGesture.identifier
                    ],
                    to: [
                        BuiltInTrackpad.fourFingerVerticalSwipeGesture.identifier,
                        BluetoothTrackpad.fourFingerVerticalSwipeGesture.identifier,
                        CurrentHostTrackpad.fourFingerVerticalSwipeGesture.identifier
                    ],
                    backups: backups,
                    managedValues: managedValues,
                    desiredValues: &desiredValues
                )

                if !didUpgradeVertical {
                    desiredValues[Dock.showMissionControlGestureEnabled.identifier] = .bool(false)
                    desiredValues[Dock.showAppExposeGestureEnabled.identifier] = .bool(false)
                }
            }
        }

        if hasFourFingerGesture {
            setTrackpadValue(
                .int(0),
                for: .threeFingerHorizontalSwipeGesture,
                .threeFingerHorizontalSwipeGesture,
                .threeFingerHorizontalSwipeGesture,
                in: &desiredValues
            )
            setTrackpadValue(
                .int(0),
                for: .fourFingerHorizontalSwipeGesture,
                .fourFingerHorizontalSwipeGesture,
                .fourFingerHorizontalSwipeGesture,
                in: &desiredValues
            )
            setTrackpadValue(
                .int(0),
                for: .fourFingerVerticalSwipeGesture,
                .fourFingerVerticalSwipeGesture,
                .fourFingerVerticalSwipeGesture,
                in: &desiredValues
            )
            setTrackpadValue(
                .int(0),
                for: .fourFingerPinchGesture,
                .fourFingerPinchGesture,
                .fourFingerPinchGesture,
                in: &desiredValues
            )
        }

        return desiredValues
    }

    @discardableResult
    private func upgradeSystemGestureIfNeeded(
        from sourceIdentifiers: [SystemGesturePreferenceIdentifier],
        to targetIdentifiers: [SystemGesturePreferenceIdentifier],
        backups: [String: SystemGesturePreferenceValue],
        managedValues: [String: SystemGesturePreferenceValue],
        desiredValues: inout [SystemGesturePreferenceIdentifier: SystemGesturePreferenceValue]
    ) -> Bool {
        var didUpgrade = false
        for (sourceIdentifier, targetIdentifier) in zip(sourceIdentifiers, targetIdentifiers) {
            guard userOwnedValue(for: sourceIdentifier, backups: backups, managedValues: managedValues) == .int(2) else {
                continue
            }
            desiredValues[targetIdentifier] = .int(2)
            didUpgrade = true
        }
        return didUpgrade
    }

    private func userOwnedValue(
        for identifier: SystemGesturePreferenceIdentifier,
        backups: [String: SystemGesturePreferenceValue],
        managedValues: [String: SystemGesturePreferenceValue]
    ) -> SystemGesturePreferenceValue {
        if let backupValue = backups[identifier.compositeKey] {
            return backupValue
        }

        let currentValue = identifier.get()
        if currentValue == managedValues[identifier.compositeKey] {
            return .missing
        }

        return currentValue
    }

    private func setTrackpadValue(
        _ value: SystemGesturePreferenceValue,
        for builtInTrackpadKey: BuiltInTrackpad,
        _ bluetoothTrackpadKey: BluetoothTrackpad,
        _ currentHostTrackpadKey: CurrentHostTrackpad,
        in desiredValues: inout [SystemGesturePreferenceIdentifier: SystemGesturePreferenceValue]
    ) {
        desiredValues[builtInTrackpadKey.identifier] = value
        desiredValues[bluetoothTrackpadKey.identifier] = value
        desiredValues[currentHostTrackpadKey.identifier] = value
    }

    private func synchronize(domains: Set<String>) {
        for domain in domains {
            if domain == CurrentHostTrackpad.domain {
                CFPreferencesSynchronize(
                    kCFPreferencesAnyApplication,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesCurrentHost
                )
            } else {
                SystemGesturePreferenceIdentifier.defaults(for: domain)?.synchronize()
            }
        }
    }

    private static func restartDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        try? process.run()
    }

    private static func activateSettings() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        process.arguments = ["-u"]
        try? process.run()
    }
}

struct SystemGesturePreferenceIdentifier: Hashable {
    let domain: String
    let key: String

    fileprivate enum ValueKind {
        case bool
        case int
    }

    var compositeKey: String {
        "\(domain).\(key)"
    }

    fileprivate var isTrackpadDomain: Bool {
        domain == SystemGestureManager.BuiltInTrackpad.domain ||
            domain == SystemGestureManager.BluetoothTrackpad.domain ||
            domain == SystemGestureManager.CurrentHostTrackpad.domain
    }

    fileprivate var isDockDomain: Bool {
        domain == SystemGestureManager.Dock.domain
    }

    private var valueKind: ValueKind {
        if domain == SystemGestureManager.Dock.domain ||
            domain == SystemGestureManager.SystemPreferences.domain {
            return .bool
        }

        if isTrackpadDomain,
           let gesture = SystemGestureManager.TrackpadGesture(preferenceKey: key),
           gesture == .threeFingerDrag {
            return .bool
        }

        return .int
    }

    init(domain: String, key: String) {
        self.domain = domain
        self.key = key
    }

    init?(compositeKey: String) {
        let knownDomains = [
            SystemGestureManager.BuiltInTrackpad.domain,
            SystemGestureManager.BluetoothTrackpad.domain,
            SystemGestureManager.CurrentHostTrackpad.domain,
            SystemGestureManager.Dock.domain,
            SystemGestureManager.SystemPreferences.domain
        ].sorted { $0.count > $1.count }

        for domain in knownDomains {
            let prefix = "\(domain)."
            guard compositeKey.hasPrefix(prefix) else { continue }
            self.domain = domain
            self.key = String(compositeKey.dropFirst(prefix.count))
            return
        }

        let components = compositeKey.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count > 1 else { return nil }

        self.key = String(components.last!)
        self.domain = components.dropLast().joined(separator: ".")
    }

    func get() -> SystemGesturePreferenceValue {
        let value: Any? = if domain == SystemGestureManager.CurrentHostTrackpad.domain {
            CFPreferencesCopyValue(
                key as CFString,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        } else {
            Self.defaults(for: domain)?.object(forKey: key)
        }

        guard let value else {
            return .missing
        }

        guard let number = value as? NSNumber else {
            return .missing
        }

        switch valueKind {
        case .bool:
            return .bool(number.boolValue)
        case .int:
            return .int(number.intValue)
        }
    }

    func set(_ value: SystemGesturePreferenceValue) {
        let value = normalized(value)

        if domain == SystemGestureManager.CurrentHostTrackpad.domain {
            let valueToSet: CFPropertyList? = switch value {
            case let .bool(value):
                value as CFBoolean
            case let .int(value):
                value as CFNumber
            case .missing:
                nil
            }

            CFPreferencesSetValue(
                key as CFString,
                valueToSet,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            return
        }

        let defaults = Self.defaults(for: domain)

        switch value {
        case let .bool(value):
            defaults?.set(value, forKey: key)
        case let .int(value):
            defaults?.set(value, forKey: key)
        case .missing:
            defaults?.removeObject(forKey: key)
        }
    }

    fileprivate func normalized(_ value: SystemGesturePreferenceValue) -> SystemGesturePreferenceValue {
        switch (valueKind, value) {
        case let (.bool, .int(value)):
            .bool(value != 0)
        case let (.int, .bool(value)):
            .int(value ? 1 : 0)
        default:
            value
        }
    }

    func synchronize() {
        if domain == SystemGestureManager.CurrentHostTrackpad.domain {
            CFPreferencesSynchronize(
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            return
        }

        Self.defaults(for: domain)?.synchronize()
    }

    fileprivate static func defaults(for domain: String) -> UserDefaults? {
        switch domain {
        case SystemGestureManager.BuiltInTrackpad.domain:
            SystemGestureManager.BuiltInTrackpad.defaults
        case SystemGestureManager.BluetoothTrackpad.domain:
            SystemGestureManager.BluetoothTrackpad.defaults
        case SystemGestureManager.Dock.domain:
            SystemGestureManager.Dock.defaults
        case SystemGestureManager.SystemPreferences.domain:
            SystemGestureManager.SystemPreferences.defaults
        default:
            UserDefaults(suiteName: domain)
        }
    }
}
