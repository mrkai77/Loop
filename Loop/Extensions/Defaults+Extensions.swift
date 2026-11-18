//
//  Defaults+Extensions.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-14.
//
// NOTE: While iCloud is enabled, its service is currently disabled to make GitHub actions work.

// These configuration keys are only read by the migration. Settings live in config.toml.
import Defaults
import Scribe
import SwiftUI
import Tome

enum LegacyDefaults {
    static let showDockIcon = Defaults.Key<Bool>("showDockIcon", default: false)
    static let notificationWhenIconUnlocked = Defaults.Key<Bool>("notificationWhenIconUnlocked", default: true)
    static let accentColorMode: Defaults.Key<LegacyAccentColorOption> = Defaults.Key("accentColorMode", default: .system)
    static let customAccentColor = Defaults.Key<Color>("customAccentColor", default: .teal)
    static let useGradient = Defaults.Key<Bool>("useGradient", default: false)
    static let gradientColor = Defaults.Key<Color>("gradientColor", default: .blue)
    static let radialMenuVisibility = Defaults.Key<Bool>("radialMenuVisibility", default: true)
    static let radialMenuCornerRadius = Defaults.Key<CGFloat>("radialMenuCornerRadius", default: 50)
    static let radialMenuThickness = Defaults.Key<CGFloat>("radialMenuThickness", default: 22)
    static let radialMenuActions = Defaults.Key<[LegacyRadialMenuAction]>("radialMenuActions", default: [])
    static let previewVisibility = Defaults.Key<Bool>("previewVisibility", default: true)
    static let previewPadding = Defaults.Key<CGFloat>("previewPadding", default: 10)
    static let previewCornerRadius = Defaults.Key<CGFloat>("previewCornerRadius", default: 10)
    static let previewBorderThickness = Defaults.Key<CGFloat>("previewBorderThickness", default: 4)
    static let previewUseWindowCornerRadius = Defaults.Key<Bool>("previewUseWindowCornerRadius", default: true)
    static let previewBackgroundStyle = Defaults.Key<LegacyPreviewBackgroundStyle>("previewBackgroundStyle", default: .system)
    static let previewBackgroundEnableBlur = Defaults.Key<Bool>("previewBackgroundEnableBlur", default: false)
    static let previewBackgroundAccentOpacity = Defaults.Key<CGFloat>("previewBackgroundAccentOpacity", default: 0.1)
    static let animationConfiguration = Defaults.Key<LegacyAnimationConfiguration>("animationConfiguration", default: .snappy)
    static let windowSnapping = Defaults.Key<Bool>("windowSnapping", default: false)
    static let suppressMissionControlOnTopDrag = Defaults.Key<Bool>("suppressMissionControlOnTopDrag", default: true)
    static let restoreWindowFrameOnDrag = Defaults.Key<Bool>("restoreWindowFrameOnDrag", default: false)
    static let enablePadding = Defaults.Key<Bool>("enablePadding", default: false)
    static let padding = Defaults.Key<LegacyPaddingConfiguration>("padding", default: .zero)
    static let useScreenWithCursor = Defaults.Key<Bool>("useScreenWithCursor", default: true)
    static let resizeWindowUnderCursor = Defaults.Key<Bool>("resizeWindowUnderCursor", default: false)
    static let focusWindowOnResize = Defaults.Key<Bool>("focusWindowOnResize", default: true)
    static let respectStageManager = Defaults.Key<Bool>("respectStageManager", default: true)
    static let stageStripSize = Defaults.Key<CGFloat>("stageStripSize", default: 150)
    static let animateStashedWindows = Defaults.Key<Bool>("animateStashedWindows", default: true)
    static let stashedWindowVisiblePadding = Defaults.Key<CGFloat>("stashedWindowVisiblePadding", default: 20)
    static let shiftFocusWhenStashed = Defaults.Key<Bool>("shiftFocusWhenStashed", default: true)
    static let cycleModeRestartEnabled = Defaults.Key<Bool>("cycleModeRestartEnabled", default: false)
    static let triggerKey = Defaults.Key<Set<CGKeyCode>>("trigger", default: [.kVK_Function])
    static let sideDependentTriggerKey = Defaults.Key<Bool>("sideDependentTriggerKey", default: true)
    static let triggerDelay = Defaults.Key<Double>("triggerDelay", default: 0)
    static let doubleClickToTrigger = Defaults.Key<Bool>("doubleClickToTrigger", default: false)
    static let middleClickTriggersLoop = Defaults.Key<Bool>("middleClickTriggersLoop", default: false)
    static let enableTriggerDelayOnMiddleClick = Defaults.Key<Bool>("enableTriggerDelayOnMiddleClick", default: false)
    static let cycleBackwardsOnShiftPressed = Defaults.Key<Bool>("cycleBackwardsOnShiftPressed", default: true)
    static let keybinds = Defaults.Key<[LegacyWindowAction]>("keybinds", default: [])
    static let enableGestures = Defaults.Key<Bool>("enableGestures", default: false)
    static let gestures = Defaults.Key<[LegacyGestureBinding]>("gestures", default: [])
    static let useSystemWindowManagerWhenAvailable = Defaults.Key<Bool>("useSystemWindowManagerWhenAvailable", default: false)
    static let animateWindowResizes = Defaults.Key<Bool>("animateWindowResizes", default: false)
    static let disableCursorInteraction = Defaults.Key<Bool>("disableCursorInteraction", default: false)
    static let ignoreFullscreen = Defaults.Key<Bool>("ignoreFullscreen", default: false)
    static let hideOnNoSelectionForKeybinds = Defaults.Key<Bool>("hideOnNoSelectionForKeybinds", default: false)
    static let hapticFeedback = Defaults.Key<Bool>("hapticFeedback", default: true)
    static let enableRadialMenuCustomization = Defaults.Key<Bool>("enableRadialMenuCustomization", default: false)
    static let sizeIncrement = Defaults.Key<CGFloat>("sizeIncrement", default: 20)
    static let screenOrder = Defaults.Key<LegacyScreenOrder>("screenOrder", default: .zShaped)
    static let excludedApps = Defaults.Key<[URL]>("excludedApps", default: [])
    #if RELEASE
        static let includeDevelopmentVersions = Defaults.Key<Bool>("includeDevelopmentVersions", default: false)
    #else
        static let includeDevelopmentVersions = Defaults.Key<Bool>("includeDevelopmentVersions", default: true)
    #endif
    static let automaticallyUpdate = Defaults.Key<Bool>("automaticallyUpdate", default: false)
    static let hideOnNoSelectionForGestures = Defaults.Key<Bool>("hideOnNoSelectionForGestures", default: true)
    static let lockRadialMenuToCenter = Defaults.Key<Bool>("lockRadialMenuToCenter", default: false)
    static let startHidden = Defaults.Key<Bool>("startHidden", default: false)
    static let hideMenuBarIcon = Defaults.Key<Bool>("hideMenuBarIcon", default: false, iCloud: false)
    static let moveCursorWithWindow = Defaults.Key<Bool>("moveCursorWithWindow", default: false)
    static let paddingMinimumScreenSize = Defaults.Key<CGFloat>("paddingMinimumScreenSize", default: 0)
    static let ignoreNotch = Defaults.Key<Bool>("ignoreNotch", default: false)
    static let snapThreshold = Defaults.Key<CGFloat>("snapThreshold", default: 2)
    static let ignoreLowPowerMode = Defaults.Key<Bool>("ignoreLowPowerMode", default: false)
    static let previewStartingPosition = Defaults.Key<LegacyPreviewStartingPosition>("previewStartingPosition", default: .actionCenter)
    static let updatesEnabled = Defaults.Key<Bool>("updatesEnabled", default: true)
    static let triggerKeyTimeout = Defaults.Key<Double>("triggerKeyTimeout", default: 0)
    static let gestureTitlebarHeight = Defaults.Key<CGFloat>("gestureTitlebarHeight", default: 50)
}

/// App state that stays in Defaults.
extension Defaults.Keys {
    static let currentIcon = Defaults.Key<String>("currentIcon", default: "AppIcon-Classic")
    static let timesLooped = Defaults.Key<Int>("timesLooped", default: 0)
    static let launchAtLogin = Defaults.Key<Bool>("launchAtLogin", default: false)
    static let enableiCloudSync = Defaults.Key<Bool>("enableiCloudSync", default: true)
    static let lastMigratorURL = Defaults.Key<URL?>("lastMigratorURL", default: nil)
    static let stashManagerStashedWindows = Defaults.Key<[CGWindowID: WindowAction]>("stashManagerStashed", default: [:])
    static let lastUsedAccentColor1 = Defaults.Key<Color>("lastUsedAccentColor1", default: .black)
    static let lastUsedAccentColor2 = Defaults.Key<Color>("lastUsedAccentColor2", default: .black)
    static let patchesApplied = Defaults.Key<DataPatcher.Patches>("patchesApplied", default: [])
    static let showSettingsInspector = Defaults.Key<Bool>("showSettingsInspector", default: true)
    static let migratedToConfigFile = Defaults.Key<Bool>("migratedToConfigFile", default: false)
    /// Lets the file of an interrupted migration be recognized.
    static let configMigrationPendingDigest = Defaults.Key<String?>("configMigrationPendingDigest", default: nil)
}

@Loggable(style: .static)
enum DefaultsiCloudSyncRegistrar {
    static func register() {
        updateiCloudSync(enabled: Defaults[.enableiCloudSync])
        Task { @MainActor in
            for await enabled in Defaults.updates(.enableiCloudSync, initial: false) {
                updateiCloudSync(enabled: enabled)
            }
        }
    }

    private static func updateiCloudSync(enabled: Bool) {
        // Remove configuration keys registered by older versions
        Defaults.iCloud.removeAll()
        guard enabled else { return }
        Defaults.iCloud.add(.currentIcon)
        Defaults.iCloud.add(.timesLooped)
    }
}

/// Read-only: legacy values are only read by the migration.
struct LegacyJSONBridge<Value: Decodable>: Defaults.Bridge {
    func serialize(_: Value?) -> String? { nil }

    func deserialize(_ object: String?) -> Value? {
        object.flatMap { try? JSONDecoder().decode(Value.self, from: Data($0.utf8)) }
    }
}

/// A binding in its legacy Defaults format.
protocol LegacyBinding: Decodable, Defaults.Serializable {
    associatedtype Binding: ActionBinding

    static var defaultsKey: Defaults.Key<[Self]> { get }
    static var settingsKeyPath: WritableKeyPath<TomeValues, [Binding]> { get }

    /// `nil` drops the entry. `names` maps legacy keybind ids to their written `id`.
    func migrated(names: [UUID: String]) -> Binding?
}

extension LegacyBinding {
    static var bridge: LegacyJSONBridge<Self> { .init() }
}

extension LegacyWindowAction: LegacyBinding {
    static var defaultsKey: Defaults.Key<[LegacyWindowAction]> { LegacyDefaults.keybinds }
    static var settingsKeyPath: WritableKeyPath<TomeValues, [KeyBinding]> { \.keyBindings }

    func migrated(names _: [UUID: String]) -> KeyBinding? {
        direction.current == .noSelection ? nil : convertToKeyBinding()
    }
}

struct LegacyRadialMenuAction: LegacyBinding {
    var id: UUID
    var type: ActionType
    enum ActionType: Decodable {
        case custom(LegacyWindowAction)
        case keybindReference(UUID)
        func target(names: [UUID: String]) -> ActionTarget {
            switch self {
            case let .custom(action): .windowAction(action.convertToWindowAction())
            case let .keybindReference(id): .reference(BindingReference(.key, names[id] ?? "missing-" + id.uuidString.lowercased()))
            }
        }
    }

    static var defaultsKey: Defaults.Key<[LegacyRadialMenuAction]> { LegacyDefaults.radialMenuActions }
    static var settingsKeyPath: WritableKeyPath<TomeValues, [RadialMenuBinding]> { \.radialMenuBindings }

    func migrated(names: [UUID: String]) -> RadialMenuBinding? {
        RadialMenuBinding(id: id, target: type.target(names: names))
    }
}

struct LegacyGestureBinding: LegacyBinding {
    var id: UUID
    var fingerCount: Int
    var kind: LegacyGestureKind?
    var action: Action
    var activationZone: LegacyActivationZone
    enum Action: Decodable {
        case radialMenuActions
        case singleAction(LegacyRadialMenuAction.ActionType)
    }

    static var defaultsKey: Defaults.Key<[LegacyGestureBinding]> { LegacyDefaults.gestures }
    static var settingsKeyPath: WritableKeyPath<TomeValues, [GestureBinding]> { \.gestureBindings }

    /// A radial-menu gesture keeps the default target, which it never runs.
    func migrated(names: [UUID: String]) -> GestureBinding? {
        var gesture = GestureBinding(id: id, fingerCount: fingerCount, kind: kind?.current, activationZone: activationZone.current)
        if case let .singleAction(type) = action { gesture.target = type.target(names: names) }
        return gesture
    }
}

/// Stored as an enum with empty payloads, such as `{"swipeLeft": {}}`.
enum LegacyGestureKind: Decodable {
    case radialMenu, swipeUp, swipeDown, swipeLeft, swipeRight, magnifyOut, magnifyIn

    var current: GestureBinding.Kind {
        switch self {
        case .radialMenu: .radialMenu
        case .swipeUp: .swipeUp
        case .swipeDown: .swipeDown
        case .swipeLeft: .swipeLeft
        case .swipeRight: .swipeRight
        case .magnifyOut: .magnifyOut
        case .magnifyIn: .magnifyIn
        }
    }
}

enum LegacyActivationZone: String, Decodable {
    case titlebar, anywhere

    var current: GestureBinding.ActivationZone { self == .titlebar ? .titlebar : .anywhere }
}

enum LegacyPreviewBackgroundStyle: String, Defaults.Serializable {
    case system, custom
    var current: PreviewBackgroundStyle {
        switch self {
        case .system: .system
        case .custom: .custom
        }
    }
}

enum LegacyPreviewStartingPosition: String, Defaults.Serializable {
    case screenCenter, radialMenu, actionCenter
    var current: PreviewStartingPosition {
        switch self {
        case .screenCenter: .screenCenter
        case .radialMenu: .radialMenu
        case .actionCenter: .actionCenter
        }
    }
}

enum LegacyAccentColorOption: Int, Codable, Defaults.Serializable {
    case system, wallpaper, custom
    var current: AccentColorOption { [.system, .wallpaper, .custom][rawValue] }
}

enum LegacyAnimationConfiguration: Int, Defaults.Serializable {
    case fluid, relaxed, snappy, brisk, instant
    var current: AnimationConfiguration { [.fluid, .relaxed, .snappy, .brisk, .instant][rawValue] }
}

enum LegacyScreenOrder: Int, Defaults.Serializable {
    case zShaped, clockwise
    var current: ScreenOrder { [.zShaped, .clockwise][rawValue] }
}

struct LegacyPaddingConfiguration: Codable, Defaults.Serializable {
    var window: CGFloat
    var externalBar: CGFloat
    var top: CGFloat
    var bottom: CGFloat
    var right: CGFloat
    var left: CGFloat
    var configureScreenPadding: Bool

    var current: PaddingConfiguration {
        PaddingConfiguration(
            window: window,
            externalBar: externalBar,
            top: top,
            bottom: bottom,
            right: right,
            left: left,
            mode: configureScreenPadding ? .custom : .simple
        )
    }

    static let zero = Self(window: 0, externalBar: 0, top: 0, bottom: 0, right: 0, left: 0, configureScreenPadding: false)
}

// MARK: - Legacy Keybinds File

struct LegacyKeybindsFile: Decodable {
    let version: String?
    let triggerKey: Set<CGKeyCode>?
    let actions: [LegacyWindowAction]

    /// Rejects nested cycles. The Defaults migration drops them instead.
    func validated() throws -> Self {
        guard !actions.contains(where: \.hasNestedCycle) else {
            throw MigratorError.invalidKeybinds("A cycle can't contain another cycle")
        }
        return self
    }
}

// MARK: - Legacy Window Action

/// The legacy `WindowAction` format, also used by stash records and keybinds files.
struct LegacyWindowAction: Decodable {
    let id: UUID?
    let direction: Direction
    let keybind: Set<CGKeyCode>
    let bypassTriggerKey: Bool?
    let name: String?
    let unit: CustomWindowActionUnit?
    let anchor: CustomWindowActionAnchor?
    let sizeMode: CustomWindowActionSizeMode?
    let width: Double?
    let height: Double?
    let positionMode: CustomWindowActionPositionMode?
    let xPoint: Double?
    let yPoint: Double?
    let cycle: [LegacyWindowAction]?

    /// Stored as the capitalized case name, such as `LeftHalf`.
    struct Direction: Decodable {
        let current: WindowDirection

        private static let byName = Dictionary(uniqueKeysWithValues: WindowDirection.allCases.map { direction in
            let name = switch direction {
            case .noAction: "NoAction"
            case .macOSCenter: "MacOSCenter"
            default: direction.rawValue.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
            }
            return (name, direction)
        })

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let name = try container.decode(String.self)
            guard let direction = Self.byName[name] else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown window direction \(ConfigurationMessage.quoted(name))")
            }
            self.current = direction
        }
    }

    var hasNestedCycle: Bool {
        direction.current == .cycle && cycle?.contains { $0.direction.current == .cycle } == true
    }

    func convertToWindowAction() -> WindowAction {
        let direction = direction.current
        var action = WindowAction(direction)
        if let id { action = action.withRuntimeID(id) }
        action.name = name
        if direction == .cycle {
            // Only old Defaults data can nest cycles here; drop the inner cycle.
            let steps = (cycle ?? []).filter { step in
                if step.direction.current == .cycle { Migrator.log.warn("Dropped a cycle nested in the cycle \(name ?? "Cycle")") }
                return step.direction.current != .cycle
            }
            action.kind = .cycle(.init(name: name, steps: steps.map { .windowAction($0.convertToWindowAction()) }))
        } else if direction == .custom || direction == .stash {
            let lengthUnit: ScreenLength.Unit = unit == .pixels ? .points : .percent
            let widthLength = width.map { ScreenLength($0, unit: lengthUnit) }
            let heightLength = height.map { ScreenLength($0, unit: lengthUnit) }
            switch sizeMode ?? .custom {
            case .custom: action.size = .custom(width: widthLength, height: heightLength)
            case .preserve: action.size = .preserve
            case .initial: action.size = .initial
            }
            action.customDimensions = .init(width: widthLength, height: heightLength)
            if positionMode == .coordinates {
                let origin = unit == .pixels ? ScreenLength(0, unit: .points) : nil
                action.position = .coordinates(x: xPoint.map { ScreenLength($0, unit: lengthUnit) } ?? origin, y: yPoint.map { ScreenLength($0, unit: lengthUnit) } ?? origin)
            } else {
                action.position = .anchor(anchor ?? .none)
            }
        }
        return action
    }

    func convertToKeyBinding() -> KeyBinding {
        KeyBinding(id: id ?? UUID(), keys: KeyCombination(keyCodes: keybind), bypassTriggerKey: bypassTriggerKey, target: .windowAction(convertToWindowAction()))
    }
}
