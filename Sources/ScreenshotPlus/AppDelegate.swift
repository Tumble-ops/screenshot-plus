import AppKit
import ScreenshotPlusCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ShotStore!
    private var notch: NotchController!
    private var statusItem: StatusItemController!
    #if DEBUG
    private var debugHooks: AnyObject?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `ScreenshotPlus --launch-at-login on|off` sets the login item (same as the menu toggle) and exits.
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--launch-at-login"), flag + 1 < arguments.count {
            do {
                try LaunchAtLogin.set(arguments[flag + 1] == "on")
            } catch {
                print("Launch at Login failed: \(error.localizedDescription)")
            }
            print("Launch at Login status: \(LaunchAtLogin.statusDescription)")
            exit(0)
        }

        // One instance only.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
               .contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }

        // SCREENSHOTPLUS_LIBRARY points the app at a different library folder (handy for testing).
        let custom = ProcessInfo.processInfo.environment["SCREENSHOTPLUS_LIBRARY"].map { URL(fileURLWithPath: $0) }
        store = ShotStore(baseURL: custom, cachesURL: custom?.appendingPathComponent("Caches"))
        notch = NotchController(store: store)
        notch.start()
        statusItem = StatusItemController(notch: notch)
        #if DEBUG
        debugHooks = DebugHooks(controller: notch) { [weak notch] in notch?.debugHostingView }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.flush()
    }
}
