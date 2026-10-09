import Foundation

enum LayoutMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case studio
    case batch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .studio: "Studio"
        case .batch: "Batch"
        }
    }

    var systemImage: String {
        switch self {
        case .studio: "rectangle.split.3x1"
        case .batch: "list.bullet.rectangle"
        }
    }
}

/// A rough guess at the finished file, shown before converting.
/// Real sizes depend on the picture, so the UI always labels this as approximate.
struct OutputEstimate: Equatable, Sendable {
    var frames: Int
    var width: Int
    var height: Int
    var duration: Double
    var bytes: Int64

    /// Change against the source file, as a fraction (0.34 means 34% larger).
    func change(from sourceBytes: Int64?) -> Double? {
        guard let sourceBytes, sourceBytes > 0 else { return nil }
        return (Double(bytes) - Double(sourceBytes)) / Double(sourceBytes)
    }
}

enum SizeEstimator {
    /// Bytes per output pixel per frame at quality 0 and at quality 100.
    /// Calibrated against screen recordings run through libwebp_anim at compression level 4.
    static let floorBytesPerPixel = 0.004
    static let ceilingBytesPerPixel = 0.036

    static func estimate(options: WebPOptions, source: SourceDescriptor) -> OutputEstimate? {
        guard let width = source.displayWidth, let height = source.displayHeight, width > 0, height > 0 else {
            return nil
        }
        guard let interval = try? options.effectiveInterval(sourceDuration: source.durationSeconds) else {
            return nil
        }
        let size = outputSize(width: width, height: height, maxPixelWidth: options.maxPixelWidth)
        let fps = options.resolvedFPS(sourceFPS: source.averageFrameRate).fps
        let frames = max(1, Int((interval.duration * Double(fps)).rounded()))
        let quality = Double(min(max(options.quality, 0), 100)) / 100
        let perPixel = floorBytesPerPixel + (ceilingBytesPerPixel - floorBytesPerPixel) * quality * quality
        let bytes = Double(frames) * Double(size.width * size.height) * perPixel
        return OutputEstimate(
            frames: frames,
            width: size.width,
            height: size.height,
            duration: interval.duration,
            bytes: Int64(bytes.rounded())
        )
    }

    /// Mirrors the ffmpeg scale filter: never upscale, even width, height keeps the aspect.
    static func outputSize(width: Int, height: Int, maxPixelWidth: Int?) -> (width: Int, height: Int) {
        let target = min(maxPixelWidth ?? width, width)
        let evenWidth = max(2, target / 2 * 2)
        let scaledHeight = Double(height) * Double(evenWidth) / Double(width)
        let evenHeight = max(2, Int((scaledHeight / 2).rounded()) * 2)
        return (evenWidth, evenHeight)
    }
}
