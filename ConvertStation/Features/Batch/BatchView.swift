import SwiftUI

/// Batch layout: every file is a row; the selected row opens to show its
/// preview, trim and settings in place.
struct BatchView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Text(fileCount)
                        .font(.headline)
                    Spacer()
                    Text("New files use")
                        .foregroundStyle(.secondary)
                    SegmentedPills(
                        options: [PresetID.smallFile, .balanced, .highQuality],
                        selection: defaultPreset,
                        title: \.shortTitle
                    )
                    .frame(width: 260)
                    .accessibilityLabel("Preset for new files")
                }
                .padding(.bottom, 6)

                BatchColumns {
                    Color.clear.frame(width: 64, height: 1)
                    Text("File").frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                    Text("Settings").frame(width: BatchLayout.settings, alignment: .leading)
                    Text("Size").frame(width: BatchLayout.size, alignment: .leading)
                    Text("Status").frame(width: BatchLayout.status, alignment: .leading)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .accessibilityHidden(true)

                ForEach(model.jobs) { job in
                    BatchRow(model: model, job: job, expanded: job.id == model.selectedJobID)
                }
            }
            .padding(24)
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: model.moveSelection(by: -1)
            case .down: model.moveSelection(by: 1)
            default: break
            }
        }
        .accessibilityLabel("Conversion queue")
    }

    private var fileCount: String {
        let ready = model.convertibleCount
        let files = model.jobs.count == 1 ? "1 file" : "\(model.jobs.count) files"
        return ready > 0 ? "\(files) · \(ready) ready" : files
    }

    private var defaultPreset: Binding<PresetID> {
        Binding(get: { model.defaultPreset }, set: { model.setDefaultPreset($0) })
    }
}

private enum BatchLayout {
    static let settings: CGFloat = 190
    static let size: CGFloat = 150
    static let status: CGFloat = 110
}

/// Header and rows share fixed column widths so they line up.
private struct BatchColumns<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 16) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BatchRow: View {
    @Bindable var model: AppModel
    var job: ConversionJob
    var expanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            summary
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.select(expanded ? nil : job.id)
                    }
                }
                .contextMenu {
                    Button("Remove from Queue", role: .destructive) { model.remove(job.id) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(expanded ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(expanded ? "Collapses this file" : "Shows preview and settings")
            if expanded {
                Rectangle().fill(Brand.hairline).frame(height: 1)
                BatchEditor(model: model, job: job)
                    .padding(16)
                    .background(Brand.canvas.opacity(0.5))
            }
        }
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(expanded ? Brand.blue : Brand.hairline, lineWidth: expanded ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var summary: some View {
        BatchColumns {
            ClipThumbnail(job: job, width: 64, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .fontWeight(expanded ? .semibold : .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
            settingsChip
                .frame(width: BatchLayout.settings, alignment: .leading)
            sizeText
                .frame(width: BatchLayout.size, alignment: .leading)
            status
                .frame(width: BatchLayout.status, alignment: .leading)
        }
    }

    @ViewBuilder
    private var subtitle: some View {
        if model.isDuplicate(job) {
            Text("Already in the queue")
                .font(.callout)
                .foregroundStyle(Brand.warning)
        } else if let message = job.errorMessage, job.state == .failed || job.state == .blockedByPermission {
            HStack(spacing: 4) {
                Text(message).lineLimit(1)
                if job.state == .blockedByPermission {
                    Button("Grant access…") { model.isChoosingFiles = true }
                        .buttonStyle(.link)
                }
            }
            .font(.callout)
            .foregroundStyle(Brand.danger)
        } else {
            Text(metaLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var settingsChip: some View {
        if job.descriptor?.hasVideo == true {
            Text(SizeText.settingsSummary(job.options))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Brand.fieldFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .lineLimit(1)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sizeText: some View {
        if let source = job.descriptor?.fileSizeBytes {
            if let result = job.result {
                sizeLine(source: source, output: result.bytes, approximate: false)
            } else if let estimate = model.estimate(for: job) {
                sizeLine(source: source, output: estimate.bytes, approximate: true)
            } else {
                Text(MediaFormat.bytes(source)).foregroundStyle(.secondary)
            }
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func sizeLine(source: Int64, output: Int64, approximate: Bool) -> some View {
        let change = (Double(output) - Double(source)) / Double(source)
        return HStack(spacing: 4) {
            Text("\(MediaFormat.bytes(source)) →")
                .foregroundStyle(.secondary)
            Text((approximate ? "≈" : "") + MediaFormat.bytes(output))
                .fontWeight(.semibold)
                .foregroundStyle(approximate ? SizeText.changeColor(change) : .primary)
            if !approximate {
                Text(SizeText.change(change))
                    .foregroundStyle(SizeText.changeColor(change))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 6) {
            JobStatusView(job: job)
            Spacer(minLength: 0)
        }
    }

    private var metaLine: String {
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
        return parts.isEmpty ? job.state.title : parts.joined(separator: " · ")
    }
}

private enum BatchEditorLayout {
    static let previewWidth: CGFloat = 480
    /// Fixed so a tall clip can't push the row past the window.
    static let stageHeight: CGFloat = 270
}

/// The open part of a Batch row.
private struct BatchEditor: View {
    @Bindable var model: AppModel
    var job: ConversionJob

    var body: some View {
        if job.descriptor?.hasVideo == true {
            PlaybackScope(url: job.sourceURL) { playback in
                HStack(alignment: .top, spacing: 24) {
                    preview(playback)
                        .frame(width: BatchEditorLayout.previewWidth)
                    side
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .id(job.id)
        } else {
            SettingsForm(model: model, job: job, compact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func preview(_ playback: PreviewPlayback) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result = job.result {
                ZStack(alignment: .topLeading) {
                    Brand.stage
                    AnimatedImageView(url: result.outputURL)
                        .padding(12)
                    StageBadge(text: "Output")
                }
                .frame(height: BatchEditorLayout.stageHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VideoStage(playback: playback, aspect: aspect, badge: nil, cornerRadius: 10, inset: 12)
                    .frame(height: BatchEditorLayout.stageHeight)
                TrimTimeline(model: model, job: job, playback: playback, compact: true)
                    .disabled(job.state.isActive)
            }
        }
    }

    @ViewBuilder
    private var side: some View {
        if let result = job.result {
            ResultSummary(model: model, job: job, result: result, compact: true)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SettingsForm(model: model, job: job, compact: true)
                HStack(spacing: 8) {
                    Spacer()
                    if model.jobs.count > 1 {
                        Button("Apply to All") { model.applyOptionsToAll(from: job.id) }
                    }
                    Button("Reset to Default") { model.resetToDefault(job.id) }
                }
                .disabled(job.state.isActive)
            }
        }
    }

    private var aspect: CGFloat {
        let width = CGFloat(job.descriptor?.displayWidth ?? 16)
        let height = CGFloat(job.descriptor?.displayHeight ?? 9)
        guard width > 0, height > 0 else { return 16 / 9 }
        return min(max(width / height, 0.5), 2.4)
    }
}
