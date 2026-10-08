import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Image bytes ready to be stored. The original encoding is kept so quality is never lost.
public struct ImportedImage: Sendable {
    public var data: Data
    /// "png", "jpg", "heic", …
    public var fileExtension: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(data: Data, fileExtension: String, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.fileExtension = fileExtension
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// Reads images from drag and general pasteboards.
///
/// Handles, in order of preference:
/// 1. File URLs (Finder, Desktop, and the macOS screenshot floating thumbnail,
///    which hands out a URL to its temporary capture file).
/// 2. File promises (browsers, Photos, some screenshot tools).
/// 3. Raw image data (PNG/TIFF/JPEG/HEIC on the pasteboard).
public enum ImageImporter {
    /// Pasteboard types the notch registers for as a drop destination.
    public static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier),
         NSPasteboard.PasteboardType(UTType.heic.identifier)]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    private static let rawTypes: [(NSPasteboard.PasteboardType, String)] = [
        (.png, "png"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (.tiff, "tiff"),
    ]

    private static let imageURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    /// Cheap check used while a drag is in flight (does not read file contents).
    public static func canImport(from pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: imageURLOptions) { return true }
        if !imagePromises(in: pasteboard).isEmpty { return true }
        let types = pasteboard.types ?? []
        return rawTypes.contains { types.contains($0.0) }
    }

    /// Images that can be read synchronously (file URLs, then raw data).
    public static func importImmediately(from pasteboard: NSPasteboard) -> [ImportedImage] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: imageURLOptions) as? [URL] ?? []
        let fromFiles = urls.compactMap(load(url:))
        if !fromFiles.isEmpty { return fromFiles }
        if !imagePromises(in: pasteboard).isEmpty { return [] }  // handled asynchronously
        return importRawData(from: pasteboard)
    }

    /// Raw pasteboard image data only (used for "paste from clipboard").
    public static func importRawData(from pasteboard: NSPasteboard) -> [ImportedImage] {
        var images: [ImportedImage] = []
        for item in pasteboard.pasteboardItems ?? [] {
            for (type, ext) in rawTypes {
                guard let data = item.data(forType: type) else { continue }
                if let image = load(data: data, fileExtension: ext) {
                    images.append(image)
                    break
                }
            }
        }
        return images
    }

    public static func imagePromises(in pasteboard: NSPasteboard) -> [NSFilePromiseReceiver] {
        let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil)
            as? [NSFilePromiseReceiver] ?? []
        return receivers.filter { receiver in
            receiver.fileTypes.contains { UTType($0)?.conforms(to: .image) ?? false }
        }
    }

    /// Fulfils file promises into `directory` and calls back on the main queue.
    public static func receive(
        _ receivers: [NSFilePromiseReceiver],
        into directory: URL,
        completion: @escaping @MainActor ([ImportedImage]) -> Void
    ) {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let collector = PromiseCollector(expected: receivers.reduce(0) { $0 + max(1, $1.fileTypes.count) }) { results in
            let images = results.sorted { $0.0 < $1.0 }.map(\.1)
            DispatchQueue.main.async { MainActor.assumeIsolated { completion(images) } }
        }
        for (index, receiver) in receivers.enumerated() {
            receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) { url, error in
                var image: ImportedImage?
                if let error {
                    NSLog("Screenshot+: file promise failed: \(error.localizedDescription)")
                } else {
                    image = load(url: url)
                    try? FileManager.default.removeItem(at: url)
                }
                collector.add(index: index, image: image)
            }
        }
        // Some sources never call back for every file; don't leave the user waiting.
        DispatchQueue.global().asyncAfter(deadline: .now() + 10) { collector.finish() }
    }

    private final class PromiseCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var remaining: Int
        private var results: [(Int, ImportedImage)] = []
        private var done = false
        private let completion: ([(Int, ImportedImage)]) -> Void

        init(expected: Int, completion: @escaping ([(Int, ImportedImage)]) -> Void) {
            remaining = expected
            self.completion = completion
        }

        func add(index: Int, image: ImportedImage?) {
            lock.lock()
            if let image { results.append((index, image)) }
            remaining -= 1
            let shouldFinish = remaining <= 0
            lock.unlock()
            if shouldFinish { finish() }
        }

        func finish() {
            lock.lock()
            guard !done else { lock.unlock(); return }
            done = true
            let snapshot = results
            lock.unlock()
            completion(snapshot)
        }
    }

    public static func load(url: URL) -> ImportedImage? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let ext = url.pathExtension.lowercased()
        return load(data: Data(data), fileExtension: ext.isEmpty ? "png" : ext)
    }

    public static func load(data: Data, fileExtension: String) -> ImportedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        // TIFF from the pasteboard is huge and awkward to share; PNG is lossless and universal.
        if fileExtension == "tiff" || fileExtension == "tif" {
            guard let rep = NSBitmapImageRep(data: data),
                  let png = rep.representation(using: .png, properties: [:])
            else { return nil }
            return ImportedImage(data: png, fileExtension: "png", pixelWidth: width, pixelHeight: height)
        }
        let ext = fileExtension == "jpeg" ? "jpg" : fileExtension
        return ImportedImage(data: data, fileExtension: ext, pixelWidth: width, pixelHeight: height)
    }

    /// Downsampled image for previews (never decodes the full-size bitmap).
    public static func downsampledImage(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return downsampledImage(source: source, maxPixelSize: maxPixelSize)
    }

    public static func downsampledImage(url: URL, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return downsampledImage(source: source, maxPixelSize: maxPixelSize)
    }

    static func downsampledCGImage(source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func downsampledImage(source: CGImageSource, maxPixelSize: Int) -> NSImage? {
        guard let cgImage = downsampledCGImage(source: source, maxPixelSize: maxPixelSize) else { return nil }
        // Report size in points for a 2x display so it renders crisply.
        let size = NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2)
        return NSImage(cgImage: cgImage, size: size)
    }
}
