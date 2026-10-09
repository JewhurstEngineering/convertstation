import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    var checkForUpdates: () -> Void = {}

    @State private var installMessage: String?
    @State private var installSucceeded = false
    @State private var isInstalling = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text(folderTitle)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(model.destinationURL == nil ? .secondary : .primary)
                            .help(model.destinationURL?.path ?? "No output folder yet")
                            .accessibilityLabel("Output folder")
                            .accessibilityValue(model.destinationURL?.path ?? "Not chosen")
                        Spacer(minLength: 8)
                        Button("Choose…") { model.chooseDestination() }
                            .accessibilityLabel("Choose output folder")
                            .accessibilityHint("Converted files are written here. Originals stay where they are.")
                        if let folder = model.destinationURL {
                            Button("Show in Finder") { model.reveal(folder) }
                                .accessibilityLabel("Show output folder in Finder")
                        }
                    }
                }
                Picker("If a file name exists", selection: policy) {
                    ForEach(CollisionPolicy.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .accessibilityHint(model.collisionPolicy.summary)
                Text(model.collisionPolicy.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } header: {
                Text("Output")
            } footer: {
                Text("Converted files go in this folder. The original movie is left alone.")
            }

            Section {
                Picker("Preset for new files", selection: preset) {
                    ForEach(PresetID.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .accessibilityHint(presetDetail(model.defaultPreset))
                Text(presetDetail(model.defaultPreset))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            } header: {
                Text("Defaults")
            } footer: {
                Text("This is used the next time you add a file. Files already in the queue keep their own settings.")
            }

            Section {
                LabeledContent("Animated WebP") {
                    Text(engineValue)
                        .foregroundStyle(engineColor)
                }
                .accessibilityLabel("Animated WebP")
                .accessibilityValue(engineValue)
                .accessibilityHint(model.engine.detail)

                if model.engineCheckComplete, !model.engine.supportsAnimatedWebP {
                    Text(model.engine.detail)
                        .font(.callout)
                        .foregroundStyle(.primary)
                }

                DisclosureGroup("Engine details") {
                    LabeledContent("Version", value: model.engine.versionSummary)
                        .accessibilityLabel("FFmpeg version")
                        .accessibilityValue(model.engine.versionSummary)
                    if let path = model.engine.ffmpegURL?.path {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location")
                                .font(.callout)
                            Text(path)
                                .font(.callout)
                                .textSelection(.enabled)
                                .accessibilityLabel("FFmpeg location")
                                .accessibilityValue(path)
                        }
                    }
                    Text(model.engine.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHint("Shows the FFmpeg version and where it lives in the app")
            } header: {
                Text("Engine")
            } footer: {
                Text("Conversion runs on this Mac with the FFmpeg copy inside the app.")
            }

            Section {
                Text("Files stay on this Mac. ConvertStation does not upload them, and it does not send telemetry.")
                Text("The app can only read files you drop or pick, and the output folder you choose.")
                Text("FFmpeg in this copy is a GPL build from this Mac. It is not cleared to ship to other people.")
            } header: {
                Text("Privacy")
            }

            Section {
                LabeledContent("Version", value: appVersion)
                Button("Check for Updates…", action: checkForUpdates)
            } header: {
                Text("Updates")
            } footer: {
                Text("ConvertStation looks for a newer release on its own. You can check now.")
            }

            Section {
                if AppInstall.isRunningFromApplications {
                    Label("Installed in Applications. Search “ConvertStation”.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        installToApplications()
                    } label: {
                        if isInstalling {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Install to Applications", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isInstalling)
                    .accessibilityLabel("Install to Applications")

                    Label("Install. This does not open a second copy.", systemImage: "1.circle")
                    Label("Quit this copy, then open Applications and ConvertStation.", systemImage: "2.circle")

                    if installSucceeded {
                        HStack(spacing: 8) {
                            Button("Reveal in Finder") {
                                AppInstall.revealInstalledApp()
                            }
                            Button("Quit this copy and open the installed app") {
                                AppInstall.launchInstalledAndTerminate()
                            }
                        }
                    }
                }

                if let installMessage {
                    Text(installMessage)
                        .font(.callout)
                        .foregroundStyle(installSucceeded ? Color.secondary : Color.orange)
                }
            } header: {
                Text("Install")
            } footer: {
                Text("A copy from Xcode or a download is not the installed app. Installing puts ConvertStation in Applications and replaces one that is already there.")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    private func installToApplications() {
        isInstalling = true
        installMessage = nil
        Task {
            do {
                let destination = try await Task.detached {
                    try AppInstall.copyRunningAppToApplications()
                }.value
                installSucceeded = true
                installMessage = "Copied to \(destination.path). Quit this copy, then open ConvertStation from Applications."
            } catch {
                installSucceeded = false
                installMessage = error.localizedDescription
            }
            isInstalling = false
        }
    }

    private var folderTitle: String {
        model.destinationURL?.path ?? "Not chosen"
    }

    private var engineValue: String {
        if !model.engineCheckComplete { return "Checking…" }
        return model.engine.supportsAnimatedWebP ? "Available" : "Missing"
    }

    private var engineColor: Color {
        if !model.engineCheckComplete { return .secondary }
        return model.engine.supportsAnimatedWebP ? .primary : .red
    }

    private var policy: Binding<CollisionPolicy> {
        Binding(
            get: { model.collisionPolicy },
            set: { model.setCollisionPolicy($0) }
        )
    }

    private var preset: Binding<PresetID> {
        Binding(
            get: { model.defaultPreset },
            set: { model.setDefaultPreset($0) }
        )
    }

    private func presetDetail(_ preset: PresetID) -> String {
        switch preset {
        case .smallFile:
            "8 fps, 480 px wide, quality 60. Smaller files."
        case .balanced:
            "12 fps, 800 px wide, quality 75. The usual starting point."
        case .highQuality:
            "20 fps, 1280 px wide, quality 85. Sharper, and the files are larger."
        case .maximum:
            "30 fps, original width, quality 100. The best this format can do, and the largest files."
        case .custom:
            "Keeps the frame rate, width, and quality from the last file you edited."
        }
    }
}
