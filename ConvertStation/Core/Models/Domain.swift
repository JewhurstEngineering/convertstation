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
    static let fpsChoices = [5, 8, 10, 12, 15, 20, 24, 30, 48, 50, 60, 120]
    static let widthChoices = [320, 480, 640, 800, 1024, 1280, 1920, 2560, 3840, 7680]
    static let longClipSeconds = 30.0
    static let qualityRange = 0...100

    /// How far a listed rate can sit above a measured rate and still count.
    /// Covers 23.976, 29.97, 59.94, and 119.88.
    static let fpsMatchSlack = 0.15

    /// Rates the menu can offer without inventing frames.
    /// A missing source rate keeps the full ladder.
    static func fpsChoices(fitting sourceFPS: Double?) -> [Int] {
        guard let sourceFPS, sourceFPS > 0 else { return fpsChoices }
        return fpsChoices.filter { Double($0) <= sourceFPS + fpsMatchSlack }
    }

    /// Widths the menu can offer without asking the encoder to upscale.
    /// A missing or unusable source width keeps the full ladder.
    static func widthChoices(fitting sourceWidth: Int?) -> [Int] {
        guard let sourceWidth, sourceWidth > 0 else { return widthChoices }
        return widthChoices.filter { $0 <= sourceWidth }
    }
}

struct WebPOptions: Codable, Equatable, Sendable {
    var presetID: PresetID
    /// Nil keeps the source timing instead of resampling.
    var framesPerSecond: Int?
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
            // Full source timing, full width, best quality.
            options = WebPOptions(
                presetID: .maximum,
                framesPerSecond: nil,
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

    var frameRateLabel: String {
        framesPerSecond.map { "\($0) fps" } ?? "original frame rate"
    }

    /// Nil means leave the source timestamps alone. A chosen rate above the
    /// source is lowered to the fastest offered rate the file can support.
    func resolvedFPS(sourceFPS: Double?) -> (fps: Int?, clamped: Bool) {
        guard let framesPerSecond else {
            return (nil, false)
        }
        guard let sourceFPS, sourceFPS > 0 else {
            return (framesPerSecond, false)
        }
        if Double(framesPerSecond) <= sourceFPS + WebPLimits.fpsMatchSlack {
            return (framesPerSecond, false)
        }
        if let fitted = WebPLimits.fpsChoices(fitting: sourceFPS).last {
            return (fitted, true)
        }
        return (max(1, Int(sourceFPS.rounded(.down))), true)
    }

    /// Rate used for estimates and "did this produce an animation" checks.
    func playbackFPS(sourceFPS: Double?) -> Double {
        if let fps = resolvedFPS(sourceFPS: sourceFPS).fps {
            return Double(fps)
        }
        if let sourceFPS, sourceFPS > 0 {
            return sourceFPS
        }
        return 30
    }

    func effectiveInterval(sourceDuration: Double?, cappingLongClips: Bool = true) throws -> TrimInterval {
        let start = trimStartSeconds
        guard start >= 0 else {
            throw ConversionError.invalidOptions("Trim start can't be negative.")
        }
        guard WebPLimits.qualityRange.contains(quality) else {
            throw ConversionError.invalidOptions("Quality must be between 0 and 100.")
        }
        if let framesPerSecond, framesPerSecond <= 0 {
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
        if cappingLongClips, !allowLongClip, duration > WebPLimits.longClipSeconds {
            duration = WebPLimits.longClipSeconds
        }
        return TrimInterval(start: start, duration: duration)
    }

    var compressionLevel: Int {
        // libwebp method 6 is about 16× slower than method 4 at 1080p and
        // finishes at the same size. It also writes nothing until the last
        // frame, so the progress bar sits at 0% for the whole encode.
        switch presetID {
        case .smallFile: 2
        case .balanced, .custom, .highQuality, .maximum: 4
        }
    }
}

struct TrimInterval: Equatable, Sendable {
    var start: Double
    var duration: Double
}

enum MediaKind: String, Codable, Equatable, Sendable {
    case video
    case audio
    case still
    case animation
    case document
}

enum OutputFamily: String, Codable, CaseIterable, Identifiable, Sendable {
    case video
    case animation
    case image
    case audio
    case document

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "Video"
        case .animation: "Animation"
        case .image: "Image"
        case .audio: "Audio"
        case .document: "Document"
        }
    }
}

struct StillOptions: Codable, Equatable, Sendable {
    var maxEdge: Int?
    var quality: Int

    static let standard = StillOptions(maxEdge: nil, quality: 85)

    static let lossyProfiles: Set<String> = [OutputID.jpeg, OutputID.heic, OutputID.stillWebP]
}

struct AudioOptions: Codable, Equatable, Sendable {
    var bitrateKbps: Int
    var sampleRate: Int

    static let standard = AudioOptions(bitrateKbps: 192, sampleRate: 48_000)
    static let bitrateChoices = [96, 128, 160, 192, 256, 320]
    static let sampleRateChoices = [22_050, 44_100, 48_000]
    static let lossyProfiles: Set<String> = [OutputID.m4aAAC, OutputID.opus, OutputID.mp3]
}

struct VideoOptions: Codable, Equatable, Sendable {
    var maxPixelWidth: Int?
    var quality: Int

    static let standard = VideoOptions(maxPixelWidth: nil, quality: 70)
}

enum OutputID {
    static let animatedWebP = "animated-webp"
    static let gifAnimated = "gif.animated"
    static let mp4 = "mp4.h264-aac"
    static let mov = "mov.h264-aac"
    static let webm = "webm.vp9-opus"
    static let jpeg = "image.jpeg"
    static let png = "image.png"
    static let tiff = "image.tiff"
    static let bmp = "image.bmp"
    static let heic = "image.heic"
    static let stillWebP = "image.webp"
    static let stillGIF = "image.gif"
    static let wav = "audio.wav"
    static let aiff = "audio.aiff"
    static let flac = "audio.flac"
    static let m4aAAC = "audio.m4a-aac"
    static let m4aALAC = "audio.m4a-alac"
    static let opus = "audio.opus"
    static let mp3 = "audio.mp3"
    static let markdown = "document.md"
    static let rtf = "document.rtf"
    static let html = "document.html"
    static let plainText = "document.txt"
    static let pdfText = "document.pdf"
    static let docx = "document.docx"
}

struct SourceDescriptor: Equatable, Sendable {
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
    var kind: MediaKind
    var audioCodecName: String?
    var pageCount: Int

    init(
        url: URL,
        detectedUTType: String,
        durationSeconds: Double?,
        width: Int?,
        height: Int?,
        rotationDegrees: Int,
        hasVideo: Bool,
        hasAudio: Bool,
        hasAlpha: Bool,
        isHDR: Bool,
        codecName: String?,
        averageFrameRate: Double?,
        fileSizeBytes: Int64?,
        formatName: String?,
        warnings: [String],
        kind: MediaKind = .video,
        audioCodecName: String? = nil,
        pageCount: Int = 1
    ) {
        self.url = url
        self.detectedUTType = detectedUTType
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.rotationDegrees = rotationDegrees
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
        self.hasAlpha = hasAlpha
        self.isHDR = isHDR
        self.codecName = codecName
        self.averageFrameRate = averageFrameRate
        self.fileSizeBytes = fileSizeBytes
        self.formatName = formatName
        self.warnings = warnings
        self.kind = kind
        self.audioCodecName = audioCodecName
        self.pageCount = max(pageCount, 1)
    }

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

extension SourceDescriptor: Codable {
    enum CodingKeys: String, CodingKey {
        case url, detectedUTType, durationSeconds, width, height, rotationDegrees
        case hasVideo, hasAudio, hasAlpha, isHDR, codecName, averageFrameRate
        case fileSizeBytes, formatName, warnings, kind, audioCodecName, pageCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(URL.self, forKey: .url)
        detectedUTType = try container.decode(String.self, forKey: .detectedUTType)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        rotationDegrees = try container.decode(Int.self, forKey: .rotationDegrees)
        hasVideo = try container.decode(Bool.self, forKey: .hasVideo)
        hasAudio = try container.decode(Bool.self, forKey: .hasAudio)
        hasAlpha = try container.decode(Bool.self, forKey: .hasAlpha)
        isHDR = try container.decode(Bool.self, forKey: .isHDR)
        codecName = try container.decodeIfPresent(String.self, forKey: .codecName)
        averageFrameRate = try container.decodeIfPresent(Double.self, forKey: .averageFrameRate)
        fileSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .fileSizeBytes)
        formatName = try container.decodeIfPresent(String.self, forKey: .formatName)
        warnings = try container.decode([String].self, forKey: .warnings)
        audioCodecName = try container.decodeIfPresent(String.self, forKey: .audioCodecName)
        pageCount = max(try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1, 1)
        if let kind = try container.decodeIfPresent(MediaKind.self, forKey: .kind) {
            self.kind = kind
        } else if hasVideo {
            kind = .video
        } else if hasAudio {
            kind = .audio
        } else {
            kind = .still
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encode(detectedUTType, forKey: .detectedUTType)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encode(rotationDegrees, forKey: .rotationDegrees)
        try container.encode(hasVideo, forKey: .hasVideo)
        try container.encode(hasAudio, forKey: .hasAudio)
        try container.encode(hasAlpha, forKey: .hasAlpha)
        try container.encode(isHDR, forKey: .isHDR)
        try container.encodeIfPresent(codecName, forKey: .codecName)
        try container.encodeIfPresent(averageFrameRate, forKey: .averageFrameRate)
        try container.encodeIfPresent(fileSizeBytes, forKey: .fileSizeBytes)
        try container.encodeIfPresent(formatName, forKey: .formatName)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(audioCodecName, forKey: .audioCodecName)
        try container.encode(pageCount, forKey: .pageCount)
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
    var family: OutputFamily = .animation
    var lossNotice: String = ""

    static let animatedWebP = TargetDescriptor(
        id: OutputID.animatedWebP,
        displayName: "Animated WebP (.webp)",
        fileExtension: "webp",
        supportsAnimation: true,
        supportsAlpha: true,
        supportsAudio: false,
        providerID: "ffmpeg-webp",
        family: .animation,
        lossNotice: "Audio is dropped. Animated WebP has no sound."
    )
}

struct ConversionRequest: Equatable, Sendable {
    var id: UUID
    var sourceURL: URL
    var targetFormatID: String
    var options: WebPOptions
    var stillOptions: StillOptions = .standard
    var audioOptions: AudioOptions = .standard
    var videoOptions: VideoOptions = .standard
    var destinationDirectory: URL
    var collisionPolicy: CollisionPolicy
}

struct ConversionResult: Equatable, Sendable {
    var outputURL: URL
    /// Later pages from one PDF. Missing on older saved jobs.
    var siblingOutputURLs: [URL]? = nil
    var bytes: Int64
    var elapsedSeconds: Double
    var width: Int
    var height: Int
    var frameCount: Int
    var loopForever: Bool
    var warnings: [String]

    var allOutputURLs: [URL] {
        [outputURL] + (siblingOutputURLs ?? [])
    }
}

extension ConversionResult: Codable {
    enum CodingKeys: String, CodingKey {
        case outputURL, siblingOutputURLs, bytes, elapsedSeconds, width, height, frameCount, loopForever, warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputURL = try container.decode(URL.self, forKey: .outputURL)
        siblingOutputURLs = try container.decodeIfPresent([URL].self, forKey: .siblingOutputURLs)
        bytes = try container.decode(Int64.self, forKey: .bytes)
        elapsedSeconds = try container.decode(Double.self, forKey: .elapsedSeconds)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        frameCount = try container.decode(Int.self, forKey: .frameCount)
        loopForever = try container.decode(Bool.self, forKey: .loopForever)
        warnings = try container.decode([String].self, forKey: .warnings)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(outputURL, forKey: .outputURL)
        try container.encodeIfPresent(siblingOutputURLs, forKey: .siblingOutputURLs)
        try container.encode(bytes, forKey: .bytes)
        try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(frameCount, forKey: .frameCount)
        try container.encode(loopForever, forKey: .loopForever)
        try container.encode(warnings, forKey: .warnings)
    }
}

struct ConversionJob: Identifiable, Equatable, Sendable {
    var id: UUID
    var sourceURL: URL
    var state: JobState
    var descriptor: SourceDescriptor?
    var profileID: String = OutputID.animatedWebP
    var options: WebPOptions
    var stillOptions: StillOptions = .standard
    var audioOptions: AudioOptions = .standard
    var videoOptions: VideoOptions = .standard
    var progress: Double?
    var errorMessage: String?
    var technicalDetail: String?
    var result: ConversionResult?
    var warnings: [String]
    var isDuplicate: Bool
    /// Kept off the saved job file. Bookmarks live beside it so older queues still open.
    var sourceBookmark: Data?

    var displayName: String { sourceURL.lastPathComponent }

    var canConvert: Bool {
        guard descriptor != nil else { return false }
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

extension ConversionJob: Codable {
    enum CodingKeys: String, CodingKey {
        case id, sourceURL, state, descriptor, options, progress, errorMessage, technicalDetail, result, warnings, isDuplicate
        case profileID, stillOptions, audioOptions, videoOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        state = try container.decode(JobState.self, forKey: .state)
        descriptor = try container.decodeIfPresent(SourceDescriptor.self, forKey: .descriptor)
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID) ?? OutputID.animatedWebP
        options = try container.decode(WebPOptions.self, forKey: .options)
        stillOptions = try container.decodeIfPresent(StillOptions.self, forKey: .stillOptions) ?? .standard
        audioOptions = try container.decodeIfPresent(AudioOptions.self, forKey: .audioOptions) ?? .standard
        videoOptions = try container.decodeIfPresent(VideoOptions.self, forKey: .videoOptions) ?? .standard
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        technicalDetail = try container.decodeIfPresent(String.self, forKey: .technicalDetail)
        result = try container.decodeIfPresent(ConversionResult.self, forKey: .result)
        warnings = try container.decode([String].self, forKey: .warnings)
        isDuplicate = try container.decode(Bool.self, forKey: .isDuplicate)
        sourceBookmark = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(state, forKey: .state)
        try container.encodeIfPresent(descriptor, forKey: .descriptor)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(options, forKey: .options)
        try container.encode(stillOptions, forKey: .stillOptions)
        try container.encode(audioOptions, forKey: .audioOptions)
        try container.encode(videoOptions, forKey: .videoOptions)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try container.encodeIfPresent(technicalDetail, forKey: .technicalDetail)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encode(warnings, forKey: .warnings)
        try container.encode(isDuplicate, forKey: .isDuplicate)
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
            "Conversion isn't available. \(detail)"
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
