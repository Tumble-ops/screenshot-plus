#if DEBUG
import AppKit
import ScreenshotPlusCore

/// Debug-build only: lets scripts drive the notch for automated checks, e.g.
///
///     swift scripts/notch-debug.swift "drop-file:/path/to/shot.png"
///
/// Drop commands go through the real NSDraggingDestination code with a stand-in
/// NSDraggingInfo, so the import path is the same one a real drag uses.
@MainActor
final class DebugHooks: NSObject {
    private let controller: NotchController
    private let hostingView: () -> NotchHostingView?

    init(controller: NotchController, hostingView: @escaping () -> NotchHostingView?) {
        self.controller = controller
        self.hostingView = hostingView
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(received(_:)), name: Notification.Name("app.screenshotplus.debug"), object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func received(_ note: Notification) {
        guard let command = note.object as? String else { return }
        MainActor.assumeIsolated { run(command) }
    }

    private func run(_ command: String) {
        let model = controller.model
        let (verb, argument) = command.split(separator: ":", maxSplits: 1).map(String.init).splitPair
        NSLog("Screenshot+ debug: \(verb) \(argument)")
        switch verb {
        case "open":
            controller.openFromMenu()
        case "settings":
            controller.openSettings()
        case "set":
            // set:key=value for quick visual checks, e.g. set:surface=midnight
            let pair = argument.split(separator: "=").map(String.init)
            guard pair.count == 2 else { return }
            let settings = AppSettings.shared
            switch pair[0] {
            case "accent": settings.accent = AppSettings.Accent(rawValue: pair[1]) ?? settings.accent
            case "surface": settings.surface = AppSettings.Surface(rawValue: pair[1]) ?? settings.surface
            case "size": settings.panelSize = AppSettings.PanelSize(rawValue: pair[1]) ?? settings.panelSize
            case "remove": settings.removeAfterDragOut = pair[1] == "on"
            case "expiry": settings.expiry = AppSettings.Expiry(rawValue: pair[1]) ?? settings.expiry
            default: break
            }
        case "freeze":
            controller.debugFreeze = argument != "off"
        case "collapse":
            model.collapse()
        case "dropzone":
            model.awaitingPointerEntry = true
            model.mode = .dropZone
            model.isDropTargeted = argument == "targeted"
        case "drop-file", "drop-data", "drop-promise":
            model.awaitingPointerEntry = true
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.screenshotplus.debug.drag"))
            pasteboard.clearContents()
            let url = URL(fileURLWithPath: argument)
            switch verb {
            case "drop-file":
                pasteboard.writeObjects([url as NSURL])
            case "drop-data":
                pasteboard.setData(try? Data(contentsOf: url), forType: .png)
            default:
                let provider = DebugPromiseProvider(url: url)
                pasteboard.writeObjects([provider])
                DebugPromiseProvider.retained = provider
            }
            let info = FakeDraggingInfo(pasteboard: pasteboard)
            guard let view = hostingView() else { return }
            let entered = view.draggingEntered(info)
            let accepted = view.performDragOperation(info)
            view.concludeDragOperation(info)
            NSLog("Screenshot+ debug: entered=\(entered.rawValue) accepted=\(accepted)")
        case "drop-pasteboard":
            // Drop whatever another process put on the named pasteboard.
            model.awaitingPointerEntry = true
            let info = FakeDraggingInfo(pasteboard: NSPasteboard(name: NSPasteboard.Name(argument)))
            guard let view = hostingView() else { return }
            let entered = view.draggingEntered(info)
            let accepted = view.performDragOperation(info)
            NSLog("Screenshot+ debug: entered=\(entered.rawValue) accepted=\(accepted)")
        case "click", "scroll":
            // In-process synthetic events at a point given in screen coordinates (top-left origin).
            guard let window = hostingView()?.window, let screen = window.screen ?? NSScreen.screens.first else { return }
            let parts = argument.split(separator: ",").compactMap { Double($0) }
            guard parts.count >= 2 else { return }
            let screenPoint = NSPoint(x: parts[0], y: screen.frame.maxY - parts[1])
            let point = window.convertPoint(fromScreen: screenPoint)
            if verb == "click" {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        window.sendEvent(event)
                    }
                }
            } else if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(parts.count > 2 ? parts[2] : -120), wheel2: 0, wheel3: 0) {
                cg.location = CGPoint(x: parts[0], y: parts[1])
                if let event = NSEvent(cgEvent: cg) {
                    let hit = window.contentView?.hitTest(window.contentView!.convert(point, from: nil))
                    NSLog("Screenshot+ debug: scroll hit=\(String(describing: hit.map { type(of: $0) })) enclosing=\(String(describing: hit?.enclosingScrollView)) loc=\(event.locationInWindow) vs \(point)")
                    hit?.scrollWheel(with: event)
                }
            }
        case "payload":
            // Write exactly what a drag would carry to a named pasteboard, and save the note pill.
            guard let shot = model.store.shots.first(where: \.hasNote), let thumb = model.store.thumbnail(for: shot) else { return }
            let payload = model.dragPayload(for: shot, image: thumb)
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("app.screenshotplus.debug.payload"))
            pasteboard.clearContents()
            pasteboard.writeObjects([payload.writer] + payload.companions.map(\.writer))
            for (index, item) in (pasteboard.pasteboardItems ?? []).enumerated() {
                NSLog("Screenshot+ debug: item \(index): \(item.types.map(\.rawValue)) url=\(item.string(forType: .fileURL) ?? "-") text=\(item.string(forType: .string) ?? "-")")
            }
            if let pill = payload.companions.first?.image, let tiff = pill.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: argument))
            }
        case "note":
            model.draft?.note = argument
        case "save":
            model.saveDraft()
        case "detail":
            if let first = model.store.shots.first {
                model.awaitingPointerEntry = true
                model.showDetail(first.id)
            }
        case "search":
            model.searchText = argument
        case "toast":
            model.showToast(argument == "note" ? .noteCopied : .saved)
        case "notice":
            model.showNotice("doc.on.clipboard.fill", "Note copied — paste with ⌘V")
        case "send":
            // Simulates a completed drag-out of the newest screenshot.
            if let first = model.store.shots.first {
                model.dragDidBegin(first)
                model.dragDidEnd(operation: .copy)
            }
        case "drag-begin":
            if let first = model.store.shots.first { model.dragDidBegin(first) }
        case "dump":
            let titles = model.store.shots.prefix(5).map { "\($0.title) | note: \($0.note)" }
            NSLog("Screenshot+ debug: mode=\(model.mode) draft=\(model.draft?.images.count ?? 0) shots=\(model.store.shots.count) \(titles)")
        default:
            NSLog("Screenshot+ debug: unknown command \(command)")
        }
    }
}

private extension Array where Element == String {
    var splitPair: (String, String) { (first ?? "", count > 1 ? self[1] : "") }
}

/// Stand-in for the drag info AppKit passes to a drop destination.
private final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    init(pasteboard: NSPasteboard) { draggingPasteboard = pasteboard }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?,
                                classes classArray: [AnyClass], searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
                                using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    func resetSpringLoading() {}
}

/// Promises a copy of a file, like a browser or the screenshot thumbnail might.
private final class DebugPromiseProvider: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
    static var retained: DebugPromiseProvider?
    let url: URL

    init(url: URL) {
        self.url = url
        super.init()
        fileType = "public.png"
        delegate = self
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        url.lastPathComponent
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo destination: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
#endif
