//
//  RadialMenuController.swift
//  Loop
//
//  Created by Kai Azim on 2023-01-23.
//

import Defaults
import Scribe
import SwiftUI

@Loggable
@MainActor
final class RadialMenuController: WindowActionIndicator {
    private var viewModel: RadialMenuViewModel = .init(isSettingsPreview: false)
    private var controller: NSWindowController?
    private var closeTask: Task<(), Never>?

    func update(context: ResizeContext) {
        viewModel.updateContext(with: context)
    }

    func open(context: ResizeContext) {
        update(context: context)

        closeTask?.cancel()
        closeTask = nil

        if let window = controller?.window {
            viewModel.setIsShown(true, animationDuration: 0.1)
            window.orderFrontRegardless()
            return
        }

        let mouseX: CGFloat = context.initialMousePosition.x
        let mouseY: CGFloat = context.initialMousePosition.y
        let windowSize: CGFloat = 100 + 80

        let panel = ActivePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        controller = .init(window: panel)

        panel.ignoresMouseEvents = true
        panel.collectionBehavior = .canJoinAllSpaces
        panel.hasShadow = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.contentView = NSHostingView(rootView: RadialMenuView(viewModel: viewModel))

        // Position the panel
        if Defaults[.lockRadialMenuToCenter], let screen = NSScreen.main {
            // Position at the center of the screen
            let screenFrame = screen.frame
            panel.setFrameOrigin(
                NSPoint(
                    x: screenFrame.midX - windowSize / 2,
                    y: screenFrame.midY - windowSize / 2
                )
            )
        } else {
            // Position at the mouse cursor
            panel.setFrameOrigin(
                NSPoint(
                    x: mouseX - windowSize / 2,
                    y: mouseY - windowSize / 2
                )
            )
        }

        panel.orderFrontRegardless()

        log.ui("Initialized controller")
    }

    func close() {
        guard controller != nil else { return }
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            guard let self else { return }
            viewModel.setIsShown(false, animationDuration: 0.15)
            try? await Task.sleep(for: .seconds(0.15))
            guard !Task.isCancelled else { return }
            controller?.window?.orderOut(nil)
            controller?.close()
            controller = nil
            closeTask = nil
            log.ui("Controller closed")
        }
    }
}
