import AppKit
import Foundation
import Observation

struct CollisionPrompt: Identifiable, Equatable {
    var id = UUID()
    var jobID: UUID
    var filename: String
    var replaceOnly: Bool
}

@MainActor
@Observable
final class AppModel {
    var jobs: [ConversionJob] = []
    var selectedJobID: UUID?
    var destinationURL: URL?
    var collisionPolicy: CollisionPolicy = .ask
    var engine: EngineStatus = .checking
    var engineCheckComplete = false
    var isChoosingFiles = false
    var dropTargeted = false
    var collisionPrompt: CollisionPrompt?
    var quickLook = QuickLookPresenter()

    private let fileAccess = FileAccessManager()
    private let preferences = PreferencesStore()
    private var registry: CapabilityRegistry
    private var conversionTask: Task<Void, Never>?
    private var activeRunner: ProcessRunner?
    private var collisionContinuation: CheckedContinuation<CollisionChoice, Never>?
    private var stopQueue = false

    init() {
        registry = CapabilityRegistry(providers: [])
        Task { await self.loadEngine() }
        collisionPolicy = preferences.collisionPolicy
        if let data = preferences.destinationBookmark, let url = try? fileAccess.resolveBookmark(data) {
            destinationURL = url
            fileAccess.beginAccess(url)
        }
        jobs = JobStore.load()
        restoreSecurityScopes()
        selectedJobID = jobs.first?.id
    }

    private func loadEngine() async {
        let located = await Task.detached(priority: .userInitiated) {
            FFmpegLocator.locate()
        }.value
        engine = located
        engineCheckComplete = true
        if let binaries = located.binaries {
            registry = CapabilityRegistry(providers: [AnimatedWebPProvider(binaries: binaries)])
        }
    }

    private func restoreSecurityScopes() {
        for index in jobs.indices {
            guard let bookmark = jobs[index].sourceBookmark else { continue }
            guard let url = try? fileAccess.resolveBookmark(bookmark) else {
                jobs[index].state = .blockedByPermission
                jobs[index].errorMessage = "ConvertStation needs access to this file again. Drop it or use Add Files."
                continue
            }
            jobs[index].sourceURL = url
            if var descriptor = jobs[index].descriptor {
                descriptor.url = url
                jobs[index].descriptor = descriptor
            }
            fileAccess.beginAccess(url)
        }
    }

    var selectedJob: ConversionJob? {
        guard let selectedJobID else { return nil }
        return jobs.first { $0.id == selectedJobID }
    }

    var convertibleCount: Int {
        jobs.filter(\.canConvert).count
    }

    func importURLs(_ urls: [URL]) {
        let preset = preferences.lastPreset
        for url in urls {
            fileAccess.beginAccess(url)
            let path = url.standardizedFileURL.path
            let duplicate = jobs.contains { $0.sourceURL.standardizedFileURL.path == path }
            var job = ConversionJob.new(url: url, duplicate: duplicate)
            job.options = WebPOptions.preset(preset)
            job.sourceBookmark = try? fileAccess.bookmark(for: url)
            jobs.append(job)
            selectedJobID = job.id
            let id = job.id
            Task { await self.probe(id) }
        }
        saveJobs()
    }

    func remove(_ id: UUID) {
        if let job = jobs.first(where: { $0.id == id }) {
            if job.state.isActive {
                cancelActive()
            }
            fileAccess.endAccess(job.sourceURL)
        }
        jobs.removeAll { $0.id == id }
        if selectedJobID == id {
            selectedJobID = jobs.first?.id
        }
        saveJobs()
    }

    func removeSelected() {
        guard let selectedJobID else { return }
        remove(selectedJobID)
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Converted files are written here. Originals stay where they are."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setDestination(url)
    }

    func setDestination(_ url: URL) {
        if let previous = destinationURL {
            fileAccess.endAccess(previous)
        }
        destinationURL = url
        fileAccess.beginAccess(url)
        if let data = try? fileAccess.bookmark(for: url) {
            preferences.destinationBookmark = data
        }
    }

    func setCollisionPolicy(_ policy: CollisionPolicy) {
        collisionPolicy = policy
        preferences.collisionPolicy = policy
    }

    func applyPreset(_ preset: PresetID, to id: UUID? = nil) {
        let target = id ?? selectedJobID
        guard let target, let index = jobs.firstIndex(where: { $0.id == target }) else { return }
        jobs[index].options = WebPOptions.preset(preset, keepingTrim: jobs[index].options)
        preferences.lastPreset = preset
        saveJobs()
    }

    func updateOptions(for id: UUID? = nil, _ change: (inout WebPOptions) -> Void) {
        let target = id ?? selectedJobID
        guard let target, let index = jobs.firstIndex(where: { $0.id == target }) else { return }
        change(&jobs[index].options)
        jobs[index].options = jobs[index].options.markingCustomIfNeeded()
        preferences.lastPreset = jobs[index].options.presetID
        saveJobs()
    }

    func convertAll() {
        if destinationURL == nil {
            chooseDestination()
        }
        guard destinationURL != nil else { return }
        guard engine.supportsAnimatedWebP else { return }
        stopQueue = false
        conversionTask?.cancel()
        conversionTask = Task { await self.runQueue() }
    }

    func convertAgain(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].result = nil
        jobs[index].errorMessage = nil
        jobs[index].progress = nil
        transition(id, to: .ready)
        convertAll()
    }

    func cancelActive() {
        stopQueue = true
        activeRunner?.cancel()
        conversionTask?.cancel()
        if collisionContinuation != nil {
            resolveCollision(.cancel)
        }
        for job in jobs where job.state == .queued || job.state == .running || job.state == .verifying {
            transition(job.id, to: .cancelled)
            setMessage(job.id, "Conversion cancelled.", technical: nil)
        }
        saveJobs()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func quickLook(_ url: URL) {
        quickLook.show(url)
    }

    func quickLookSelected() {
        guard let job = selectedJob else { return }
        if let output = job.result?.outputURL {
            quickLook(output)
        }
    }

    func resolveCollision(_ choice: CollisionChoice) {
        collisionPrompt = nil
        let continuation = collisionContinuation
        collisionContinuation = nil
        continuation?.resume(returning: choice)
    }

    func targets(for job: ConversionJob) -> [TargetDescriptor] {
        guard let descriptor = job.descriptor else { return [] }
        return registry.targets(for: descriptor)
    }

    private func probe(_ id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let url = jobs[index].sourceURL
        fileAccess.beginAccess(url)
        defer { fileAccess.endAccess(url) }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            transition(id, to: .blockedByPermission)
            setMessage(id, "ConvertStation can't read this file.", technical: nil)
            saveJobs()
            return
        }
        guard let ffprobe = engine.ffprobeURL else {
            transition(id, to: .failed)
            setMessage(id, "ffprobe isn't available, so this file can't be inspected.", technical: engine.detail)
            saveJobs()
            return
        }
        do {
            let descriptor = try await Task.detached {
                try FFProbeParser.inspect(url: url, ffprobe: ffprobe)
            }.value
            guard jobs.contains(where: { $0.id == id }) else { return }
            if let index = jobs.firstIndex(where: { $0.id == id }) {
                jobs[index].descriptor = descriptor
                jobs[index].warnings.append(contentsOf: descriptor.warnings.filter { warning in
                    !jobs[index].warnings.contains(warning)
                })
                if descriptor.hasAudio {
                    let note = "Audio will be dropped. Animated WebP has no audio."
                    if !jobs[index].warnings.contains(note) {
                        jobs[index].warnings.append(note)
                    }
                }
                if let duration = descriptor.durationSeconds, duration > WebPLimits.longClipSeconds {
                    let note = "Clips longer than 30 seconds are capped unless you allow the full length."
                    if !jobs[index].warnings.contains(note) {
                        jobs[index].warnings.append(note)
                    }
                }
            }
            if !descriptor.hasVideo {
                transition(id, to: .failed)
                setMessage(
                    id,
                    descriptor.hasAudio
                        ? "This file has audio but no video. Animated WebP needs a video track."
                        : "No readable video stream was found.",
                    technical: descriptor.formatName
                )
            } else if registry.targets(for: descriptor).isEmpty {
                transition(id, to: .failed)
                setMessage(id, engine.supportsAnimatedWebP
                    ? "Animated WebP isn't available for this file."
                    : engine.detail, technical: nil)
            } else {
                transition(id, to: .ready)
                setMessage(id, nil, technical: nil)
            }
        } catch {
            transition(id, to: .failed)
            let conversion = error as? ConversionError
            setMessage(id, conversion?.errorDescription ?? error.localizedDescription, technical: conversion?.technicalLog)
        }
        saveJobs()
    }

    private func runQueue() async {
        while !Task.isCancelled && !stopQueue {
            guard let id = jobs.first(where: \.canConvert)?.id else { return }
            await convert(id)
        }
    }

    private func convert(_ id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard let descriptor = jobs[index].descriptor, let binaries = engine.binaries, let destination = destinationURL else {
            return
        }
        let options = jobs[index].options
        let sourceURL = jobs[index].sourceURL
        transition(id, to: .queued)
        guard !stopQueue, !Task.isCancelled else {
            transition(id, to: .cancelled)
            return
        }

        let proposed = OutputPublisher.proposedURL(source: sourceURL, directory: destination)
        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
        let publishTarget: URL
        let replacing: Bool
        do {
            switch try OutputPublisher.plan(proposed: proposed, source: sourceURL, policy: collisionPolicy, fileExists: exists) {
            case .write(let url):
                publishTarget = url
                replacing = false
            case .replace(let url):
                let choice = await promptCollision(jobID: id, filename: url.lastPathComponent, replaceOnly: true)
                guard choice == .replace else {
                    finishSkipOrCancel(id, choice: choice)
                    return
                }
                publishTarget = url
                replacing = true
            case .skip:
                transition(id, to: .cancelled)
                setMessage(id, ConversionError.skippedExisting.errorDescription, technical: nil)
                saveJobs()
                return
            case .ask(_, let url):
                let choice = await promptCollision(jobID: id, filename: url.lastPathComponent, replaceOnly: false)
                switch choice {
                case .keepBoth:
                    publishTarget = OutputPublisher.uniqueURL(url, fileExists: exists)
                    replacing = false
                case .replace:
                    publishTarget = url
                    replacing = true
                case .skip, .cancel:
                    finishSkipOrCancel(id, choice: choice)
                    return
                }
            }
        } catch {
            fail(id, error)
            return
        }

        transition(id, to: .running)
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            jobs[index].progress = 0
            jobs[index].errorMessage = nil
            jobs[index].result = nil
        }
        let runner = ProcessRunner()
        activeRunner = runner
        fileAccess.beginAccess(sourceURL)
        fileAccess.beginAccess(destination)
        defer {
            fileAccess.endAccess(sourceURL)
            fileAccess.endAccess(destination)
            if activeRunner === runner {
                activeRunner = nil
            }
        }
        do {
            let result = try await WebPConversion.convert(
                source: descriptor,
                options: options,
                destinationDirectory: destination,
                collisionPolicy: collisionPolicy,
                binaries: binaries,
                runner: runner,
                resolvedDestination: publishTarget,
                replacing: replacing
            ) { fraction in
                Task { @MainActor in
                    self.setProgress(id, fraction)
                }
            }
            guard jobs.contains(where: { $0.id == id }) else { return }
            if let index = jobs.firstIndex(where: { $0.id == id }) {
                jobs[index].result = result
                jobs[index].progress = 1
                for warning in result.warnings where !jobs[index].warnings.contains(warning) {
                    jobs[index].warnings.append(warning)
                }
            }
            transition(id, to: .completed)
            setMessage(id, nil, technical: nil)
        } catch is CancellationError {
            transition(id, to: .cancelled)
            setMessage(id, "Conversion cancelled.", technical: nil)
            return
        } catch let error as ConversionError where error == .cancelled {
            transition(id, to: .cancelled)
            setMessage(id, error.errorDescription, technical: nil)
        } catch {
            fail(id, error)
        }
        saveJobs()
    }

    private func promptCollision(jobID: UUID, filename: String, replaceOnly: Bool) async -> CollisionChoice {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                collisionContinuation = continuation
                collisionPrompt = CollisionPrompt(jobID: jobID, filename: filename, replaceOnly: replaceOnly)
            }
        } onCancel: {
            Task { @MainActor in
                self.resolveCollision(.cancel)
            }
        }
    }

    private func finishSkipOrCancel(_ id: UUID, choice: CollisionChoice) {
        if choice == .cancel {
            stopQueue = true
            transition(id, to: .ready)
            setMessage(id, nil, technical: nil)
        } else {
            transition(id, to: .cancelled)
            setMessage(id, ConversionError.skippedExisting.errorDescription, technical: nil)
        }
        saveJobs()
    }

    private func fail(_ id: UUID, _ error: Error) {
        let conversion = error as? ConversionError
        transition(id, to: .failed)
        setMessage(id, conversion?.errorDescription ?? error.localizedDescription, technical: conversion?.technicalLog ?? Diagnostics.redact(String(describing: error)))
        saveJobs()
    }

    private func transition(_ id: UUID, to state: JobState) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard JobTransition.allows(jobs[index].state, state) else { return }
        jobs[index].state = state
    }

    private func setMessage(_ id: UUID, _ message: String?, technical: String?) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].errorMessage = message
        jobs[index].technicalDetail = technical.map(Diagnostics.redact)
    }

    private func setProgress(_ id: UUID, _ fraction: Double) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let current = jobs[index].progress ?? 0
        jobs[index].progress = max(current, fraction)
    }

    private func saveJobs() {
        var snapshot = jobs
        for index in snapshot.indices {
            snapshot[index].progress = nil
            if let detail = snapshot[index].technicalDetail {
                snapshot[index].technicalDetail = Diagnostics.redact(detail)
            }
        }
        JobStore.save(snapshot)
    }
}
