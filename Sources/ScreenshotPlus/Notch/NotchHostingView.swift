import AppKit
import ScreenshotPlusCore
import SwiftUI

/// Hosts the SwiftUI notch and acts as the drop destination for screenshots.
final class NotchHostingView: NSHostingView<NotchRootView> {
    var dropHandler: DropHandler?

    required init(rootView: NotchRootView) {
        super.init(rootView: rootView)
        registerForDraggedTypes(ImageImporter.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Clicks work on the first try even though the panel isn't key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
