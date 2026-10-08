import ScreenshotPlusCore
import SwiftUI

/// The whole notch: one black surface that morphs between states, with the
/// state's content clipped inside it.
struct NotchRootView: View {
    let model: NotchModel

    var body: some View {
        let size = model.shapeSize
        let radii = model.cornerRadii
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)

        ZStack(alignment: .top) {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(model.mode.isExpanded ? 0.5 : 0), radius: 16, y: 8)

            ZStack(alignment: .top) {
                content
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .overlay(alignment: .topTrailing) { notice }
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(.notch, value: model.mode)
        .animation(.notch, value: model.draft != nil)
        .animation(.notch, value: model.metrics)
        .animation(.easeOut(duration: 0.2), value: model.notice)
    }

    @ViewBuilder private var content: some View {
        let notch = model.notchSize
        switch model.mode {
        case .collapsed:
            if let draft = model.draft {
                DraftEars(draft: draft, notch: notch)
                    .transition(.notchContent)
                    .onTapGesture { model.open() }
            } else {
                // Invisible, but clickable: a click on the notch opens it immediately.
                Color.black.opacity(0.001)
                    .frame(width: notch.width, height: notch.height)
                    .onTapGesture { model.open() }
            }

        case .toast(let toast):
            ToastEars(toast: toast, notch: notch)
                .id(toast.id)
                .transition(.notchContent)

        case .dropZone:
            DropZoneView(model: model)
                .padding(.top, notch.height)
                .transition(.notchContent)

        case .compose:
            ComposeView(model: model)
                .padding(.top, notch.height)
                .transition(.notchContent)

        case .library:
            LibraryView(model: model)
                .padding(.top, notch.height)
                .transition(.notchContent)

        case .detail(let id):
            if let shot = model.store.shot(id) {
                DetailView(model: model, shot: shot)
                    .id(id)
                    .padding(.top, notch.height)
                    .transition(.notchContent)
            }
        }
    }

    /// Short confirmations appear in the strip beside the physical notch, which is
    /// otherwise empty when expanded, so they never cover content.
    @ViewBuilder private var notice: some View {
        if let notice = model.notice, model.mode.isExpanded, model.mode != .dropZone {
            let notch = model.notchSize
            let earWidth = (model.shapeSize.width - notch.width) / 2
            HStack(spacing: 6) {
                Image(systemName: notice.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.noteAccent)
                Text(notice.text)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 12)
            .frame(width: earWidth, height: notch.height)
            .id(notice.id)
            .transition(.opacity.combined(with: .offset(y: -6)))
        }
    }
}

private struct ToastEars: View {
    let toast: Toast
    let notch: CGSize

    var body: some View {
        NotchEars(notchWidth: notch.width, earWidth: NotchModel.toastEarWidth, height: notch.height) {
            HStack {
                Image(systemName: toast.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(toast.tint)
                    .symbolEffect(.bounce, value: toast.id)
                Spacer(minLength: 0)
            }
            .padding(.leading, 18)
        } right: {
            HStack {
                Spacer(minLength: 0)
                Text(toast.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.trailing, 16)
        }
    }
}

private struct DraftEars: View {
    let draft: Draft
    let notch: CGSize

    var body: some View {
        NotchEars(notchWidth: notch.width, earWidth: NotchModel.draftEarWidth, height: notch.height) {
            HStack {
                if let preview = draft.previews.first {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 14)
        } right: {
            HStack {
                Spacer(minLength: 0)
                Circle()
                    .fill(Palette.noteAccent)
                    .frame(width: 7, height: 7)
                    .shadow(color: Palette.noteAccent.opacity(0.8), radius: 4)
            }
            .padding(.trailing, 16)
        }
        .help("Unsaved screenshot — hover to finish saving")
    }
}
