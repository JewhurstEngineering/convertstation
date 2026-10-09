import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ConvertStation

final class FixtureAnchor: NSObject {}

enum Fixtures {
    static func url(_ name: String) -> URL {
        let file = name as NSString
        if let bundled = Bundle(for: FixtureAnchor.self).url(forResource: file.deletingPathExtension, withExtension: file.pathExtension) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }
}

struct MockImageProvider: ConversionProvider {
    var id: String { "mock-image" }

    func canRead(_ source: SourceDescriptor) -> Bool {
        source.detectedUTType == "mock.image"
    }

    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor] {
        guard canRead(source) else { return [] }
        return [
            TargetDescriptor(
                id: "mock-png",
                displayName: "Mock PNG",
                fileExtension: "png",
                supportsAnimation: false,
                supportsAlpha: true,
                supportsAudio: false,
                providerID: id
            )
        ]
    }

    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws {}

    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        ExecutionPlan(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"),
            arguments: [],
            expectedDuration: 0,
            temporaryOutput: temporaryOutput,
            warnings: []
        )
    }
}

struct MockAudioProvider: ConversionProvider {
    var id: String { "mock-audio" }

    func canRead(_ source: SourceDescriptor) -> Bool {
        source.detectedUTType == "mock.audio"
    }

    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor] {
        guard canRead(source) else { return [] }
        return [
            TargetDescriptor(
                id: "mock-wav",
                displayName: "Mock WAV",
                fileExtension: "wav",
                supportsAnimation: false,
                supportsAlpha: false,
                supportsAudio: true,
                providerID: id
            )
        ]
    }

    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws {}

    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        throw ConversionError.invalidOptions("Mock audio is not a real conversion.")
    }
}

@Test func registryOffersWebPOnlyForVideo() {
    let webp = AnimatedWebPProvider(binaries: EngineBinaries(
        ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
        ffprobe: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"),
        versionSummary: "test"
    ))
    let registry = CapabilityRegistry(providers: [webp, MockImageProvider(), MockAudioProvider()])
    let video = sampleSource(hasVideo: true, hasAudio: true, type: "com.apple.quicktime-movie")
    let audio = sampleSource(hasVideo: false, hasAudio: true, type: "public.audio")
    let image = sampleSource(hasVideo: false, hasAudio: false, type: "mock.image")

    #expect(registry.targets(for: video).map(\.id) == ["animated-webp"])
    #expect(registry.targets(for: audio).isEmpty)
    #expect(registry.targets(for: image).map(\.id) == ["mock-png"])
}

@Test func registryKeepsTheFirstProviderForADuplicateTarget() {
    let registry = CapabilityRegistry(providers: [MockImageProvider(), MockImageProvider()])
    let image = sampleSource(hasVideo: false, hasAudio: false, type: "mock.image")
    #expect(registry.targets(for: image).count == 1)
}

@Test func presetNumbersMatchThePRD() {
    let small = WebPOptions.preset(.smallFile)
    #expect(small.framesPerSecond == 8)
    #expect(small.maxPixelWidth == 480)
    #expect(small.quality == 60)

    let balanced = WebPOptions.preset(.balanced)
    #expect(balanced.framesPerSecond == 12)
    #expect(balanced.maxPixelWidth == 800)
    #expect(balanced.quality == 75)

    let high = WebPOptions.preset(.highQuality)
    #expect(high.framesPerSecond == 20)
    #expect(high.maxPixelWidth == 1280)
    #expect(high.quality == 85)
}

@Test func maxPresetTurnsEverythingUp() {
    let max = WebPOptions.preset(.maximum)
    #expect(max.framesPerSecond == 30)
    #expect(max.maxPixelWidth == nil)
    #expect(max.quality == 100)
    #expect(max.compressionLevel == 6)
    #expect(SizeText.lighterPreset(than: .maximum) == .highQuality)
}

@Test func customSettingsSnapBackToAMatchingPreset() {
    var options = WebPOptions.preset(.balanced)
    options.quality = 40
    options = options.markingCustomIfNeeded()
    #expect(options.presetID == .custom)
    options.quality = 75
    #expect(options.matchingPresetIfPossible().presetID == .balanced)
}

@Test func savedPresetRoundTripsAndKeepsTrim() throws {
    var custom = WebPOptions.preset(.balanced)
    custom.framesPerSecond = 24
    custom.quality = 90
    custom.presetID = .custom
    let saved = SavedPreset(name: "Docs", options: custom)
    let decoded = try JSONDecoder().decode(SavedPreset.self, from: JSONEncoder().encode(saved))
    #expect(decoded == saved)

    var other = WebPOptions.preset(.smallFile)
    other.trimStartSeconds = 1.5
    let applied = saved.applied(to: other)
    #expect(applied.framesPerSecond == 24)
    #expect(applied.quality == 90)
    #expect(applied.trimStartSeconds == 1.5)
    #expect(applied.presetID == .custom)
    #expect(saved.matches(applied))
}

@Test func editingAPresetValueMarksItCustom() {
    var options = WebPOptions.balanced
    options.quality = 40
    #expect(options.markingCustomIfNeeded().presetID == .custom)
}

@Test func trimRejectsAnEndBeforeTheStart() {
    var options = WebPOptions.balanced
    options.trimStartSeconds = 4
    options.trimEndSeconds = 2
    #expect(throws: ConversionError.self) {
        try options.effectiveInterval(sourceDuration: 10)
    }
}

@Test func longClipIsCappedUntilAllowed() throws {
    var options = WebPOptions.balanced
    let capped = try options.effectiveInterval(sourceDuration: 45)
    #expect(capped.duration == 30)
    options.allowLongClip = true
    let full = try options.effectiveInterval(sourceDuration: 45)
    #expect(full.duration == 45)
}

@Test func frameRateDoesNotExceedTheSource() {
    let options = WebPOptions.balanced
    let resolved = options.resolvedFPS(sourceFPS: 8)
    #expect(resolved.fps == 8)
    #expect(resolved.clamped)
}

@Test func jobTransitionsFollowTheStateMachine() {
    #expect(JobTransition.allows(.probing, .ready))
    #expect(JobTransition.allows(.ready, .queued))
    #expect(JobTransition.allows(.queued, .running))
    #expect(JobTransition.allows(.running, .completed))
    #expect(JobTransition.allows(.running, .cancelled))
    #expect(JobTransition.allows(.completed, .ready))
    #expect(!JobTransition.allows(.completed, .running))
    #expect(!JobTransition.allows(.probing, .completed))
}

@Test func namesStayInsideTheDestinationFolder() {
    let source = URL(fileURLWithPath: "/tmp/clips/../secret/my file:name.mov")
    #expect(OutputPublisher.fileName(for: source) == "..-secret-my file-name.webp" || !OutputPublisher.fileName(for: source).contains("/"))
    #expect(!OutputPublisher.fileName(for: source).contains("/"))
    #expect(!OutputPublisher.fileName(for: source).contains(":"))
    #expect(OutputPublisher.sanitize("..") == "output")
    #expect(OutputPublisher.sanitize("") == "output")
}

@Test func collisionsNeverTargetTheSource() throws {
    let source = URL(fileURLWithPath: "/tmp/clip.mov")
    let proposed = URL(fileURLWithPath: "/tmp/out/clip.webp")
    let plan = try OutputPublisher.plan(proposed: proposed, source: source, policy: .keepBoth) { _ in false }
    #expect(plan == .write(proposed))

    let existing = try OutputPublisher.plan(proposed: proposed, source: source, policy: .ask) { $0 == proposed }
    #expect(existing == .ask(existing: proposed, proposed: proposed))

    let skipped = try OutputPublisher.plan(proposed: proposed, source: source, policy: .skip) { $0 == proposed }
    #expect(skipped == .skip)

    let kept = try OutputPublisher.plan(proposed: proposed, source: source, policy: .keepBoth) { $0 == proposed }
    if case .write(let url) = kept {
        #expect(url.lastPathComponent == "clip-2.webp")
    } else {
        Issue.record("Expected a new file name")
    }

    #expect(throws: ConversionError.samePathAsSource) {
        try OutputPublisher.assertDistinct(source: source, destination: source)
    }
}

@Test func probeReadsRotationAudioAndHDR() throws {
    let json = """
    {
      "streams": [
        {
          "codec_type": "video",
          "codec_name": "hevc",
          "width": 1920,
          "height": 1080,
          "avg_frame_rate": "30000/1001",
          "pix_fmt": "yuv420p10le",
          "color_transfer": "smpte2084",
          "tags": { "rotate": "90" }
        },
        { "codec_type": "audio", "codec_name": "aac" }
      ],
      "format": { "format_name": "mov,mp4,m4a", "duration": "12.5", "size": "1000" }
    }
    """.data(using: .utf8)!
    let source = try FFProbeParser.parse(json: json, fileURL: URL(fileURLWithPath: "/tmp/phone.mov"))
    #expect(source.hasVideo)
    #expect(source.hasAudio)
    #expect(source.isHDR)
    #expect(source.rotationDegrees == 90)
    #expect(source.displayWidth == 1080)
    #expect(source.displayHeight == 1920)
    #expect(source.durationSeconds == 12.5)
    #expect(source.detectedUTType == "com.apple.quicktime-movie")
}

@Test func commandKeepsTheFilenameAsOneArgument() throws {
    let input = URL(fileURLWithPath: "/tmp/my clips/quote's (1).mov")
    let temp = URL(fileURLWithPath: "/tmp/staging/job.partial.webp")
    var source = sampleSource(hasVideo: true, hasAudio: true, type: "com.apple.quicktime-movie")
    source.url = input
    source.durationSeconds = 8
    source.averageFrameRate = 30
    let request = ConversionRequest(
        id: UUID(),
        sourceURL: input,
        targetFormatID: "animated-webp",
        options: .balanced,
        destinationDirectory: URL(fileURLWithPath: "/tmp/out"),
        collisionPolicy: .ask
    )
    let plan = try FFmpegCommandBuilder.plan(
        request: request,
        source: source,
        temporaryOutput: temp,
        ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    )
    #expect(plan.arguments.contains(input.path))
    #expect(plan.arguments.contains(temp.path))
    #expect(plan.arguments.contains("libwebp_anim"))
    #expect(plan.arguments.contains("-f"))
    #expect(plan.arguments.contains("webp"))
    #expect(plan.arguments.contains("-an"))
    #expect(!plan.arguments.contains("/tmp/out/quote's (1).webp"))
    let filter = plan.arguments[plan.arguments.firstIndex(of: "-vf")! + 1]
    #expect(filter.contains("fps=12"))
    #expect(filter.contains("min(800,iw)"))
    #expect(!plan.arguments.joined(separator: " ").contains("&&"))
}

@Test func progressStaysMonotonicAndBelowFinished() {
    var parser = FFmpegProgressParser()
    let first = parser.consume(line: "out_time_us=1000000", expectedDuration: 4)
    let backwards = parser.consume(line: "out_time_us=500000", expectedDuration: 4)
    let later = parser.consume(line: "out_time=00:00:03.000000", expectedDuration: 4)
    let unknown = parser.consume(line: "frame=10", expectedDuration: 0)
    #expect(first == 0.25)
    #expect(backwards == 0.25)
    #expect(later == 0.75)
    #expect(unknown == nil)
}

@Test func cancelStopsARunningProcess() async throws {
    let status = FFmpegLocator.locate()
    let ffmpeg = try #require(status.ffmpegURL)
    let runner = ProcessRunner()
    let task = Task {
        try await runner.run(
            executable: ffmpeg,
            arguments: ["-hide_banner", "-nostdin", "-re", "-f", "lavfi", "-i", "anullsrc=duration=30", "-f", "null", "-"]
        ) { _ in }
    }
    try await Task.sleep(for: .milliseconds(400))
    runner.cancel()
    let output = try await task.value
    #expect(output.cancelled)
    #expect(output.exitCode != 0)
}

@Test func malformedFileDoesNotBecomeASource() throws {
    let status = FFmpegLocator.locate()
    try #require(status.ffprobeURL != nil)
    #expect(throws: ConversionError.self) {
        try FFProbeParser.inspect(url: Fixtures.url("malformed.mov"), ffprobe: status.ffprobeURL!)
    }
}

@Test func baselineConvertsToAnimatedWebPAndLeavesTheSourceAlone() async throws {
    let status = FFmpegLocator.locate()
    let binaries = try #require(status.binaries)
    let sourceURL = Fixtures.url("baseline.mov")
    let before = try Data(contentsOf: sourceURL)
    let digest = SHA256.hash(data: before)
    let source = try FFProbeParser.inspect(url: sourceURL, ffprobe: binaries.ffprobe)
    #expect(source.hasVideo)
    #expect(source.hasAudio)

    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("convertstation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: destination) }

    let runner = ProcessRunner()
    let outputURL = destination.appendingPathComponent("baseline.webp")
    let result = try await WebPConversion.convert(
        source: source,
        options: .balanced,
        destinationDirectory: destination,
        collisionPolicy: .ask,
        binaries: binaries,
        runner: runner,
        resolvedDestination: outputURL,
        replacing: false
    ) { _ in }

    let after = try Data(contentsOf: sourceURL)
    #expect(SHA256.hash(data: after) == digest)
    let info = try WebPHeaderParser.parse(file: result.outputURL)
    #expect(info.hasAnimation)
    #expect(info.loopCount == 0)
    #expect(info.frameCount > 1)
    #expect(info.canvasWidth == 640)
    #expect(info.canvasHeight == 360)
    #expect(result.bytes > 0)
    let probed = try FFProbeParser.inspect(url: result.outputURL, ffprobe: binaries.ffprobe)
    #expect(probed.hasAudio == false)
}

@Test func estimateMirrorsTheScaleFilter() {
    #expect(SizeEstimator.outputSize(width: 756, height: 426, maxPixelWidth: 1280) == (756, 426))
    #expect(SizeEstimator.outputSize(width: 1920, height: 1080, maxPixelWidth: 800) == (800, 450))
    #expect(SizeEstimator.outputSize(width: 641, height: 361, maxPixelWidth: nil) == (640, 360))
}

@Test func estimateGrowsWithQualityAndFrameRate() throws {
    let source = sampleSource(hasVideo: true, hasAudio: false, type: "com.apple.quicktime-movie")
    let small = try #require(SizeEstimator.estimate(options: .preset(.smallFile), source: source))
    let balanced = try #require(SizeEstimator.estimate(options: .preset(.balanced), source: source))
    let high = try #require(SizeEstimator.estimate(options: .preset(.highQuality), source: source))
    #expect(small.bytes < balanced.bytes)
    #expect(balanced.bytes < high.bytes)
    #expect(balanced.frames == 24)
    #expect(balanced.width == 640)
}

@Test func estimateFollowsTheTrim() throws {
    let source = sampleSource(hasVideo: true, hasAudio: false, type: "com.apple.quicktime-movie")
    var options = WebPOptions.balanced
    options.trimStartSeconds = 0.5
    options.trimEndSeconds = 1.5
    let estimate = try #require(SizeEstimator.estimate(options: options, source: source))
    #expect(estimate.frames == 12)
    #expect(abs(estimate.duration - 1) < 0.001)
    #expect(estimate.change(from: 0) == nil)
}

@Test func clockReadsAndWritesTrimTimes() {
    #expect(Clock.precise(5.45) == "0:05.45")
    #expect(Clock.precise(61.2) == "1:01.20")
    #expect(Clock.parse("5.45") == 5.45)
    #expect(Clock.parse("1:02") == 62)
    #expect(Clock.parse("abc") == nil)
}

@Test func applicationsPathDetectsTheInstalledCopy() {
    #expect(AppInstall.isApplicationsPath("/Applications/ConvertStation.app"))
    #expect(!AppInstall.isApplicationsPath("/tmp/ConvertStation.app"))
    #expect(!AppInstall.isRunningFromApplications)
}

@Test func sparkleFeedPointsAtGitHubAppcast() {
    let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    #expect(url == "https://github.com/JewhurstEngineering/convertstation/releases/latest/download/appcast.xml")
    #expect(Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String == "AppIcon")
    let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
    #expect(!(key ?? "").isEmpty)
}

@Test func silentVideoHidesAudioTargets() {
    let registry = profileRegistry()
    let silent = sampleSource(hasVideo: true, hasAudio: false, type: "com.apple.quicktime-movie", kind: .video)
    let ids = Set(registry.targets(for: silent).map(\.id))
    #expect(ids.contains(OutputID.animatedWebP))
    #expect(ids.contains(OutputID.mp4))
    #expect(ids.contains(OutputID.gifAnimated))
    #expect(ids.contains(OutputID.jpeg))
    #expect(!ids.contains(OutputID.wav))
    #expect(!ids.contains(OutputID.mp3))
    #expect(!ids.contains(OutputID.m4aAAC))
}

@Test func stillImageHidesAnimationAndAudio() {
    let registry = profileRegistry()
    let jpeg = sampleSource(hasVideo: false, hasAudio: false, type: UTType.jpeg.identifier, kind: .still)
    let ids = Set(registry.targets(for: jpeg).map(\.id))
    #expect(ids.contains(OutputID.jpeg))
    #expect(ids.contains(OutputID.png))
    #expect(!ids.contains(OutputID.animatedWebP))
    #expect(!ids.contains(OutputID.gifAnimated))
    #expect(!ids.contains(OutputID.mp4))
    #expect(registry.targets(for: jpeg).allSatisfy { $0.family == .image })
}

@Test func audioFileHidesGif() {
    let registry = profileRegistry()
    let audio = sampleSource(hasVideo: false, hasAudio: true, type: UTType.wav.identifier, kind: .audio)
    let ids = Set(registry.targets(for: audio).map(\.id))
    #expect(ids.contains(OutputID.wav))
    #expect(ids.contains(OutputID.flac))
    #expect(ids.contains(OutputID.mp3))
    #expect(!ids.contains(OutputID.gifAnimated))
    #expect(!ids.contains(OutputID.animatedWebP))
    #expect(!ids.contains(OutputID.jpeg))
}

@Test func missingEncoderHidesThatProfile() {
    let binaries = testBinaries()
    let registry = CapabilityRegistry(providers: [
        VideoProfileProvider(binaries: binaries, encoders: ["gif", "h264_videotoolbox"]),
        AudioProfileProvider(binaries: binaries, encoders: ["pcm_s16le"])
    ])
    let silent = sampleSource(hasVideo: true, hasAudio: false, type: "com.apple.quicktime-movie", kind: .video)
    let ids = Set(registry.targets(for: silent).map(\.id))
    #expect(ids == [OutputID.gifAnimated])
}

@Test func encoderListReadsFFmpegColumns() {
    let text = """
     Encoders:
     V..... libx264              H.264
     A....D aac                  AAC
    """
    let names = FFmpegLocator.parseEncoders(text)
    #expect(names.contains("libx264"))
    #expect(names.contains("aac"))
    #expect(!names.contains("Encoders:"))
}

@Test func probeTreatsASingleJPEGAsAStill() throws {
    let json = """
    {
      "streams": [
        { "codec_type": "video", "codec_name": "mjpeg", "width": 32, "height": 16, "nb_frames": "1", "pix_fmt": "yuvj420p" }
      ],
      "format": { "format_name": "image2", "duration": "0.04", "size": "400" }
    }
    """.data(using: .utf8)!
    let source = try FFProbeParser.parse(json: json, fileURL: URL(fileURLWithPath: "/tmp/photo.jpg"))
    #expect(source.kind == .still)
    #expect(!source.hasVideo)
    #expect(!profileRegistry().targets(for: source).contains { $0.id == OutputID.animatedWebP })
}

@Test func probeTreatsASilentClipAsVideo() throws {
    let json = """
    {
      "streams": [
        { "codec_type": "video", "codec_name": "h264", "width": 64, "height": 36, "nb_frames": "30", "avg_frame_rate": "30/1" }
      ],
      "format": { "format_name": "mov,mp4,m4a", "duration": "1.0", "size": "2000" }
    }
    """.data(using: .utf8)!
    let source = try FFProbeParser.parse(json: json, fileURL: URL(fileURLWithPath: "/tmp/silent.mov"))
    #expect(source.kind == .video)
    #expect(!source.hasAudio)
    let ids = Set(profileRegistry().targets(for: source).map(\.id))
    #expect(!ids.contains(OutputID.wav))
}

@Test func outputNameUsesTheProfileExtension() {
    let source = URL(fileURLWithPath: "/tmp/clips/phone.mov")
    #expect(OutputPublisher.fileName(for: source, extension: "mp4") == "phone.mp4")
    #expect(OutputPublisher.fileName(for: source, extension: ".WAV") == "phone.wav")
    #expect(!OutputPublisher.fileName(for: source, extension: "../png").contains("/"))
}

@Test func oldJobWithoutAProfileStillOpensAsWebP() throws {
    let job = ConversionJob.new(url: URL(fileURLWithPath: "/tmp/clip.mov"), duplicate: false)
    let data = try JSONEncoder().encode(job)
    var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    object.removeValue(forKey: "profileID")
    object.removeValue(forKey: "stillOptions")
    let legacy = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(ConversionJob.self, from: legacy)
    #expect(decoded.profileID == OutputID.animatedWebP)
    #expect(decoded.stillOptions == .standard)
}

@Test func jpegBecomesPNGAndLeavesTheSourceAlone() async throws {
    let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("convertstation-src-\(UUID().uuidString).jpg")
    let image = try makeJPEG(width: 16, height: 8)
    try image.write(to: sourceURL)
    defer { try? FileManager.default.removeItem(at: sourceURL) }
    let before = try Data(contentsOf: sourceURL)
    let descriptor = try #require(StillInspector.inspect(url: sourceURL))
    #expect(descriptor.kind == .still)
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("convertstation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: destination) }
    let output = destination.appendingPathComponent("photo.png")
    let request = ConversionRequest(
        id: UUID(),
        sourceURL: sourceURL,
        targetFormatID: OutputID.png,
        options: .balanced,
        destinationDirectory: destination,
        collisionPolicy: .ask
    )
    let result = try await StillImageConversion.convert(
        request: request,
        source: descriptor,
        resolvedDestination: output,
        replacing: false
    )
    #expect(result.width == 16)
    #expect(result.height == 8)
    #expect(try Data(contentsOf: sourceURL) == before)
    let reopened = CGImageSourceCreateWithURL(result.outputURL as CFURL, nil)
    #expect(CGImageSourceGetType(reopened!) as String? == UTType.png.identifier)
}

@Test func fixtureFilesOnlyOfferMatchingTargets() throws {
    let status = FFmpegLocator.locate()
    let binaries = try #require(status.binaries)
    let registry = AppModel.makeRegistry(from: status)

    let silent = try FFProbeParser.inspect(url: Fixtures.url("silent.mov"), ffprobe: binaries.ffprobe)
    let silentIDs = Set(registry.targets(for: silent).map(\.id))
    #expect(silent.kind == .video)
    #expect(!silent.hasAudio)
    #expect(!silentIDs.contains(OutputID.wav))
    #expect(!silentIDs.contains(OutputID.mp3))

    let tone = try FFProbeParser.inspect(url: Fixtures.url("tone.wav"), ffprobe: binaries.ffprobe)
    let toneIDs = Set(registry.targets(for: tone).map(\.id))
    #expect(tone.kind == .audio)
    #expect(!toneIDs.contains(OutputID.gifAnimated))
    #expect(!toneIDs.contains(OutputID.animatedWebP))
    #expect(toneIDs.contains(OutputID.wav))

    let jpeg = try FFProbeParser.inspect(url: Fixtures.url("sample.jpg"), ffprobe: binaries.ffprobe)
    let jpegIDs = Set(registry.targets(for: jpeg).map(\.id))
    #expect(jpeg.kind == .still)
    #expect(!jpegIDs.contains(OutputID.animatedWebP))
    #expect(!jpegIDs.contains(OutputID.gifAnimated))
    #expect(jpegIDs.contains(OutputID.png))
}

@Test func audioAndStillProfilesMatchTheirContainers() async throws {
    let status = FFmpegLocator.locate()
    let binaries = try #require(status.binaries)
    let registry = AppModel.makeRegistry(from: status)
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("convertstation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: destination) }
    let runner = ProcessRunner()

    let tone = try FFProbeParser.inspect(url: Fixtures.url("tone.wav"), ffprobe: binaries.ffprobe)
    for target in registry.targets(for: tone) where target.family == .audio {
        let output = try await convertProfile(target.id, source: tone, binaries: binaries, runner: runner, destination: destination)
        let facts = try OutputChecker.inspect(url: output, ffprobe: binaries.ffprobe)
        let expected = try #require(AudioProfileProvider.expect(for: target.id))
        #expect(facts.audioCodec == expected.codec)
        #expect(facts.formatName.contains(expected.format))
        #expect(facts.videoCodec == nil)
    }

    let jpeg = try FFProbeParser.inspect(url: Fixtures.url("sample.jpg"), ffprobe: binaries.ffprobe)
    for target in registry.targets(for: jpeg) where target.family == .image {
        let output = destination.appendingPathComponent("still-\(target.id.replacingOccurrences(of: ".", with: "-")).\(target.fileExtension)")
        let request = ConversionRequest(
            id: UUID(),
            sourceURL: jpeg.url,
            targetFormatID: target.id,
            options: .balanced,
            destinationDirectory: destination,
            collisionPolicy: .ask
        )
        let result = try await StillImageConversion.convert(
            request: request,
            source: jpeg,
            resolvedDestination: output,
            replacing: false
        )
        #expect(result.width == 16)
        #expect(result.height == 8)
        #expect(result.bytes > 0)
    }
}

@Test func baselineConvertsToTheNewProfiles() async throws {
    let status = FFmpegLocator.locate()
    let binaries = try #require(status.binaries)
    let sourceURL = Fixtures.url("baseline.mov")
    let before = try Data(contentsOf: sourceURL)
    let source = try FFProbeParser.inspect(url: sourceURL, ffprobe: binaries.ffprobe)
    let registry = AppModel.makeRegistry(from: status)
    let ids = Set(registry.targets(for: source).map(\.id))
    #expect(ids.contains(OutputID.mp4))
    #expect(ids.contains(OutputID.gifAnimated))
    #expect(ids.contains(OutputID.wav))
    #expect(!profileRegistry().targets(for: sampleSource(hasVideo: false, hasAudio: true, type: "public.audio", kind: .audio)).contains { $0.id == OutputID.gifAnimated })

    let destination = FileManager.default.temporaryDirectory.appendingPathComponent("convertstation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: destination) }
    let runner = ProcessRunner()

    let mp4 = try await convertProfile(OutputID.mp4, source: source, binaries: binaries, runner: runner, destination: destination)
    let mp4Facts = try OutputChecker.inspect(url: mp4, ffprobe: binaries.ffprobe)
    #expect(mp4Facts.videoCodec == "h264")
    #expect(mp4Facts.audioCodec == "aac")
    #expect(mp4Facts.majorBrand != "qt")

    let mov = try await convertProfile(OutputID.mov, source: source, binaries: binaries, runner: runner, destination: destination)
    let movFacts = try OutputChecker.inspect(url: mov, ffprobe: binaries.ffprobe)
    #expect(movFacts.videoCodec == "h264")
    #expect(movFacts.audioCodec == "aac")
    #expect(movFacts.majorBrand == "qt")

    let frame = destination.appendingPathComponent("frame.png")
    let frameRequest = ConversionRequest(
        id: UUID(),
        sourceURL: source.url,
        targetFormatID: OutputID.png,
        options: .balanced,
        destinationDirectory: destination,
        collisionPolicy: .ask
    )
    let frameResult = try await StillImageConversion.convert(
        request: frameRequest,
        source: source,
        resolvedDestination: frame,
        replacing: false
    )
    #expect(frameResult.width == 640)
    #expect(frameResult.height == 360)

    let gif = try await convertProfile(OutputID.gifAnimated, source: source, binaries: binaries, runner: runner, destination: destination)
    let gifFacts = try OutputChecker.inspect(url: gif, ffprobe: binaries.ffprobe)
    #expect(gifFacts.videoCodec == "gif")
    #expect(gifFacts.audioCodec == nil)

    let wav = try await convertProfile(OutputID.wav, source: source, binaries: binaries, runner: runner, destination: destination)
    let wavFacts = try OutputChecker.inspect(url: wav, ffprobe: binaries.ffprobe)
    #expect(wavFacts.audioCodec == "pcm_s16le")
    #expect(wavFacts.videoCodec == nil)
    #expect(try Data(contentsOf: sourceURL) == before)

    if status.encoders.contains("libvpx-vp9"), status.encoders.contains("libopus") {
        let webm = try await convertProfile(OutputID.webm, source: source, binaries: binaries, runner: runner, destination: destination)
        let facts = try OutputChecker.inspect(url: webm, ffprobe: binaries.ffprobe)
        #expect(facts.videoCodec == "vp9")
        #expect(facts.audioCodec == "opus")
    }
}

private func convertProfile(
    _ id: String,
    source: SourceDescriptor,
    binaries: EngineBinaries,
    runner: ProcessRunner,
    destination: URL
) async throws -> URL {
    let registry = AppModel.makeRegistry(from: FFmpegLocator.locate())
    let target = try #require(registry.targets(for: source).first { $0.id == id })
    let provider = try #require(registry.provider(for: target))
    let output = destination.appendingPathComponent("out-\(id.replacingOccurrences(of: ".", with: "-")).\(target.fileExtension)")
    let request = ConversionRequest(
        id: UUID(),
        sourceURL: source.url,
        targetFormatID: id,
        options: .preset(.smallFile),
        destinationDirectory: destination,
        collisionPolicy: .ask
    )
    _ = try await ProfileConversion.convert(
        provider: provider,
        request: request,
        source: source,
        binaries: binaries,
        runner: runner,
        resolvedDestination: output,
        replacing: false
    ) { _ in }
    return output
}

private func makeJPEG(width: Int, height: Int) throws -> Data {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ), let image = context.makeImage() else {
        throw ConversionError.unreadable("Could not draw a test image.")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        throw ConversionError.unreadable("Could not start a JPEG.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw ConversionError.unreadable("Could not finish a JPEG.")
    }
    return data as Data
}

@Test func lighterPresetStepsDown() {
    #expect(SizeText.lighterPreset(than: .custom) == .balanced)
    #expect(SizeText.lighterPreset(than: .balanced) == .smallFile)
    #expect(SizeText.lighterPreset(than: .smallFile) == nil)
    #expect(SizeText.change(0.34) == "+34%")
    #expect(SizeText.change(-0.55) == "\u{2212}55%")
}

private func sampleSource(hasVideo: Bool, hasAudio: Bool, type: String, kind: MediaKind? = nil) -> SourceDescriptor {
    let resolved: MediaKind = kind ?? (hasVideo ? .video : (hasAudio ? .audio : .still))
    return SourceDescriptor(
        url: URL(fileURLWithPath: "/tmp/sample.mov"),
        detectedUTType: type,
        durationSeconds: 2,
        width: 640,
        height: 360,
        rotationDegrees: 0,
        hasVideo: hasVideo,
        hasAudio: hasAudio,
        hasAlpha: false,
        isHDR: false,
        codecName: hasVideo ? "h264" : nil,
        averageFrameRate: 30,
        fileSizeBytes: 1000,
        formatName: "mov",
        warnings: [],
        kind: resolved,
        audioCodecName: hasAudio ? "aac" : nil
    )
}

private func testBinaries() -> EngineBinaries {
    EngineBinaries(
        ffmpeg: URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"),
        ffprobe: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"),
        versionSummary: "test"
    )
}

private func fullEncoders() -> Set<String> {
    ["libwebp_anim", "h264_videotoolbox", "aac", "libvpx-vp9", "libopus", "gif", "flac", "alac", "libmp3lame", "pcm_s16le", "pcm_s16be"]
}

private func profileRegistry(writable: Set<String> = [
    UTType.jpeg.identifier,
    UTType.png.identifier,
    UTType.webP.identifier,
    UTType.tiff.identifier,
    UTType.bmp.identifier,
    UTType.heic.identifier,
    UTType.gif.identifier
]) -> CapabilityRegistry {
    let binaries = testBinaries()
    let encoders = fullEncoders()
    return CapabilityRegistry(providers: [
        AnimatedWebPProvider(binaries: binaries),
        VideoProfileProvider(binaries: binaries, encoders: encoders),
        StillImageProvider(writable: writable),
        AudioProfileProvider(binaries: binaries, encoders: encoders)
    ])
}
