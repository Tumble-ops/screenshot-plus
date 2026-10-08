# Screenshot+

A screenshot inbox that lives in the MacBook notch.
**Save:** drag a screenshot onto the notch → add a note (optional) → Save (⏎).
**Use:** hover the notch → find it → drag it into any app. The note comes along as text and is also copied to the clipboard so ⌘V always works.

## Build & run

```bash
scripts/build-app.sh            # build/Screenshot+.app (release)
scripts/build-app.sh --install  # also copy to /Applications and launch
swift test                      # title generator + file naming tests
```

Requires macOS 14+, Xcode 16+ toolchain. No accounts, network, or permissions.

## How it works

| Piece | File |
| --- | --- |
| Floating, non-activating panel over the notch; ignores the mouse except over the visible black surface | `Notch/NotchPanel.swift`, `Notch/NotchController.swift` |
| Invisible sensor exactly on the notch (no pixels/menu items there) so hover, click and drop always land | `Notch/NotchSensor.swift` |
| Drag-in: file URLs (Finder, screenshot thumbnail), file promises (browsers), raw PNG/TIFF/JPEG/HEIC | `Notch/DropHandler.swift`, `ScreenshotPlusCore/ImageImporter.swift` |
| Drag-out: real `NSDraggingSession` with the image file (named after the title) + the note as a second text item | `Notch/DragSource.swift`, `NotchModel.dragPayload` |
| On-device titles via Apple's NaturalLanguage ("Fix the alignment of these buttons…" → "Fix Button Alignment") | `ScreenshotPlusCore/TitleGenerator.swift` |
| Storage: `~/Library/Application Support/Screenshot+/` (`library.json`, original images untouched, thumbnails) | `ScreenshotPlusCore/ShotStore.swift` |

States: collapsed → drop zone → compose → library → detail, plus "ears" toasts (Saved / Note copied) and an unsaved-draft indicator.
Pointer tracking uses NSEvent mouse monitors (no Accessibility permission) and only polls while expanded, so it's idle at rest.
Without a notch (external display, clamshell) a small notch-shaped pill appears at the top centre of the main display.

Menu bar item: open inbox, save image from clipboard, drag/copy note options, Launch at Login, show library in Finder.

## Notes on drag-and-drop targets

What a destination does with a drop is up to that app. Native text views (Notes, Mail, Messages, TextEdit) take both image and text. Most AI chat inputs (Claude, ChatGPT, Cursor) and Terminal attach the image and ignore the text; the clipboard copy covers those. Turn "Drag Note Along with Image" off in the menu if an app ever inserts the note instead of the image.

## Debug builds

`scripts/build-app.sh debug` enables `DebugHooks.swift`, which scripts can drive with
`swift scripts/notch-debug.swift "open" | "drop-file:/path.png" | "note:…" | "save" | "detail" | …`.
`SCREENSHOTPLUS_LIBRARY=/some/dir` points any build at a separate library.
