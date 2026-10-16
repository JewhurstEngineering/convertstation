import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    var checkForUpdates: () -> Void = {}

    @State private var installMessage: String?
    @State private var installSucceeded = false
    @State private var isInstalling = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                appearanceSection
                outputSection
                defaultsSection
                engineSection
                aboutSection
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Brand.canvas)
    }

    private var header: some View {
        VStack(spacing: 6) {
            BrandLockup()
            Text("Files stay on this Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Appearance")
            HStack(spacing: 10) {
                ForEach(AppearancePreference.allCases) { preference in
                    AppearanceCard(preference: preference, selected: model.appearance == preference) {
                        model.setAppearance(preference)
                    }
                }
            }
            .accessibilityRepresentation {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppearancePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
            }
            Text(model.appearance.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var outputSection: some View {
        SettingsBlock(
            title: "Output",
            footer: "Converted files go in this folder. The original file is left alone."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Folder")
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(folderTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(model.destinationURL == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Brand.fieldFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .help(model.destinationURL?.path ?? "No output folder yet")
                        .accessibilityLabel("Output folder")
                        .accessibilityValue(model.destinationURL?.path ?? "Not chosen")
                    Button("Choose…") { model.chooseDestination() }
                        .accessibilityLabel("Choose output folder")
                        .accessibilityHint("Converted files are written here. Originals stay where they are.")
                    if let folder = model.destinationURL {
                        Button("Show in Finder") { model.reveal(folder) }
                            .accessibilityLabel("Show output folder in Finder")
                    }
                }
            }
            .padding(12)

            GroupedRowDivider()

            VStack(alignment: .leading, spacing: 8) {
                Text("If a file name exists")
                    .foregroundStyle(.secondary)
                SegmentedPills(options: CollisionPolicy.allCases, selection: policy) { $0.title }
                    .accessibilityLabel("If a file name exists")
                Text(model.collisionPolicy.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .accessibilityHint(model.collisionPolicy.summary)
        }
    }

    private var defaultsSection: some View {
        SettingsBlock(
            title: "Defaults",
            footer: "This is used the next time you add a file. Files already in the queue keep their own settings."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset for new files")
                    .foregroundStyle(.secondary)
                SegmentedPills(options: Array(PresetID.allCases), selection: preset) { $0.shortTitle }
                    .accessibilityLabel("Preset for new files")
                Text(presetDetail(model.defaultPreset))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .accessibilityHint(presetDetail(model.defaultPreset))
        }
    }

    private var engineSection: some View {
        SettingsBlock(
            title: "Engine",
            footer: "Conversion runs on this Mac with the FFmpeg copy inside the app."
        ) {
            settingsLine {
                Text("Still images")
                Spacer()
                Text("Built in")
                    .foregroundStyle(.secondary)
            }
            GroupedRowDivider()
            settingsLine {
                Text("Animated WebP")
                Spacer()
                Text(engineValue)
                    .foregroundStyle(engineColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Animated WebP")
            .accessibilityValue(engineValue)
            .accessibilityHint(model.engine.detail)

            if model.engineCheckComplete, !model.engine.supportsAnimatedWebP {
                Text(model.engine.detail)
                    .font(.callout)
                    .foregroundStyle(Brand.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            GroupedRowDivider()
            DisclosureGroup("Engine details") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Version", value: model.engine.versionSummary)
                        .accessibilityLabel("FFmpeg version")
                        .accessibilityValue(model.engine.versionSummary)
                    if let path = model.engine.ffmpegURL?.path {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Location")
                                .foregroundStyle(.secondary)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityHint("Shows the FFmpeg version and where it lives in the app")
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsBlock(
                title: "Updates",
                footer: "ConvertStation looks for a newer release on its own. You can check now."
            ) {
                settingsLine {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button("Check for Updates…", action: checkForUpdates)
                }
            }

            SettingsBlock(title: "Privacy") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Files stay on this Mac. ConvertStation does not upload them, and it does not send telemetry.")
                    Text("The app can only read files you drop or pick, and the output folder you choose.")
                    Text("FFmpeg in this copy is a GPL build from this Mac. It is not cleared to ship to other people.")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
            }

            SettingsBlock(
                title: "Install",
                footer: "A copy from Xcode or a download is not the installed app. Installing puts ConvertStation in Applications and replaces one that is already there."
            ) {
                installContent
            }
        }
    }

    @ViewBuilder
    private var installContent: some View {
        if AppInstall.isRunningFromApplications {
            settingsLine {
                Label("Installed in Applications. Search “ConvertStation”.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Brand.success)
                Spacer(minLength: 0)
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    installToApplications()
                } label: {
                    if isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Install to Applications", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isInstalling)
                .accessibilityLabel("Install to Applications")

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
            .padding(12)
        }

        if let installMessage {
            Text(installMessage)
                .font(.callout)
                .foregroundStyle(installSucceeded ? Color.secondary : Brand.warning)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, AppInstall.isRunningFromApplications ? 0 : -4)
        }
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
                let destination = try await AppInstall.copyRunningAppToApplications()
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
        return model.engine.supportsAnimatedWebP ? Brand.success : Brand.danger
    }

    private var appearance: Binding<AppearancePreference> {
        Binding(get: { model.appearance }, set: { model.setAppearance($0) })
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

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func settingsLine<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
    }
}

private struct SettingsBlock<Content: View>: View {
    var title: String
    var footer: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            GroupedRows { content() }
            if let footer {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct AppearanceCard: View {
    var preference: AppearancePreference
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                AppearancePreview(preference: preference)
                    .frame(height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text(preference.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Brand.blue.opacity(0.08) : Brand.panel)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Brand.blue : Brand.hairline, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: selected)
        .accessibilityLabel(preference.title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint(preference.detail)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct AppearancePreview: View {
    var preference: AppearancePreference

    var body: some View {
        switch preference {
        case .system:
            HStack(spacing: 0) {
                ThemeSample(scheme: .light)
                Rectangle()
                    .fill(Brand.Surface.hairline(.light))
                    .frame(width: 1)
                ThemeSample(scheme: .dark)
            }
        case .light:
            ThemeSample(scheme: .light)
        case .dark:
            ThemeSample(scheme: .dark)
        }
    }
}

/// A tiny window, drawn in one scheme so the choice stays readable after you pick it.
private struct ThemeSample: View {
    var scheme: ColorScheme

    var body: some View {
        HStack(spacing: 0) {
            Brand.Surface.sidebar(scheme)
                .frame(width: 14)
            Rectangle()
                .fill(Brand.Surface.hairline(scheme))
                .frame(width: 1)
            ZStack(alignment: .topLeading) {
                Brand.Surface.canvas(scheme)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Brand.accentGradient)
                            .frame(width: 8, height: 8)
                        Capsule()
                            .fill(Brand.Surface.hairline(scheme))
                            .frame(width: 28, height: 4)
                    }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Brand.Surface.panel(scheme))
                        .frame(height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .strokeBorder(Brand.Surface.hairline(scheme), lineWidth: 1)
                        )
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Brand.blue)
                                .frame(width: 16, height: 4)
                                .padding(.leading, 5)
                        }
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Brand.Surface.field(scheme))
                        .frame(width: 46, height: 8)
                }
                .padding(7)
            }
        }
    }
}
