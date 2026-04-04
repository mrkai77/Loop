//
//  CommandOutputWindowManager.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-28.
//

import AppKit

@MainActor
final class CommandOutputWindowManager {
    static let shared = CommandOutputWindowManager()

    private var controllers: [UUID: CommandOutputWindowController] = [:]
    private var cascadePoint: NSPoint?

    private init() {}

    func show(title: String, content: String) {
        let identifier = UUID()
        let controller = CommandOutputWindowController(
            title: title,
            content: content
        ) { [weak self] in
            self?.removeController(for: identifier)
        }

        controllers[identifier] = controller

        if let window = controller.window {
            let origin = cascadePoint ?? initialCascadePoint()
            cascadePoint = window.cascadeTopLeft(from: origin)
        }

        controller.show()
    }

    private func removeController(for identifier: UUID) {
        controllers.removeValue(forKey: identifier)

        if controllers.isEmpty {
            cascadePoint = nil
        }
    }

    private func initialCascadePoint() -> NSPoint {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            return NSPoint(
                x: screen.visibleFrame.minX + 80,
                y: screen.visibleFrame.maxY - 80
            )
        }

        return NSPoint(x: 120, y: 800)
    }
}
