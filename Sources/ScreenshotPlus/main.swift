import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Menu bar utility: no Dock icon, no app menu (LSUIElement does the same when bundled).
    app.setActivationPolicy(.accessory)
    app.run()
}
