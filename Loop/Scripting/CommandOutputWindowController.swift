//
//  CommandOutputWindowController.swift
//  Loop
//
//  Created by Kai Azim on 2026-03-28.
//

import AppKit

@MainActor
final class CommandOutputWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum ToolbarIdentifier {
        static let toolbar = NSToolbar.Identifier("LoopCommandOutputToolbar")
        static let format = NSToolbarItem.Identifier("LoopCommandOutputFormat")
        static let copy = NSToolbarItem.Identifier("LoopCommandOutputCopy")
    }

    private let title: String
    private let text: LoopAutomationText
    private let json: String
    private let onClose: (CommandOutputWindowController) -> ()

    private weak var textView: NSTextView?
    private var showsJSON = false

    private var output: String {
        showsJSON ? json : text.plainText
    }

    init(title: String, text: LoopAutomationText, json: String, onClose: @escaping (CommandOutputWindowController) -> ()) {
        self.title = title
        self.text = text
        self.json = json
        self.onClose = onClose
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// AppKit only loads the window, and cascades it from the previous one, when there's a nib name
    override var windowNibName: NSNib.Name? {
        "CommandOutputWindow"
    }

    override func loadWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.toolbar = makeToolbar()

        let contentView = NSVisualEffectView()
        contentView.material = .popover
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        window.contentView = contentView

        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = contentView.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = false
            textView.usesFindBar = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 12, height: 12)
            textView.textStorage?.setAttributedString(Self.attributedString(for: text))
            self.textView = textView
        }

        // center() uses the window's current screen, so move it to the one with the cursor first
        if let screen = NSScreen.screenWithMouse {
            window.setFrameOrigin(screen.visibleFrame.origin)
        }
        window.center()

        self.window = window
    }

    func show() {
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        showWindow(nil)
        // Activation is only a request since macOS 14, so the window has to come forward even if it's declined
        window?.orderFrontRegardless()
    }

    func windowWillClose(_: Notification) {
        onClose(self)
    }

    @objc private func changeFormat(_ sender: NSToolbarItemGroup) {
        showsJSON = sender.selectedIndex == 1
        let content = showsJSON ? LoopAutomationText(json) : text
        textView?.textStorage?.setAttributedString(Self.attributedString(for: content))
    }

    private static func attributedString(for text: LoopAutomationText) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let regularFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)

        for run in text.runs {
            var attributes: [NSAttributedString.Key: Any] = [
                .font: regularFont,
                .foregroundColor: NSColor.labelColor
            ]

            switch run.style {
            case .plain:
                break
            case .bold:
                attributes[.font] = boldFont
            case .secondary:
                attributes[.foregroundColor] = NSColor.secondaryLabelColor
            case .heading:
                attributes[.font] = boldFont
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }

            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }

        return result
    }

    @objc private func copyOutput(_: Any?) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(output, forType: .string)
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: ToolbarIdentifier.toolbar)
        toolbar.delegate = self
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        return toolbar
    }

    func toolbarAllowedItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarIdentifier.format, ToolbarIdentifier.copy, .space]
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarIdentifier.format, .space, ToolbarIdentifier.copy]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        if itemIdentifier == ToolbarIdentifier.format {
            let item = NSToolbarItemGroup(
                itemIdentifier: itemIdentifier,
                titles: [String(localized: "Text"), String(localized: "JSON")],
                selectionMode: .selectOne,
                labels: nil,
                target: self,
                action: #selector(changeFormat(_:))
            )
            item.label = String(localized: "Format")
            item.paletteLabel = String(localized: "Format")
            item.selectedIndex = 0
            return item
        }

        guard itemIdentifier == ToolbarIdentifier.copy else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = String(localized: "Copy")
        item.paletteLabel = String(localized: "Copy")
        item.toolTip = String(localized: "Copy output to the clipboard")
        item.target = self
        item.action = #selector(copyOutput(_:))

        if let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: String(localized: "Copy")) {
            item.image = image
        }

        return item
    }
}
