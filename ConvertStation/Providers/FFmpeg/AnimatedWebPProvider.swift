import Foundation

struct AnimatedWebPProvider: ConversionProvider {
    var binaries: EngineBinaries

    var id: String { "ffmpeg-webp" }

    func canRead(_ source: SourceDescriptor) -> Bool {
        source.hasVideo && (source.kind == .video || source.kind == .animation)
    }

    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor] {
        guard canRead(source) else { return [] }
        var target = TargetDescriptor.animatedWebP
        if !source.hasAudio {
            target.lossNotice = "Animated WebP has no sound."
        }
        return [target]
    }

    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws {
        guard request.targetFormatID == TargetDescriptor.animatedWebP.id else {
            throw ConversionError.invalidOptions("Animated WebP is the only output in this version.")
        }
        guard source.hasVideo else {
            throw ConversionError.invalidOptions(
                source.hasAudio
                    ? "This file has audio but no video. Animated WebP needs a video track."
                    : "No readable video stream was found."
            )
        }
        _ = try request.options.effectiveInterval(sourceDuration: source.durationSeconds)
    }

    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        try validate(request, source: source)
        return try FFmpegCommandBuilder.plan(
            request: request,
            source: source,
            temporaryOutput: temporaryOutput,
            ffmpeg: binaries.ffmpeg
        )
    }
}

enum WebPConversion {
    static func convert(
        source: SourceDescriptor,
        options: WebPOptions,
        destinationDirectory: URL,
        collisionPolicy: CollisionPolicy,
        binaries: EngineBinaries,
        runner: ProcessRunner,
        resolvedDestination: URL,
        replacing: Bool,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> ConversionResult {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destinationDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ConversionError.destinationNotWritable
        }
        guard fileManager.isWritableFile(atPath: destinationDirectory.path) else {
            throw ConversionError.destinationNotWritable
        }
        try OutputPublisher.assertDistinct(source: source.url, destination: resolvedDestination)

        let request = ConversionRequest(
            id: UUID(),
            sourceURL: source.url,
            targetFormatID: TargetDescriptor.animatedWebP.id,
            options: options,
            destinationDirectory: destinationDirectory,
            collisionPolicy: collisionPolicy
        )
        let provider = AnimatedWebPProvider(binaries: binaries)
        let staging = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationDirectory,
            create: true
        )
        let temporary = staging.appendingPathComponent("\(request.id.uuidString).partial.webp")
        let plan = try provider.makePlan(request, source: source, temporaryOutput: temporary)
        return try await FFmpegSession.run(
            plan: plan,
            runner: runner,
            resolvedDestination: resolvedDestination,
            replacing: replacing,
            onProgress: onProgress
        ) { url in
            let info = try WebPHeaderParser.parse(file: url)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
            let interval = try options.effectiveInterval(sourceDuration: source.durationSeconds)
            try OutputValidator.validate(
                info: info,
                fileSize: bytes,
                options: options,
                source: source,
                interval: interval
            )
            return CheckedMedia(
                width: info.canvasWidth,
                height: info.canvasHeight,
                frameCount: info.frameCount,
                loopForever: info.loopCount == 0
            )
        }
    }
}
