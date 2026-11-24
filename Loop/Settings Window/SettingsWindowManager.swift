//
//  SettingsWindowManager.swift
//  Loop
//
//  Created by Kai Azim on 2024-05-28.
//

import Combine
import Defaults
import Luminare
import Scribe
import SwiftUI

@Loggable
@MainActor
final class SettingsWindowManager: ObservableObject {
    static let shared = SettingsWindowManager()
    private var controller: NSWindowController?
    private var previewActionTimerTask: Task<(), Error>?

    @Published var isPreviewingUserSelection: Bool = false {
        didSet { restartTimerIfNeeded() }
    }

    @Published private(set) var previewedParentAction: WindowAction? = nil
    @Published private(set) var previewedAction: WindowAction = .init(.noSelection) {
        didSet { updatePreviewContexts() }
    }

    private(set) var previewBounds: CGRect = .zero
    private(set) var didSetBounds: Bool = false

    @Published var showRadialMenu: Bool = true
    @Published var showPreview: Bool = true

    @Published var currentTab: SettingsTab = .icon {
        didSet {
            if currentTab == .radialMenu {
                showRadialMenu = true
                showPreview = false
            } else if currentTab == .preview {
                showRadialMenu = false
                showPreview = true
            } else {
                showRadialMenu = true
                showPreview = true
            }
        }
    }

    @Published var showInspector: Bool = Defaults[.showSettingsInspector] {
        didSet {
            Defaults[.showSettingsInspector] = showInspector

            if showInspector {
                startTimer()
            } else {
                stopTimer()
            }
        }
    }

    let radialMenuViewModel: RadialMenuViewModel
    let previewViewModel: PreviewViewModel

    var window: NSWindow? {
        controller?.window
    }

    private init() {
        self.radialMenuViewModel = .init(isSettingsPreview: true)
        self.previewViewModel = .init(isSettingsPreview: true)

        if let firstAction = RadialMenuAction.userConfiguredActions.first?.resolved {
            setPreviewedAction(to: firstAction)
        }
    }

    func show() {
        if controller == nil {
            let window = LuminareWindow {
                SettingsContentView(model: self)
                    .frame(height: 620)
            }

            controller = NSWindowController(window: window)
        }

        NSApp.setActivationPolicy(.regular)

        if showInspector {
            startTimer()
        }

        controller?.showWindow(self)
        window?.orderFrontRegardless()

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        log.success("Settings window opened")
    }

    /// Hides the Dock icon while the settings window is closed, unless the user wants it shown
    func hideDockIconIfUnused() {
        guard controller == nil, !Defaults[.showDockIcon] else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
    }

    func close() {
        if let controller {
            controller.close()
            self.controller = nil

            log.success("Settings window closed")
        }

        stopTimer()

        if !Defaults[.showDockIcon] {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func restartTimerIfNeeded() {
        guard showInspector else { return }

        stopTimer()
        startTimer(immediatelySelectNext: true)
    }

    private func startTimer(immediatelySelectNext: Bool = false) {
        previewActionTimerTask?.cancel()
        previewActionTimerTask = Task(priority: .utility) {
            if !immediatelySelectNext {
                try await Task.sleep(for: .seconds(1))
            }

            while !Task.isCancelled {
                if NSApp.isActive {
                    setNextPreviewedAction()
                }

                try await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopTimer() {
        previewActionTimerTask?.cancel()
        previewActionTimerTask = nil
    }

    private func setNextPreviewedAction() {
        if isPreviewingUserSelection {
            guard let parent = previewedParentAction,
                  parent.direction == .cycle,
                  let cycle = parent.cycle,
                  let index = cycle.firstIndex(of: previewedAction)
            else {
                return
            }

            let nextIndex = (index + 1) % cycle.count
            setPreviewedAction(to: parent, cycleAction: cycle[nextIndex])
        } else {
            let radialMenuActions: [WindowAction] = RadialMenuAction.userConfiguredActions
                .compactMap(\.resolved)

            let nextAction = if let index = radialMenuActions.firstIndex(of: previewedParentAction ?? previewedAction) {
                radialMenuActions[(index + 1) % radialMenuActions.count]
            } else {
                radialMenuActions.first ?? .init(.noAction)
            }

            setPreviewedAction(to: nextAction)
        }
    }

    func setPreviewedAction(to newAction: WindowAction, cycleAction: WindowAction? = nil) {
        if newAction.direction == .cycle {
            previewedParentAction = newAction
            previewedAction = cycleAction ?? newAction.cycle?.first ?? .init(.noAction)
        } else {
            previewedParentAction = nil
            previewedAction = newAction
        }
    }

    func setPreviewBounds(_ bounds: CGRect) {
        previewBounds = bounds
        didSetBounds = true

        updatePreviewContexts()
    }

    private func updatePreviewContexts() {
        guard didSetBounds else {
            return
        }

        let context = ResizeContext(bounds: previewBounds)
        context.setAction(to: previewedAction, parent: previewedParentAction)
        radialMenuViewModel.updateContext(with: context)
        previewViewModel.updateContext(with: context, isScreenSwitch: false)
    }
}
