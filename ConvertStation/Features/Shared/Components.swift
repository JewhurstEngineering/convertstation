import AppKit
import ImageIO
import SwiftUI

/// Poster frame for a queue row. Falls back to a neutral tile until the frame loads.
struct ClipThumbnail: View {
    var job: ConversionJob
    var width: CGFloat = 52
    var height: CGFloat = 36

    var body: some View {
        Brand.fieldFill
            .overlay {
                if job.state == .failed || job.state == .blockedByPermission {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Brand.danger)
                } else if let image = FrameStore.shared.thumbnails[job.sourceURL] {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        )
        .task(id: job.sourceURL) {
            guard job.state != .blockedByPermission else { return }
            await FrameStore.shared.loadThumbnail(job.sourceURL)
        }
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    var title: String
    var foreground: Color
    var fill: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
            .fixedSize()
    }
}

/// Status shown at the end of a row: a pill, a progress bar, or a check.
struct JobStatusView: View {
    var job: ConversionJob

    var body: some View {
        switch job.state {
        case .running, .verifying:
            ProgressRow(progress: job.progress)
        case .queued:
            StatusPill(title: "Queued", foreground: .secondary, fill: Brand.fieldFill)
        case .completed:
            Label("Done", systemImage: "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Brand.success)
        case .ready:
            StatusPill(title: "Ready", foreground: Brand.success, fill: Brand.successFill)
        case .failed, .blockedByPermission:
            Text(job.state.title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Brand.danger)
        case .probing, .importing:
            ProgressView().controlSize(.small)
        case .cancelled, .interrupted:
            StatusPill(title: job.state.title, foreground: .secondary, fill: Brand.fieldFill)
        }
    }
}

struct ProgressRow: View {
    var progress: Double?

    var body: some View {
        HStack(spacing: 6) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Brand.blue)
                Text("\(Int(progress * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Brand.blue)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Conversion progress")
        .accessibilityValue(progress.map { "\(Int($0 * 100)) percent" } ?? "Starting")
    }
}

/// Amber box for "this will be bigger than the original" and similar advice.
struct AdviceBox<Actions: View>: View {
    var title: String?
    var message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.warning)
            }
            Text(message)
                .foregroundStyle(Brand.warningText)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.warningFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.warningStroke, lineWidth: 1)
        )
    }
}

/// Grouped rows with hairlines between them, like a System Settings list.
struct GroupedRows<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .background(Brand.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Brand.hairline, lineWidth: 1)
        )
    }
}

/// Equal-width pill segments. Unlike the system segmented control it shrinks with its column.
struct SegmentedPills<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(title(option))
                        .fontWeight(selected ? .semibold : .regular)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Brand.panel)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Brand.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct GroupedRowDivider: View {
    var body: some View {
        Rectangle().fill(Brand.hairline).frame(height: 1)
    }
}

enum SizeText {
    /// "+34%" or "−55%".
    static func change(_ fraction: Double) -> String {
        let percent = Int((fraction * 100).rounded())
        if percent > 0 { return "+\(percent)%" }
        if percent < 0 { return "\u{2212}\(-percent)%" }
        return "±0%"
    }

    /// "34%", without a sign, for sentences that already say larger or smaller.
    static func percent(_ fraction: Double) -> String {
        "\(Int((abs(fraction) * 100).rounded()))%"
    }

    static func changeColor(_ fraction: Double) -> Color {
        fraction > 0 ? Brand.warning : Brand.success
    }

    /// Next lighter preset to suggest when a file comes out large.
    static func lighterPreset(than preset: PresetID) -> PresetID? {
        switch preset {
        case .highQuality, .custom: .balanced
        case .balanced: .smallFile
        case .smallFile: nil
        }
    }

    static func settingsSummary(_ options: WebPOptions) -> String {
        if options.presetID == .custom {
            return "Custom · \(options.framesPerSecond) fps · Q\(options.quality)"
        }
        return options.presetID.shortTitle
    }
}

/// Plays an animated WebP (or GIF) through ImageIO, which composites each frame.
/// Frames land in SwiftUI state so the picture sizes like any other image.
struct AnimatedImageView: View {
    var url: URL
    @StateObject private var driver = AnimationDriver()

    var body: some View {
        Group {
            if let frame = driver.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if driver.failed {
                Label("Can't play this file", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color(white: 0.7))
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { driver.start(url) }
        .onChange(of: url) { driver.start(url) }
        .onDisappear { driver.stop() }
    }
}

@MainActor
final class AnimationDriver: ObservableObject {
    @Published private(set) var frame: CGImage?
    @Published private(set) var failed = false
    private var generation = 0

    func start(_ url: URL) {
        generation += 1
        let current = generation
        failed = false
        let status = CGAnimateImageAtURLWithBlock(url as CFURL, nil) { [weak self] _, image, stop in
            // ImageIO calls back on the main queue.
            MainActor.assumeIsolated {
                guard let self, self.generation == current else {
                    stop.pointee = true
                    return
                }
                self.frame = image
            }
        }
        if status != noErr {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let first = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                frame = first
            } else {
                failed = true
            }
        }
    }

    func stop() {
        generation += 1
    }
}
