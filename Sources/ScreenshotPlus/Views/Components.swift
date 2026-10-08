import SwiftUI

extension Animation {
    /// The one spring used for every notch size/shape change.
    static let notch = Animation.spring(response: 0.42, dampingFraction: 0.8)
}

enum Layout {
    /// Horizontal content inset from the panel frame. The notch's concave top corners
    /// pull the visible edge in by ~14 pt, so this leaves ~16 pt of breathing room
    /// between controls and the edge you actually see.
    static let sideInset: CGFloat = 30
}

enum Palette {
    static let surface = Color.white.opacity(0.07)
    static let surfaceHover = Color.white.opacity(0.11)
    static let hairline = Color.white.opacity(0.09)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.52)
    static let tertiaryText = Color.white.opacity(0.32)
    /// Follows the accent colour chosen in Settings.
    @MainActor static var noteAccent: Color { AppSettings.shared.accent.color }
}

extension AnyTransition {
    /// Content fades/unblurs in slightly after the surface starts growing, and gets out of the way fast.
    static var notchContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: NotchContentEffect(progress: 0), identity: NotchContentEffect(progress: 1))
                .animation(.spring(response: 0.4, dampingFraction: 0.86).delay(0.06)),
            removal: .modifier(active: NotchContentEffect(progress: 0), identity: NotchContentEffect(progress: 1))
                .animation(.easeOut(duration: 0.12))
        )
    }
}

private struct NotchContentEffect: ViewModifier {
    var progress: CGFloat
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 8)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
    }
}

/// White pill for the main action, translucent pill for secondary ones.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PillButton(configuration: configuration, prominent: prominent)
    }

    private struct PillButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Palette.primaryText)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(
                    Capsule().fill(prominent
                        ? Color.white.opacity(hovering ? 1 : 0.92)
                        : (hovering ? Palette.surfaceHover : Palette.surface))
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .onHover { hovering = $0 }
                .contentShape(Capsule())
        }
    }
}

/// Small icon + label button used in the detail view's action row.
struct ActionButton: View {
    let symbol: String
    let label: String
    var tint: Color = Palette.primaryText
    var disabled = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(height: 16)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint.opacity(disabled ? 0.3 : 1))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering && !disabled ? Palette.surfaceHover : Palette.surface))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Plain circular icon button (back, paste, clear).
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 26
    var help: String = ""
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(hovering ? Palette.primaryText : Palette.secondaryText)
                .frame(width: size, height: size)
                .background(Circle().fill(hovering ? Palette.surfaceHover : Palette.surface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// Little marker on thumbnails that carry a note.
struct NoteBadge: View {
    var body: some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.black)
            .frame(width: 18, height: 18)
            .background(Circle().fill(Palette.noteAccent))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
    }
}

/// The two "ears" either side of the physical notch, used for toasts and the draft indicator.
struct NotchEars<Left: View, Right: View>: View {
    let notchWidth: CGFloat
    let earWidth: CGFloat
    let height: CGFloat
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(spacing: 0) {
            left.frame(width: earWidth, height: height)
            Color.clear.frame(width: notchWidth, height: height)
            right.frame(width: earWidth, height: height)
        }
    }
}
