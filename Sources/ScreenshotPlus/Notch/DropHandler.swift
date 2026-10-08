import AppKit
import ScreenshotPlusCore

/// Drop-destination logic shared by the notch panel and the notch sensor.
///
/// Images are read straight off the drag pasteboard in AppKit (not SwiftUI's
/// `onDrop`) so file URLs, file promises and raw image data all work, and the
/// bytes are copied before the source (e.g. the screenshot thumbnail) cleans up.
@MainActor
struct DropHandler {
    unowned let model: NotchModel

    func accepts(_ info: NSDraggingInfo) -> Bool {
        // Ignore our own drags (a saved screenshot dragged back over the notch).
        guard info.draggingSource == nil else { return false }
        return ImageImporter.canImport(from: info.draggingPasteboard)
    }

    func entered(_ info: NSDraggingInfo) -> NSDragOperation {
        guard accepts(info) else { return [] }
        if model.mode != .compose { model.mode = .dropZone }
        model.isDropTargeted = true
        return .copy
    }

    func updated(_ info: NSDraggingInfo) -> NSDragOperation {
        guard accepts(info) else { return [] }
        model.isDropTargeted = true
        return .copy
    }

    func exited() {
        model.isDropTargeted = false
    }

    func perform(_ info: NSDraggingInfo) -> Bool {
        let pasteboard = info.draggingPasteboard
        let images = ImageImporter.importImmediately(from: pasteboard)
        if !images.isEmpty {
            model.receive(images)
            return true
        }
        let promises = ImageImporter.imagePromises(in: pasteboard)
        guard !promises.isEmpty else { return false }
        model.isImporting = true
        let model = self.model
        ImageImporter.receive(promises, into: model.store.incomingURL) { [weak model] images in
            model?.receive(images)
        }
        return true
    }
}
