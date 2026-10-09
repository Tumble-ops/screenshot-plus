import Foundation

/// A saved screenshot and the note/prompt that travels with it.
public struct Shot: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var note: String
    public let createdAt: Date
    /// File name of the original image inside the library's `Images` folder.
    public var fileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// True once the user has typed their own title. Auto titles are regenerated when the note changes.
    public var hasCustomTitle: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        note: String,
        createdAt: Date = Date(),
        fileName: String,
        pixelWidth: Int,
        pixelHeight: Int,
        hasCustomTitle: Bool = false
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hasCustomTitle = hasCustomTitle
    }

    public var hasNote: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public var fileExtension: String { (fileName as NSString).pathExtension }
}

/// A screenshot that was just moved to the Trash, kept so the deletion can be undone.
public struct DeletedShot: Sendable {
    public let shot: Shot
    public let trashedURL: URL?
}

/// On-disk representation of the whole library (`library.json`).
struct LibraryFile: Codable {
    var version: Int = 1
    /// Counter used for "Screenshot 001 — …" names of screenshots saved without a note.
    var nextSequence: Int = 1
    var shots: [Shot] = []
}
