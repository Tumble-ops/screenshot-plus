import AppKit
import ScreenshotPlusCore

/// A tiny invisible window exactly over the notch. The notch has no pixels and no
/// menu bar items, so this can always accept the mouse without getting in the
/// way. It guarantees that hovering, clicking, or dragging an image onto the
/// notch works even when the main panel is letting events pass through.
final class NotchSensorPanel: NSPanel {
    let sensorView = NotchSensorView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = sensorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class NotchSensorView: NSView {
    var dropHandler: DropHandler?
    var onHover: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(ImageImporter.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Fully transparent windows don't receive clicks, so draw an almost-invisible fill.
    // It sits under the physical notch, which has no pixels anyway.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.01).setFill()
        dirtyRect.fill()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover(true) }
    override func mouseExited(with event: NSEvent) { onHover(false) }
    override func mouseDown(with event: NSEvent) { onClick() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandler?.entered(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandler?.updated(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { dropHandler?.exited() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { dropHandler?.accepts(sender) ?? false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { dropHandler?.perform(sender) ?? false }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { dropHandler?.exited() }
}
