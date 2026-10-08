import AppKit
import Observation
import ScreenshotPlusCore
import SwiftUI

enum NotchMode: Equatable {
    case collapsed
    /// A screenshot is being dragged toward the notch.
    case dropZone
    /// Preview + note field for screenshots that were just dropped.
    case compose
    case library
    case detail(UUID)
    /// Small Dynamic-Island-style confirmation in the notch's "ears".
    case toast(Toast)

    var isExpanded: Bool {
        switch self {
        case .compose, .library, .detail, .dropZone: return true
        case .collapsed, .toast: return false
        }
    }
}

struct Toast: Equatable {
    enum Kind { case saved, noteCopied, imageCopied, deleted }
    var kind: Kind
    var id = UUID()

    var symbol: String {
        switch kind {
        case .saved: return "checkmark.circle.fill"
        case .noteCopied: return "doc.on.clipboard.fill"
        case .imageCopied: return "photo.on.rectangle"
        case .deleted: return "trash.fill"
        }
    }

    var text: String {
        switch kind {
        case .saved: return "Saved"
        case .noteCopied: return "Note copied"
        case .imageCopied: return "Copied"
        case .deleted: return "Deleted"
        }
    }

    var tint: Color {
        switch kind {
        case .saved: return Color(red: 0.30, green: 0.85, blue: 0.47)
        case .noteCopied, .imageCopied: return Color(red: 0.38, green: 0.66, blue: 1.0)
        case .deleted: return Color(white: 0.75)
        }
    }
}

/// Screenshots that were dropped but not saved yet.
struct Draft {
    var images: [ImportedImage]
    var previews: [NSImage]
    var note = ""
}

/// A short message shown inside the expanded panel ("Note copied — ⌘V to paste").
struct InlineNotice: Equatable {
    var symbol: String
    var text: String
    var id = UUID()
}

@MainActor
@Observable
final class NotchModel {
    let store: ShotStore

    var mode: NotchMode = .collapsed {
        didSet {
            guard mode != oldValue else { return }
            onModeChange?(oldValue, mode)
        }
    }
    var metrics: NotchMetrics
    var draft: Draft?
    var isDropTargeted = false
    var isImporting = false
    var searchText = ""
    var isDraggingOut = false
    var isTextFieldFocused = false
    var notice: InlineNotice?

    @ObservationIgnored var onModeChange: ((NotchMode, NotchMode) -> Void)?
    /// Set when the panel was opened from the menu bar, so it doesn't collapse
    /// before the pointer has even reached it.
    @ObservationIgnored var awaitingPointerEntry = false
    /// Supplied by the controller, which knows where the surface is on screen.
    @ObservationIgnored var isPointerInsideSurface: () -> Bool = { false }
    @ObservationIgnored private var toastWork: DispatchWorkItem?
    @ObservationIgnored private var noticeWork: DispatchWorkItem?

    init(store: ShotStore, metrics: NotchMetrics) {
        self.store = store
        self.metrics = metrics
    }

    // MARK: - Layout

    static let toastEarWidth: CGFloat = 104
    static let draftEarWidth: CGFloat = 46
    /// Room around the shape for its shadow.
    static let shadowPadding: CGFloat = 28

    var notchSize: CGSize { metrics.notchSize }

    /// Size of the black notch surface for a mode.
    func shapeSize(for mode: NotchMode) -> CGSize {
        let notch = metrics.notchSize
        switch mode {
        case .collapsed:
            if draft != nil {
                return CGSize(width: notch.width + 2 * Self.draftEarWidth, height: notch.height)
            }
            return notch
        case .toast:
            return CGSize(width: notch.width + 2 * Self.toastEarWidth, height: notch.height)
        case .dropZone:
            return CGSize(width: 420, height: notch.height + 136)
        case .compose:
            return CGSize(width: 480, height: notch.height + 300)
        case .library:
            return CGSize(width: 604, height: notch.height + 336)
        case .detail:
            return CGSize(width: 640, height: notch.height + 316)
        }
    }

    var shapeSize: CGSize { shapeSize(for: mode) }

    /// Largest surface any state can need; the panel is sized to fit it.
    var maximumShapeSize: CGSize {
        let modes: [NotchMode] = [.dropZone, .compose, .library, .detail(UUID()), .toast(Toast(kind: .saved))]
        return modes.map { shapeSize(for: $0) }.reduce(.zero) {
            CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
        }
    }

    var cornerRadii: (top: CGFloat, bottom: CGFloat) {
        switch mode {
        case .collapsed: return draft != nil ? (6, 12) : (6, 10)
        case .toast: return (7, 14)
        case .dropZone: return (12, 26)
        default: return (14, 28)
        }
    }

    // MARK: - Navigation

    func open() {
        mode = draft != nil ? .compose : .library
    }

    func collapse() {
        isDropTargeted = false
        mode = .collapsed
    }

    func showDetail(_ id: UUID) { mode = .detail(id) }

    func handleEscape() {
        switch mode {
        case .detail: mode = .library
        case .compose: cancelDraft()
        case .library where !searchText.isEmpty: searchText = ""
        default: collapse()
        }
    }

    func showToast(_ kind: Toast.Kind) {
        toastWork?.cancel()
        mode = .toast(Toast(kind: kind))
        let work = DispatchWorkItem { [weak self] in
            guard let self, case .toast = self.mode else { return }
            self.mode = .collapsed
        }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func showNotice(_ symbol: String, _ text: String) {
        noticeWork?.cancel()
        notice = InlineNotice(symbol: symbol, text: text)
        let work = DispatchWorkItem { [weak self] in self?.notice = nil }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    // MARK: - Saving

    /// Called when images arrive (drop or paste). Adds to an unsaved draft if there is one.
    func receive(_ images: [ImportedImage]) {
        isImporting = false
        isDropTargeted = false
        guard !images.isEmpty else {
            if mode == .dropZone { collapse() }
            return
        }
        let previews = images.map { ImageImporter.downsampledImage(data: $0.data, maxPixelSize: 1000) ?? NSImage() }
        if var existing = draft {
            existing.images += images
            existing.previews += previews
            draft = existing
        } else {
            draft = Draft(images: images, previews: previews)
        }
        mode = .compose
    }

    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        var images = ImageImporter.importImmediately(from: pasteboard)
        if images.isEmpty { images = ImageImporter.importRawData(from: pasteboard) }
        if images.isEmpty {
            showNotice("doc.on.clipboard", "No image on the clipboard")
        } else {
            receive(images)
        }
    }

    func saveDraft() {
        guard let draft else { return }
        store.add(draft.images, note: draft.note)
        self.draft = nil
        searchText = ""
        showToast(.saved)
    }

    func cancelDraft() {
        draft = nil
        mode = .collapsed
    }

    /// Live preview of the title the note will produce.
    var draftTitlePreview: String {
        if let draft, let title = TitleGenerator.title(for: draft.note) { return title }
        return "Auto-named with date"
    }

    // MARK: - Using saved screenshots

    var filteredShots: [Shot] { store.search(searchText) }

    func copyNote(_ shot: Shot) {
        guard shot.hasNote else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shot.note, forType: .string)
        showNotice("doc.on.clipboard.fill", "Note copied")
    }

    func copyImage(_ shot: Shot) {
        let url = store.imageURL(for: shot)
        guard let data = try? Data(contentsOf: url) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        if shot.fileExtension.lowercased() == "png" {
            item.setData(data, forType: .png)
        } else if let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        if let rep = NSBitmapImageRep(data: data), let tiff = rep.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
        showNotice("photo.on.rectangle", "Image copied")
    }

    func delete(_ shot: Shot) {
        store.delete(shot.id)
        mode = .library
        showNotice("trash", "Moved to Trash")
    }

    func revealInFinder(_ shot: Shot) {
        NSWorkspace.shared.activateFileViewerSelecting([store.imageURL(for: shot)])
    }

    /// What gets dragged into another app: the image file (named after the title)
    /// and, when there's a note, the note as a separate plain-text item.
    func dragPayload(for shot: Shot, image: NSImage) -> DragSource.Payload {
        let url = store.exportURL(for: shot)
        var payload = DragSource.Payload(writer: url as NSURL, image: image)
        if Preferences.includeNoteTextInDrag, shot.hasNote {
            payload.companions = [(shot.note as NSString, NotePill.image(for: shot.note))]
        }
        return payload
    }

    private var noteCopiedDuringDrag = false

    func dragDidBegin(_ shot: Shot) {
        isDraggingOut = true
        noteCopiedDuringDrag = false
        guard Preferences.copyNoteOnDrag, shot.hasNote else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(shot.note, forType: .string)
        noteCopiedDuringDrag = true
        showNotice("doc.on.clipboard.fill", Preferences.includeNoteTextInDrag
                   ? "Note attached · also copied for ⌘V"
                   : "Note copied — paste with ⌘V")
    }

    func dragDidEnd(operation: NSDragOperation) {
        isDraggingOut = false
        // Dropped back onto the panel (or cancelled over it): stay open.
        guard operation != [] || !isPointerInsideSurface() else { return }
        if noteCopiedDuringDrag {
            showToast(.noteCopied)
        } else if !isPointerInsideSurface() {
            collapse()
        }
    }
}
