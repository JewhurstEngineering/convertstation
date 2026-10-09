import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.jobs.isEmpty {
                EmptyStateView(model: model)
            } else {
                switch model.layoutMode {
                case .studio:
                    HStack(spacing: 0) {
                        QueueSidebar(model: model)
                            .frame(minWidth: 240, idealWidth: 280, maxWidth: 300)
                        Divider()
                        StudioDetail(model: model)
                            .frame(minWidth: 420)
                            .layoutPriority(1)
                        Divider()
                        InspectorPanel(model: model)
                            .frame(minWidth: 280, idealWidth: 320, maxWidth: 340)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .batch:
                    BatchView(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Divider()
                BottomBar(model: model)
            }
        }
        .background(Brand.canvas)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Image("Mark")
                    .resizable()
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("ConvertStation")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.layoutMode == .batch, !model.jobs.isEmpty {
                    Picker("Default preset", selection: defaultPreset) {
                        ForEach([PresetID.smallFile, .balanced, .highQuality]) { preset in
                            Text(preset.shortTitle).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Preset for files you add")
                }
                Menu {
                    Button {
                    } label: {
                        Label("Animated WebP", systemImage: "checkmark")
                    }
                    Text("More formats are on the way")
                } label: {
                    Label("Animated WebP", systemImage: "play.rectangle")
                        .labelStyle(.titleAndIcon)
                }
                .help("Output format")
                .accessibilityLabel("Output format, Animated WebP")

                Picker("Layout", selection: layout) {
                    ForEach(LayoutMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImage).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Studio shows one file at a time. Batch lists every file.")

                Button {
                    model.isChoosingFiles = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .keyboardShortcut("o", modifiers: .command)
                .help("Choose files to convert")
            }
        }
        .fileImporter(
            isPresented: $model.isChoosingFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.importURLs(urls)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            Task {
                let urls = await Self.loadURLs(providers)
                await MainActor.run { model.importURLs(urls) }
            }
            return true
        }
        .alert(
            "\(model.collisionPrompt?.filename ?? "This file") already exists",
            isPresented: collisionPresented,
            presenting: model.collisionPrompt
        ) { prompt in
            if !prompt.replaceOnly {
                Button("Keep Both") { model.resolveCollision(.keepBoth) }
                Button("Skip") { model.resolveCollision(.skip) }
            }
            Button("Replace", role: .destructive) { model.resolveCollision(.replace) }
            Button("Cancel", role: .cancel) { model.resolveCollision(.cancel) }
        } message: { _ in
            Text("The original file is left alone. Replace only swaps the previous output after the new one checks out.")
        }
        .onDeleteCommand { model.removeSelected() }
        .onKeyPress(.space) {
            model.quickLookSelected()
            return .handled
        }
    }

    private var layout: Binding<LayoutMode> {
        Binding(get: { model.layoutMode }, set: { model.setLayoutMode($0) })
    }

    private var defaultPreset: Binding<PresetID> {
        Binding(get: { model.defaultPreset }, set: { model.setDefaultPreset($0) })
    }

    private var collisionPresented: Binding<Bool> {
        Binding(
            get: { model.collisionPrompt != nil },
            set: { presented in
                if !presented, model.collisionPrompt != nil {
                    model.resolveCollision(.cancel)
                }
            }
        )
    }

    private static func loadURLs(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = await loadURL(provider) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }
                if let data = item as? Data {
                    continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil))
                    return
                }
                continuation.resume(returning: nil)
            }
        }
    }
}

private struct BottomBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.engineCheckComplete, !model.engine.supportsAnimatedWebP {
                Label(model.engine.detail, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(Brand.warning)
            }
            HStack(spacing: 12) {
                Button {
                    model.chooseDestination()
                } label: {
                    Label(destinationTitle, systemImage: "folder")
                }
                .help(model.destinationURL?.path ?? "Choose where converted files go")
                .accessibilityLabel("Output folder")
                .accessibilityValue(model.destinationURL?.lastPathComponent ?? "Not chosen")

                Picker("If the name exists", selection: policy) {
                    ForEach(CollisionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .foregroundStyle(.secondary)
                .accessibilityLabel("If the name exists")

                Spacer(minLength: 12)

                if model.layoutMode == .batch, let totals = model.queueTotals {
                    Text("Total ≈ \(MediaFormat.bytes(totals.output)) from \(MediaFormat.bytes(totals.source))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if model.isConverting {
                    Button("Cancel") { model.cancelActive() }
                        .keyboardShortcut(.cancelAction)
                } else if canConvert {
                    Text("⌘↩")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Button(convertTitle) {
                    model.convertAll()
                }
                .buttonStyle(AccentButtonStyle(enabled: canConvert))
                .disabled(!canConvert)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityHint(model.destinationURL == nil ? "Asks for an output folder first" : "Converts ready files to animated WebP")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Brand.panel)
    }

    private var destinationTitle: String {
        guard let folder = model.destinationURL?.lastPathComponent else { return "Choose Folder…" }
        return "Save to \(folder)"
    }

    private var canConvert: Bool {
        model.engine.supportsAnimatedWebP && !model.isConverting && model.convertibleCount > 0
    }

    private var convertTitle: String {
        if model.isConverting {
            return model.progressTitle
        }
        switch model.convertibleCount {
        case 0: return model.jobs.allSatisfy { $0.state == .completed } ? "All Converted" : "Convert"
        case 1: return "Convert"
        case let count: return "Convert \(count) Files"
        }
    }

    private var policy: Binding<CollisionPolicy> {
        Binding(
            get: { model.collisionPolicy },
            set: { model.setCollisionPolicy($0) }
        )
    }
}
