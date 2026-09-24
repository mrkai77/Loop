//
//  WindowActionIndicatorService.swift
//  Loop
//
//  Created by Kai Azim on 2026-01-19.
//

import AppKit
import Defaults

@MainActor
final class WindowActionIndicatorService {
    private let radialMenuController = RadialMenuController()
    private let previewController = PreviewController()

    func openAndUpdate(
        context: ResizeContext,
        hideOnNoSelection: Bool
    ) {
        if hideOnNoSelection,
           context.action.direction == .noSelection {
            // The radial menu caches its selected action across presentations, so it must receive
            // `.noSelection`. The preview has no selection state and should only be closed here.
            radialMenuController.update(context: context)
            closeAll()
            return
        }

        if Defaults[.previewVisibility] {
            previewController.open(context: context)
        }

        if Defaults[.radialMenuVisibility] {
            radialMenuController.open(context: context)
        }
    }

    func closeAll() {
        radialMenuController.close()
        previewController.close()
    }
}
