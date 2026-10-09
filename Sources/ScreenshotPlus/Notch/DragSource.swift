import AppKit
import SwiftUI

/// Makes a SwiftUI view draggable into other apps using a real AppKit drag session,
/// and reports clicks and hover (the overlay sits on top, so it owns those events).
struct DragSource: NSViewRepresentable {
    struct Payload {
        var writer: NSPasteboardWriting
        var image: NSImage
        /// Extra items dragged together with the image (the note as text), each with
        /// its own drag image shown just below the picture.
        var companions: [(writer: NSPasteboardWriting, image: NSImage)] = []
    }

    var payload: () -> Payload?
    var onClick: () -> Void = {}
    var onHover: (Bool) -> Void = { _ in }
    var onBegin: () -> Void = {}
    var onEnd: (_ operation: NSDragOperation, _ endedInsideWindow: Bool) -> Void = { _, _ in }
    /// A small button region drawn by SwiftUI underneath (top-left origin, in points).
    /// Clicks there call `onAccessory` instead of opening or dragging. The overlay owns
    /// all mouse events, so the button can't handle them itself.
    var accessoryRect: CGRect?
    var onAccessory: () -> Void = {}
    var onAccessoryHover: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.configuration = self
        return view
    }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.configuration = self
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var configuration: DragSource?
    private var mouseDownEvent: NSEvent?
    private var dragStarted = false
    private var trackingArea: NSTrackingArea?
    private var accessoryPressed = false
    private var overAccessory = false {
        didSet { if overAccessory != oldValue { configuration?.onAccessoryHover(overAccessory) } }
    }

    /// The accessory rect converted from SwiftUI's top-left coordinates.
    private var accessoryFrame: NSRect? {
        guard let rect = configuration?.accessoryRect else { return nil }
        return NSRect(x: rect.minX, y: bounds.height - rect.maxY, width: rect.width, height: rect.height)
    }

    private func isOverAccessory(_ event: NSEvent) -> Bool {
        guard let frame = accessoryFrame else { return false }
        return frame.contains(convert(event.locationInWindow, from: nil))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) { overAccessory = isOverAccessory(event) }

    // Let the gallery scroll when the pointer is over a thumbnail.
    override func scrollWheel(with event: NSEvent) {
        if let scrollView = enclosingScrollView {
            scrollView.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        configuration?.onHover(true)
        overAccessory = isOverAccessory(event)
    }

    override func mouseExited(with event: NSEvent) {
        overAccessory = false
        configuration?.onHover(false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        if let frame = accessoryFrame { addCursorRect(frame, cursor: .arrow) }
    }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        if isOverAccessory(event) {
            accessoryPressed = true
            mouseDownEvent = nil
            return
        }
        mouseDownEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard !accessoryPressed, let down = mouseDownEvent, !dragStarted else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy > 16, let payload = configuration?.payload() else { return }
        dragStarted = true

        let imageFrame = dragFrame(for: payload.image)
        let item = NSDraggingItem(pasteboardWriter: payload.writer)
        item.setDraggingFrame(imageFrame, contents: payload.image)
        var items = [item]
        var top = imageFrame.minY - 6
        for companion in payload.companions {
            let size = companion.image.size
            let frame = NSRect(x: imageFrame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
            let extra = NSDraggingItem(pasteboardWriter: companion.writer)
            extra.setDraggingFrame(frame, contents: companion.image)
            items.append(extra)
            top = frame.minY - 4
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
        configuration?.onBegin()
    }

    override func mouseUp(with event: NSEvent) {
        if accessoryPressed {
            accessoryPressed = false
            if isOverAccessory(event) { configuration?.onAccessory() }
            return
        }
        if mouseDownEvent != nil, !dragStarted { configuration?.onClick() }
        mouseDownEvent = nil
    }

    /// The drag image starts exactly where the picture is drawn (aspect-fit in our bounds).
    private func dragFrame(for image: NSImage) -> NSRect {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = NSSize(width: size.width * scale, height: size.height * scale)
        return NSRect(x: bounds.midX - fitted.width / 2, y: bounds.midY - fitted.height / 2,
                      width: fitted.width, height: fitted.height)
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownEvent = nil
        dragStarted = false
        let inside = window?.frame.contains(screenPoint) ?? false
        configuration?.onEnd(operation, inside)
    }
}
