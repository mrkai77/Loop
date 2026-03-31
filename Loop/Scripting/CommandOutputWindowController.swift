//
//  CommandOutputWindowController.swift
//  Loop
//
//  Created by Codex on 2026-03-28.
//

import AppKit

@MainActor
final class CommandOutputWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum ToolbarIdentifier {
        static let toolbar = NSToolbar.Identifier("LoopCommandOutputToolbar")
        static let copy = NSToolbarItem.Identifier("LoopCommandOutputCopy")
    }

    private let output: String
    private let onClose: () -> ()

    init(title: String, content: String, onClose: @escaping () -> ()) {
        self.output = content
        self.onClose = onClose

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = content
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false

        scrollView.documentView = textView

        let contentView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 720, height: 560))
        contentView.material = .popover
        contentView.blendingMode = .behindWindow
        contentView.state = .active
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 480, height: 320)
        window.isReleasedWhenClosed = false
        window.contentView = contentView

        super.init(window: window)

        self.window?.delegate = self
        self.window?.toolbar = makeToolbar()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        showWindow(self)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func windowWillClose(_: Notification) {
        onClose()
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
        [ToolbarIdentifier.copy]
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarIdentifier.copy]
    }

    func toolbar(
        _: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        guard itemIdentifier == ToolbarIdentifier.copy else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Copy"
        item.paletteLabel = "Copy"
        item.toolTip = "Copy output to the clipboard"
        item.target = self
        item.action = #selector(copyOutput(_:))

        if let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy") {
            item.image = image
        }

        return item
    }
}
