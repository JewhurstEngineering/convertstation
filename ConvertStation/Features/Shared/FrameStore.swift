import AVFoundation
import CoreGraphics
import Observation

/// Poster thumbnails for queue rows and evenly spaced frames for the trim strip.
/// Generated once per file and kept for the session.
@MainActor
@Observable
final class FrameStore {
    static let shared = FrameStore()

    private(set) var thumbnails: [URL: CGImage] = [:]
    private(set) var strips: [URL: [CGImage]] = [:]
    @ObservationIgnored private var pending: Set<String> = []

    func loadThumbnail(_ url: URL) async {
        let key = "thumb:" + url.path
        guard thumbnails[url] == nil, !pending.contains(key) else { return }
        pending.insert(key)
        defer { pending.remove(key) }
        let frames = await Self.frames(url: url, count: 1, maxSize: CGSize(width: 160, height: 160))
        if let first = frames.images.first {
            thumbnails[url] = first
        }
    }

    func loadStrip(_ url: URL, count: Int) async {
        let key = "strip:" + url.path
        guard strips[url] == nil, !pending.contains(key) else { return }
        pending.insert(key)
        defer { pending.remove(key) }
        let frames = await Self.frames(url: url, count: count, maxSize: CGSize(width: 220, height: 140))
        if !frames.images.isEmpty {
            strips[url] = frames.images
        }
    }

    private nonisolated static func frames(url: URL, count: Int, maxSize: CGSize) async -> FrameImages {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite, duration.seconds > 0 else {
            return FrameImages(images: [])
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        let tolerance = CMTime(seconds: min(0.5, duration.seconds / Double(count * 2)), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        var images: [CGImage] = []
        for index in 0..<count {
            // Sample the middle of each slice; a poster frame at 0 is often black.
            let fraction = count == 1 ? 0.1 : (Double(index) + 0.5) / Double(count)
            let time = CMTime(seconds: duration.seconds * fraction, preferredTimescale: 600)
            if let frame = try? await generator.image(at: time) {
                images.append(frame.image)
            }
        }
        return FrameImages(images: images)
    }
}

private struct FrameImages: @unchecked Sendable {
    var images: [CGImage]
}
