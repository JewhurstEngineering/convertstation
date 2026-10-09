import AVKit
import SwiftUI

/// Muted player shared by the preview stage and the trim strip, so the playhead
/// and the picture stay in step. Playback loops inside the trim range.
@MainActor
final class PreviewPlayback: ObservableObject {
    @Published var playing = false
    @Published var time = 0.0
    @Published var duration = 0.0
    var scrubbing = false
    var range: ClosedRange<Double>?
    let player: AVPlayer
    private var observer: Any?

    init(url: URL) {
        let player = AVPlayer(url: url)
        player.isMuted = true
        self.player = player
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600),
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
            if let range, time >= range.upperBound - 0.05 || time < range.lowerBound {
                seek(range.lowerBound)
            }
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
        if playing, !scrubbing, let range, time >= range.upperBound {
            seek(range.lowerBound)
        }
    }
}

/// The dark stage with the source video centred in it.
struct VideoStage: View {
    @ObservedObject var playback: PreviewPlayback
    var aspect: CGFloat
    var badge: String?
    var cornerRadius: CGFloat = 12
    var inset: CGFloat = 24

    var body: some View {
        ZStack(alignment: .topLeading) {
            Brand.stage
            PlayerHost(player: playback.player)
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(inset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let badge {
                StageBadge(text: badge)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { playback.toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Source preview")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(playback.playing ? "Pauses playback" : "Plays the clip")
    }
}

struct StageBadge: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color(white: 0.86))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.12), in: Capsule())
            .padding(12)
    }
}

/// Frame strip with draggable trim handles, a playhead, and play controls.
struct TrimTimeline: View {
    @Bindable var model: AppModel
    var job: ConversionJob
    @ObservedObject var playback: PreviewPlayback
    var compact = false

    @State private var dragStart: Double?
    @State private var dragEnd: Double?
    private var frames: FrameStore { FrameStore.shared }

    private var duration: Double {
        let known = job.descriptor?.durationSeconds ?? playback.duration
        return max(known, 0.01)
    }

    private var start: Double { dragStart ?? job.options.trimStartSeconds }
    private var end: Double { dragEnd ?? min(job.options.trimEndSeconds ?? duration, duration) }
    private var stripCount: Int { compact ? 10 : 12 }
    private let handleWidth: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                controlsRow
            }
            strip
                .frame(height: compact ? 36 : 48)
            if compact {
                HStack {
                    Text(Clock.precise(start))
                    Spacer()
                    Text("\(MediaFormat.duration(end - start)) selected")
                    Spacer()
                    Text(Clock.precise(end))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .task(id: job.sourceURL) { await frames.loadStrip(job.sourceURL, count: 12) }
        .onAppear { playback.range = start...end }
        .onChange(of: start) { playback.range = start...end }
        .onChange(of: end) { playback.range = start...end }
    }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            Button {
                playback.toggle()
            } label: {
                Image(systemName: playback.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .frame(width: 30, height: 30)
                    .background(Brand.fieldFill, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.playing ? "Pause" : "Play")

            Text(Clock.precise(playback.time))
                .font(.body.monospacedDigit().weight(.medium))
            Text("/ \(Clock.precise(duration))")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Trim")
                .foregroundStyle(.secondary)
            TimeField(label: "Trim start", value: start) { value in
                commit(start: min(max(0, value), end - 0.1), end: nil)
            }
            Text("→")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TimeField(label: "Trim end", value: end) { value in
                commit(start: nil, end: min(max(value, start + 0.1), duration))
            }
        }
    }

    private var strip: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let startX = x(for: start, width: width)
            let endX = x(for: end, width: width)
            ZStack(alignment: .leading) {
                filmstrip
                // Dim what falls outside the trim.
                Color(nsColor: .windowBackgroundColor).opacity(0.72)
                    .frame(width: max(0, startX))
                Color(nsColor: .windowBackgroundColor).opacity(0.72)
                    .frame(width: max(0, width - endX))
                    .offset(x: endX)
                // Selection frame with thick grab edges.
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Brand.blue, lineWidth: 3)
                    .frame(width: max(handleWidth * 2, endX - startX))
                    .offset(x: startX)
                    .allowsHitTesting(false)
                handle(at: startX, isStart: true, width: width)
                handle(at: endX - handleWidth, isStart: false, width: width)
                // Playhead.
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: x(for: playback.time, width: width) - 1)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        playback.scrubbing = true
                        playback.seek(seconds(for: value.location.x, width: width))
                    }
                    .onEnded { _ in playback.scrubbing = false }
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Trim timeline")
    }

    private var filmstrip: some View {
        HStack(spacing: 2) {
            let images = frames.strips[job.sourceURL] ?? []
            ForEach(0..<stripCount, id: \.self) { index in
                // Fill images sit in an overlay so their size never feeds back into the strip's layout.
                Brand.fieldFill
                    .overlay {
                        if !images.isEmpty {
                            let image = images[min(images.count - 1, index * images.count / stripCount)]
                            Image(decorative: image, scale: 1)
                                .resizable()
                                .scaledToFill()
                        }
                    }
                    .clipped()
            }
        }
        .background(Brand.hairline)
    }

    private func handle(at offset: CGFloat, isStart: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Brand.blue)
            .overlay(
                Capsule().fill(Color.white.opacity(0.9)).frame(width: 2, height: 14)
            )
            .frame(width: handleWidth)
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .local)
                    .onChanged { value in
                        let base = isStart ? x(for: job.options.trimStartSeconds, width: width) : x(for: min(job.options.trimEndSeconds ?? duration, duration), width: width)
                        let proposed = seconds(for: base + value.translation.width, width: width)
                        playback.scrubbing = true
                        if isStart {
                            dragStart = min(max(0, proposed), end - 0.1)
                            playback.seek(dragStart ?? 0)
                        } else {
                            dragEnd = max(min(duration, proposed), start + 0.1)
                            playback.seek(dragEnd ?? duration)
                        }
                    }
                    .onEnded { _ in
                        playback.scrubbing = false
                        commit(start: dragStart, end: dragEnd)
                        dragStart = nil
                        dragEnd = nil
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(isStart ? "Trim start" : "Trim end")
            .accessibilityValue(Clock.precise(isStart ? start : end))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.1 : -0.1
                if isStart {
                    commit(start: min(max(0, start + step), end - 0.1), end: nil)
                } else {
                    commit(start: nil, end: max(min(duration, end + step), start + 0.1))
                }
            }
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    private func commit(start newStart: Double?, end newEnd: Double?) {
        guard newStart != nil || newEnd != nil else { return }
        model.updateOptions(for: job.id) { options in
            if let newStart {
                options.trimStartSeconds = (newStart * 100).rounded() / 100
            }
            if let newEnd {
                // Dragging to the very end means "to the end of the clip".
                options.trimEndSeconds = newEnd >= duration - 0.01 ? nil : (newEnd * 100).rounded() / 100
            }
        }
    }

    private func x(for seconds: Double, width: CGFloat) -> CGFloat {
        CGFloat(min(max(seconds / duration, 0), 1)) * width
    }

    private func seconds(for x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(x / width, 0), 1)) * duration
    }
}

/// A small editable time readout, such as 0:05.45.
private struct TimeField: View {
    var label: String
    var value: Double
    var commit: (Double) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .textFieldStyle(.plain)
            .font(.body.monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: 64)
            .padding(.vertical, 3)
            .background(Brand.fieldFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .focused($focused)
            .onAppear { text = Clock.precise(value) }
            .onChange(of: value) { if !focused { text = Clock.precise(value) } }
            .onSubmit {
                if let parsed = Clock.parse(text) { commit(parsed) }
                text = Clock.precise(value)
            }
            .accessibilityLabel(label)
    }
}

enum Clock {
    /// 0:05.45
    static func precise(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00.00" }
        let hundredths = Int((seconds * 100).rounded())
        return String(format: "%d:%02d.%02d", hundredths / 6000, (hundredths / 100) % 60, hundredths % 100)
    }

    /// Accepts 5.45, 0:05.45 or 1:02.
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        switch parts.count {
        case 1:
            return Double(parts[0])
        case 2:
            guard let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
            return minutes * 60 + seconds
        default:
            return nil
        }
    }
}

struct PlayerHost: NSViewRepresentable {
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

/// Owns a `PreviewPlayback` for one file and hands it to its content.
/// Keyed by the file so switching files starts a fresh player.
struct PlaybackScope<Content: View>: View {
    @StateObject private var playback: PreviewPlayback
    private let content: (PreviewPlayback) -> Content

    init(url: URL, @ViewBuilder content: @escaping (PreviewPlayback) -> Content) {
        _playback = StateObject(wrappedValue: PreviewPlayback(url: url))
        self.content = content
    }

    var body: some View {
        content(playback)
            .onDisappear { playback.stop() }
    }
}
