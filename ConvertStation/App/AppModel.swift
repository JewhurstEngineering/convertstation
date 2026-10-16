import AppKit
import Foundation
import Observation

struct CollisionPrompt: Identifiable, Equatable {
    var id = UUID()
    var jobID: UUID
    var filename: String
    var replaceOnly: Bool
}

enum ConversionQueue {
    /// The next file this run should start. Jobs already attempted are skipped,
    /// including one that just failed.
    static func nextJobID(in jobs: [ConversionJob], skipping attempted: Set<UUID>) -> UUID? {
        jobs.first { $0.canConvert && !attempted.contains($0.id) }?.id
    }
}

@MainActor
@Observable
final class AppModel {
    var jobs: [ConversionJob] = []
    var selectedJobID: UUID?
    var destinationURL: URL?
    var collisionPolicy: CollisionPolicy = .ask
    var defaultPreset: PresetID = .balanced
    var engine: EngineStatus = .checking
    var engineCheckComplete = false
    var isChoosingFiles = false
    var dropTargeted = false
    var collisionPrompt: CollisionPrompt?
    var quickLook = QuickLookPresenter()
    var layoutMode: LayoutMode = .studio
    var appearance: AppearancePreference = .system
    private(set) var savedPresets: [SavedPreset] = []
    /// Size of the current run and how many of its files have finished, for "Converting 1 of 2".
    private(set) var runTotal = 0
    private(set) var runFinished = 0

    private let fileAccess = FileAccessManager()
    private let preferences = PreferencesStore()
    private var registry: CapabilityRegistry
    private var conversionTask: Task<Void, Never>?
    private var activeRunner: ProcessRunner?
    private var collisionContinuation: CheckedContinuation<CollisionChoice, Never>?
    private var stopQueue = false

    init() {
        registry = CapabilityRegistry(providers: [StillImageProvider()])
        Task { await self.loadEngine() }
        collisionPolicy = preferences.collisionPolicy
        defaultPreset = preferences.lastPreset
        layoutMode = preferences.layoutMode
        appearance = preferences.appearance
        appearance.apply()
        savedPresets = preferences.savedPresets
        if let data = preferences.destinationBookmark, let url = try? fileAccess.resolveBookmark(data) {
            destinationURL = url
            fileAccess.beginAccess(url)
        }
        jobs = JobStore.load().map { job in
            var job = job
            job.options = job.options.matchingPresetIfPossible()
            return job
        }
        if defaultPreset == .custom {
            setDefaultPreset(.balanced)
        }
        restoreSecurityScopes()
        selectedJobID = jobs.first?.id
    }

    private func loadEngine() async {
        let located = await Task.detached(priority: .userInitiated) {
            FFmpegLocator.locate()
        }.value
        engine = located
        registry = Self.makeRegistry(from: located)
        engineCheckComplete = true
        let retry = jobs.filter { $0.descriptor == nil && ($0.state == .probing || $0.state == .failed) }.map(\.id)
        for id in retry {
            await probe(id)
        }
    }

    nonisolated static func makeRegistry(from status: EngineStatus) -> CapabilityRegistry {
        var providers: [any ConversionProvider] = [StillImageProvider(), DocumentProvider()]
        guard let binaries = status.binaries else {
            return CapabilityRegistry(providers: providers)
        }
        if status.supportsAnimatedWebP {
            providers.insert(AnimatedWebPProvider(binaries: binaries), at: 0)
        }
        providers.append(VideoProfileProvider(binaries: binaries, encoders: status.encoders))
        providers.append(AudioProfileProvider(binaries: binaries, encoders: status.encoders))
        return CapabilityRegistry(providers: providers)
    }

    nonisolated static func preferredProfile(for source: SourceDescriptor, among targets: [TargetDescriptor]) -> String {
        let ids = Set(targets.map(\.id))
        switch source.kind {
        case .video, .animation:
            if ids.contains(OutputID.animatedWebP) { return OutputID.animatedWebP }
            return targets.first { $0.family == .animation }?.id ?? targets[0].id
        case .still:
            if ids.contains(OutputID.png) { return OutputID.png }
            return targets.first { $0.family == .image }?.id ?? targets[0].id
        case .audio:
            if ids.contains(OutputID.m4aAAC) { return OutputID.m4aAAC }
            return targets.first { $0.family == .audio }?.id ?? targets[0].id
        case .document:
            let ext = DocumentInspector.normalizedExtension(source.url)
            if ext == "md" {
                if ids.contains(OutputID.rtf) { return OutputID.rtf }
            } else if ids.contains(OutputID.markdown) {
                return OutputID.markdown
            }
            return targets[0].id
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

    var isConverting: Bool {
        jobs.contains { $0.state.isActive }
    }

    var progressTitle: String {
        let percent = jobs.first { $0.state == .running || $0.state == .verifying }?.progress
        let count = percent.map { "\(Int(($0 * 100).rounded()))%" }
        if runTotal > 1 {
            let place = "Converting \(min(runFinished + 1, runTotal)) of \(runTotal)"
            return count.map { "\(place)… \($0)" } ?? "\(place)…"
        }
        return count.map { "Converting… \($0)" } ?? "Converting…"
    }

    func estimate(for job: ConversionJob) -> OutputEstimate? {
        guard job.profileID == OutputID.animatedWebP, let descriptor = job.descriptor, descriptor.hasVideo else { return nil }
        return SizeEstimator.estimate(options: job.options, source: descriptor)
    }

    func estimate(for job: ConversionJob, preset: PresetID) -> OutputEstimate? {
        guard job.profileID == OutputID.animatedWebP, let descriptor = job.descriptor, descriptor.hasVideo else { return nil }
        return SizeEstimator.estimate(options: WebPOptions.preset(preset, keepingTrim: job.options), source: descriptor)
    }

    func target(for job: ConversionJob) -> TargetDescriptor? {
        targets(for: job).first { $0.id == job.profileID }
    }

    func profileSummary(for job: ConversionJob) -> String {
        if job.profileID == OutputID.animatedWebP {
            return savedPreset(matching: job.options)?.name ?? SizeText.settingsSummary(job.options)
        }
        return target(for: job)?.displayName ?? "Output"
    }

    /// Bytes for the whole queue: finished files count as written, the rest as estimated.
    var queueTotals: (source: Int64, output: Int64)? {
        var source: Int64 = 0
        var output: Int64 = 0
        for job in jobs {
            guard let sourceBytes = job.descriptor?.fileSizeBytes else { continue }
            if let result = job.result {
                source += sourceBytes
                output += result.bytes
            } else if let estimate = estimate(for: job) {
                source += sourceBytes
                output += estimate.bytes
            }
        }
        return source > 0 ? (source, output) : nil
    }

    func isDuplicate(_ job: ConversionJob) -> Bool {
        let path = job.sourceURL.standardizedFileURL.path
        guard let first = jobs.first(where: { $0.sourceURL.standardizedFileURL.path == path }) else { return false }
        return first.id != job.id
    }

    func setLayoutMode(_ mode: LayoutMode) {
        layoutMode = mode
        preferences.layoutMode = mode
    }

    func setAppearance(_ preference: AppearancePreference) {
        appearance = preference
        preferences.appearance = preference
        preference.apply()
    }

    func select(_ id: UUID?) {
        selectedJobID = id
    }

    func moveSelection(by offset: Int) {
        guard !jobs.isEmpty else { return }
        let current = jobs.firstIndex { $0.id == selectedJobID } ?? (offset > 0 ? -1 : jobs.count)
        let next = min(max(current + offset, 0), jobs.count - 1)
        selectedJobID = jobs[next].id
    }

    /// Copies output settings to every other file. Each file keeps its own trim.
    func applyOptionsToAll(from id: UUID) {
        guard let source = jobs.first(where: { $0.id == id }) else { return }
        for index in jobs.indices where jobs[index].id != id && !jobs[index].state.isActive {
            guard targets(for: jobs[index]).contains(where: { $0.id == source.profileID }) else { continue }
            jobs[index].profileID = source.profileID
            var options = jobs[index].options
            options.presetID = source.options.presetID
            options.framesPerSecond = source.options.framesPerSecond
            options.maxPixelWidth = source.options.maxPixelWidth
            options.quality = source.options.quality
            options.loopForever = source.options.loopForever
            jobs[index].options = options
            jobs[index].stillOptions = source.stillOptions
            jobs[index].audioOptions = source.audioOptions
            jobs[index].videoOptions = source.videoOptions
        }
        saveJobs()
    }

    /// The saved preset whose numbers match this file, if any.
    func savedPreset(matching options: WebPOptions) -> SavedPreset? {
        guard options.presetID == .custom else { return nil }
        return savedPresets.first { $0.matches(options) }
    }

    func applySavedPreset(_ preset: SavedPreset, to id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].options = preset.applied(to: jobs[index].options)
        saveJobs()
    }

    /// Saves a file's current settings under a name. A preset with the same name is replaced.
    @discardableResult
    func saveCustomPreset(named rawName: String, from id: UUID) -> SavedPreset? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let options = jobs.first(where: { $0.id == id })?.options else { return nil }
        let existing = savedPresets.firstIndex { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        let preset = SavedPreset(id: existing.map { savedPresets[$0].id } ?? UUID(), name: name, options: options)
        if let existing {
            savedPresets[existing] = preset
        } else {
            savedPresets.append(preset)
        }
        preferences.savedPresets = savedPresets
        return preset
    }

    func deleteSavedPreset(_ id: UUID) {
        savedPresets.removeAll { $0.id == id }
        preferences.savedPresets = savedPresets
    }

    func resetToDefault(_ id: UUID) {
        applyPreset(defaultPreset == .custom ? .balanced : defaultPreset, to: id)
    }

    /// Puts a finished file back into editing. The output already written stays on disk.
    func editAgain(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].result = nil
        jobs[index].progress = nil
        jobs[index].errorMessage = nil
        transition(id, to: .ready)
        saveJobs()
    }

    func redo(_ id: UUID, with preset: PresetID) {
        applyPreset(preset, to: id)
        convertAgain(id)
    }

    func importURLs(_ urls: [URL]) {
        let preset = preferences.lastPreset
        for url in urls {
            fileAccess.beginAccess(url)
            let path = url.standardizedFileURL.path
            if let index = jobs.firstIndex(where: {
                $0.state == .blockedByPermission && $0.sourceURL.standardizedFileURL.path == path
            }) {
                // Choosing a file the queue lost access to restores that entry instead of adding another.
                jobs[index].sourceURL = url
                jobs[index].sourceBookmark = try? fileAccess.bookmark(for: url)
                jobs[index].errorMessage = nil
                let id = jobs[index].id
                transition(id, to: .probing)
                selectedJobID = id
                Task { await self.probe(id) }
                continue
            }
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

    func setDefaultPreset(_ preset: PresetID) {
        defaultPreset = preset
        preferences.lastPreset = preset
    }

    func selectProfile(_ id: String, for jobID: UUID? = nil) {
        let target = jobID ?? selectedJobID
        guard let target, let index = jobs.firstIndex(where: { $0.id == target }) else { return }
        guard targets(for: jobs[index]).contains(where: { $0.id == id }) else { return }
        jobs[index].profileID = id
        saveJobs()
    }

    func applyPreset(_ preset: PresetID, to id: UUID? = nil) {
        let target = id ?? selectedJobID
        guard let target, let index = jobs.firstIndex(where: { $0.id == target }) else { return }
        guard jobs[index].profileID == OutputID.animatedWebP else { return }
        jobs[index].options = WebPOptions.preset(preset, keepingTrim: jobs[index].options)
        preferences.lastPreset = preset
        defaultPreset = preset
        saveJobs()
    }

    func updateOptions(for id: UUID? = nil, _ change: (inout WebPOptions) -> Void) {
        let target = id ?? selectedJobID
        guard let target, let index = jobs.firstIndex(where: { $0.id == target }) else { return }
        change(&jobs[index].options)
        jobs[index].options = jobs[index].options.markingCustomIfNeeded().matchingPresetIfPossible()
        // Tweaking one file shouldn't turn the default for new files into "Custom".
        if jobs[index].profileID == OutputID.animatedWebP, jobs[index].options.presetID != .custom {
            preferences.lastPreset = jobs[index].options.presetID
            defaultPreset = jobs[index].options.presetID
        }
        saveJobs()
    }

    func updateStillOptions(for id: UUID, _ change: (inout StillOptions) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index].stillOptions)
        saveJobs()
    }

    func updateAudioOptions(for id: UUID, _ change: (inout AudioOptions) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index].audioOptions)
        saveJobs()
    }

    func updateVideoOptions(for id: UUID, _ change: (inout VideoOptions) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index].videoOptions)
        saveJobs()
    }

    func convertAll() {
        if destinationURL == nil {
            chooseDestination()
        }
        guard destinationURL != nil else { return }
        guard engineCheckComplete else { return }
        stopQueue = false
        runTotal = convertibleCount
        runFinished = 0
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
        reveal([url])
    }

    func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private static func collisionName(_ urls: [URL]) -> String {
        guard let first = urls.first else { return "This file" }
        if urls.count == 1 { return first.lastPathComponent }
        return "\(first.lastPathComponent) and \(urls.count - 1) more"
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
        let ffprobe = engine.ffprobeURL
        do {
            let descriptor = try await inspect(url: url, ffprobe: ffprobe)
            guard jobs.contains(where: { $0.id == id }) else { return }
            let available = registry.targets(for: descriptor)
            if let index = jobs.firstIndex(where: { $0.id == id }) {
                jobs[index].descriptor = descriptor
                jobs[index].warnings.append(contentsOf: descriptor.warnings.filter { warning in
                    !jobs[index].warnings.contains(warning)
                })
                if !available.isEmpty, !available.contains(where: { $0.id == jobs[index].profileID }) {
                    jobs[index].profileID = Self.preferredProfile(for: descriptor, among: available)
                }
            }
            if available.isEmpty {
                transition(id, to: .failed)
                setMessage(id, "No conversion is available for this file.", technical: descriptor.formatName ?? engine.detail)
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

    private func inspect(url: URL, ffprobe: URL?) async throws -> SourceDescriptor {
        if PDFInspector.isPDF(url) {
            return try PDFInspector.inspect(url: url)
        }
        if DocumentInspector.isDocument(url) {
            return try DocumentInspector.inspect(url: url)
        }
        if let ffprobe {
            do {
                return try await Task.detached {
                    try FFProbeParser.inspect(url: url, ffprobe: ffprobe)
                }.value
            } catch {
                if let still = StillInspector.inspect(url: url) {
                    return still
                }
                throw error
            }
        }
        if let still = StillInspector.inspect(url: url) {
            return still
        }
        throw ConversionError.engineMissing(engine.detail)
    }

    private func runQueue() async {
        var attempted: Set<UUID> = []
        while !Task.isCancelled && !stopQueue {
            // A failure stays failed for this run. `canConvert` includes failed
            // jobs so Convert can try them again, but picking the same one here
            // made a bad file restart from 0% forever.
            guard let id = ConversionQueue.nextJobID(in: jobs, skipping: attempted) else { return }
            attempted.insert(id)
            await convert(id)
            runFinished += 1
        }
    }

    private func convert(_ id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard let descriptor = jobs[index].descriptor, let destination = destinationURL else {
            return
        }
        guard let target = registry.targets(for: descriptor).first(where: { $0.id == jobs[index].profileID }),
              let provider = registry.provider(for: target) else {
            fail(id, ConversionError.invalidOptions("That format isn't available for this file."))
            return
        }
        let options = jobs[index].options
        let stillOptions = jobs[index].stillOptions
        let audioOptions = jobs[index].audioOptions
        let videoOptions = jobs[index].videoOptions
        let sourceURL = jobs[index].sourceURL
        let fileExtension = target.fileExtension
        transition(id, to: .queued)
        guard !stopQueue, !Task.isCancelled else {
            transition(id, to: .cancelled)
            return
        }

        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
        let pageCount = target.providerID == "imageio-still" ? descriptor.pageCount : 1
        let proposedPages = OutputPublisher.pageURLs(
            source: sourceURL,
            directory: destination,
            fileExtension: fileExtension,
            pageCount: pageCount
        )
        let publishTargets: [URL]
        let replacing: Bool
        do {
            if pageCount > 1 {
                switch try OutputPublisher.planPages(proposedPages, source: sourceURL, policy: collisionPolicy, fileExists: exists) {
                case .write(let urls, let replace):
                    publishTargets = urls
                    replacing = replace
                case .confirmReplace(let urls):
                    let choice = await promptCollision(jobID: id, filename: Self.collisionName(urls), replaceOnly: true)
                    guard choice == .replace else {
                        finishSkipOrCancel(id, choice: choice)
                        return
                    }
                    publishTargets = urls
                    replacing = true
                case .skip:
                    transition(id, to: .cancelled)
                    setMessage(id, ConversionError.skippedExisting.errorDescription, technical: nil)
                    saveJobs()
                    return
                case .ask(let urls):
                    let choice = await promptCollision(jobID: id, filename: Self.collisionName(urls), replaceOnly: false)
                    switch choice {
                    case .keepBoth:
                        publishTargets = urls.map { OutputPublisher.uniqueURL($0, fileExists: exists) }
                        replacing = false
                    case .replace:
                        publishTargets = urls
                        replacing = true
                    case .skip, .cancel:
                        finishSkipOrCancel(id, choice: choice)
                        return
                    }
                }
            } else {
                let proposed = proposedPages[0]
                switch try OutputPublisher.plan(proposed: proposed, source: sourceURL, policy: collisionPolicy, fileExists: exists) {
                case .write(let url):
                    publishTargets = [url]
                    replacing = false
                case .replace(let url):
                    let choice = await promptCollision(jobID: id, filename: url.lastPathComponent, replaceOnly: true)
                    guard choice == .replace else {
                        finishSkipOrCancel(id, choice: choice)
                        return
                    }
                    publishTargets = [url]
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
                        publishTargets = [OutputPublisher.uniqueURL(url, fileExists: exists)]
                        replacing = false
                    case .replace:
                        publishTargets = [url]
                        replacing = true
                    case .skip, .cancel:
                        finishSkipOrCancel(id, choice: choice)
                        return
                    }
                }
            }
        } catch {
            fail(id, error)
            return
        }

        transition(id, to: .running)
        if let index = jobs.firstIndex(where: { $0.id == id }) {
            // Animated WebP emits no timestamp until the encoder finishes, so a
            // 0% bar would sit there for the whole job. Leave it unset and the
            // row shows an indeterminate bar instead.
            jobs[index].progress = target.id == OutputID.animatedWebP ? nil : 0
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
        let request = ConversionRequest(
            id: UUID(),
            sourceURL: sourceURL,
            targetFormatID: target.id,
            options: options,
            stillOptions: stillOptions,
            audioOptions: audioOptions,
            videoOptions: videoOptions,
            destinationDirectory: destination,
            collisionPolicy: collisionPolicy
        )
        do {
            let result: ConversionResult
            if target.providerID == "appkit-document" {
                result = try DocumentConversion.convert(
                    request: request,
                    source: descriptor,
                    resolvedDestination: publishTargets[0],
                    replacing: replacing
                )
            } else if target.providerID == "imageio-still" {
                result = try await StillImageConversion.convert(
                    request: request,
                    source: descriptor,
                    destinations: publishTargets,
                    replacing: replacing
                )
            } else if target.id == OutputID.animatedWebP {
                guard let binaries = engine.binaries else {
                    throw ConversionError.engineMissing(engine.detail)
                }
                result = try await WebPConversion.convert(
                    source: descriptor,
                    options: options,
                    destinationDirectory: destination,
                    collisionPolicy: collisionPolicy,
                    binaries: binaries,
                    runner: runner,
                    resolvedDestination: publishTargets[0],
                    replacing: replacing
                ) { fraction in
                    Task { @MainActor in
                        self.setProgress(id, fraction)
                    }
                }
            } else {
                guard let binaries = engine.binaries else {
                    throw ConversionError.engineMissing(engine.detail)
                }
                result = try await ProfileConversion.convert(
                    provider: provider,
                    request: request,
                    source: descriptor,
                    binaries: binaries,
                    runner: runner,
                    resolvedDestination: publishTargets[0],
                    replacing: replacing
                ) { fraction in
                    Task { @MainActor in
                        self.setProgress(id, fraction)
                    }
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
