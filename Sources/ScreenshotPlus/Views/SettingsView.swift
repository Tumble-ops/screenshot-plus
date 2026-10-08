import ScreenshotPlusCore
import SwiftUI

/// Settings, inside the notch like everything else. Changes apply immediately.
struct SettingsView: View {
    let model: NotchModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginNeedsApproval = false
    @State private var librarySummary = ""

    private var settings: AppSettings { AppSettings.shared }

    var body: some View {
        let size = model.shapeSize(for: .settings)

        VStack(spacing: 12) {
            header

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        appearance
                        dragging
                        library
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 16) {
                        behavior
                        general
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
        }
        .padding(EdgeInsets(top: 8, leading: Layout.sideInset, bottom: 10, trailing: Layout.sideInset))
        .frame(width: size.width, height: size.height - model.notchSize.height, alignment: .top)
        .task { await loadLibrarySummary() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "chevron.left", size: 24, help: "Back to screenshots") {
                model.mode = .library
            }
            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Spacer(minLength: 8)
            Text(librarySummary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)
            IconButton(symbol: "folder", size: 24, help: "Show library in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([model.store.imagesURL])
            }
            IconButton(symbol: "power", size: 24, help: "Quit Screenshot+") {
                NSApp.terminate(nil)
            }
        }
    }

    private var appearance: some View {
        SettingsSection(title: "Appearance") {
            SettingsRow("Accent") {
                HStack(spacing: 6) {
                    ForEach(AppSettings.Accent.allCases) { accent in
                        Swatch(fill: AnyShapeStyle(accent.color), selected: settings.accent == accent, help: accent.name) {
                            settings.accent = accent
                        }
                    }
                }
            }
            SettingsRow("Panel color") {
                HStack(spacing: 6) {
                    ForEach(AppSettings.Surface.allCases) { surface in
                        Swatch(
                            fill: AnyShapeStyle(LinearGradient(colors: [.black, surface.swatch], startPoint: .top, endPoint: .bottom)),
                            selected: settings.surface == surface,
                            help: surface.name
                        ) {
                            settings.surface = surface
                        }
                    }
                }
            }
            SettingsRow("Size") {
                PillPicker(options: AppSettings.PanelSize.allCases, selection: Binding(
                    get: { settings.panelSize }, set: { settings.panelSize = $0 }
                )) { $0.name }
            }
        }
    }

    private var general: some View {
        SettingsSection(title: "General") {
            SettingsRow("Open at login", caption: loginNeedsApproval ? "Approve in System Settings › Login Items" : nil) {
                NotchSwitch(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            }
            SettingsRow("Menu bar icon", caption: settings.showMenuBarIcon ? nil : "Reopen the app to bring back Settings") {
                NotchSwitch(isOn: Binding(get: { settings.showMenuBarIcon }, set: { settings.showMenuBarIcon = $0 }))
            }
            SettingsRow("Display") {
                PillPicker(options: AppSettings.DisplayChoice.allCases, selection: Binding(
                    get: { settings.display }, set: { settings.display = $0 }
                )) { $0.name }
            }
        }
    }

    private var behavior: some View {
        SettingsSection(title: "Opening") {
            SettingsRow("Open on hover", caption: settings.openOnHover ? nil : "Click the notch to open") {
                NotchSwitch(isOn: Binding(get: { settings.openOnHover }, set: { settings.openOnHover = $0 }))
            }
            SettingsRow("Hover delay") {
                PillPicker(options: AppSettings.HoverDelay.allCases, selection: Binding(
                    get: { settings.hoverDelay }, set: { settings.hoverDelay = $0 }
                )) { $0.name }
                .disabled(!settings.openOnHover)
                .opacity(settings.openOnHover ? 1 : 0.4)
            }
            SettingsRow("Haptic feedback") {
                NotchSwitch(isOn: Binding(get: { settings.haptics }, set: { settings.haptics = $0 }))
            }
        }
    }

    private var dragging: some View {
        SettingsSection(title: "Dragging out") {
            SettingsRow("Send note with image", caption: "Apps that accept text get it too") {
                NotchSwitch(isOn: Binding(get: { settings.includeNoteTextInDrag }, set: { settings.includeNoteTextInDrag = $0 }))
            }
            SettingsRow("Copy note to clipboard", caption: "So ⌘V always works") {
                NotchSwitch(isOn: Binding(get: { settings.copyNoteOnDrag }, set: { settings.copyNoteOnDrag = $0 }))
            }
        }
    }

    private var library: some View {
        SettingsSection(title: "Library") {
            SettingsRow("Remove after sending", caption: "Once dropped into another app") {
                NotchSwitch(isOn: Binding(get: { settings.removeAfterDragOut }, set: { settings.removeAfterDragOut = $0 }))
            }
            HStack(alignment: .center, spacing: 10) {
                Text("Delete after")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                    .fixedSize()
                    .help("Older screenshots go to the Trash automatically")
                Spacer(minLength: 4)
                PillPicker(options: AppSettings.Expiry.allCases, selection: Binding(
                    get: { settings.expiry }, set: { settings.expiry = $0 }
                )) { $0.name }
                .fixedSize()
            }
        }
    }

    // MARK: Actions

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            model.showNotice("exclamationmark.triangle.fill", "Couldn’t change login item")
        }
        launchAtLogin = LaunchAtLogin.isEnabled
        loginNeedsApproval = LaunchAtLogin.statusDescription.hasPrefix("needs approval")
    }

    private func loadLibrarySummary() async {
        let count = model.store.shots.count
        let folder = model.store.imagesURL
        let bytes = await Task.detached(priority: .utility) { () -> Int64 in
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return files.reduce(Int64(0)) { total, url in
                total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }.value
        let sizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        librarySummary = "\(count) \(count == 1 ? "screenshot" : "screenshots") · \(sizeText)"
    }
}

// MARK: - Building blocks

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(Palette.tertiaryText)
            VStack(alignment: .leading, spacing: 9) {
                content
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let label: String
    var caption: String?
    @ViewBuilder var control: Control

    init(_ label: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.primaryText)
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(Palette.tertiaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            // Controls keep their natural width; labels and captions wrap around them.
            control.fixedSize()
        }
        .frame(minHeight: 22)
    }
}

private struct Swatch: View {
    let fill: AnyShapeStyle
    let selected: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .frame(width: 16, height: 16)
                .padding(2.5)
                .overlay(Circle().strokeBorder(Color.white.opacity(selected ? 0.95 : (hovering ? 0.3 : 0)), lineWidth: 1.5))
                .scaleEffect(hovering ? 1.1 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// Switch drawn in SwiftUI so it keeps the accent colour even though the notch
/// panel is never the "active" window (system switches turn grey there).
private struct NotchSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? Palette.noteAccent : Color.white.opacity(0.14))
                Circle()
                    .fill(isOn ? Color.black.opacity(0.85) : Color.white.opacity(0.85))
                    .padding(2)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
            }
            .frame(width: 30, height: 17)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Compact segmented control matching the notch's look.
private struct PillPicker<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black : Palette.secondaryText)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background {
                            if isSelected {
                                Capsule().fill(Color.white.opacity(0.92))
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.surface))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
    }
}
