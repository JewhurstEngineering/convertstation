import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                QueuePane(model: model)
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 380, maxHeight: .infinity)
                InspectorView(model: model)
                    .frame(minWidth: 520, idealWidth: 760, maxHeight: .infinity)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            BottomBar(model: model)
        }
        .background(colorScheme == .dark ? Brand.navy : Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Image("Mark")
                    .resizable()
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("ConvertStation")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.isChoosingFiles = true
                } label: {
                    Label("Add Files", systemImage: "plus")
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
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 12) {
                Button {
                    model.chooseDestination()
                } label: {
                    Label(model.destinationURL?.lastPathComponent ?? "Choose Folder", systemImage: "folder")
                }
                .help(model.destinationURL?.path ?? "Choose where converted files go")
                .accessibilityLabel("Output folder")

                Picker("If the name exists", selection: policy) {
                    ForEach(CollisionPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 180)
                .accessibilityLabel("Name conflict")

                Spacer()

                if let output = finishedOutput {
                    Button("Show in Finder") { model.reveal(output) }
                        .help("Show the converted file in Finder")
                }

                if model.jobs.contains(where: { $0.state.isActive }) {
                    Button("Cancel") { model.cancelActive() }
                        .keyboardShortcut(.cancelAction)
                }

                Button(convertTitle) {
                    if model.convertibleCount == 0, let selected = model.selectedJob, selected.state == .completed {
                        model.convertAgain(selected.id)
                    } else {
                        model.convertAll()
                    }
                }
                .buttonStyle(AccentButtonStyle(enabled: canConvert))
                .disabled(!canConvert)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityHint(model.destinationURL == nil ? "Choose an output folder first" : "Convert ready files to animated WebP")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var finishedOutput: URL? {
        guard let job = model.selectedJob, job.state == .completed else { return nil }
        return job.result?.outputURL
    }

    private var canConvert: Bool {
        guard model.engine.supportsAnimatedWebP else { return false }
        if model.convertibleCount > 0 { return true }
        return model.selectedJob?.state == .completed && model.selectedJob?.descriptor?.hasVideo == true
    }

    private var convertTitle: String {
        if model.convertibleCount == 0, model.selectedJob?.state == .completed {
            return "Convert Again"
        }
        return model.convertibleCount > 1 ? "Convert All" : "Convert"
    }

    private var policy: Binding<CollisionPolicy> {
        Binding(
            get: { model.collisionPolicy },
            set: { model.setCollisionPolicy($0) }
        )
    }
}
