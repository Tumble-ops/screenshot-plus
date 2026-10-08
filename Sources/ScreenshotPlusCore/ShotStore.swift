import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Local, file-based library:
///
///     ~/Library/Application Support/Screenshot+/
///         library.json        titles, notes, timestamps
///         Images/<id>.png     original bytes, untouched
///         Thumbnails/<id>.jpg small previews for the gallery
///
/// Drag-out copies live in ~/Library/Caches/Screenshot+/Exports as hard links
/// named after the title, so attachments arrive as "Fix Button Alignment.png".
@MainActor
@Observable
public final class ShotStore {
    /// Newest first.
    public private(set) var shots: [Shot] = []

    public let baseURL: URL
    public let imagesURL: URL
    public let thumbnailsURL: URL
    public let exportsURL: URL
    public let incomingURL: URL

    @ObservationIgnored private var nextSequence = 1
    @ObservationIgnored private let thumbnailCache = NSCache<NSString, NSImage>()
    @ObservationIgnored private let ioQueue = DispatchQueue(label: "screenshotplus.store", qos: .utility)

    public static let thumbnailPixelSize = 480

    public init(baseURL: URL? = nil, cachesURL: URL? = nil) {
        let fm = FileManager.default
        let support = baseURL ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screenshot+", isDirectory: true)
        let caches = cachesURL ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Screenshot+", isDirectory: true)
        self.baseURL = support
        imagesURL = support.appendingPathComponent("Images", isDirectory: true)
        thumbnailsURL = support.appendingPathComponent("Thumbnails", isDirectory: true)
        exportsURL = caches.appendingPathComponent("Exports", isDirectory: true)
        incomingURL = caches.appendingPathComponent("Incoming", isDirectory: true)
        for url in [imagesURL, thumbnailsURL, exportsURL, incomingURL] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
        thumbnailCache.countLimit = 120
        load()
        pruneExports()
    }

    private var libraryFileURL: URL { baseURL.appendingPathComponent("library.json") }

    // MARK: - Queries

    public func shot(_ id: UUID) -> Shot? { shots.first { $0.id == id } }

    public func search(_ query: String) -> [Shot] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !terms.isEmpty else { return shots }
        return shots.filter { shot in
            let haystack = shot.title + "\n" + shot.note
            return terms.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    public func imageURL(for shot: Shot) -> URL { imagesURL.appendingPathComponent(shot.fileName) }

    private func thumbnailURL(for id: UUID) -> URL { thumbnailsURL.appendingPathComponent("\(id.uuidString).jpg") }

    public func thumbnail(for shot: Shot) -> NSImage? {
        let key = shot.id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        let url = thumbnailURL(for: shot.id)
        if !FileManager.default.fileExists(atPath: url.path) {
            writeThumbnail(from: imageURL(for: shot), to: url)
        }
        guard let image = ImageImporter.downsampledImage(url: url, maxPixelSize: Self.thumbnailPixelSize) else { return nil }
        thumbnailCache.setObject(image, forKey: key)
        return image
    }

    /// A title-named file for dragging out. Hard link, so it costs no disk space.
    public func exportURL(for shot: Shot) -> URL {
        let source = imageURL(for: shot)
        let folder = exportsURL.appendingPathComponent(shot.id.uuidString, isDirectory: true)
        let name = Self.safeFileName(shot.title) + "." + shot.fileExtension
        let target = folder.appendingPathComponent(name)
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) { return target }
        try? fm.removeItem(at: folder)
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            do { try fm.linkItem(at: source, to: target) } catch { try fm.copyItem(at: source, to: target) }
            return target
        } catch {
            return source
        }
    }

    // MARK: - Mutations

    /// Saves images with a shared note. Returns the new shots (in the order given).
    @discardableResult
    public func add(_ images: [ImportedImage], note: String, date: Date = Date()) -> [Shot] {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let generated = TitleGenerator.title(for: trimmedNote)
        var created: [Shot] = []

        for (index, image) in images.enumerated() {
            let id = UUID()
            let fileName = "\(id.uuidString).\(image.fileExtension)"
            let url = imagesURL.appendingPathComponent(fileName)
            do {
                try image.data.write(to: url, options: .atomic)
            } catch {
                NSLog("Screenshot+: failed to write image: \(error)")
                continue
            }
            writeThumbnail(from: url, to: thumbnailURL(for: id))

            let title: String
            if let generated {
                title = images.count > 1 && index > 0 ? "\(generated) (\(index + 1))" : generated
            } else {
                title = TitleGenerator.sequentialTitle(number: nextSequence, date: date)
                nextSequence += 1
            }
            created.append(Shot(id: id, title: title, note: trimmedNote, createdAt: date,
                                fileName: fileName, pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight))
        }
        shots.insert(contentsOf: created.reversed(), at: 0)
        persist()
        return created
    }

    public func rename(_ id: UUID, to title: String) {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != shots[index].title else { return }
        shots[index].title = trimmed
        shots[index].hasCustomTitle = true
        persist()
    }

    public func updateNote(_ id: UUID, to note: String) {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != shots[index].note else { return }
        shots[index].note = trimmed
        // Auto titles follow the note; titles the user typed are left alone.
        if !shots[index].hasCustomTitle, let generated = TitleGenerator.title(for: trimmed) {
            shots[index].title = generated
        }
        persist()
    }

    /// Moves the image to the Trash (recoverable) and forgets the entry.
    ///
    /// `keepDragCopy`: leave the title-named copy that was just dragged into another
    /// app in place. Some destinations only receive a path and read the file later
    /// (Terminal → Claude Code reads it when the message is sent). It is a hard
    /// link, so it survives the original going to the Trash, and is pruned after a day.
    public func delete(_ id: UUID, keepDragCopy: Bool = false) {
        guard let index = shots.firstIndex(where: { $0.id == id }) else { return }
        let shot = shots.remove(at: index)
        removeFiles(of: shot, keepDragCopy: keepDragCopy)
        persist()
    }

    /// Trashes every screenshot saved before `cutoff`. Returns how many were removed.
    @discardableResult
    public func deleteShots(olderThan cutoff: Date) -> Int {
        let expired = shots.filter { $0.createdAt < cutoff }
        guard !expired.isEmpty else { return 0 }
        shots.removeAll { $0.createdAt < cutoff }
        for shot in expired { removeFiles(of: shot, keepDragCopy: false) }
        persist()
        return expired.count
    }

    private func removeFiles(of shot: Shot, keepDragCopy: Bool) {
        thumbnailCache.removeObject(forKey: shot.id.uuidString as NSString)
        let fm = FileManager.default
        try? fm.trashItem(at: imageURL(for: shot), resultingItemURL: nil)
        try? fm.removeItem(at: thumbnailURL(for: shot.id))
        if !keepDragCopy {
            try? fm.removeItem(at: exportsURL.appendingPathComponent(shot.id.uuidString))
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: libraryFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let file = try decoder.decode(LibraryFile.self, from: data)
            let fm = FileManager.default
            shots = file.shots
                .filter { fm.fileExists(atPath: imagesURL.appendingPathComponent($0.fileName).path) }
                .sorted { $0.createdAt > $1.createdAt }
            nextSequence = max(1, file.nextSequence)
        } catch {
            // Never overwrite a library we couldn't read; keep a copy aside.
            let backup = baseURL.appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: libraryFileURL, to: backup)
            NSLog("Screenshot+: could not read library.json (\(error)); backed up to \(backup.path)")
        }
    }

    private func persist() {
        let file = LibraryFile(nextSequence: nextSequence, shots: shots)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(file) else { return }
        let url = libraryFileURL
        ioQueue.async {
            do { try data.write(to: url, options: .atomic) } catch { NSLog("Screenshot+: save failed: \(error)") }
        }
    }

    /// Blocks until pending writes are on disk (used at quit and in tests).
    public func flush() { ioQueue.sync {} }

    private func writeThumbnail(from source: URL, to destination: URL) {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let cgImage = ImageImporter.downsampledCGImage(source: imageSource, maxPixelSize: Self.thumbnailPixelSize),
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        CGImageDestinationFinalize(dest)
    }

    private func pruneExports() {
        let fm = FileManager.default
        let known = Set(shots.map(\.id.uuidString))
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let dayAgo = Date().addingTimeInterval(-24 * 3600)
        for folder in (try? fm.contentsOfDirectory(at: exportsURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            // Copies of removed screenshots get a day's grace in case a destination reads them late.
            let orphaned = !known.contains(folder.lastPathComponent)
            if modified < weekAgo || (orphaned && modified < dayAgo) {
                try? fm.removeItem(at: folder)
            }
        }
        for item in (try? fm.contentsOfDirectory(at: incomingURL, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.removeItem(at: item)
        }
    }

    nonisolated static func safeFileName(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>\0").union(.newlines).union(.controlCharacters)
        let timeSafe = title.replacingOccurrences(of: #"(\d):(\d)"#, with: "$1.$2", options: .regularExpression)
        let cleaned = timeSafe.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        let name = cleaned.isEmpty ? "Screenshot" : cleaned
        return String(name.prefix(80))
    }
}
