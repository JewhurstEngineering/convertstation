import Foundation

enum JobState: String, Codable, Equatable, Sendable, CaseIterable {
    case importing
    case probing
    case ready
    case queued
    case running
    case verifying
    case completed
    case failed
    case cancelled
    case interrupted
    case blockedByPermission

    var title: String {
        switch self {
        case .importing: "Importing"
        case .probing: "Inspecting"
        case .ready: "Ready"
        case .queued: "Queued"
        case .running: "Converting"
        case .verifying: "Checking"
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .interrupted: "Interrupted"
        case .blockedByPermission: "Needs access"
        }
    }

    var isActive: Bool {
        self == .queued || self == .running || self == .verifying
    }
}

enum JobTransition {
    static func allows(_ from: JobState, _ to: JobState) -> Bool {
        if from == to { return true }
        switch (from, to) {
        case (.importing, .probing),
             (.probing, .ready),
             (.probing, .failed),
             (.probing, .blockedByPermission),
             (.ready, .queued),
             (.ready, .failed),
             (.ready, .cancelled),
             (.queued, .running),
             (.queued, .ready),
             (.queued, .cancelled),
             (.queued, .interrupted),
             (.running, .verifying),
             (.running, .completed),
             (.running, .failed),
             (.running, .cancelled),
             (.running, .interrupted),
             (.verifying, .completed),
             (.verifying, .failed),
             (.verifying, .cancelled),
             (.failed, .queued),
             (.failed, .probing),
             (.cancelled, .queued),
             (.cancelled, .probing),
             (.interrupted, .queued),
             (.interrupted, .probing),
             (.completed, .queued),
             (.completed, .ready),
             (.blockedByPermission, .probing),
             (.blockedByPermission, .queued):
            return true
        default:
            return false
        }
    }
}

enum CollisionPolicy: String, Codable, CaseIterable, Identifiable, Sendable {
    case ask
    case keepBoth
    case skip
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .keepBoth: "Keep Both"
        case .skip: "Skip"
        case .replace: "Replace"
        }
    }

    var summary: String {
        switch self {
        case .ask: "Ask before replacing a file"
        case .keepBoth: "Keep both by adding a number"
        case .skip: "Skip if the name is taken"
        case .replace: "Replace after you confirm"
        }
    }
}

enum CollisionChoice: Equatable, Sendable {
    case keepBoth
    case skip
    case replace
    case cancel
}

enum PresetID: String, Codable, CaseIterable, Identifiable, Sendable {
    case smallFile
    case balanced
    case highQuality
    case maximum
    case custom

    var id: String { rawValue }

    /// The presets with fixed numbers, in the order the UI shows them.
    static let builtIn: [PresetID] = [.smallFile, .balanced, .highQuality, .maximum]

    var title: String {
        switch self {
        case .smallFile: "Small File"
        case .balanced: "Balanced"
        case .highQuality: "High Quality"
        case .maximum: "Maximum"
        case .custom: "Custom"
        }
    }

    var shortTitle: String {
        switch self {
        case .smallFile: "Small"
        case .balanced: "Balanced"
        case .highQuality: "High"
        case .maximum: "Max"
        case .custom: "Custom"
        }
    }
}

enum WebPLimits {
    static let fpsChoices = [5, 8, 10, 12, 15, 20, 24, 30]
    static let widthChoices = [320, 480, 640, 800, 1024, 1280]
    static let longClipSeconds = 30.0
    static let qualityRange = 0...100
}

struct WebPOptions: Codable, Equatable, Sendable {
    var presetID: PresetID
    var framesPerSecond: Int
    var maxPixelWidth: Int?
    var quality: Int
    var loopForever: Bool
    var trimStartSeconds: Double
    var trimEndSeconds: Double?
    var allowLongClip: Bool

    static let balanced = WebPOptions(
        presetID: .balanced,
        framesPerSecond: 12,
        maxPixelWidth: 800,
        quality: 75,
        loopForever: true,
        trimStartSeconds: 0,
        trimEndSeconds: nil,
        allowLongClip: false
    )

    static func preset(_ id: PresetID, keepingTrim current: WebPOptions = .balanced) -> WebPOptions {
        var options: WebPOptions
        switch id {
        case .smallFile:
            options = WebPOptions(
                presetID: .smallFile,
                framesPerSecond: 8,
                maxPixelWidth: 480,
                quality: 60,
                loopForever: current.loopForever,
                trimStartSeconds: current.trimStartSeconds,
                trimEndSeconds: current.trimEndSeconds,
                allowLongClip: current.allowLongClip
            )
        case .balanced:
            options = .balanced
            options.loopForever = current.loopForever
            options.trimStartSeconds = current.trimStartSeconds
            options.trimEndSeconds = current.trimEndSeconds
            options.allowLongClip = current.allowLongClip
        case .highQuality:
            options = WebPOptions(
                presetID: .highQuality,
                framesPerSecond: 20,
                maxPixelWidth: 1280,
                quality: 85,
                loopForever: current.loopForever,
                trimStartSeconds: current.trimStartSeconds,
                trimEndSeconds: current.trimEndSeconds,
                allowLongClip: current.allowLongClip
            )
        case .maximum:
            // Every control at its top value: fastest frame rate offered, full width, best quality.
            options = WebPOptions(
                presetID: .maximum,
                framesPerSecond: WebPLimits.fpsChoices.max() ?? 30,
                maxPixelWidth: nil,
                quality: WebPLimits.qualityRange.upperBound,
                loopForever: current.loopForever,
                trimStartSeconds: current.trimStartSeconds,
                trimEndSeconds: current.trimEndSeconds,
                allowLongClip: current.allowLongClip
            )
        case .custom:
            options = current
            options.presetID = .custom
        }
        return options
    }

    func markingCustomIfNeeded() -> WebPOptions {
        guard presetID != .custom else { return self }
        let baseline = WebPOptions.preset(presetID, keepingTrim: self)
        if framesPerSecond != baseline.framesPerSecond
            || maxPixelWidth != baseline.maxPixelWidth
            || quality != baseline.quality {
            var copy = self
            copy.presetID = .custom
            return copy
        }
        return self
    }

    /// A custom setup whose numbers land back on a preset is shown as that preset again.
    func matchingPresetIfPossible() -> WebPOptions {
        guard presetID == .custom else { return self }
        for candidate in PresetID.builtIn {
            let baseline = WebPOptions.preset(candidate, keepingTrim: self)
            if framesPerSecond == baseline.framesPerSecond
                && maxPixelWidth == baseline.maxPixelWidth
                && quality == baseline.quality {
                var copy = self
                copy.presetID = candidate
                return copy
            }
        }
        return self
    }

    func resolvedFPS(sourceFPS: Double?) -> (fps: Int, clamped: Bool) {
        guard let sourceFPS, sourceFPS > 0 else {
            return (framesPerSecond, false)
        }
        if Double(framesPerSecond) <= sourceFPS + 0.05 {
            return (framesPerSecond, false)
        }
        let fitted = WebPLimits.fpsChoices.last(where: { Double($0) <= sourceFPS + 0.05 })
        if let fitted {
            return (fitted, true)
        }
        return (max(1, Int(sourceFPS.rounded(.down))), true)
    }

    func effectiveInterval(sourceDuration: Double?) throws -> TrimInterval {
        let start = trimStartSeconds
        guard start >= 0 else {
            throw ConversionError.invalidOptions("Trim start can't be negative.")
        }
        guard WebPLimits.qualityRange.contains(quality) else {
            throw ConversionError.invalidOptions("Quality must be between 0 and 100.")
        }
        guard framesPerSecond > 0 else {
            throw ConversionError.invalidOptions("Frame rate must be greater than zero.")
        }
        let end: Double
        if let trimEndSeconds {
            end = trimEndSeconds
        } else if let sourceDuration {
            end = sourceDuration
        } else {
            throw ConversionError.invalidOptions("This file has no duration. Set a trim end before converting.")
        }
        guard end > start + 0.001 else {
            throw ConversionError.invalidOptions("Trim end has to be after the start.")
        }
        if let sourceDuration, end > sourceDuration + 0.05 {
            throw ConversionError.invalidOptions("Trim end is past the end of the file.")
        }
        var duration = end - start
        if !allowLongClip, duration > WebPLimits.longClipSeconds {
            duration = WebPLimits.longClipSeconds
        }
        return TrimInterval(start: start, duration: duration)
    }

    var compressionLevel: Int {
        switch presetID {
        case .smallFile: 2
        case .balanced, .custom: 4
        case .highQuality, .maximum: 6
        }
    }
}

struct TrimInterval: Equatable, Sendable {
    var start: Double
    var duration: Double
}

struct SourceDescriptor: Codable, Equatable, Sendable {
    var url: URL
    var detectedUTType: String
    var durationSeconds: Double?
    var width: Int?
    var height: Int?
    var rotationDegrees: Int
    var hasVideo: Bool
    var hasAudio: Bool
    var hasAlpha: Bool
    var isHDR: Bool
    var codecName: String?
    var averageFrameRate: Double?
    var fileSizeBytes: Int64?
    var formatName: String?
    var warnings: [String]

    var displayWidth: Int? {
        guard let width, let height else { return nil }
        return swapsAxes ? height : width
    }

    var displayHeight: Int? {
        guard let width, let height else { return nil }
        return swapsAxes ? width : height
    }

    private var swapsAxes: Bool {
        abs(rotationDegrees) % 180 == 90
    }
}

struct TargetDescriptor: Identifiable, Equatable, Sendable {
    var id: String
    var displayName: String
    var fileExtension: String
    var supportsAnimation: Bool
    var supportsAlpha: Bool
    var supportsAudio: Bool
    var providerID: String

    static let animatedWebP = TargetDescriptor(
        id: "animated-webp",
        displayName: "Animated WebP",
        fileExtension: "webp",
        supportsAnimation: true,
        supportsAlpha: true,
        supportsAudio: false,
        providerID: "ffmpeg-webp"
    )
}

struct ConversionRequest: Equatable, Sendable {
    var id: UUID
    var sourceURL: URL
    var targetFormatID: String
    var options: WebPOptions
    var destinationDirectory: URL
    var collisionPolicy: CollisionPolicy
}

struct ConversionResult: Codable, Equatable, Sendable {
    var outputURL: URL
    var bytes: Int64
    var elapsedSeconds: Double
    var width: Int
    var height: Int
    var frameCount: Int
    var loopForever: Bool
    var warnings: [String]
}

struct ConversionJob: Identifiable, Equatable, Codable, Sendable {
    var id: UUID
    var sourceURL: URL
    var state: JobState
    var descriptor: SourceDescriptor?
    var options: WebPOptions
    var progress: Double?
    var errorMessage: String?
    var technicalDetail: String?
    var result: ConversionResult?
    var warnings: [String]
    var isDuplicate: Bool
    /// Kept off the saved job file. Bookmarks live beside it so older queues still open.
    var sourceBookmark: Data?

    enum CodingKeys: String, CodingKey {
        case id, sourceURL, state, descriptor, options, progress, errorMessage, technicalDetail, result, warnings, isDuplicate
    }

    var displayName: String { sourceURL.lastPathComponent }

    var canConvert: Bool {
        guard descriptor?.hasVideo == true else { return false }
        switch state {
        case .ready, .interrupted, .cancelled, .failed:
            return true
        default:
            return false
        }
    }

    static func new(url: URL, duplicate: Bool) -> ConversionJob {
        ConversionJob(
            id: UUID(),
            sourceURL: url,
            state: .probing,
            descriptor: nil,
            options: .balanced,
            progress: nil,
            errorMessage: nil,
            technicalDetail: nil,
            result: nil,
            warnings: duplicate ? ["This file is already in the queue."] : [],
            isDuplicate: duplicate,
            sourceBookmark: nil
        )
    }
}

enum ConversionError: LocalizedError, Equatable {
    case engineMissing(String)
    case unreadable(String)
    case invalidOptions(String)
    case processFailed(exitCode: Int32, log: String)
    case validationFailed(String)
    case samePathAsSource
    case destinationNotWritable
    case skippedExisting
    case cancelled

    var errorDescription: String? {
        switch self {
        case .engineMissing(let detail):
            "Animated WebP isn't available. \(detail)"
        case .unreadable(let detail):
            "This file couldn't be read. \(detail)"
        case .invalidOptions(let detail):
            detail
        case .processFailed(let code, _):
            "Conversion failed (exit \(code))."
        case .validationFailed(let detail):
            "The output didn't check out. \(detail)"
        case .samePathAsSource:
            "The output can't replace the original file."
        case .destinationNotWritable:
            "ConvertStation can't write to that folder."
        case .skippedExisting:
            "Skipped because a file with this name already exists."
        case .cancelled:
            "Conversion cancelled."
        }
    }

    var technicalLog: String? {
        switch self {
        case .processFailed(_, let log):
            Diagnostics.redact(log)
        case .unreadable(let detail), .engineMissing(let detail), .validationFailed(let detail):
            Diagnostics.redact(detail)
        default:
            nil
        }
    }
}

enum Diagnostics {
    static func redact(_ text: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return text }
        return text.replacingOccurrences(of: home, with: "~")
    }
}

enum MediaFormat {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        if minutes > 0 {
            return String(format: "%d:%02d", minutes, remainder)
        }
        return String(format: "%.1fs", seconds)
    }

    static func dimensions(width: Int?, height: Int?) -> String {
        guard let width, let height else { return "—" }
        return "\(width)×\(height)"
    }
}
