import AppKit

/// Where the (real or simulated) notch is on a given screen, in screen coordinates.
struct NotchMetrics: Equatable {
    var notchSize: CGSize
    var hasNotch: Bool
    /// Horizontal centre of the notch.
    var centerX: CGFloat
    /// Top edge of the screen.
    var top: CGFloat

    /// The display the notch UI lives on: by default the built-in notched display if
    /// present, otherwise (or when chosen in Settings) the primary menu bar display.
    @MainActor
    static func preferredScreen() -> NSScreen? {
        if AppSettings.shared.display == .primary { return NSScreen.screens.first }
        return NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    static func measure(_ screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let width = right.minX - left.maxX
            return NotchMetrics(
                notchSize: CGSize(width: width, height: screen.safeAreaInsets.top),
                hasNotch: true,
                centerX: left.maxX + width / 2,
                top: frame.maxY
            )
        }
        // No notch (external display, older Mac): draw a small notch-like pill in the
        // menu bar's centre, which apps rarely use.
        let menuBar = frame.maxY - screen.visibleFrame.maxY
        let height = min(max(menuBar > 0 ? menuBar : 24, 22), 32)
        return NotchMetrics(
            notchSize: CGSize(width: 170, height: height),
            hasNotch: false,
            centerX: frame.midX,
            top: frame.maxY
        )
    }
}
