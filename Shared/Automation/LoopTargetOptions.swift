//
//  LoopTargetOptions.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-25.
//

import Foundation

/// Which window and screen `run` acts on, sent as `?windowID=`, `?bundleID=` and `?screenID=`
struct LoopTargetOptions: Equatable {
    enum Problem: Error, Equatable {
        case windowAndBundleID
        case emptyBundleID
    }

    private enum Name: String, CaseIterable {
        case windowID
        case bundleID
        case screenID
    }

    var windowID: UInt32?
    var bundleID: String?
    var screenID: UInt32?

    init(windowID: UInt32? = nil, bundleID: String? = nil, screenID: UInt32? = nil) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.screenID = screenID
    }

    var isEmpty: Bool {
        windowID == nil && bundleID == nil && screenID == nil
    }

    var problem: Problem? {
        if windowID != nil, bundleID != nil {
            return .windowAndBundleID
        }

        if let bundleID, bundleID.trimmingCharacters(in: .whitespaces).isEmpty {
            return .emptyBundleID
        }

        return nil
    }

    var queryItems: [URLQueryItem] {
        [
            windowID.map { URLQueryItem(name: Name.windowID.rawValue, value: String($0)) },
            bundleID.map { URLQueryItem(name: Name.bundleID.rawValue, value: $0) },
            screenID.map { URLQueryItem(name: Name.screenID.rawValue, value: String($0)) }
        ].compactMap(\.self)
    }

    /// Present but malformed values are errors, so a typo can't act on some other window
    init(queryItems: [URLQueryItem]) throws(LoopAutomationError) {
        func name(of item: URLQueryItem) -> Name? {
            Name.allCases.first { $0.rawValue.lowercased() == item.name.lowercased() }
        }

        // So a parameter added later isn't silently ignored by this version
        if let unknown = queryItems.first(where: { name(of: $0) == nil }) {
            throw LoopAutomationError(.invalidRequest, message: "Unknown parameter: \(unknown.name)")
        }

        func value(_ wanted: Name) -> String? {
            queryItems.first { name(of: $0) == wanted }.map { $0.value ?? "" }
        }

        self.init()

        if let windowID = value(.windowID) {
            guard let parsed = UInt32(windowID) else {
                throw LoopAutomationError(.invalidRequest, message: "Invalid window ID: \(windowID)", suggesting: .list(.windows))
            }
            self.windowID = parsed
        }

        self.bundleID = value(.bundleID)

        if let screenID = value(.screenID) {
            guard let parsed = UInt32(screenID) else {
                throw LoopAutomationError(.invalidRequest, message: "Invalid screen ID: \(screenID)", suggesting: .list(.screens))
            }
            self.screenID = parsed
        }

        switch problem {
        case .windowAndBundleID:
            throw LoopAutomationError(.invalidRequest, message: "windowID and bundleID can’t be used together")
        case .emptyBundleID:
            throw LoopAutomationError(.invalidRequest, message: "Empty bundle ID")
        case nil:
            break
        }
    }
}
