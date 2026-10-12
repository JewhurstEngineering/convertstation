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
        try AnimatedWebPProvider(binaries: binaries).validate(request, source: source)
        let staging = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destinationDirectory,
            create: true
        )
        let plans = try FFmpegCommandBuilder.chunkedPlans(
            request: request,
            source: source,
            directory: staging,
            ffmpeg: binaries.ffmpeg
        )
        let started = Date()
        do {
            for (index, plan) in plans.enumerated() {
                let output = try await runner.run(executable: plan.executableURL, arguments: plan.arguments) { _ in }
                if output.cancelled || Task.isCancelled {
                    try? fileManager.removeItem(at: staging)
                    throw ConversionError.cancelled
                }
                guard output.exitCode == 0 else {
                    try? fileManager.removeItem(at: staging)
                    throw ConversionError.processFailed(exitCode: output.exitCode, log: output.standardError)
                }
                onProgress(min(0.99, Double(index + 1) / Double(plans.count)))
            }
            let joined = staging.appendingPathComponent("\(request.id.uuidString).partial.webp")
            try WebPAnimationJoiner.join(plans.map(\.temporaryOutput), to: joined)
            let info = try WebPHeaderParser.parse(file: joined)
            let bytes = (try? fileManager.attributesOfItem(atPath: joined.path)[.size] as? Int64) ?? 0
            let interval = try options.effectiveInterval(sourceDuration: source.durationSeconds)
            try OutputValidator.validate(
                info: info,
                fileSize: bytes,
                options: options,
                source: source,
                interval: interval
            )
            try OutputPublisher.publish(temporary: joined, to: resolvedDestination, replacing: replacing)
            try? fileManager.removeItem(at: staging)
            let publishedSize = (try? fileManager.attributesOfItem(atPath: resolvedDestination.path)[.size] as? Int64) ?? 0
            return ConversionResult(
                outputURL: resolvedDestination,
                bytes: publishedSize,
                elapsedSeconds: Date().timeIntervalSince(started),
                width: info.canvasWidth,
                height: info.canvasHeight,
                frameCount: info.frameCount,
                loopForever: info.loopCount == 0,
                warnings: plans.first?.warnings ?? []
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}
