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

    /// Keeps each controller alive until its window closes
    private var controllers: [CommandOutputWindowController] = []

    private init() {}

    func show(title: String, text: LoopAutomationText, json: String) {
        let controller = CommandOutputWindowController(title: title, text: text, json: json) { [weak self] closed in
            self?.controllers.removeAll { $0 === closed }
        }

        controllers.append(controller)
        controller.show()
    }
}
