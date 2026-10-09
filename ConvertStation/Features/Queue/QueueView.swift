import SwiftUI

struct QueuePane: View {
    @Bindable var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if model.jobs.isEmpty {
                EmptyQueue(targeted: model.dropTargeted, colorScheme: colorScheme) {
                    model.isChoosingFiles = true
                }
            } else {
                List(selection: $model.selectedJobID) {
                    ForEach(model.jobs) { job in
                        QueueRow(job: job, duplicateCount: duplicateCount(job)) {
                            model.remove(job.id)
                        }
                        .tag(job.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 8))
                    }
                }
                .listStyle(.inset)
                .accessibilityLabel("Conversion queue")
            }
        }
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.magenta, lineWidth: 2)
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
    }

    private func duplicateCount(_ job: ConversionJob) -> Int {
        model.jobs.filter { $0.sourceURL.standardizedFileURL.path == job.sourceURL.standardizedFileURL.path }.count
    }
}

private struct EmptyQueue: View {
    var targeted: Bool
    var colorScheme: ColorScheme
    var browse: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(colorScheme == .dark ? "WordmarkDark" : "WordmarkLight")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 420)
                .accessibilityLabel("ConvertStation")
            Text("Drop files to convert")
                .font(.title2.weight(.semibold))
            Text("Everything happens on your Mac.")
                .foregroundStyle(.secondary)
            Button("Browse Files", action: browse)
                .buttonStyle(AccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .foregroundStyle(targeted ? AnyShapeStyle(Brand.accentGradient) : AnyShapeStyle(.secondary.opacity(0.45)))
                .padding(24)
        }
    }
}

private struct QueueRow: View {
    var job: ConversionJob
    var duplicateCount: Int
    var remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(job.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Spacer()
                status
                Button(role: .destructive) {
                    remove()
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove from the queue")
                .accessibilityLabel("Remove \(job.displayName)")
            }
            HStack(spacing: 10) {
                meta(job.descriptor?.codecName?.uppercased() ?? typeName)
                if let bytes = job.descriptor?.fileSizeBytes ?? fileSize {
                    meta(MediaFormat.bytes(bytes))
                }
                meta(MediaFormat.dimensions(width: job.descriptor?.displayWidth, height: job.descriptor?.displayHeight))
                if let duration = job.descriptor?.durationSeconds {
                    meta(MediaFormat.duration(duration))
                }
                if duplicateCount > 1 || job.isDuplicate {
                    Text("Duplicate")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Brand.violet.opacity(0.16), in: Capsule())
                        .foregroundStyle(Brand.violet)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if job.state == .running || job.state == .verifying {
                if let progress = job.progress {
                    ProgressView(value: progress)
                        .tint(Brand.magenta)
                        .accessibilityLabel("Conversion progress")
                        .accessibilityValue("\(Int(progress * 100)) percent")
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Conversion progress")
                }
            }
            if let message = job.errorMessage, job.state == .failed || job.state == .blockedByPermission || job.state == .cancelled {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(job.state == .failed ? .red : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.displayName), \(job.state.title)")
    }

    @ViewBuilder
    private var status: some View {
        Text(job.state.title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.16), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch job.state {
        case .completed: .green
        case .failed, .blockedByPermission: .red
        case .running, .verifying, .queued: Brand.orange
        case .ready: Brand.blue
        default: .secondary
        }
    }

    private var typeName: String {
        job.sourceURL.pathExtension.uppercased()
    }

    private var fileSize: Int64? {
        guard let value = try? FileManager.default.attributesOfItem(atPath: job.sourceURL.path)[.size] else {
            return nil
        }
        return (value as? NSNumber)?.int64Value
    }

    private func meta(_ text: String) -> some View {
        Text(text)
    }
}
