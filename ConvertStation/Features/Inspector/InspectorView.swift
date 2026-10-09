import AVKit
import SwiftUI

struct InspectorView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let job = model.selectedJob {
                VStack(alignment: .leading, spacing: 12) {
                    header(job)
                    if job.descriptor?.hasVideo == true {
                        SourcePreview(url: job.sourceURL, aspect: pictureAspect(job))
                            .id(job.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if job.descriptor?.hasAudio == true {
                        note("Audio will be dropped. Animated WebP is silent.")
                    }
                    formatSection(job)
                    if model.targets(for: job).contains(where: { $0.id == TargetDescriptor.animatedWebP.id }) {
                        controls(job)
                    }
                    if !job.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Notes")
                                .font(.headline)
                            ForEach(job.warnings, id: \.self) { warning in
                                Text(warning)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let result = job.result {
                        resultSection(job, result)
                    }
                    if let message = job.errorMessage {
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(job.state == .failed ? .red : .secondary)
                    }
                    if let detail = job.technicalDetail, !detail.isEmpty {
                        DisclosureGroup("Technical details") {
                            Text(detail)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ContentUnavailableView(
                    "No file selected",
                    systemImage: "film",
                    description: Text("Drop a MOV or choose a file. The inspector shows what can be converted.")
                )
            }
        }
        .frame(maxHeight: .infinity)
        .background(.thinMaterial)
        .accessibilityLabel("Inspector")
    }

    private func pictureAspect(_ job: ConversionJob) -> CGFloat {
        let width = CGFloat(job.descriptor?.displayWidth ?? 16)
        let height = CGFloat(job.descriptor?.displayHeight ?? 9)
        guard width > 0, height > 0 else { return 16 / 9 }
        return min(max(width / height, 0.5), 2.4)
    }

    private func header(_ job: ConversionJob) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.displayName)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            Text(metadataLine(job))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func metadataLine(_ job: ConversionJob) -> String {
        var parts: [String] = []
        if let codec = job.descriptor?.codecName {
            parts.append(codec.uppercased())
        }
        parts.append(MediaFormat.dimensions(width: job.descriptor?.displayWidth, height: job.descriptor?.displayHeight))
        if let duration = job.descriptor?.durationSeconds {
            parts.append(MediaFormat.duration(duration))
        }
        if let fps = job.descriptor?.averageFrameRate {
            parts.append(String(format: "%.2g fps", fps))
        }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private func formatSection(_ job: ConversionJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Output")
                .font(.headline)
            let targets = model.targets(for: job)
            if targets.isEmpty {
                Text(job.state == .probing ? "Checking this file…" : "Animated WebP isn't available for this file.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(targets) { target in
                    HStack {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundStyle(Brand.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.displayName)
                            Text(target.supportsAudio ? "Includes audio" : "No audio")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Brand.blue)
                            .accessibilityHidden(true)
                    }
                    .padding(10)
                    .background(Brand.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(target.displayName), available")
                }
            }
        }
    }

    private func controls(_ job: ConversionJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.headline)
            Picker("Preset", selection: preset(job)) {
                ForEach(PresetID.allCases) { preset in
                    Text(preset.shortTitle).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Preset")

            HStack(spacing: 12) {
                Picker("Frame rate", selection: fps(job)) {
                    ForEach(WebPLimits.fpsChoices, id: \.self) { fps in
                        Text("\(fps) fps").tag(fps)
                    }
                }
                .accessibilityLabel("Frame rate")

                Picker("Max width", selection: width(job)) {
                    Text("Original").tag(Optional<Int>.none)
                    ForEach(WebPLimits.widthChoices, id: \.self) { width in
                        Text("\(width) px").tag(Optional(width))
                    }
                }
                .accessibilityLabel("Maximum width")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Quality")
                    Spacer()
                    Text("\(job.options.quality)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: quality(job), in: 0...100, step: 1)
                    .labelsHidden()
                    .accessibilityLabel("Quality")
                    .tint(Brand.magenta)
            }

            Toggle("Loop forever", isOn: loop(job))
                .accessibilityHint("Animated WebP can loop when a player supports it")

            HStack {
                Text("Start")
                TextField("Start seconds", value: trimStart(job), format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 72)
                Text("End")
                TextField("End seconds", value: trimEnd(job), format: .number.precision(.fractionLength(0...2)))
                    .frame(width: 72)
                Text("sec")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .contain)

            if let duration = job.descriptor?.durationSeconds, duration > WebPLimits.longClipSeconds {
                Toggle("Convert past 30 seconds", isOn: longClip(job))
            }

            if let estimate = frameEstimate(job) {
                Text(estimate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resultSection(_ job: ConversionJob, _ result: ConversionResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Result")
                .font(.headline)
            Text("\(MediaFormat.bytes(result.bytes))  ·  \(result.width)×\(result.height)  ·  \(result.frameCount) frames")
                .font(.callout)
            if let sourceBytes = job.descriptor?.fileSizeBytes, sourceBytes > 0 {
                let delta = (Double(result.bytes) - Double(sourceBytes)) / Double(sourceBytes) * 100
                Text(String(format: "%@%.0f%% compared with the original", delta > 0 ? "+" : "", delta))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Quick Look") { model.quickLook(result.outputURL) }
                Button("Show in Finder") { model.reveal(result.outputURL) }
                Button("Convert Again") { model.convertAgain(job.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func frameEstimate(_ job: ConversionJob) -> String? {
        guard let duration = job.descriptor?.durationSeconds else { return nil }
        guard let interval = try? job.options.effectiveInterval(sourceDuration: duration) else { return nil }
        let fps = job.options.resolvedFPS(sourceFPS: job.descriptor?.averageFrameRate).fps
        let frames = max(1, Int((interval.duration * Double(fps)).rounded()))
        return "About \(frames) frames over \(MediaFormat.duration(interval.duration)). This is an estimate, not the finished file."
    }

    private func preset(_ job: ConversionJob) -> Binding<PresetID> {
        Binding(
            get: { job.options.presetID },
            set: { model.applyPreset($0, to: job.id) }
        )
    }

    private func fps(_ job: ConversionJob) -> Binding<Int> {
        Binding(
            get: { job.options.framesPerSecond },
            set: { value in model.updateOptions(for: job.id) { $0.framesPerSecond = value } }
        )
    }

    private func width(_ job: ConversionJob) -> Binding<Int?> {
        Binding(
            get: { job.options.maxPixelWidth },
            set: { value in model.updateOptions(for: job.id) { $0.maxPixelWidth = value } }
        )
    }

    private func quality(_ job: ConversionJob) -> Binding<Double> {
        Binding(
            get: { Double(job.options.quality) },
            set: { value in model.updateOptions(for: job.id) { $0.quality = Int(value.rounded()) } }
        )
    }

    private func loop(_ job: ConversionJob) -> Binding<Bool> {
        Binding(
            get: { job.options.loopForever },
            set: { value in model.updateOptions(for: job.id) { $0.loopForever = value } }
        )
    }

    private func trimStart(_ job: ConversionJob) -> Binding<Double> {
        Binding(
            get: { job.options.trimStartSeconds },
            set: { value in model.updateOptions(for: job.id) { $0.trimStartSeconds = max(0, value) } }
        )
    }

    private func trimEnd(_ job: ConversionJob) -> Binding<Double> {
        Binding(
            get: { job.options.trimEndSeconds ?? job.descriptor?.durationSeconds ?? 0 },
            set: { value in
                model.updateOptions(for: job.id) { options in
                    options.trimEndSeconds = value
                }
            }
        )
    }

    private func longClip(_ job: ConversionJob) -> Binding<Bool> {
        Binding(
            get: { job.options.allowLongClip },
            set: { value in model.updateOptions(for: job.id) { $0.allowLongClip = value } }
        )
    }
}

/// The system player chrome is a large floating bar that covers a small preview.
/// Playback stays in an `AVPlayerView` with no controls, and a short bar sits under the picture.
private struct SourcePreview: View {
    var aspect: CGFloat
    @StateObject private var playback: PreviewPlayback

    init(url: URL, aspect: CGFloat) {
        self.aspect = aspect
        _playback = StateObject(wrappedValue: PreviewPlayback(url: url))
    }

    var body: some View {
        VStack(spacing: 6) {
            PlayerHost(player: playback.player)
                .aspectRatio(aspect, contentMode: .fit)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                Button {
                    playback.toggle()
                } label: {
                    Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(playback.playing ? "Pause" : "Play")

                Text(Self.clock(playback.time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)

                Slider(
                    value: Binding(
                        get: { playback.time },
                        set: { playback.seek($0) }
                    ),
                    in: 0...max(playback.duration, 0.01),
                    onEditingChanged: { editing in
                        playback.scrubbing = editing
                    }
                )
                .controlSize(.small)
                .accessibilityLabel("Playback position")

                Text(Self.clock(playback.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Source preview")
        .onDisappear { playback.stop() }
    }

    private static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

@MainActor
private final class PreviewPlayback: ObservableObject {
    @Published var playing = false
    @Published var time = 0.0
    @Published var duration = 0.0
    var scrubbing = false
    let player: AVPlayer
    private var observer: Any?

    init(url: URL) {
        let player = AVPlayer(url: url)
        player.isMuted = true
        self.player = player
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] current in
            Task { @MainActor in
                self?.apply(current)
            }
        }
    }

    func toggle() {
        if player.timeControlStatus == .playing {
            player.pause()
            playing = false
        } else {
            player.play()
            playing = true
        }
    }

    func seek(_ seconds: Double) {
        let upper = duration > 0 ? duration : seconds
        let target = min(max(0, seconds), upper)
        time = target
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        if let observer {
            player.removeTimeObserver(observer)
            self.observer = nil
        }
        player.pause()
        playing = false
    }

    private func apply(_ current: CMTime) {
        if !scrubbing {
            let seconds = current.seconds
            time = seconds.isFinite ? max(0, seconds) : 0
        }
        let length = player.currentItem?.duration.seconds ?? 0
        duration = length.isFinite ? max(0, length) : 0
        playing = player.timeControlStatus == .playing
    }
}

private struct PlayerHost: NSViewRepresentable {
    var player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.controlsStyle = .none
        if view.player !== player {
            view.player = player
        }
    }
}
