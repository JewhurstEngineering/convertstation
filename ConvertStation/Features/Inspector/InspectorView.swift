import SwiftUI

/// Studio's middle column: file header, the preview stage, and the trim strip.
struct StudioDetail: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let job = model.selectedJob {
                PlaybackScope(url: job.sourceURL) { playback in
                    StudioCenter(model: model, job: job, playback: playback)
                }
                .id(job.id)
            } else {
                ContentUnavailableView(
                    "No file selected",
                    systemImage: "film",
                    description: Text("Pick a file in the queue to preview and trim it.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case source, output, sideBySide
    var id: String { rawValue }
    var title: String {
        switch self {
        case .source: "Source"
        case .output: "Output"
        case .sideBySide: "Side by Side"
        }
    }
}

private struct StudioCenter: View {
    @Bindable var model: AppModel
    var job: ConversionJob
    @ObservedObject var playback: PreviewPlayback
    @State private var mode: PreviewMode = .output

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: 280)
            if job.result == nil, job.descriptor?.hasVideo == true {
                TrimTimeline(model: model, job: job, playback: playback)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Brand.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Brand.hairline, lineWidth: 1)
                    )
                    .disabled(job.state.isActive)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.result?.outputURL.lastPathComponent ?? job.displayName)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(metadataLine)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if job.result != nil {
                Picker("Preview", selection: $mode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
        }
    }

    @ViewBuilder
    private var stage: some View {
        if let result = job.result {
            switch mode {
            case .source:
                VideoStage(playback: playback, aspect: aspect, badge: "Source")
            case .output:
                OutputStage(url: result.outputURL, aspect: aspect, badge: "Output · loops")
            case .sideBySide:
                HStack(spacing: 12) {
                    VideoStage(playback: playback, aspect: aspect, badge: "Source", inset: 14)
                    OutputStage(url: result.outputURL, aspect: aspect, badge: "Output", inset: 14)
                }
                .onAppear { if !playback.playing { playback.toggle() } }
            }
        } else if job.descriptor?.hasVideo == true {
            VideoStage(playback: playback, aspect: aspect, badge: "Source")
        } else {
            ZStack {
                Brand.stage
                if job.state == .probing || job.state == .importing {
                    ProgressView("Inspecting…")
                        .foregroundStyle(Color(white: 0.86))
                } else {
                    Label("No preview", systemImage: "film")
                        .foregroundStyle(Color(white: 0.7))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var aspect: CGFloat {
        let width = CGFloat(job.descriptor?.displayWidth ?? 16)
        let height = CGFloat(job.descriptor?.displayHeight ?? 9)
        guard width > 0, height > 0 else { return 16 / 9 }
        return min(max(width / height, 0.3), 3)
    }

    private var metadataLine: String {
        if let result = job.result {
            var parts = ["Animated WebP", "\(result.width)×\(result.height)", "\(result.frameCount) frames"]
            parts.append(result.loopForever ? "loops" : "plays once")
            return parts.joined(separator: " · ")
        }
        var parts: [String] = []
        if let codec = job.descriptor?.codecName {
            parts.append(codec.uppercased())
        }
        if job.descriptor?.displayWidth != nil {
            parts.append(MediaFormat.dimensions(width: job.descriptor?.displayWidth, height: job.descriptor?.displayHeight))
        }
        if let duration = job.descriptor?.durationSeconds {
            parts.append(MediaFormat.duration(duration))
        }
        if let fps = job.descriptor?.averageFrameRate {
            parts.append("\(Int(fps.rounded())) fps")
        }
        if let bytes = job.descriptor?.fileSizeBytes {
            parts.append(MediaFormat.bytes(bytes))
        }
        return parts.isEmpty ? job.state.title : parts.joined(separator: " · ")
    }
}

private struct OutputStage: View {
    var url: URL
    var aspect: CGFloat
    var badge: String
    var inset: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            Brand.stage
            AnimatedImageView(url: url)
                .padding(inset)
            StageBadge(text: badge)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Converted animation preview")
    }
}

/// Studio's right column: settings before converting, the result after.
struct InspectorPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            Group {
                if let job = model.selectedJob {
                    if let result = job.result {
                        ResultSummary(model: model, job: job, result: result)
                    } else {
                        SettingsForm(model: model, job: job)
                    }
                } else {
                    Text("Select a file to see its settings.")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
        .background(Brand.panel)
        .accessibilityLabel("Inspector")
    }
}

/// Preset, encoding controls, estimate and notes for one file.
/// Used by the Studio inspector and, with `compact`, inside an expanded Batch row.
struct SettingsForm: View {
    @Bindable var model: AppModel
    var job: ConversionJob
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 20) {
            if job.descriptor?.hasVideo == true {
                if !compact {
                    presetSection
                }
                controls
                if compact {
                    compactEstimate
                } else {
                    estimateCard
                }
                largerAdvice
            }
            notes
            if !compact, model.jobs.count > 1, job.descriptor?.hasVideo == true {
                HStack(spacing: 4) {
                    Text("Settings apply to this file.")
                        .foregroundStyle(.secondary)
                    Button("Apply to all \(model.jobs.count)") { model.applyOptionsToAll(from: job.id) }
                        .buttonStyle(.link)
                }
                .font(.caption)
            }
        }
        .disabled(job.state.isActive)
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preset")
                .font(.headline)
            SegmentedPills(options: PresetID.allCases, selection: preset, title: \.shortTitle)
                .accessibilityLabel("Preset")
            Text(presetCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if compact {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    labeled("Frame rate") { fpsPicker }
                    labeled("Max width") { widthPicker }
                }
                qualityRow
                Toggle("Loop forever", isOn: loop)
                    .toggleStyle(.checkbox)
                longClipToggle
            }
        } else {
            GroupedRows {
                row {
                    Text("Frame rate")
                    Spacer()
                    fpsPicker.fixedSize()
                }
                GroupedRowDivider()
                row {
                    Text("Max width")
                    Spacer()
                    widthPicker.fixedSize()
                }
                GroupedRowDivider()
                qualityRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                GroupedRowDivider()
                row {
                    Text("Loop forever")
                    Spacer()
                    Toggle("Loop forever", isOn: loop)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                if hasLongClip {
                    GroupedRowDivider()
                    row { longClipToggle }
                }
            }
        }
    }

    private var fpsPicker: some View {
        Picker("Frame rate", selection: fps) {
            ForEach(WebPLimits.fpsChoices, id: \.self) { fps in
                Text("\(fps) fps").tag(fps)
            }
        }
        .labelsHidden()
        .accessibilityLabel("Frame rate")
    }

    private var widthPicker: some View {
        Picker("Max width", selection: width) {
            Text("Original").tag(Optional<Int>.none)
            ForEach(WebPLimits.widthChoices, id: \.self) { width in
                Text("\(width.formatted()) px").tag(Optional(width))
            }
        }
        .labelsHidden()
        .accessibilityLabel("Maximum width")
    }

    private var qualityRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Quality")
                Spacer()
                Text("\(job.options.quality)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: quality, in: 0...100, step: 1)
                .labelsHidden()
                .tint(Brand.blue)
                .accessibilityLabel("Quality")
        }
    }

    @ViewBuilder
    private var longClipToggle: some View {
        if hasLongClip {
            HStack {
                Text("Convert past 30 seconds")
                Spacer()
                Toggle("Convert past 30 seconds", isOn: longClip)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }
        }
    }

    private var hasLongClip: Bool {
        (job.descriptor?.durationSeconds ?? 0) > WebPLimits.longClipSeconds
    }

    @ViewBuilder
    private var compactEstimate: some View {
        if let estimate = model.estimate(for: job) {
            HStack(spacing: 6) {
                Text("Estimate")
                    .foregroundStyle(.secondary)
                Text("≈ \(MediaFormat.bytes(estimate.bytes))")
                    .fontWeight(.semibold)
                if let change = estimate.change(from: job.descriptor?.fileSizeBytes) {
                    Text(SizeText.change(change))
                        .foregroundStyle(SizeText.changeColor(change))
                }
                Text("· \(estimate.frames) frames · \(estimate.width)×\(estimate.height)")
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var estimateCard: some View {
        if let estimate = model.estimate(for: job) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ESTIMATE")
                    .font(.caption.weight(.semibold))
                    .tracking(0.4)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("≈ \(MediaFormat.bytes(estimate.bytes))")
                        .font(.title2.weight(.semibold))
                    if let change = estimate.change(from: job.descriptor?.fileSizeBytes) {
                        Text(SizeText.change(change))
                            .fontWeight(.semibold)
                            .foregroundStyle(SizeText.changeColor(change))
                    }
                }
                Text("\(estimate.frames) frames · \(estimate.width)×\(estimate.height) · \(MediaFormat.duration(estimate.duration))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Estimated size, about \(MediaFormat.bytes(estimate.bytes)), \(estimate.frames) frames")
        }
    }

    @ViewBuilder
    private var largerAdvice: some View {
        if let estimate = model.estimate(for: job),
           let change = estimate.change(from: job.descriptor?.fileSizeBytes), change > 0.05 {
            let lighter = SizeText.lighterPreset(than: job.options.presetID)
            let lighterBytes = lighter.flatMap { model.estimate(for: job, preset: $0)?.bytes }
            AdviceBox(
                title: compact ? nil : "Likely larger than the original",
                message: compact
                    ? "Likely larger than the source."
                    : "\(job.options.framesPerSecond) fps at quality \(job.options.quality) keeps a lot of detail."
            ) {
                if let lighter, let lighterBytes {
                    Button("Use \(lighter.title) (≈ \(MediaFormat.bytes(lighterBytes)))") {
                        model.applyPreset(lighter, to: job.id)
                    }
                    .buttonStyle(.link)
                }
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        let visible = job.warnings.filter { $0 != "This file is already in the queue." }
        if !visible.isEmpty || job.errorMessage != nil {
            VStack(alignment: .leading, spacing: 6) {
                if !compact {
                    Text("Notes")
                        .font(.headline)
                }
                ForEach(visible, id: \.self) { warning in
                    Label(warning, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let message = job.errorMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(job.state == .failed || job.state == .blockedByPermission ? Brand.danger : .secondary)
                    if job.state == .blockedByPermission {
                        Button("Grant Access…") { model.isChoosingFiles = true }
                    }
                }
                if let detail = job.technicalDetail, !detail.isEmpty {
                    DisclosureGroup("Technical details") {
                        Text(detail)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 40)
    }

    private func labeled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var presetCaption: String {
        let options = job.options
        let width = options.maxPixelWidth.map { "up to \($0.formatted()) px" } ?? "original width"
        return "\(options.framesPerSecond) fps · \(width) · quality \(options.quality)"
    }

    private var preset: Binding<PresetID> {
        Binding(get: { job.options.presetID }, set: { model.applyPreset($0, to: job.id) })
    }

    private var fps: Binding<Int> {
        Binding(
            get: { job.options.framesPerSecond },
            set: { value in model.updateOptions(for: job.id) { $0.framesPerSecond = value } }
        )
    }

    private var width: Binding<Int?> {
        Binding(
            get: { job.options.maxPixelWidth },
            set: { value in model.updateOptions(for: job.id) { $0.maxPixelWidth = value } }
        )
    }

    private var quality: Binding<Double> {
        Binding(
            get: { Double(job.options.quality) },
            set: { value in model.updateOptions(for: job.id) { $0.quality = Int(value.rounded()) } }
        )
    }

    private var loop: Binding<Bool> {
        Binding(
            get: { job.options.loopForever },
            set: { value in model.updateOptions(for: job.id) { $0.loopForever = value } }
        )
    }

    private var longClip: Binding<Bool> {
        Binding(
            get: { job.options.allowLongClip },
            set: { value in model.updateOptions(for: job.id) { $0.allowLongClip = value } }
        )
    }
}

/// What a finished conversion produced, compared with the source.
struct ResultSummary: View {
    @Bindable var model: AppModel
    var job: ConversionJob
    var result: ConversionResult
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !compact {
                Label("Converted", systemImage: "checkmark")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.success)
            }
            bars
            advice
            GroupedRows {
                fact("Used", SizeText.settingsSummary(job.options) + (job.options.presetID == .custom ? "" : " · \(job.options.framesPerSecond) fps · Q\(job.options.quality)"))
                GroupedRowDivider()
                fact("Frames", "\(result.frameCount)")
                GroupedRowDivider()
                fact("Saved to", result.outputURL.deletingLastPathComponent().lastPathComponent)
            }
            HStack(spacing: 8) {
                Button("Quick Look") { model.quickLook(result.outputURL) }
                    .frame(maxWidth: .infinity)
                Button("Show in Finder") { model.reveal(result.outputURL) }
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            Button("Edit settings and convert again") { model.editAgain(job.id) }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
        }
    }

    private var sourceBytes: Int64? { job.descriptor?.fileSizeBytes }

    private var change: Double? {
        guard let sourceBytes, sourceBytes > 0 else { return nil }
        return (Double(result.bytes) - Double(sourceBytes)) / Double(sourceBytes)
    }

    @ViewBuilder
    private var bars: some View {
        if let sourceBytes {
            let largest = Double(max(sourceBytes, result.bytes))
            VStack(spacing: 10) {
                bar("Original", bytes: sourceBytes, fraction: Double(sourceBytes) / largest, color: .secondary, bold: false)
                bar("WebP", bytes: result.bytes, fraction: Double(result.bytes) / largest,
                    color: (change ?? 0) > 0 ? Brand.warning : Brand.success, bold: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(MediaFormat.bytes(result.bytes))
                .font(.title2.weight(.semibold))
        }
    }

    private func bar(_ title: String, bytes: Int64, fraction: Double, color: Color, bold: Bool) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).foregroundStyle(.secondary)
                Spacer()
                Text(MediaFormat.bytes(bytes))
                    .monospacedDigit()
                    .fontWeight(bold ? .semibold : .regular)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Brand.fieldFill)
                    Capsule().fill(color).frame(width: max(8, geometry.size.width * fraction))
                }
            }
            .frame(height: 8)
        }
    }

    @ViewBuilder
    private var advice: some View {
        if let change, change > 0.05 {
            let lighter = SizeText.lighterPreset(than: job.options.presetID)
            let lighterBytes = lighter.flatMap { model.estimate(for: job, preset: $0)?.bytes }
            AdviceBox(
                title: "\(SizeText.percent(change)) larger than the original",
                message: reason(lighter: lighter, lighterBytes: lighterBytes)
            ) {
                if let lighter {
                    Button("Redo with \(lighter.title)") { model.redo(job.id, with: lighter) }
                        .disabled(model.isConverting)
                }
            }
        } else if let change, change < -0.05 {
            Text("\(SizeText.percent(change)) smaller than the original")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Brand.success)
        }
    }

    private func reason(lighter: PresetID?, lighterBytes: Int64?) -> String {
        let cause = "\(job.options.framesPerSecond) fps at quality \(job.options.quality) keeps nearly every frame."
        guard let lighter, let lighterBytes else {
            return cause + " Try a lower quality or a shorter trim."
        }
        return cause + " \(lighter.title) should land near \(MediaFormat.bytes(lighterBytes))."
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}
