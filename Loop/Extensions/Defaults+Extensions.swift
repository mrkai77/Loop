//
//  Defaults+Extensions.swift
//  Loop
//
//  Created by Kai Azim on 2023-06-14.
//
// NOTE: While iCloud is enabled, its service is currently disabled to make GitHub actions work.

import Defaults
import Scribe
import SwiftUI

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
    static let radialMenuActions = Defaults.Key<[LegacyRadialMenuAction]>("radialMenuActions", default: RadialMenuBinding.defaultRadialMenuActions.map(LegacyRadialMenuAction.init))
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
    static let keybinds = Defaults.Key<[LegacyWindowAction]>("keybinds", default: KeyBinding.defaultKeybinds.map(LegacyWindowAction.init))
    static let enableGestures = Defaults.Key<Bool>("enableGestures", default: false)
    static let gestures = Defaults.Key<[LegacyGestureBinding]>("gestures", default: GestureBinding.defaults.map(LegacyGestureBinding.init))
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
    static let configMigrationVersion = Defaults.Key<Int>("configMigrationVersion", default: 0)
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
        Defaults.iCloud.removeAll()
        guard enabled else { return }
        Defaults.iCloud.add(.currentIcon)
        Defaults.iCloud.add(.timesLooped)
    }
}

extension LegacyWindowAction: Defaults.Serializable {}

struct LegacyRadialMenuAction: Codable, Defaults.Serializable {
    var id: UUID
    var type: ActionType
    enum ActionType: Codable {
        case custom(LegacyWindowAction)
        case keybindReference(UUID)
        func target(names: [UUID: String]) -> ActionTarget {
            switch self {
            case let .custom(action): .windowAction(action.convertToWindowAction())
            case let .keybindReference(id): .keyBinding(names[id] ?? "missing-" + id.uuidString.lowercased())
            }
        }
    }

    init(id: UUID = UUID(), type: ActionType) { self.id = id; self.type = type }
    static func keybindReference(_ id: UUID) -> Self { Self(type: .keybindReference(id)) }
    init(_ binding: RadialMenuBinding) {
        self.id = binding.id
        if case let .windowAction(action) = binding.target { self.type = .custom(LegacyWindowAction(KeyBinding(target: .windowAction(action)))) }
        else { self.type = .custom(LegacyWindowAction(KeyBinding(.noAction))) }
    }
}

struct LegacyGestureBinding: Codable, Defaults.Serializable {
    var id: UUID
    var fingerCount: Int
    var kind: LegacyGestureKind?
    var action: Action
    var activationZone: LegacyActivationZone
    enum Action: Codable {
        case radialMenuActions
        case singleAction(LegacyRadialMenuAction.ActionType)
    }

    init(id: UUID = UUID(), fingerCount: Int = 2, kind: LegacyGestureKind? = nil, action: Action, activationZone: LegacyActivationZone = .titlebar) {
        self.id = id; self.fingerCount = fingerCount; self.kind = kind; self.action = action; self.activationZone = activationZone
    }

    init(_ binding: GestureBinding) {
        self.id = binding.id; self.fingerCount = binding.fingerCount; self.kind = binding.kind.map(LegacyGestureKind.init); self.activationZone = LegacyActivationZone(binding.activationZone)
        self.action = binding.target == .radialMenuMode ? .radialMenuActions : .singleAction(LegacyRadialMenuAction(binding: binding).type)
    }
}

enum LegacyGestureKind: Codable, Hashable {
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

    init(_ kind: GestureBinding.Kind) {
        switch kind {
        case .radialMenu: self = .radialMenu
        case .swipeUp: self = .swipeUp
        case .swipeDown: self = .swipeDown
        case .swipeLeft: self = .swipeLeft
        case .swipeRight: self = .swipeRight
        case .magnifyOut: self = .magnifyOut
        case .magnifyIn: self = .magnifyIn
        }
    }
}

enum LegacyActivationZone: String, Codable {
    case titlebar, anywhere

    var current: GestureBinding.ActivationZone { self == .titlebar ? .titlebar : .anywhere }

    init(_ zone: GestureBinding.ActivationZone) { self = zone == .titlebar ? .titlebar : .anywhere }
}

private extension LegacyRadialMenuAction {
    init(binding: GestureBinding) { self.init(RadialMenuBinding(id: binding.id, target: binding.target)) }
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

struct LegacyKeybindsFile: Codable {
    let version: String?
    let triggerKey: Set<CGKeyCode>?
    let actions: [LegacyWindowAction]

    func validated() throws -> Self {
        guard !actions.contains(where: \.hasNestedCycle) else {
            throw MigratorError.invalidKeybinds("A cycle can't contain another cycle")
        }
        return self
    }
}

// MARK: - Legacy Window Action

struct LegacyWindowAction: Codable {
    let bypassTriggerKey: Bool?
    let configID: String?
    let direction: WindowDirection
    let keybind: Set<CGKeyCode>
    let name: String?
    let unit: CustomWindowActionUnit?
    let widthUnit: CustomWindowActionUnit?
    let heightUnit: CustomWindowActionUnit?
    let xUnit: CustomWindowActionUnit?
    let yUnit: CustomWindowActionUnit?
    let anchor: CustomWindowActionAnchor?
    let sizeMode: CustomWindowActionSizeMode?
    let width: Double?
    let height: Double?
    let positionMode: CustomWindowActionPositionMode?
    let xPoint: Double?
    let yPoint: Double?
    let cycle: [LegacyWindowAction]?

    let id: UUID?

    var hasNestedCycle: Bool {
        direction == .cycle && cycle?.contains { $0.direction == .cycle } == true
    }

    init(_ binding: KeyBinding) {
        let action: WindowAction = if case let .windowAction(value) = binding.target { value } else { WindowAction(.noAction) }
        self.init(action: action, id: binding.id, keybind: Set(binding.keys.names.compactMap { KeyboardLayout.shared.keyCode(forName: $0) }), bypassTriggerKey: binding.bypassTriggerKey, configID: binding.configID)
    }

    init(action: WindowAction, id: UUID, keybind: Set<CGKeyCode> = [], bypassTriggerKey: Bool? = nil, configID: String? = nil) {
        self.id = id
        self.bypassTriggerKey = bypassTriggerKey
        self.configID = configID
        self.direction = action.direction
        self.keybind = keybind
        self.name = action.name
        let dimensions = action.customDimensions
        self.width = dimensions?.width?.value
        self.height = dimensions?.height?.value
        switch action.size {
        case .custom: self.sizeMode = .custom
        case .preserve: self.sizeMode = .preserve
        case .initial: self.sizeMode = .initial
        case nil: self.sizeMode = nil
        }
        func legacyUnit(_ length: ScreenLength?) -> CustomWindowActionUnit? {
            length.map { $0.unit == .points ? .pixels : .percentage }
        }
        self.widthUnit = legacyUnit(dimensions?.width)
        self.heightUnit = legacyUnit(dimensions?.height)
        let firstLength: ScreenLength?
        switch action.position {
        case let .anchor(value):
            self.anchor = value
            self.positionMode = .generic
            self.xPoint = nil
            self.yPoint = nil
            self.xUnit = nil
            self.yUnit = nil
            firstLength = dimensions?.width ?? dimensions?.height
        case let .coordinates(x, y):
            self.anchor = nil
            self.positionMode = .coordinates
            self.xPoint = x?.value
            self.yPoint = y?.value
            self.xUnit = legacyUnit(x)
            self.yUnit = legacyUnit(y)
            firstLength = dimensions?.width ?? dimensions?.height ?? x ?? y
        case nil:
            self.anchor = nil
            self.positionMode = nil
            self.xPoint = nil
            self.yPoint = nil
            self.xUnit = nil
            self.yUnit = nil
            firstLength = nil
        }
        self.unit = firstLength.map { $0.unit == .points ? .pixels : .percentage }
        if case let .cycle(payload) = action.kind {
            self.cycle = payload.steps.compactMap { if case let .windowAction(action) = $0 { LegacyWindowAction(action: action, id: action.id) } else { nil } }
        } else { self.cycle = nil }
    }

    func convertToWindowAction() -> WindowAction {
        var action = WindowAction(direction)
        if let id { action = action.withRuntimeID(id) }
        action.name = name
        if direction == .cycle {
            let steps = (cycle ?? []).filter { step in
                if step.direction == .cycle { Migrator.log.warn("Dropped a cycle nested in the cycle \(name ?? "Cycle")") }
                return step.direction != .cycle
            }
            action.kind = .cycle(.init(name: name, steps: steps.map { .windowAction($0.convertToWindowAction()) }))
        } else if direction == .custom || direction == .stash {
            func length(_ value: Double?, _ dimensionUnit: CustomWindowActionUnit?) -> ScreenLength? {
                value.flatMap { value in
                    let lengthUnit: ScreenLength.Unit = (dimensionUnit ?? unit) == .pixels ? .points : .percent
                    return ScreenLength(value, unit: lengthUnit)
                }
            }
            let widthLength = length(width, widthUnit)
            let heightLength = length(height, heightUnit)
            switch sizeMode ?? .custom {
            case .custom: action.size = .custom(width: widthLength, height: heightLength)
            case .preserve: action.size = .preserve
            case .initial: action.size = .initial
            }
            action.customDimensions = .init(width: widthLength, height: heightLength)
            if positionMode == .coordinates { action.position = .coordinates(x: length(xPoint, xUnit) ?? (unit == .pixels ? ScreenLength(0, unit: .points) : nil), y: length(yPoint, yUnit) ?? (unit == .pixels ? ScreenLength(0, unit: .points) : nil)) }
            else { action.position = .anchor(anchor ?? .none) }
        }
        return action
    }

    func convertToKeyBinding() -> KeyBinding {
        KeyBinding(id: id ?? UUID(), configID: configID, keys: KeyCombination(keyCodes: keybind), bypassTriggerKey: bypassTriggerKey, target: .windowAction(convertToWindowAction()))
    }
}
