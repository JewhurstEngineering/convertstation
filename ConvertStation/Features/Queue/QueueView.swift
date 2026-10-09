import SwiftUI

/// Studio's left column: every file with a poster frame and its state.
struct QueueSidebar: View {
    @Bindable var model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Queue")
                    .font(.headline)
                Spacer()
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 6)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.jobs) { job in
                        QueueRow(
                            job: job,
                            selected: job.id == model.selectedJobID,
                            duplicate: model.isDuplicate(job),
                            select: { model.select(job.id) },
                            remove: { model.remove(job.id) }
                        )
                    }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onMoveCommand { direction in
                switch direction {
                case .up: model.moveSelection(by: -1)
                case .down: model.moveSelection(by: 1)
                default: break
                }
            }
            .accessibilityLabel("Conversion queue")

            Button {
                model.isChoosingFiles = true
            } label: {
                Text(model.dropTargeted ? "Release to add" : "Drop more videos here")
                    .font(.caption)
                    .foregroundStyle(model.dropTargeted ? Brand.blue : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            .foregroundStyle(model.dropTargeted ? Brand.blue : Brand.hairline)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Choose files to convert")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Brand.sidebar, ignoresSafeAreaEdges: [])
    }

    private var summary: String {
        let total = model.jobs.count
        let files = total == 1 ? "1 file" : "\(total) files"
        if model.isConverting {
            let done = model.jobs.filter { $0.state == .completed }.count
            return done > 0 ? "\(done) done · converting" : "converting"
        }
        let ready = model.convertibleCount
        return ready > 0 ? "\(files) · \(ready) ready" : files
    }
}

private struct QueueRow: View {
    var job: ConversionJob
    var selected: Bool
    var duplicate: Bool
    var select: () -> Void
    var remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            ClipThumbnail(job: job)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.result?.outputURL.lastPathComponent ?? job.displayName)
                    .font(.body.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Brand.blue.opacity(0.08) : (hovering ? Brand.fieldFill.opacity(0.6) : .clear))
        }
        .overlay {
            if selected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Brand.blue, lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove from Queue", role: .destructive, action: remove)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.displayName), \(duplicate ? "already in the queue" : job.state.title)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Remove", remove)
    }

    @ViewBuilder
    private var detail: some View {
        if duplicate {
            Text("Already in the queue")
                .font(.caption)
                .foregroundStyle(Brand.warning)
        } else if job.state == .running || job.state == .verifying {
            ProgressRow(progress: job.progress)
        } else if let result = job.result {
            HStack(spacing: 0) {
                Text(MediaFormat.bytes(result.bytes))
                if let change = changeFromSource(result.bytes) {
                    Text(" · ")
                    Text(SizeText.change(change))
                        .fontWeight(.semibold)
                        .foregroundStyle(SizeText.changeColor(change))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let message = job.errorMessage, job.state == .failed || job.state == .blockedByPermission {
            Text(message)
                .font(.caption)
                .foregroundStyle(Brand.danger)
                .lineLimit(2)
        } else {
            Text(metaLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if duplicate || hovering {
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove from the queue")
            .accessibilityLabel("Remove \(job.displayName)")
        } else if job.state == .completed {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Brand.success)
                .accessibilityHidden(true)
        } else if job.state != .running && job.state != .verifying && job.state != .failed && job.state != .blockedByPermission {
            JobStatusView(job: job)
        }
    }

    private func changeFromSource(_ bytes: Int64) -> Double? {
        guard let source = job.descriptor?.fileSizeBytes, source > 0 else { return nil }
        return (Double(bytes) - Double(source)) / Double(source)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let duration = job.descriptor?.durationSeconds {
            parts.append(MediaFormat.duration(duration))
        }
        if job.descriptor?.displayWidth != nil {
            parts.append(MediaFormat.dimensions(width: job.descriptor?.displayWidth, height: job.descriptor?.displayHeight))
        }
        if let bytes = job.descriptor?.fileSizeBytes {
            parts.append(MediaFormat.bytes(bytes))
        }
        return parts.isEmpty ? job.state.title : parts.joined(separator: " · ")
    }
}
