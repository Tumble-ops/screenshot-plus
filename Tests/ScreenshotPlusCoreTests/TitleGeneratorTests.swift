import XCTest
@testable import ScreenshotPlusCore

final class TitleGeneratorTests: XCTestCase {
    func testSpecExample() {
        XCTAssertEqual(
            TitleGenerator.title(for: "Fix the alignment of these buttons and make the hover animation smoother."),
            "Fix Button Alignment"
        )
    }

    func testEmptyNoteHasNoTitle() {
        XCTAssertNil(TitleGenerator.title(for: "   \n "))
    }

    func testSequentialTitle() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 8; components.hour = 22; components.minute = 42
        let date = Calendar(identifier: .gregorian).date(from: components)!
        let title = TitleGenerator.sequentialTitle(number: 1, date: date, locale: Locale(identifier: "en_US"))
        XCTAssertTrue(title.hasPrefix("Screenshot 001 — Oct 8"), title)
        XCTAssertTrue(title.contains("10:42"), title)
    }

    func testTitlesAreShortAndCapitalised() {
        let notes = [
            "Can you explain what this error means?",
            "please make the header sticky on scroll",
            "The login page looks broken on mobile",
            "Use this as reference for the landing page hero, keep the colors",
            "Why is this button misaligned?",
            "Update the API docs for the new auth flow",
            "landing page",
            "Fix this",
            "Change the color of the primary button to blue",
            "Reminder: renew the domain before friday",
            "Recreate this onboarding screen in SwiftUI",
        ]
        for note in notes {
            let title = TitleGenerator.title(for: note)
            print("\(note)  →  \(title ?? "nil")")
            XCTAssertNotNil(title, note)
            XCTAssertLessThanOrEqual(title!.split(separator: " ").count, TitleGenerator.maxWords, note)
            XCTAssertLessThanOrEqual(title!.count, TitleGenerator.maxLength, note)
            XCTAssertTrue(title!.first!.isUppercase, note)
        }
    }

    func testFileNameSanitising() {
        XCTAssertEqual(ShotStore.safeFileName("Screenshot 001 — Oct 8, 10:42 PM"), "Screenshot 001 — Oct 8, 10.42 PM")
        XCTAssertEqual(ShotStore.safeFileName("a/b"), "a b")
        XCTAssertEqual(ShotStore.safeFileName("..."), "Screenshot")
    }
}
