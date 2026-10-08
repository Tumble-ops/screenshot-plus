import Foundation
import ServiceManagement

/// The few user preferences, stored in UserDefaults.
enum Preferences {
    private static let defaults = UserDefaults.standard

    /// Copy a screenshot's note to the clipboard when it's dragged out (the reliable fallback).
    static var copyNoteOnDrag: Bool {
        get { defaults.object(forKey: "copyNoteOnDrag") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "copyNoteOnDrag") }
    }

    /// Drag the note out alongside the image, as a second (text) item. Apps that
    /// accept both get both; apps that only take images ignore it, and the
    /// clipboard copy covers them.
    static var includeNoteTextInDrag: Bool {
        get { defaults.object(forKey: "includeNoteTextInDrag") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "includeNoteTextInDrag") }
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
