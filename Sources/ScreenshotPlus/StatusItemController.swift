import AppKit

/// Menu bar item: the only "chrome" the app has besides the notch itself.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let notch: NotchController

    private let copyNoteItem = NSMenuItem(title: "Copy Note When Dragging Out", action: #selector(toggleCopyNote), keyEquivalent: "")
    private let includeTextItem = NSMenuItem(title: "Drag Note Along with Image", action: #selector(toggleIncludeText), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    init(notch: NotchController) {
        self.notch = notch
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "rectangle.dashed.and.paperclip", accessibilityDescription: "Screenshot+")
                ?? NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: "Screenshot+")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Screenshot+ — drag screenshots onto the notch"
        }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Open Screenshot Inbox", #selector(openInbox)))
        menu.addItem(item("Save Image from Clipboard", #selector(pasteClipboard)))
        menu.addItem(.separator())
        menu.addItem(copyNoteItem)
        menu.addItem(includeTextItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("Show Library in Finder", #selector(revealLibrary)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Screenshot+", #selector(quit), key: "q"))
        for entry in [copyNoteItem, includeTextItem, loginItem] { entry.target = self }
        includeTextItem.toolTip = "Drags the note as text next to the image. Apps that only accept images ignore it; the clipboard copy covers those."
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        copyNoteItem.state = Preferences.copyNoteOnDrag ? .on : .off
        includeTextItem.state = Preferences.includeNoteTextInDrag ? .on : .off
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    @objc private func openInbox() { notch.openFromMenu() }

    @objc private func pasteClipboard() {
        notch.openFromMenu()
        notch.model.pasteFromClipboard()
    }

    @objc private func toggleCopyNote() { Preferences.copyNoteOnDrag.toggle() }

    @objc private func toggleIncludeText() { Preferences.includeNoteTextInDrag.toggle() }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.set(!LaunchAtLogin.isEnabled)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = "\(error.localizedDescription)\n\nMove Screenshot+ to your Applications folder and try again."
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func revealLibrary() {
        NSWorkspace.shared.activateFileViewerSelecting([notch.model.store.imagesURL])
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
