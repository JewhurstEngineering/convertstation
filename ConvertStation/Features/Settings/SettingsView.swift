import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Output") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.destinationURL?.path ?? "Not chosen")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.destinationURL == nil ? .secondary : .primary)
                        Button("Choose…") { model.chooseDestination() }
                    }
                }
                Picker("If a file name exists", selection: policy) {
                    ForEach(CollisionPolicy.allCases) { policy in
                        Text("\(policy.title) — \(policy.summary)").tag(policy)
                    }
                }
            }

            Section("Engine") {
                LabeledContent("FFmpeg", value: model.engine.versionSummary)
                LabeledContent("Animated WebP", value: model.engine.supportsAnimatedWebP ? "Available" : "Missing")
                if let path = model.engine.ffmpegURL?.path {
                    LabeledContent("Path") {
                        Text(path)
                            .font(.caption)
                            .textSelection(.enabled)
                    }
                }
                Text(model.engine.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Text("Files stay on this Mac. ConvertStation does not upload them, and it does not send telemetry.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("The app is sandboxed. It can only read files you drop or pick, and the output folder you choose. FFmpeg is copied into the app at build time from this Mac. A Homebrew GPL build is still not cleared for redistribution.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    private var policy: Binding<CollisionPolicy> {
        Binding(
            get: { model.collisionPolicy },
            set: { model.setCollisionPolicy($0) }
        )
    }
}
