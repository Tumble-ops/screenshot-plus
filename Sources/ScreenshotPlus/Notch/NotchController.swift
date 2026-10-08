import AppKit
import ScreenshotPlusCore
import SwiftUI

/// Owns the notch panel and decides when it opens and closes.
///
/// The panel has a fixed frame big enough for the largest state, but it ignores
/// the mouse everywhere except over the visible black surface, so the menu bar
/// and apps underneath keep working. Pointer position comes from global/local
/// mouse monitors (no Accessibility or Screen Recording permission needed) and,
/// only while expanded, a light 30 Hz poll.
@MainActor
final class NotchController: NSObject, NSWindowDelegate {
    let model: NotchModel
    private var panel: NotchPanel!
    private var hostingView: NotchHostingView!
    private let sensor = NotchSensorPanel()

    private var monitors: [Any] = []
    private var trackingTimer: Timer?
    private var hoverWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?
    private var focusRestoreWork: DispatchWorkItem?

    /// Drag pasteboard change count at the last mouse-down; a different value while
    /// the mouse is dragged means a drag-and-drop session is in progress.
    private var dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var dragCheck: (changeCount: Int, isImage: Bool)?

    init(store: ShotStore) {
        let metrics = NotchMetrics.preferredScreen().map(NotchMetrics.measure)
            ?? NotchMetrics(notchSize: CGSize(width: 170, height: 24), hasNotch: false, centerX: 0, top: 0)
        model = NotchModel(store: store, metrics: metrics)
        super.init()
    }

    func start() {
        panel = NotchPanel(contentRect: .zero)
        hostingView = NotchHostingView(rootView: NotchRootView(model: model))
        hostingView.dropHandler = DropHandler(model: model)
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.delegate = self

        sensor.sensorView.dropHandler = DropHandler(model: model)
        sensor.sensorView.onHover = { [weak self] inside in
            guard let self, inside, !self.model.mode.isExpanded, NSEvent.pressedMouseButtons == 0 else { return }
            self.scheduleHoverOpen()
        }
        sensor.sensorView.onClick = { [weak self] in
            guard let self, !self.model.mode.isExpanded else { return }
            self.cancelHover()
            self.model.open()
        }

        layoutPanel()
        sensor.orderFrontRegardless()
        panel.orderFrontRegardless()  // above the sensor

        model.onModeChange = { [weak self] old, new in self?.modeChanged(from: old, to: new) }
        model.isPointerInsideSurface = { [weak self] in self?.pointerInsideShape(margin: 14) ?? false }
        installMonitors()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil
        )
    }

    #if DEBUG
    var debugHostingView: NotchHostingView? { hostingView }
    #endif

    /// Opens the library from the menu bar item.
    func openFromMenu() {
        model.awaitingPointerEntry = true
        model.open()
    }

    // MARK: - Geometry

    private func layoutPanel() {
        let maxSize = model.maximumShapeSize
        let pad = NotchModel.shadowPadding
        let size = CGSize(width: maxSize.width + 2 * pad, height: maxSize.height + pad)
        let frame = CGRect(x: model.metrics.centerX - size.width / 2, y: model.metrics.top - size.height,
                           width: size.width, height: size.height)
        panel.setFrame(frame.integral, display: true)

        let notch = model.metrics.notchSize
        sensor.setFrame(CGRect(x: model.metrics.centerX - notch.width / 2, y: model.metrics.top - notch.height,
                               width: notch.width, height: notch.height), display: true)
    }

    /// The visible black surface for a mode, in screen coordinates.
    private func shapeRect(_ mode: NotchMode? = nil) -> CGRect {
        let size = model.shapeSize(for: mode ?? model.mode)
        return CGRect(x: model.metrics.centerX - size.width / 2, y: model.metrics.top - size.height,
                      width: size.width, height: size.height)
    }

    /// Region that opens the notch on hover. Slightly taller than the notch so the
    /// very top row of pixels counts.
    private var hoverRect: CGRect {
        let rect = shapeRect(.collapsed)
        return CGRect(x: rect.minX - 4, y: rect.minY - 4, width: rect.width + 8, height: rect.height + 8)
    }

    /// Dragging an image into this region (around and below the notch) opens the drop zone.
    private var dragApproachRect: CGRect {
        let notch = model.notchSize
        let top = model.metrics.top
        return CGRect(x: model.metrics.centerX - notch.width / 2 - 160, y: top - notch.height - 130,
                      width: notch.width + 320, height: notch.height + 134)
    }

    private func pointerInsideShape(margin: CGFloat = 0) -> Bool {
        let rect = shapeRect().insetBy(dx: -margin, dy: -margin)
        return rect.contains(NSEvent.mouseLocation)
    }

    // MARK: - Mode changes

    private func modeChanged(from old: NotchMode, to new: NotchMode) {
        cancelCollapse()
        cancelHover()
        if new.isExpanded { startTracking() } else { stopTracking() }

        if new == .compose {
            // Take keyboard focus for the note field without activating the app.
            focusRestoreWork?.cancel()
            panel.makeKey()
        }
        if !new.isExpanded { restoreFocusSoon() }
        updateMouseIgnoring()
    }

    /// Hands keyboard focus back to the app the user was in after the panel closes.
    private func restoreFocusSoon() {
        focusRestoreWork?.cancel()
        guard panel.isKeyWindow else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.mode.isExpanded, self.panel.isKeyWindow else { return }
            self.panel.makeFirstResponder(nil)
            self.panel.orderOut(nil)
            self.panel.orderFrontRegardless()
        }
        focusRestoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
    }

    // MARK: - Pointer tracking

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, isGlobal: true) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, isGlobal: false) }
            return event
        }) {
            monitors.append(local)
        }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event) ?? event }
        }) {
            monitors.append(keys)
        }
    }

    private func handle(_ event: NSEvent, isGlobal: Bool) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            dragCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            dragCheck = nil
            // A click anywhere else closes the panel.
            if isGlobal, model.mode.isExpanded, model.mode != .dropZone, !pointerInsideShape() {
                model.collapse()
            }
        case .leftMouseUp:
            if model.mode == .dropZone { scheduleCollapse(after: 0.35) }
        default:
            break
        }
        pointerMoved(dragging: event.type == .leftMouseDragged)
    }

    private func startTracking() {
        guard trackingTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pointerMoved(dragging: NSEvent.pressedMouseButtons & 1 != 0)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackingTimer = timer
    }

    private func stopTracking() {
        trackingTimer?.invalidate()
        trackingTimer = nil
    }

    private func updateMouseIgnoring() {
        let rect = shapeRect()
        let hitRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height + 4)
        let ignore = !hitRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents != ignore { panel.ignoresMouseEvents = ignore }
    }

    private func isExternalImageDrag() -> Bool {
        guard !model.isDraggingOut else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragCountAtMouseDown else { return false }
        if let check = dragCheck, check.changeCount == pasteboard.changeCount { return check.isImage }
        let isImage = ImageImporter.canImport(from: pasteboard)
        dragCheck = (pasteboard.changeCount, isImage)
        return isImage
    }

    #if DEBUG
    /// Lets debug scripts hold a state (e.g. the drop zone) without a real drag in progress.
    var debugFreeze = false
    #endif

    private func pointerMoved(dragging: Bool) {
        updateMouseIgnoring()
        #if DEBUG
        if debugFreeze { return }
        #endif
        let point = NSEvent.mouseLocation
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        let imageDrag = dragging && buttonDown && isExternalImageDrag()

        switch model.mode {
        case .collapsed, .toast:
            if imageDrag && dragApproachRect.contains(point) {
                model.mode = .dropZone
            } else if !buttonDown && hoverRect.contains(point) {
                scheduleHoverOpen()
            } else {
                cancelHover()
            }

        case .dropZone:
            if model.isImporting {
                cancelCollapse()
            } else if buttonDown {
                let keep = shapeRect().insetBy(dx: -70, dy: -70).union(dragApproachRect)
                if keep.contains(point) { cancelCollapse() } else { scheduleCollapse(after: 0.25) }
            } else {
                scheduleCollapse(after: 0.35)
            }

        case .compose, .library, .detail:
            if imageDrag && model.mode != .compose && shapeRect().contains(point) {
                model.mode = .dropZone
                return
            }
            if pointerInsideShape(margin: 14) {
                model.awaitingPointerEntry = false
                cancelCollapse()
            } else if shouldStayOpen {
                cancelCollapse()
            } else {
                scheduleCollapse(after: 0.32)
            }
        }
    }

    /// The panel stays open while the user is busy with it, even if the pointer wanders.
    private var shouldStayOpen: Bool {
        if model.awaitingPointerEntry || model.isDraggingOut { return true }
        guard panel.isKeyWindow else { return false }
        return model.isTextFieldFocused || model.mode == .compose
    }

    private func scheduleHoverOpen() {
        guard hoverWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverWork = nil
            guard !self.model.mode.isExpanded, NSEvent.pressedMouseButtons == 0,
                  self.hoverRect.contains(NSEvent.mouseLocation) else { return }
            self.model.open()
        }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func cancelHover() {
        hoverWork?.cancel()
        hoverWork = nil
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        guard collapseWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWork = nil
            guard self.model.mode.isExpanded, !self.model.isImporting else { return }
            if self.model.mode == .dropZone, NSEvent.pressedMouseButtons & 1 != 0,
               self.dragApproachRect.contains(NSEvent.mouseLocation) { return }
            self.model.collapse()
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelCollapse() {
        collapseWork?.cancel()
        collapseWork = nil
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }
        // Don't steal keys from an input method that's composing text.
        if let textView = panel.firstResponder as? NSTextView, textView.hasMarkedText() { return event }

        switch event.keyCode {
        case 53: // Escape
            if model.isTextFieldFocused, case .detail = model.mode {
                panel.makeFirstResponder(nil)
            } else {
                model.handleEscape()
            }
            return nil
        case 36, 76: // Return, Enter
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if model.mode == .compose, flags.isDisjoint(with: [.shift, .option]) {
                model.saveDraft()
                return nil
            }
            return event
        default:
            return event
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        model.isTextFieldFocused = false
        guard model.mode.isExpanded, model.mode != .dropZone, !model.isDraggingOut else { return }
        if !pointerInsideShape(margin: 14) { model.collapse() }
    }

    // MARK: - Displays and Spaces

    @objc private func screenParametersChanged() {
        guard let screen = NotchMetrics.preferredScreen() else { return }
        let metrics = NotchMetrics.measure(screen)
        if metrics != model.metrics { model.metrics = metrics }
        layoutPanel()
    }

    @objc private func activeSpaceChanged() {
        sensor.orderFrontRegardless()
        panel.orderFrontRegardless()
    }
}
