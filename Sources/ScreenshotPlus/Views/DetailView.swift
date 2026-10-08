import ScreenshotPlusCore
import SwiftUI

/// One screenshot: large draggable preview, editable title and note, actions.
struct DetailView: View {
    let model: NotchModel
    let shot: Shot

    @State private var image: NSImage?
    @State private var title = ""
    @State private var noteDraft = ""
    @State private var editingNote = false
    @State private var confirmDelete = false
    @State private var previewHovering = false
    @FocusState private var focus: Field?

    private enum Field { case title, note }

    var body: some View {
        let size = model.shapeSize(for: .detail(shot.id))

        HStack(alignment: .top, spacing: 16) {
            previewPane
                .frame(width: 320)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    IconButton(symbol: "chevron.left", size: 24, help: "Back to all screenshots") {
                        model.mode = .library
                    }
                    Text(metadata)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                TextField("Title", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...2)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .focused($focus, equals: .title)
                    .onSubmit(commitTitle)
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(focus == .title ? Palette.surface : .clear))
                    .padding(.horizontal, -6)
                    .help("Click to rename")

                noteArea
                    .frame(maxHeight: .infinity, alignment: .top)

                actions
            }
            .frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 8, leading: 18, bottom: 16, trailing: 18))
        .frame(width: size.width, height: size.height - model.notchSize.height, alignment: .top)
        .onAppear {
            title = shot.title
            noteDraft = shot.note
        }
        .onChange(of: shot.title) { _, newValue in if focus != .title { title = newValue } }
        .onChange(of: focus) { old, new in
            model.isTextFieldFocused = new != nil
            if old == .title, new != .title { commitTitle() }
        }
        .task(id: shot.id) {
            let url = model.store.imageURL(for: shot)
            image = model.store.thumbnail(for: shot)
            let full = await Task.detached(priority: .userInitiated) {
                ImageImporter.downsampledImage(url: url, maxPixelSize: 1400)
            }.value
            if let full { image = full }
        }
    }

    private var dragHint: String {
        guard shot.hasNote else { return "Drag into any app" }
        if Preferences.includeNoteTextInDrag { return "Drag into any app — the note comes along" }
        return Preferences.copyNoteOnDrag ? "Drag into any app — the note is copied for ⌘V" : "Drag into any app"
    }

    private var metadata: String {
        let date = shot.createdAt.formatted(.dateTime.month(.abbreviated).day()) + ", "
            + shot.createdAt.formatted(date: .omitted, time: .shortened)
        return "\(date) · \(shot.pixelWidth)×\(shot.pixelHeight)"
    }

    // MARK: Preview

    private var previewPane: some View {
        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                        .padding(6)
                        .scaleEffect(previewHovering ? 1.01 : 1)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(previewHovering ? 0.22 : 0.06)))
            .overlay(
                DragSource(
                    payload: {
                        guard let image else { return nil }
                        return model.dragPayload(for: shot, image: image)
                    },
                    onHover: { previewHovering = $0 },
                    onBegin: { model.dragDidBegin(shot) },
                    onEnd: { operation, _ in model.dragDidEnd(operation: operation) }
                )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: previewHovering)

            HStack(spacing: 5) {
                Image(systemName: "hand.draw")
                Text(dragHint)
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Palette.tertiaryText)
        }
    }

    // MARK: Note

    @ViewBuilder private var noteArea: some View {
        let box = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if editingNote {
            VStack(alignment: .trailing, spacing: 6) {
                TextField("Add a note or prompt…", text: $noteDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(5, reservesSpace: true)
                    .focused($focus, equals: .note)
                    .padding(10)
                    .background(box.fill(Palette.surface))
                    .overlay(box.strokeBorder(Color.white.opacity(0.25)))
                HStack(spacing: 6) {
                    Button("Cancel") {
                        noteDraft = shot.note
                        editingNote = false
                    }
                    .buttonStyle(PillButtonStyle())
                    Button("Done") {
                        model.store.updateNote(shot.id, to: noteDraft)
                        editingNote = false
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            .onAppear { DispatchQueue.main.async { focus = .note } }
        } else if shot.hasNote {
            ScrollView(.vertical) {
                Text(shot.note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .scrollIndicators(.never)
            .frame(maxHeight: 132)
            .background(box.fill(Palette.surface))
            .overlay(alignment: .topLeading) {
                Rectangle().fill(Palette.noteAccent).frame(width: 2.5).padding(.vertical, 10)
            }
            .clipShape(box)
        } else {
            Button {
                noteDraft = ""
                editingNote = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add a note or prompt")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(box.strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                .contentShape(box)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 6) {
            ActionButton(symbol: "doc.on.doc", label: "Copy Note", disabled: !shot.hasNote) {
                model.copyNote(shot)
            }
            ActionButton(symbol: "photo", label: "Copy Image") {
                model.copyImage(shot)
            }
            ActionButton(symbol: "pencil", label: "Edit") {
                noteDraft = shot.note
                editingNote = true
            }
            ActionButton(
                symbol: confirmDelete ? "trash.fill" : "trash",
                label: confirmDelete ? "Confirm" : "Delete",
                tint: confirmDelete ? Color(red: 1, green: 0.42, blue: 0.4) : Palette.primaryText
            ) {
                if confirmDelete {
                    model.delete(shot)
                } else {
                    confirmDelete = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirmDelete = false }
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: confirmDelete)
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            title = shot.title
        } else {
            model.store.rename(shot.id, to: trimmed)
        }
    }
}
