import SwiftUI

/// Preview of the dropped screenshot, an optional note, and Save.
struct ComposeView: View {
    let model: NotchModel
    @FocusState private var noteFocused: Bool

    var body: some View {
        let size = model.shapeSize(for: .compose)

        VStack(spacing: 12) {
            preview
                .frame(height: 158)

            noteField

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text(model.draftTitlePreview)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: model.draftTitlePreview)
                }
                .foregroundStyle(Palette.secondaryText)
                .help("Title — editable later")

                Spacer(minLength: 8)

                Button("Cancel") { model.cancelDraft() }
                    .buttonStyle(PillButtonStyle())
                Button {
                    model.saveDraft()
                } label: {
                    HStack(spacing: 5) {
                        Text("Save")
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .bold))
                            .opacity(0.55)
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
            }
        }
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        .frame(width: size.width, height: size.height - model.notchSize.height, alignment: .top)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { noteFocused = true }
        }
        .onChange(of: noteFocused) { _, focused in model.isTextFieldFocused = focused }
    }

    @ViewBuilder private var preview: some View {
        if let draft = model.draft, let first = draft.previews.first {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    // A hint of a stack when several screenshots were dropped together.
                    if draft.previews.count > 1 {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .padding(.horizontal, 26)
                            .offset(y: -8)
                    }
                    Image(nsImage: first)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.hairline))
                        .shadow(color: .black.opacity(0.6), radius: 10, y: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if draft.previews.count > 1 {
                    Text("\(draft.previews.count) screenshots")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(Color.white.opacity(0.9)))
                        .padding(6)
                }
            }
        }
    }

    private var noteField: some View {
        let note = Binding<String>(
            get: { model.draft?.note ?? "" },
            set: { model.draft?.note = $0 }
        )
        return TextField("Add a note or prompt (optional)...", text: note, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(Palette.primaryText)
            .lineLimit(3, reservesSpace: true)
            .focused($noteFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Palette.surface))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(noteFocused ? 0.28 : 0.08))
            )
            .animation(.easeOut(duration: 0.15), value: noteFocused)
    }
}
