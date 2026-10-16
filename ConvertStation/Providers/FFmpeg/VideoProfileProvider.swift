import Foundation

struct VideoProfileProvider: ConversionProvider {
    var binaries: EngineBinaries
    var encoders: Set<String>

    var id: String { "ffmpeg-video" }

    func canRead(_ source: SourceDescriptor) -> Bool {
        source.kind == .video || source.kind == .animation
    }

    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor] {
        guard canRead(source) else { return [] }
        var targets: [TargetDescriptor] = []
        if encoders.contains("h264_videotoolbox"), encoders.contains("aac") {
            targets.append(container(
                OutputID.mp4,
                "MP4 (H.264 + AAC)",
                "mp4",
                source: source,
                notice: "Video is recompressed as H.264 with AAC. Transparency is flattened, and HDR is mapped to standard color."
            ))
            targets.append(container(
                OutputID.mov,
                "MOV (H.264 + AAC)",
                "mov",
                source: source,
                notice: "Video is recompressed as H.264 with AAC. Transparency is flattened, and HDR is mapped to standard color."
            ))
        }
        if encoders.contains("libvpx-vp9"), encoders.contains("libopus") {
            targets.append(container(
                OutputID.webm,
                "WebM (VP9 + Opus)",
                "webm",
                source: source,
                notice: source.hasAudio
                    ? "Video is recompressed as VP9 and audio as Opus. Transparency is flattened."
                    : "Video is recompressed as VP9. This file has no audio. Transparency is flattened."
            ))
        }
        if encoders.contains("gif") {
            var gif = TargetDescriptor(
                id: OutputID.gifAnimated,
                displayName: "Animated GIF (.gif)",
                fileExtension: "gif",
                supportsAnimation: true,
                supportsAlpha: false,
                supportsAudio: false,
                providerID: id,
                family: .animation,
                lossNotice: "Audio is dropped. GIF is limited to a color palette, so gradients can band."
            )
            if !source.hasAudio {
                gif.lossNotice = "GIF is limited to a color palette, so gradients can band."
            }
            targets.append(gif)
        }
        return targets
    }

    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws {
        guard canRead(source) else {
            throw ConversionError.invalidOptions("This file has no video to convert.")
        }
        guard availableTargets(for: source).contains(where: { $0.id == request.targetFormatID }) else {
            throw ConversionError.invalidOptions("That video format isn't available for this file.")
        }
        if request.targetFormatID == OutputID.gifAnimated {
            _ = try request.options.effectiveInterval(sourceDuration: source.durationSeconds)
        } else {
            _ = try request.options.effectiveInterval(sourceDuration: source.durationSeconds, cappingLongClips: false)
            guard (0...100).contains(request.videoOptions.quality) else {
                throw ConversionError.invalidOptions("Quality must be between 0 and 100.")
            }
        }
    }

    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        try validate(request, source: source)
        if request.targetFormatID == OutputID.gifAnimated {
            return try gifPlan(request: request, source: source, temporaryOutput: temporaryOutput)
        }
        return try videoPlan(request: request, source: source, temporaryOutput: temporaryOutput)
    }

    private func container(_ id: String, _ name: String, _ ext: String, source: SourceDescriptor, notice: String) -> TargetDescriptor {
        var text = notice
        if !source.hasAudio, id != OutputID.webm {
            text += " This file has no audio, so the output is silent."
        }
        return TargetDescriptor(
            id: id,
            displayName: name,
            fileExtension: ext,
            supportsAnimation: false,
            supportsAlpha: false,
            supportsAudio: source.hasAudio,
            providerID: "ffmpeg-video",
            family: .video,
            lossNotice: text
        )
    }

    private func videoPlan(request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        let interval = try request.options.effectiveInterval(sourceDuration: source.durationSeconds, cappingLongClips: false)
        let quality = min(100, max(1, request.videoOptions.quality))
        var warnings: [String] = []
        if source.hasAlpha {
            warnings.append("Transparency is flattened.")
        }
        if source.isHDR {
            warnings.append("HDR is mapped to standard color.")
        }
        if !source.hasAudio {
            warnings.append("This file has no audio, so the output is silent.")
        }

        var arguments = ["-hide_banner", "-nostdin", "-y"]
        if interval.start > 0.0005 {
            arguments.append(contentsOf: ["-ss", format(interval.start)])
        }
        arguments.append(contentsOf: ["-i", request.sourceURL.path, "-t", format(interval.duration)])
        arguments.append(contentsOf: ["-map", "0:v:0", "-sn", "-dn", "-map_metadata", "-1"])
        arguments.append(contentsOf: ["-vf", Self.scale(request.videoOptions.maxPixelWidth)])

        switch request.targetFormatID {
        case OutputID.webm:
            let crf = (100 - quality) * 63 / 100
            arguments.append(contentsOf: ["-c:v", "libvpx-vp9", "-crf", String(crf), "-b:v", "0", "-row-mt", "1", "-cpu-used", "4"])
            if source.hasAudio {
                arguments.append(contentsOf: ["-map", "0:a:0", "-c:a", "libopus", "-b:a", "128k"])
            } else {
                arguments.append("-an")
            }
            arguments.append(contentsOf: ["-f", "webm"])
        default:
            arguments.append(contentsOf: ["-c:v", "h264_videotoolbox", "-allow_sw", "1", "-q:v", String(quality), "-pix_fmt", "yuv420p"])
            if source.hasAudio {
                arguments.append(contentsOf: ["-map", "0:a:0", "-c:a", "aac", "-b:a", "160k"])
            } else {
                arguments.append("-an")
            }
            arguments.append(contentsOf: ["-movflags", "+faststart", "-f", request.targetFormatID == OutputID.mov ? "mov" : "mp4"])
        }
        arguments.append(contentsOf: ["-progress", "pipe:1", "-stats_period", "0.25", temporaryOutput.path])
        return ExecutionPlan(
            executableURL: binaries.ffmpeg,
            arguments: arguments,
            expectedDuration: interval.duration,
            temporaryOutput: temporaryOutput,
            warnings: warnings
        )
    }

    private func gifPlan(request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        let interval = try request.options.effectiveInterval(sourceDuration: source.durationSeconds)
        let resolved = request.options.resolvedFPS(sourceFPS: source.averageFrameRate)
        var warnings = ["Audio is dropped. GIF is limited to a color palette, so gradients can band."]
        if resolved.clamped, let fps = resolved.fps {
            warnings.append("Frame rate was lowered to \(fps) fps so it doesn't exceed the source.")
        }
        if !request.options.allowLongClip,
           let duration = source.durationSeconds,
           duration - request.options.trimStartSeconds > WebPLimits.longClipSeconds {
            warnings.append("Output is capped at 30 seconds. Turn on full length to keep more.")
        }
        let palette = FFmpegCommandBuilder.filter(fps: resolved.fps, maxPixelWidth: request.options.maxPixelWidth)
            + ",split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3"
        var arguments = ["-hide_banner", "-nostdin", "-y"]
        if interval.start > 0.0005 {
            arguments.append(contentsOf: ["-ss", format(interval.start)])
        }
        arguments.append(contentsOf: ["-i", request.sourceURL.path, "-t", format(interval.duration)])
        arguments.append(contentsOf: [
            "-map", "0:v:0", "-an", "-sn", "-dn", "-map_metadata", "-1",
            "-vf", palette,
            "-loop", request.options.loopForever ? "0" : "-1",
            "-f", "gif",
            "-progress", "pipe:1",
            "-stats_period", "0.25",
            temporaryOutput.path
        ])
        return ExecutionPlan(
            executableURL: binaries.ffmpeg,
            arguments: arguments,
            expectedDuration: interval.duration,
            temporaryOutput: temporaryOutput,
            warnings: warnings
        )
    }

    static func scale(_ maxPixelWidth: Int?) -> String {
        if let maxPixelWidth {
            return "scale='trunc(min(\(maxPixelWidth),iw)/2)*2':-2:flags=lanczos,format=yuv420p,setsar=1"
        }
        return "scale='trunc(iw/2)*2':-2:flags=lanczos,format=yuv420p,setsar=1"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

enum ProfileConversion {
    static func convert(
        provider: any ConversionProvider,
        request: ConversionRequest,
        source: SourceDescriptor,
        binaries: EngineBinaries,
        runner: ProcessRunner,
        resolvedDestination: URL,
        replacing: Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        let fileManager = FileManager.default
        let destinationDirectory = resolvedDestination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ConversionError.destinationNotWritable
        }
        guard fileManager.isWritableFile(atPath: destinationDirectory.path) else {
            throw ConversionError.destinationNotWritable
        }
        try OutputPublisher.assertDistinct(source: source.url, destination: resolvedDestination)
        let staging = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationDirectory,
            create: true
        )
        let temporary = staging.appendingPathComponent("\(request.id.uuidString).partial.\(resolvedDestination.pathExtension)")
        let plan = try provider.makePlan(request, source: source, temporaryOutput: temporary)
        return try await FFmpegSession.run(
            plan: plan,
            runner: runner,
            resolvedDestination: resolvedDestination,
            replacing: replacing,
            onProgress: onProgress
        ) { url in
            let facts = try OutputChecker.inspect(url: url, ffprobe: binaries.ffprobe)
            return try check(facts, request: request, source: source)
        }
    }

    private static func check(_ facts: OutputFacts, request: ConversionRequest, source: SourceDescriptor) throws -> CheckedMedia {
        switch request.targetFormatID {
        case OutputID.mp4:
            return try OutputChecker.require(
                facts,
                videoCodec: "h264",
                audioCodec: source.hasAudio ? "aac" : nil,
                requiresAudio: source.hasAudio,
                forbidsAudio: !source.hasAudio,
                rejectsBrand: "qt"
            )
        case OutputID.mov:
            return try OutputChecker.require(
                facts,
                videoCodec: "h264",
                audioCodec: source.hasAudio ? "aac" : nil,
                requiresAudio: source.hasAudio,
                forbidsAudio: !source.hasAudio,
                majorBrand: "qt"
            )
        case OutputID.webm:
            return try OutputChecker.require(
                facts,
                videoCodec: "vp9",
                audioCodec: source.hasAudio ? "opus" : nil,
                requiresAudio: source.hasAudio,
                forbidsAudio: !source.hasAudio,
                formatContains: "webm"
            )
        case OutputID.gifAnimated:
            let interval = try request.options.effectiveInterval(sourceDuration: source.durationSeconds)
            let fps = request.options.playbackFPS(sourceFPS: source.averageFrameRate)
            let minimum = interval.duration * fps >= 2 ? 2 : nil
            var media = try OutputChecker.require(
                facts,
                videoCodec: "gif",
                forbidsAudio: true,
                formatContains: "gif",
                minimumFrames: minimum
            )
            media.loopForever = request.options.loopForever
            return media
        default:
            break
        }
        if let expected = AudioProfileProvider.expect(for: request.targetFormatID) {
            return try OutputChecker.require(
                facts,
                audioCodec: expected.codec,
                requiresAudio: true,
                forbidsAudio: false,
                formatContains: expected.format
            )
        }
        throw ConversionError.validationFailed("This output has no checker.")
    }
}
