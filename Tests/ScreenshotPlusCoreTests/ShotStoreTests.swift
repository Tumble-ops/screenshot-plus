import AppKit
import XCTest
@testable import ScreenshotPlusCore

@MainActor
final class ShotStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ShotStoreTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> ShotStore {
        ShotStore(baseURL: root.appendingPathComponent("Library"), cachesURL: root.appendingPathComponent("Caches"),
                  trashURL: root.appendingPathComponent("Trash"))
    }

    private func samplePNG() -> ImportedImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 6, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let data = rep.representation(using: .png, properties: [:])!
        return ImageImporter.load(data: data, fileExtension: "png")!
    }

    func testOriginalBytesAndNoteArePersisted() {
        let store = makeStore()
        let image = samplePNG()
        let shot = store.add([image], note: "Fix the alignment of these buttons").first!
        store.flush()
        XCTAssertEqual(try Data(contentsOf: store.imageURL(for: shot)), image.data)

        let reloaded = makeStore()
        XCTAssertEqual(reloaded.shots.first?.note, "Fix the alignment of these buttons")
        XCTAssertEqual(reloaded.shots.first?.title, "Fix Button Alignment")
    }

    func testDeleteShotsOlderThanCutoff() {
        let store = makeStore()
        let now = Date()
        store.add([samplePNG()], note: "old", date: now.addingTimeInterval(-10 * 24 * 3600))
        store.add([samplePNG()], note: "new", date: now.addingTimeInterval(-3600))

        XCTAssertEqual(store.deleteShots(olderThan: now.addingTimeInterval(-7 * 24 * 3600)), 1)
        XCTAssertEqual(store.shots.map(\.note), ["new"])
        XCTAssertEqual(store.deleteShots(olderThan: now.addingTimeInterval(-7 * 24 * 3600)), 0)
    }

    func testRemovingAfterDragKeepsTheDraggedCopy() {
        let store = makeStore()
        let shot = store.add([samplePNG()], note: "Send me").first!
        let dragged = store.exportURL(for: shot)

        store.delete(shot.id, keepDragCopy: true)

        XCTAssertTrue(store.shots.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dragged.path), "destination may still read this file")
    }

    func testPlainDeleteRemovesTheDraggedCopy() {
        let store = makeStore()
        let shot = store.add([samplePNG()], note: "Bye").first!
        let dragged = store.exportURL(for: shot)

        store.delete(shot.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: dragged.path))
    }

    func testDeleteCanBeUndone() {
        let store = makeStore()
        let older = store.add([samplePNG()], note: "older", date: Date().addingTimeInterval(-60)).first!
        let shot = store.add([samplePNG()], note: "undo me").first!
        let original = try? Data(contentsOf: store.imageURL(for: shot))

        let deleted = store.delete(shot.id)
        XCTAssertEqual(store.shots.map(\.id), [older.id])
        XCTAssertNotNil(deleted?.trashedURL)

        XCTAssertTrue(store.restore(deleted!))
        XCTAssertEqual(store.shots.map(\.id), [shot.id, older.id], "restored in date order")
        XCTAssertEqual(try? Data(contentsOf: store.imageURL(for: shot)), original)
        XCTAssertNotNil(store.thumbnail(for: shot))
        XCTAssertFalse(store.restore(deleted!), "can't restore twice")
    }
}
