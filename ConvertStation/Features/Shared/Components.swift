import AppKit
import ImageIO
import SwiftUI

/// Poster frame for a queue row. Falls back to a neutral tile until the frame loads.
struct ClipThumbnail: View {
    var job: ConversionJob
    var width: CGFloat = 52
    var height: CGFloat = 36

    var body: some View {
        ZStack {
            Brand.fieldFill
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
struct AnimatedImageView: NSViewRepresentable {
    var url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        context.coordinator.start(url: url, in: view)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.start(url: url, in: view)
        }
    }

    static func dismantleNSView(_ view: NSImageView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        var url: URL?
        private var generation = 0

        func start(url: URL, in view: NSImageView) {
            stop()
            self.url = url
            let current = generation
            let options = [kCGImageAnimationLoopCount: 0] as CFDictionary
            let status = CGAnimateImageAtURLWithBlock(url as CFURL, options) { [weak self, weak view] _, image, stopFlag in
                MainActor.assumeIsolated {
                    guard let self, let view, self.generation == current else {
                        stopFlag.pointee = true
                        return
                    }
                    view.image = NSImage(cgImage: image, size: .zero)
                }
            }
            if status != noErr, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let first = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                view.image = NSImage(cgImage: first, size: .zero)
            }
        }

        func stop() {
            generation += 1
        }
    }
}
