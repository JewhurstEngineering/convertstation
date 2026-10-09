import SwiftUI

/// The whole window before any file is added: one drop target.
struct EmptyStateView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            Image("Mark")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .accessibilityLabel("ConvertStation")
            Text(model.dropTargeted ? "Release to add" : "Drop files to convert")
                .font(.title2.weight(.semibold))
            Text("Video, images, and audio stay on this Mac. The format list only shows what this file can become. Originals are never changed.")
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
