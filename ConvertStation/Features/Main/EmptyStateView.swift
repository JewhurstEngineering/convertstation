import SwiftUI

/// The whole window before any file is added: one drop target.
struct EmptyStateView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Brand.magenta)
                .frame(width: 72, height: 72)
                .background(Brand.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                .accessibilityHidden(true)
            Text(model.dropTargeted ? "Release to add" : "Drop videos to convert")
                .font(.title2.weight(.semibold))
            Text("MOV, MP4 and M4V clips become looping Animated WebP files. Your originals are never changed.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Choose Files…") { model.isChoosingFiles = true }
                .controlSize(.large)
            HStack(spacing: 6) {
                Text("Saves to")
                Button {
                    model.chooseDestination()
                } label: {
                    Label(model.destinationURL?.lastPathComponent ?? "Choose a folder", systemImage: "folder")
                }
                .buttonStyle(.link)
                Text("· \(model.defaultPreset.title) preset")
            }
            .foregroundStyle(.secondary)
            .padding(.top, 12)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 56)
        .frame(maxWidth: 620)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(model.dropTargeted ? Brand.blue.opacity(0.06) : .clear)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(model.dropTargeted ? Brand.blue : Brand.hairline)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: model.dropTargeted)
    }
}
