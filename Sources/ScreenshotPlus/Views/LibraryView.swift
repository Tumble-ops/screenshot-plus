import ScreenshotPlusCore
import SwiftUI

/// Compact, searchable gallery of saved screenshots. Thumbnails drag straight out.
struct LibraryView: View {
    let model: NotchModel
    @FocusState private var searchFocused: Bool


    var body: some View {
        let size = model.shapeSize(for: .library)
        let shots = model.filteredShots
        let columnCount = AppSettings.shared.panelSize.libraryColumns
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columnCount)
        let cardWidth = (size.width - 2 * Layout.sideInset - 4 - 12 * CGFloat(columnCount - 1)) / CGFloat(columnCount)

        VStack(spacing: 10) {
            header(count: shots.count)

            if model.store.shots.isEmpty {
                emptyState(symbol: "tray", title: "No screenshots yet",
                           subtitle: "Take a screenshot and drag it onto the notch.")
            } else if shots.isEmpty {
                emptyState(symbol: "magnifyingglass", title: "No matches",
                           subtitle: "Nothing matches “\(model.searchText)” in titles or notes.")
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(shots) { shot in
                            ShotCard(model: model, shot: shot, thumbnailHeight: (cardWidth * 0.62).rounded())
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                    .padding(.bottom, 10)
                }
                .scrollIndicators(.never)
                .mask(
                    LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .padding(EdgeInsets(top: 8, leading: Layout.sideInset, bottom: 6, trailing: Layout.sideInset))
        .frame(width: size.width, height: size.height - model.notchSize.height, alignment: .top)
    }

    private func header(count: Int) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
                TextField("Search titles and notes", text: Binding(
                    get: { model.searchText }, set: { model.searchText = $0 }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.primaryText)
                .focused($searchFocused)
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(searchFocused ? 0.25 : 0)))
            .onChange(of: searchFocused) { _, focused in model.isTextFieldFocused = focused }

            Text(count == 1 ? "1 screenshot" : "\(count) screenshots")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.tertiaryText)
                .fixedSize()
                .padding(.horizontal, 4)

            IconButton(symbol: "doc.on.clipboard", help: "Save the image on the clipboard") {
                model.pasteFromClipboard()
            }
            IconButton(symbol: "gearshape", help: "Settings") {
                model.mode = .settings
            }
        }
    }

    private func emptyState(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 12)
    }
}

struct ShotCard: View {
    let model: NotchModel
    let shot: Shot
    var thumbnailHeight: CGFloat = 80
    @State private var hovering = false

    var body: some View {
        let thumbnail = model.store.thumbnail(for: shot)

        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Palette.surface
                    }
                }
                .frame(height: thumbnailHeight)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(hovering ? 0.4 : 0.08), lineWidth: hovering ? 1.5 : 1)
                )

                if shot.hasNote {
                    NoteBadge().padding(5)
                }
            }
            .shadow(color: .black.opacity(hovering ? 0.6 : 0), radius: 8, y: 3)

            Text(shot.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(hovering ? Palette.primaryText : Color.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 2)
        }
        .scaleEffect(hovering ? 1.035 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .overlay(
            DragSource(
                payload: {
                    guard let image = thumbnail else { return nil }
                    return model.dragPayload(for: shot, image: image)
                },
                onClick: { model.showDetail(shot.id) },
                onHover: { hovering = $0 },
                onBegin: { model.dragDidBegin(shot) },
                onEnd: { operation, _ in model.dragDidEnd(operation: operation) }
            )
        )
        .help(shot.hasNote ? shot.note : shot.title)
    }
}
