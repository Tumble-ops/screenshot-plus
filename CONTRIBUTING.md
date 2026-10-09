# Contributing to Screenshot+

Thanks for helping! Screenshot+ aims to stay small: a fast screenshot inbox in the notch. Features that keep "drag in, note, drag out" quick are the best fit; accounts, sync, tagging systems or AI integrations are out of scope.

## Getting set up

```bash
swift build            # compile
swift test             # title generator, storage and file-naming tests
scripts/build-app.sh debug && open "build/Screenshot+.app"
```

Requires macOS 14+ and Xcode 16+ (or the command line tools). Quit any installed copy first; only one instance runs at a time.

### Test without touching your real library

```bash
SCREENSHOTPLUS_LIBRARY=/tmp/shots-test "build/Screenshot+.app/Contents/MacOS/ScreenshotPlus"
```

### Driving a debug build from scripts

Debug builds listen for commands (see `Sources/ScreenshotPlus/DebugHooks.swift`), which makes it possible to exercise and screenshot each state without a mouse:

```bash
swift scripts/notch-debug.swift "open"
swift scripts/notch-debug.swift "drop-file:/path/to/image.png"   # runs the real drop code
swift scripts/notch-debug.swift "note:Fix the header spacing"
swift scripts/notch-debug.swift "save"
swift scripts/notch-debug.swift "freeze:on"                       # keep states open for screenshots
```

These hooks are compiled out of release builds.

## Pull requests

- Keep changes focused, and match the surrounding style (SwiftUI views in `Views/`, window and event logic in `Notch/`, model/storage in `ScreenshotPlusCore`).
- Add or update tests in `Tests/` for anything in `ScreenshotPlusCore`.
- For UI changes, include a before/after screenshot.
- Real drag-and-drop can't be automated, so please say which apps you tried dragging into.
