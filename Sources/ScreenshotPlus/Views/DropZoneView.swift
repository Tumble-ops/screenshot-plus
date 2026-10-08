import SwiftUI

/// Shown while a screenshot is dragged toward the notch.
struct DropZoneView: View {
    let model: NotchModel

    var body: some View {
        let targeted = model.isDropTargeted
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        ZStack {
            shape.fill(Color.white.opacity(targeted ? 0.09 : 0.035))
            shape.strokeBorder(
                Color.white.opacity(targeted ? 0.55 : 0.22),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: targeted ? 11 : 0)
            )

            VStack(spacing: 7) {
                if model.isImporting {
                    ProgressView().controlSize(.small)
                    Text("Importing…")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                } else {
                    Image(systemName: targeted ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(Palette.primaryText)
                        .offset(y: targeted ? 2 : 0)
                        .contentTransition(.symbolEffect(.replace))
                    Text(targeted ? "Release to save" : "Drop screenshot here")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.primaryText)
                        .contentTransition(.opacity)
                    Text("You can add a note next — optional")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.secondaryText)
                }
            }
        }
        .scaleEffect(targeted ? 1.015 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .padding(EdgeInsets(top: 8, leading: 16, bottom: 16, trailing: 16))
        .frame(width: model.shapeSize(for: .dropZone).width,
               height: model.shapeSize(for: .dropZone).height - model.notchSize.height)
    }
}
