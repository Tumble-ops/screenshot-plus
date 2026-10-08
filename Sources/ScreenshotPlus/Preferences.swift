import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// User settings, persisted in UserDefaults. Observable so the notch updates live
/// while the Settings view is open.
@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()
    static let didChange = Notification.Name("app.screenshotplus.settingsChanged")

    @ObservationIgnored private let defaults = UserDefaults.standard

    // MARK: Appearance

    enum Accent: String, CaseIterable, Identifiable {
        case amber, blue, green, pink, purple, red, white
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var color: Color { Color(nsColor: nsColor) }
        var nsColor: NSColor {
            switch self {
            case .amber: return NSColor(red: 1.0, green: 0.78, blue: 0.32, alpha: 1)
            case .blue: return NSColor(red: 0.40, green: 0.66, blue: 1.0, alpha: 1)
            case .green: return NSColor(red: 0.36, green: 0.86, blue: 0.52, alpha: 1)
            case .pink: return NSColor(red: 1.0, green: 0.50, blue: 0.70, alpha: 1)
            case .purple: return NSColor(red: 0.70, green: 0.56, blue: 1.0, alpha: 1)
            case .red: return NSColor(red: 1.0, green: 0.45, blue: 0.40, alpha: 1)
            case .white: return NSColor(white: 0.92, alpha: 1)
            }
        }
    }

    /// The panel's colour. The top always stays black so it melts into the physical notch.
    enum Surface: String, CaseIterable, Identifiable {
        case black, graphite, midnight, forest, plum
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        /// Colour at the bottom of the panel (black at the top).
        var tint: Color {
            switch self {
            case .black: return .black
            case .graphite: return Color(white: 0.13)
            case .midnight: return Color(red: 0.05, green: 0.08, blue: 0.20)
            case .forest: return Color(red: 0.04, green: 0.14, blue: 0.10)
            case .plum: return Color(red: 0.16, green: 0.06, blue: 0.18)
            }
        }
        /// A brighter version for the swatch, so the options are tellable apart.
        var swatch: Color {
            switch self {
            case .black: return .black
            case .graphite: return Color(white: 0.36)
            case .midnight: return Color(red: 0.18, green: 0.26, blue: 0.58)
            case .forest: return Color(red: 0.13, green: 0.42, blue: 0.30)
            case .plum: return Color(red: 0.45, green: 0.20, blue: 0.50)
            }
        }
    }

    enum PanelSize: String, CaseIterable, Identifiable {
        case compact, regular, large
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var scale: CGFloat {
            switch self {
            case .compact: return 0.86
            case .regular: return 1.0
            case .large: return 1.2
            }
        }
        var libraryColumns: Int {
            switch self {
            case .compact: return 3
            case .regular: return 4
            case .large: return 5
            }
        }
    }

    var accent: Accent { didSet { save(accent.rawValue, "accent") } }
    var surface: Surface { didSet { save(surface.rawValue, "surface") } }
    var panelSize: PanelSize { didSet { save(panelSize.rawValue, "panelSize") } }

    // MARK: Behavior

    enum HoverDelay: String, CaseIterable, Identifiable {
        case instant, short, relaxed
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var seconds: TimeInterval {
            switch self {
            case .instant: return 0.03
            case .short: return 0.15
            case .relaxed: return 0.45
            }
        }
    }

    /// Open when the pointer rests on the notch. Off: click to open.
    var openOnHover: Bool { didSet { save(openOnHover, "openOnHover") } }
    var hoverDelay: HoverDelay { didSet { save(hoverDelay.rawValue, "hoverDelay") } }
    /// Trackpad haptic tap when a screenshot is over the drop zone and when it's saved.
    var haptics: Bool { didSet { save(haptics, "haptics") } }

    // MARK: Dragging

    /// Drag the note out alongside the image, as a second (text) item. Apps that
    /// accept both get both; apps that only take images ignore it, and the
    /// clipboard copy covers them.
    var includeNoteTextInDrag: Bool { didSet { save(includeNoteTextInDrag, "includeNoteTextInDrag") } }
    /// Copy a screenshot's note to the clipboard when it's dragged out.
    var copyNoteOnDrag: Bool { didSet { save(copyNoteOnDrag, "copyNoteOnDrag") } }

    // MARK: General

    enum DisplayChoice: String, CaseIterable, Identifiable {
        case notch, primary
        var id: String { rawValue }
        var name: String { self == .notch ? "Built-in" : "Primary" }
    }

    // MARK: Library

    enum Expiry: String, CaseIterable, Identifiable {
        case never, day, week, month
        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        var maxAge: TimeInterval? {
            switch self {
            case .never: return nil
            case .day: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .month: return 30 * 24 * 3600
            }
        }
    }

    /// Remove a screenshot from the library once it has been dropped into another app.
    var removeAfterDragOut: Bool { didSet { save(removeAfterDragOut, "removeAfterDragOut") } }
    /// Screenshots older than this go to the Trash automatically.
    var expiry: Expiry { didSet { save(expiry.rawValue, "expiry") } }

    var showMenuBarIcon: Bool { didSet { save(showMenuBarIcon, "showMenuBarIcon") } }
    var display: DisplayChoice { didSet { save(display.rawValue, "display") } }

    private init() {
        func value<T: RawRepresentable>(_ key: String, _ fallback: T) -> T where T.RawValue == String {
            UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:)) ?? fallback
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool {
            UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
        }
        accent = value("accent", Accent.amber)
        surface = value("surface", Surface.black)
        panelSize = value("panelSize", PanelSize.regular)
        openOnHover = flag("openOnHover", true)
        hoverDelay = value("hoverDelay", HoverDelay.short)
        haptics = flag("haptics", true)
        includeNoteTextInDrag = flag("includeNoteTextInDrag", true)
        copyNoteOnDrag = flag("copyNoteOnDrag", true)
        removeAfterDragOut = flag("removeAfterDragOut", false)
        expiry = value("expiry", Expiry.never)
        showMenuBarIcon = flag("showMenuBarIcon", true)
        display = value("display", DisplayChoice.notch)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: ["key": key])
    }

    func hapticTap() {
        guard haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .requiresApproval: return "needs approval in System Settings → General → Login Items"
        case .notRegistered: return "off"
        case .notFound: return "app not found"
        @unknown default: return "unknown"
        }
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
