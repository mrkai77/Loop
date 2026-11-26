//
//  LoopAutomationTests.swift
//  LoopTests
//
//  Created by Kai Azim on 2026-11-22.
//

import CoreGraphics
import Foundation
@testable import Loop
import Testing

/// The ids and spellings here are a contract with scripts, and with the ids Loop will write to its settings file
struct LoopAutomationIdentityTests {
    @Test(arguments: [
        ("HTTPServer", "http-server"),
        ("macOSCenter", "macos-center"),
        ("MoveToSpace12", "move-to-space-12"),
        ("Top Cycle", "top-cycle"),
        ("Maximize + macOS Center", "maximize-macos-center"),
        ("Café Layout", "cafe-layout"),
        ("Left 1/3", "left-1-3"),
        ("日本語", "")
    ])
    func kebabCaseSplitsWordsLikeTheSettingsFile(input: String, expected: String) {
        #expect(LoopAutomationIdentity.kebabCase(input) == expected)
    }

    @Test func repeatedStemsGetNumberedInOrder() {
        #expect(LoopAutomationIdentity.uniqueIDs(for: ["halves", "halves", "portrait", "halves"]) == ["halves", "halves-2", "portrait", "halves-3"])
        #expect(LoopAutomationIdentity.uniqueIDs(for: ["link", "link-2", "link"]) == ["link", "link-2", "link-3"])
    }

    @Test func targetsParseLikeSettingsFileActions() {
        #expect(LoopTarget("left-half") == .action("left-half"))
        #expect(LoopTarget("keybind:portrait") == .binding(.keybind, id: "portrait"))
        #expect(LoopTarget("Radial-Menu:top-cycle") == .binding(.radialMenu, id: "top-cycle"))
        #expect(LoopTarget("gesture:left-half")?.description == "gesture:left-half")
        #expect(LoopTarget("menu:top-cycle") == nil)
        #expect(LoopTarget("keybind:") == nil)
        #expect(LoopTarget(" ") == nil)
    }

    @Test func routesRoundTripThroughURLs() {
        let routes: [LoopRoute] = [
            .list(.radialMenu),
            .run(.action("next-screen")),
            .run(.binding(.keybind, id: "left 1/3"))
        ]

        for route in routes {
            let url = route.url(queryItems: [URLQueryItem(name: "windowID", value: "12")])
            #expect(LoopRoute(string: url.absoluteString) == route, "\(url)")
        }

        // The readable form only parses back when the id has no "/"
        #expect(LoopRoute(string: LoopRoute.run(.binding(.keybind, id: "portrait")).displayString) == .run(.binding(.keybind, id: "portrait")))

        #expect(LoopRoute(string: "loop://list/keybinds") == .list(.keybinds))
        #expect(LoopRoute(string: "loop://run") == nil)
    }
}

struct WindowDirectionAutomationKeyTests {
    @Test(arguments: [
        (WindowDirection.leftHalf, "left-half"),
        (.macOSCenter, "macos-center"),
        (.moveToSpace12, "move-to-space-12"),
        (.focusNextInStack, "focus-next-in-stack"),
        (.topTwoThirds, "top-two-thirds"),
        (.maximize, "maximize"),
        (.noAction, "none")
    ])
    func keysAreTheSettingsFileSpellings(direction: WindowDirection, expected: String) {
        #expect(direction.automationKey == expected)
    }

    @Test func everyKeyIsUnique() {
        let keys = WindowDirection.allCases.map(\.automationKey)
        #expect(Set(keys).count == keys.count)
    }

    @Test(arguments: [
        ("lefthalf", WindowDirection.leftHalf), ("left-half", .leftHalf), ("LeftHalf", .leftHalf),
        ("macoscenter", .macOSCenter), ("MacOSCenter", .macOSCenter),
        ("movetospace12", .moveToSpace12), ("move-to-space12", .moveToSpace12),
        ("noaction", .noAction), ("none", .noAction)
    ])
    func namesMatchWithOrWithoutHyphensAndInAnyCase(input: String, expected: WindowDirection) {
        #expect(WindowDirection.matching(input) == expected)
    }

    @Test func unknownNamesDontMatch() {
        #expect(WindowDirection.matching("sideways") == nil)
    }

    @Test func directionCommandsKeepTheirAliases() {
        #expect(WindowDirection.matchingDirectionCommand("left") == .leftHalf)
        #expect(WindowDirection.matchingDirectionCommand("bottom") == .bottomHalf)
        #expect(WindowDirection.matchingDirectionCommand("RightHalf") == .rightHalf)
        #expect(WindowDirection.matchingDirectionCommand("horizontalcenterhalf") == .horizontalCenterHalf)
    }

    @Test(arguments: [
        ("loop://direction/right", LoopRoute.run(.action("right-half"))),
        ("loop://direction/LeftHalf", .run(.action("left-half"))),
        ("loop://direction/maximize", .run(.action("maximize"))),
        ("loop://screen/next", .run(.action("next-screen"))),
        ("loop://screen/previous", .run(.action("previous-screen"))),
        ("loop://list/all", .list(.actions))
    ])
    @MainActor func urlsFromEarlierVersionsMapOntoCurrentRoutes(url: String, expected: LoopRoute) throws {
        let components = try #require(LoopRoute.pathComponents(of: url))
        #expect(AutomationRequest.legacyRoute(from: components) == expected)
    }

    @Test @MainActor func unknownOlderURLsDontMap() {
        #expect(AutomationRequest.legacyRoute(from: ["direction", "sideways"]) == nil)
        #expect(AutomationRequest.legacyRoute(from: ["screen", "sideways"]) == nil)
    }

    @Test @MainActor func everyDesktopIsListedWhateverTheCurrentCount() {
        let keys = LoopAutomationCatalog.builtInActions().map(\.direction.automationKey)
        for direction in WindowDirection.spaceSwitching {
            #expect(keys.contains(direction.automationKey), "\(direction)")
        }
        #expect(Set(keys).count == keys.count)
    }

    @Test @MainActor func onlyStandaloneActionsAreRunnableBuiltIns() {
        #expect(LoopAutomationCatalog.builtInAction(named: "left-half") == .leftHalf)
        #expect(LoopAutomationCatalog.builtInAction(named: "custom") == nil)
        #expect(LoopAutomationCatalog.builtInAction(named: "cycle") == nil)
        #expect(LoopAutomationCatalog.builtInAction(named: "none") == nil)
    }
}

@MainActor
struct LoopAutomationCatalogTests {
    @Test func keybindIDsComeFromNamesThenActionKeys() {
        let catalog = LoopAutomationCatalog(
            keybinds: [
                WindowAction(.custom, keybind: [.kVK_ANSI_P], name: "Portrait"),
                WindowAction(.custom, keybind: [], name: "Portrait"),
                WindowAction("Halves", cycle: [.init(.leftHalf), .init(.rightHalf)]),
                WindowAction(.leftHalf, keybind: [.kVK_LeftArrow]),
                WindowAction(.custom, keybind: [], name: "日本語"),
                WindowAction(.custom, keybind: [])
            ],
            radialMenuActions: [],
            gestures: []
        )

        let bindings = catalog.keyBindings
        #expect(bindings.map(\.id) == ["portrait", "portrait-2", "halves", "left-half", "custom", "custom-2"])
        #expect(bindings.map(\.target?.description) == ["keybind:portrait", "keybind:portrait-2", "keybind:halves", "keybind:left-half", "keybind:custom", "keybind:custom-2"])
        #expect(bindings.map(\.isActive) == [true, false, false, true, false, false])
    }

    @Test func radialMenuLinksPointAtTheirKeybind() {
        let portrait = WindowAction(.custom, keybind: [.kVK_ANSI_P], name: "Portrait")
        let catalog = LoopAutomationCatalog(
            keybinds: [portrait],
            radialMenuActions: [.keybindReference(portrait.id), .custom(WindowAction(.maximize))],
            gestures: []
        )

        let bindings = catalog.radialMenuBindings
        #expect(bindings.map(\.id) == ["link", "maximize"])
        #expect(bindings[0].linkedTarget == .binding(.keybind, id: "portrait"))
        #expect(bindings[0].action?.id == portrait.id)
        #expect(bindings.map(\.trigger) == ["Slot 1", "Center"])
    }

    @Test func linksToRemovedKeybindsSayWhy() {
        let catalog = LoopAutomationCatalog(
            keybinds: [],
            radialMenuActions: [.keybindReference(UUID()), .custom(WindowAction(.maximize))],
            gestures: []
        )

        let removed = catalog.radialMenuBindings[0]
        #expect(removed.action == nil)
        #expect(removed.note == "Links to a keybind that was removed")
        #expect(catalog.radialMenuBindings[1].note == nil)
    }

    @Test func namesWithoutLatinLettersFallBackToTheActionKey() {
        let catalog = LoopAutomationCatalog(
            keybinds: [
                WindowAction("上側サイクル", cycle: [.init(.topHalf), .init(.topThird)]),
                WindowAction("右側サイクル", cycle: [.init(.rightHalf), .init(.rightThird)])
            ],
            radialMenuActions: [.custom(WindowAction("上側サイクル", cycle: [.init(.topHalf)]))],
            gestures: []
        )

        #expect(catalog.keyBindings.map(\.id) == ["cycle", "cycle-2"])
        #expect(catalog.radialMenuBindings.map(\.id) == ["cycle"])
    }

    @Test func gesturesThatOpenTheRadialMenuCantBeRun() {
        let catalog = LoopAutomationCatalog(
            keybinds: [],
            radialMenuActions: [],
            gestures: [
                GestureBinding(fingerCount: 3, kind: .radialMenu, action: .radialMenuActions),
                GestureBinding(fingerCount: 3, kind: .swipeLeft, action: .singleAction(.custom(WindowAction(.leftHalf))), activationZone: .anywhere),
                GestureBinding(fingerCount: 4, kind: nil, action: .singleAction(.custom(WindowAction(.leftHalf))))
            ]
        )

        let bindings = catalog.gestureBindings
        #expect(bindings.map(\.id) == [nil, "left-half", "left-half-2"])
        #expect(bindings[0].action == nil)
        #expect(bindings[2].isActive == false)
    }
}

struct LoopAutomationJSONTests {
    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func everyKeyIsPresentWithNullsForMissingValues() throws {
        let response = LoopAutomationResponse(
            result: .run(LoopRunResult(target: "keybind:portrait", action: LoopBoundAction(key: "custom", name: "Portrait"), window: nil))
        )
        let json = LoopAutomationJSON.encodeString(response)
        let root = try object(json)
        let result = try #require(root["result"] as? [String: Any])

        #expect(Set(root.keys) == ["version", "success", "result", "error"])
        #expect(root["version"] as? Int == 1)
        #expect(root["error"] is NSNull)
        #expect(Set(result.keys) == ["kind", "target", "action", "window"])
        #expect(result["kind"] as? String == "run")
        #expect(result["window"] is NSNull)

        let decoded = try LoopAutomationJSON.decodeResponse(from: json)
        #expect(decoded.success)
        #expect(decoded.error == nil)
    }

    @Test func responsesFromANewerLoopStillDecode() throws {
        let unknownCode = #"{ "version" : 1, "success" : false, "result" : null, "error" : { "code" : "somethingNew", "message" : "Nope" } }"#
        #expect(try LoopAutomationJSON.decodeResponse(from: unknownCode).error?.code == .failed)

        let unknownKind = #"{ "version" : 1, "success" : true, "result" : { "kind" : "somethingNew" }, "error" : null }"#
        let decoded = try LoopAutomationJSON.decodeResponse(from: unknownKind)
        #expect(decoded.success)
        #expect(decoded.result == nil)
    }

    @Test func missingKeysDecodeAsNil() throws {
        let json = #"{ "version" : 1, "success" : false, "error" : { "code" : "failed", "message" : "Nope" } }"#
        let decoded = try LoopAutomationJSON.decodeResponse(from: json)
        #expect(decoded.result == nil)
        #expect(decoded.error?.replacementRoute == nil)
        #expect(decoded.error?.availableRoutes == nil)
    }

    @Test func failuresCarryAStableCode() throws {
        let json = LoopAutomationJSON.encodedFailure(.notFound, message: "Unknown action: sideways")
        let root = try object(json)
        let error = try #require(root["error"] as? [String: Any])

        #expect(root["result"] is NSNull)
        #expect(error["code"] as? String == "notFound")
        #expect(error["replacementRoute"] is NSNull)
        #expect(error["availableRoutes"] is NSNull)

        let decoded = try LoopAutomationJSON.decodeResponse(from: json)
        #expect(decoded.error?.code == .notFound)
    }
}

struct LoopAutomationFormatterTests {
    /// The table as a terminal without a width limit would show it, without styling
    private func table(_ result: LoopAutomationResult) -> String {
        LoopAutomationFormatter(layout: .table(maxWidth: nil)).format(result).plainText
    }

    private let bindings = LoopAutomationResult.bindingList(LoopBindingListResult(
        bindingKind: .keybind,
        bindings: [
            LoopBindingSummary(kind: .keybind, id: "maximize", target: "keybind:maximize", action: LoopBoundAction(key: "maximize", name: "Maximize"), linkedTarget: nil, trigger: "Trigger + ↩", isActive: true, note: nil),
            LoopBindingSummary(kind: .keybind, id: "halves", target: "keybind:halves", action: LoopBoundAction(key: "cycle", name: "Halves"), linkedTarget: nil, trigger: nil, isActive: false, note: "No keys")
        ]
    ))

    @Test func tablesAlignUnderAHeaderAndHideEmptyColumns() {
        let text = table(bindings)
        #expect(text == """
        TARGET             ACTION     TRIGGER       NOTE
        keybind:maximize   Maximize   Trigger + ↩
        keybind:halves     Halves                   No keys
        """)
    }

    @Test func pipedOutputIsTabSeparatedWithStableColumns() {
        let text = LoopAutomationFormatter(layout: .tabSeparated).format(bindings).plainText
        #expect(text == "keybind:maximize\tMaximize\tTrigger + ↩\t\t\nkeybind:halves\tHalves\t\t\tNo keys")
    }

    @Test func emptyListsOnlyExplainThemselvesInATable() {
        let empty = LoopAutomationResult.bindingList(LoopBindingListResult(bindingKind: .gesture, bindings: []))
        #expect(table(empty) == "No gestures")
        #expect(LoopAutomationFormatter(layout: .tabSeparated).format(empty).isEmpty)
    }

    @Test func theFirstColumnStaysEvenWithoutAnyValues() {
        let gestures = LoopAutomationResult.bindingList(LoopBindingListResult(
            bindingKind: .gesture,
            bindings: [
                LoopBindingSummary(kind: .gesture, id: nil, target: nil, action: nil, linkedTarget: nil, trigger: "2-finger Radial Menu, Title bar", isActive: true, note: "Can’t be run")
            ]
        ))
        #expect(table(gestures) == """
        TARGET   ACTION                  TRIGGER                           NOTE
        —        Opens the radial menu   2-finger Radial Menu, Title bar   Can’t be run
        """)
    }

    @Test func wideCharactersCountAsTwoColumns() {
        #expect(LoopAutomationFormatter.displayWidth(of: "日本語") == 6)
        #expect(LoopAutomationFormatter.displayWidth(of: "🪟 ↩") == 4)
        #expect(LoopAutomationFormatter.truncated("Built-in Retina Display", toWidth: 10) == "Built-in…")
        #expect(LoopAutomationFormatter.truncated("日本語レイアウト", toWidth: 7) == "日本語…")
    }

    @Test func flexibleColumnsShrinkToFitTheTerminal() {
        let windows = LoopAutomationResult.windowList(LoopWindowListResult(windows: [
            LoopWindowSummary(id: 1, bundleID: "com.apple.Safari", appName: "Safari", title: String(repeating: "Long title ", count: 10), frame: LoopRect(x: 0, y: 0, width: 800, height: 600))
        ]))
        let lines = LoopAutomationFormatter(layout: .table(maxWidth: 80)).format(windows).plainText.split(separator: "\n")
        #expect(lines.allSatisfy { LoopAutomationFormatter.displayWidth(of: String($0)) <= 80 })
        #expect(lines.last?.hasSuffix("…") == true)
    }
}

struct AutomationRequestTests {
    private func parse(_ string: String) throws -> Result<AutomationRequest, LoopAutomationError> {
        try AutomationRequest.parse(#require(URL(string: string)))
    }

    @Test func routesAndTheirParametersParse() throws {
        let request = try parse("loop://run/keybind:portrait?windowID=12&screenID=3").get()
        #expect(request.command == .route(.run(.binding(.keybind, id: "portrait"))))
        #expect(request.options == LoopTargetOptions(windowID: 12, screenID: 3))
        #expect(try parse("loop://list/windows").get().command == .route(.list(.windows)))
    }

    @Test func parameterNamesIgnoreCase() throws {
        let request = try parse("loop://run/maximize?BUNDLEID=com.apple.Safari").get()
        #expect(request.options.bundleID == "com.apple.Safari")
    }

    @Test(arguments: [
        ("https://run/maximize", "URLs must start with loop://"),
        ("loop://run/maximize?window=12", "Unknown parameter: window"),
        ("loop://run/maximize?windowID=abc", "Invalid window ID: abc"),
        ("loop://run/maximize?bundleID", "Empty bundle ID"),
        ("loop://run/maximize?windowID=1&bundleID=com.apple.Safari", "windowID and bundleID can’t be used together"),
        ("loop://list/windows?screenID=1", "list doesn’t take windowID, bundleID or screenID"),
        ("loop://list/everything", "Unknown list type: everything"),
        ("loop://run", "No action given"),
        ("loop://dance/now", "Unknown command: dance")
    ])
    func invalidRequestsSayWhy(url: String, message: String) throws {
        guard case let .failure(error) = try parse(url) else {
            Issue.record("\(url) parsed")
            return
        }

        #expect(error.code == .invalidRequest)
        #expect(error.message == message)
    }

    @Test func errorsPointAtWhatExists() throws {
        guard case let .failure(error) = try parse("loop://run/maximize?screenID=main") else {
            Issue.record("An invalid screen ID parsed")
            return
        }

        #expect(error.replacementRoute == "loop://list/screens")
    }

    @Test func olderNameRoutesStillMatchKeybinds() throws {
        #expect(try parse("loop://action/Portrait").get().command == .legacyNamedAction("Portrait", scope: .customOrBuiltIn))
        #expect(try parse("loop://keybind/Portrait").get().command == .legacyNamedAction("Portrait", scope: .keybinds))
        #expect(try parse("loop://direction/customLayout").get().command == .legacyNamedAction("customLayout", scope: .customOrBuiltIn))
        #expect(try parse("loop://direction/right").get().command == .route(.run(.action("right-half"))))
    }
}

struct LoopCommandLineTests {
    @Test(arguments: [
        (LoopRoute.list(.radialMenu), "loop list radial-menu"),
        (.run(.binding(.keybind, id: "portrait")), "loop run keybind:portrait"),
        (.run(.binding(.keybind, id: "my layout")), "loop run 'keybind:my layout'"),
        (.run(.binding(.keybind, id: "it's")), #"loop run 'keybind:it'\''s'"#)
    ])
    func routesBecomeShellSafeInvocations(route: LoopRoute, expected: String) {
        #expect(route.commandLineInvocation(executableName: "loop") == expected)
    }

    @Test func exitCodesFollowSysexits() {
        #expect(LoopAutomationErrorCode.invalidRequest.exitCode == 64)
        #expect(LoopAutomationErrorCode.unavailable.exitCode == 69)
        #expect(LoopAutomationErrorCode.timeout.exitCode == 75)
        #expect(LoopAutomationErrorCode.notFound.exitCode == 1)
        #expect(LoopAutomationErrorCode.failed.exitCode == 1)
    }
}

struct LoopSocketIOTests {
    private func withSocketPair(_ body: (_ client: Int32, _ server: Int32) throws -> ()) throws {
        var descriptors: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        defer { descriptors.forEach { close($0) } }
        try body(descriptors[0], descriptors[1])
    }

    @Test func aRequestIsReadUntilTheClientStopsWriting() throws {
        try withSocketPair { client, server in
            try LoopSocketIO.write("loop://list/windows", to: client)
            shutdown(client, SHUT_WR)
            #expect(try LoopSocketIO.readToEnd(from: server) == "loop://list/windows")
        }
    }

    @Test func requestsPastTheLimitAreRejected() throws {
        try withSocketPair { client, server in
            try LoopSocketIO.write(String(repeating: "a", count: 100), to: client)
            shutdown(client, SHUT_WR)
            #expect(throws: POSIXError(.EMSGSIZE)) { try LoopSocketIO.readToEnd(from: server, limit: 10) }
        }
    }

    @Test func aStalledClientTimesOut() throws {
        try withSocketPair { _, server in
            LoopSocketIO.configure(server, timeout: .seconds(1))
            #expect(throws: POSIXError(.EAGAIN)) { try LoopSocketIO.readToEnd(from: server) }
        }
    }

    @Test func writingToAClosedPeerThrowsInsteadOfRaisingSIGPIPE() throws {
        var descriptors: [Int32] = [0, 0]
        try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let (client, server) = (descriptors[0], descriptors[1])
        defer { close(server) }

        LoopSocketIO.configure(server, timeout: .seconds(1))
        close(client)
        #expect(throws: POSIXError.self) { try LoopSocketIO.write("response", to: server) }
    }
}
