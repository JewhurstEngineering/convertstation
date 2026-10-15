import Foundation

enum FFmpegCommandBuilder {
    static func plan(
        request: ConversionRequest,
        source: SourceDescriptor,
        temporaryOutput: URL,
        ffmpeg: URL
    ) throws -> ExecutionPlan {
        let interval = try request.options.effectiveInterval(sourceDuration: source.durationSeconds)
        return try makePlan(
            request: request,
            source: source,
            temporaryOutput: temporaryOutput,
            ffmpeg: ffmpeg,
            fastSeek: interval.start,
            accurateSeek: 0,
            duration: interval.duration,
            includeWarnings: true
        )
    }

    private static func makePlan(
        request: ConversionRequest,
        source: SourceDescriptor,
        temporaryOutput: URL,
        ffmpeg: URL,
        fastSeek: Double,
        accurateSeek: Double,
        duration: Double,
        includeWarnings: Bool
    ) throws -> ExecutionPlan {
        let resolved = request.options.resolvedFPS(sourceFPS: source.averageFrameRate)
        var warnings: [String] = []
        if includeWarnings {
            if resolved.clamped {
                warnings.append("Frame rate was lowered to \(resolved.fps) fps so it doesn't exceed the source.")
            }
            if source.hasAudio {
                warnings.append("Audio will be dropped. Animated WebP has no audio.")
            }
            if !request.options.allowLongClip,
               let sourceDuration = source.durationSeconds,
               sourceDuration - request.options.trimStartSeconds > WebPLimits.longClipSeconds,
               request.options.trimEndSeconds == nil || (request.options.trimEndSeconds ?? 0) - request.options.trimStartSeconds > WebPLimits.longClipSeconds {
                warnings.append("Output is capped at 30 seconds. Turn on full length to keep more.")
            }
        }

        var arguments = ["-hide_banner", "-nostdin", "-y"]
        if fastSeek > 0.0005 {
            arguments.append(contentsOf: ["-ss", format(fastSeek)])
        }
        arguments.append(contentsOf: ["-i", request.sourceURL.path])
        if accurateSeek > 0.0005 {
            arguments.append(contentsOf: ["-ss", format(accurateSeek)])
        }
        arguments.append(contentsOf: ["-t", format(duration)])
        arguments.append(contentsOf: [
            "-map", "0:v:0",
            "-an", "-sn", "-dn",
            "-map_metadata", "-1",
            "-vf", filter(fps: resolved.fps, maxPixelWidth: request.options.maxPixelWidth),
            "-c:v", "libwebp_anim",
            "-lossless", "0",
            "-quality", String(request.options.quality),
            "-compression_level", String(request.options.compressionLevel),
            "-loop", request.options.loopForever ? "0" : "1",
            "-f", "webp",
            "-progress", "pipe:1",
            "-stats_period", "0.25",
            temporaryOutput.path
        ])

        return ExecutionPlan(
            executableURL: ffmpeg,
            arguments: arguments,
            expectedDuration: duration,
            temporaryOutput: temporaryOutput,
            warnings: warnings
        )
    }

    static func filter(fps: Int, maxPixelWidth: Int?) -> String {
        let scale: String
        if let maxPixelWidth {
            scale = "scale='trunc(min(\(maxPixelWidth),iw)/2)*2':-2:flags=lanczos"
        } else {
            scale = "scale='trunc(iw/2)*2':-2:flags=lanczos"
        }
        return "fps=\(fps),\(scale),setsar=1"
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

struct FFmpegProgressParser {
    private var lastFraction: Double = 0

    mutating func consume(line: String, expectedDuration: Double) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expectedDuration > 0 else { return nil }
        let microseconds: Double?
        if trimmed.hasPrefix("out_time_us=") {
            microseconds = value(after: "out_time_us=", in: trimmed)
        } else if trimmed.hasPrefix("out_time=") {
            microseconds = valueString(after: "out_time=", in: trimmed).flatMap(Self.clockMicroseconds)
        } else if let seconds = Self.labeledTime("pts_time:", in: trimmed) {
            let fraction = min(0.99, max(0, seconds / expectedDuration))
            lastFraction = max(lastFraction, fraction)
            return lastFraction
        } else {
            return nil
        }
        // libwebp_anim reports out_time_us=N/A until the whole animation is done.
        // Frame timestamps from showinfo move while that encode is still running.
        guard let microseconds else { return nil }
        let fraction = min(0.99, max(0, (microseconds / 1_000_000) / expectedDuration))
        lastFraction = max(lastFraction, fraction)
        return lastFraction
    }

    /// `pts_time:1.25` inside an ffmpeg showinfo line.
    private static func labeledTime(_ key: String, in line: String) -> Double? {
        guard let range = line.range(of: key) else { return nil }
        let token = line[range.upperBound...].prefix { $0.isNumber || $0 == "." || $0 == "-" }
        guard !token.isEmpty else { return nil }
        return Double(token)
    }

    private func value(after key: String, in line: String) -> Double? {
        guard line.hasPrefix(key) else { return nil }
        return Double(line.dropFirst(key.count))
    }

    private func valueString(after key: String, in line: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        return String(line.dropFirst(key.count))
    }

    private static func clockMicroseconds(_ clock: String) -> Double? {
        let parts = clock.split(separator: ":")
        guard parts.count == 3, let hours = Double(parts[0]), let minutes = Double(parts[1]), let seconds = Double(parts[2]) else {
            return nil
        }
        return ((hours * 3600) + (minutes * 60) + seconds) * 1_000_000
    }
}
