//
//  URLSchemePresenter.swift
//  Loop
//
//  Created by Kai Azim on 2026-11-22.
//

import AppKit

/// What a `loop://` URL shows: a list's output, or an alert when it fails
@MainActor
enum URLSchemePresenter {
    /// `request` is `nil` when the URL couldn't be parsed
    static func present(_ response: LoopAutomationResponse, for request: AutomationRequest?) {
        if let request, request.showsOutput {
            let json = LoopAutomationJSON.encodeString(response)
            CommandOutputWindowManager.shared.show(
                title: String(localized: "Loop Output: \(request.title)", comment: "Title of the window that shows the result of a loop:// list URL. %@ is the command that was run, such as “list windows”."),
                text: response.result.map { LoopAutomationFormatter().format($0) } ?? LoopAutomationText(response.error?.message ?? json),
                json: json
            )
        } else if let error = response.error {
            showFailureAlert(message: error.message)
        }
    }

    private static func showFailureAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "The command couldn’t be run.", comment: "Title of the alert shown when a loop:// URL fails. The reason is shown below it.")
        alert.informativeText = message
        alert.alertStyle = .warning

        let button = alert.addButton(withTitle: String(localized: "OK"))
        if #available(macOS 26.0, *) {
            button.tintProminence = .primary
        }

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
