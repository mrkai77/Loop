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
import Tome

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

        if let firstAction = WindowActionCache.shared.radialMenuActions.first {
            setPreviewedAction(to: firstAction)
        }
    }

    func show() {
        if controller == nil {
            let window = LuminareWindow {
                SettingsContentView(model: self)
                    .frame(height: 620)
            }

            SkyLightToolBelt.setBackgroundBlur(
                windowID: CGWindowID(window.windowNumber),
                radius: 20
            )

            window.backgroundColor = .white.withAlphaComponent(0.001)
            window.ignoresMouseEvents = false

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

    func close() {
        if let controller {
            controller.close()
            self.controller = nil

            log.success("Settings window closed")
        }

        stopTimer()

        if !Tome.showDockIcon {
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
                  let cycle = parent.resolvedCycleSteps,
                  let index = cycle.firstIndex(of: previewedAction)
            else {
                return
            }

            let nextIndex = (index + 1) % cycle.count
            setPreviewedAction(to: parent, cycleAction: cycle[nextIndex])
        } else {
            let radialMenuActions = WindowActionCache.shared.radialMenuActions

            let nextAction = if let index = radialMenuActions.firstIndex(of: previewedParentAction ?? previewedAction) {
                radialMenuActions[(index + 1) % radialMenuActions.count]
            } else {
                radialMenuActions.first ?? .init(.noAction)
            }

            setPreviewedAction(to: nextAction)
        }
    }

    /// Reads from `bindings` rather than `selection`, so an edited target shows at once.
    func previewSelection<Binding: ActionBinding>(_ selection: Set<Binding>, in bindings: [Binding], graph: ActionTargetEditorGraph) {
        if selection.count == 1, let selected = selection.first,
           let current = bindings.first(where: { $0.id == selected.id }),
           let action = graph.previewAction(for: current.target) {
            isPreviewingUserSelection = true
            setPreviewedAction(to: action)
        } else {
            isPreviewingUserSelection = false
        }
    }

    /// `newAction` must have its cycle steps resolved (see `ActionTargetEditorGraph.previewAction(for:)`).
    func setPreviewedAction(to newAction: WindowAction, cycleAction: WindowAction? = nil) {
        if newAction.direction == .cycle {
            previewedParentAction = newAction
            previewedAction = cycleAction ?? newAction.resolvedCycleSteps?.first ?? .init(.noAction)
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
