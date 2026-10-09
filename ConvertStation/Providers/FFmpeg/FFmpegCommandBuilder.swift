import Foundation

enum FFmpegCommandBuilder {
    static func plan(
        request: ConversionRequest,
        source: SourceDescriptor,
        temporaryOutput: URL,
        ffmpeg: URL
    ) throws -> ExecutionPlan {
        let interval = try request.options.effectiveInterval(sourceDuration: source.durationSeconds)
        let resolved = request.options.resolvedFPS(sourceFPS: source.averageFrameRate)
        var warnings: [String] = []
        if resolved.clamped {
            warnings.append("Frame rate was lowered to \(resolved.fps) fps so it doesn't exceed the source.")
        }
        if source.hasAudio {
            warnings.append("Audio will be dropped. Animated WebP has no audio.")
        }
        if !request.options.allowLongClip,
           let duration = source.durationSeconds,
           duration - request.options.trimStartSeconds > WebPLimits.longClipSeconds,
           request.options.trimEndSeconds == nil || (request.options.trimEndSeconds ?? 0) - request.options.trimStartSeconds > WebPLimits.longClipSeconds {
            warnings.append("Output is capped at 30 seconds. Turn on full length to keep more.")
        }

        var arguments = ["-hide_banner", "-nostdin", "-y"]
        if interval.start > 0.0005 {
            arguments.append(contentsOf: ["-ss", format(interval.start)])
        }
        arguments.append(contentsOf: ["-i", request.sourceURL.path])
        arguments.append(contentsOf: ["-t", format(interval.duration)])
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
            expectedDuration: interval.duration,
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
        if let value = value(after: "out_time_us=", in: trimmed) {
            microseconds = value
        } else if let clock = valueString(after: "out_time=", in: trimmed) {
            microseconds = Self.clockMicroseconds(clock)
        } else {
            return lastFraction
        }
        guard let microseconds else { return lastFraction }
        let fraction = min(0.99, max(0, (microseconds / 1_000_000) / expectedDuration))
        lastFraction = max(lastFraction, fraction)
        return lastFraction
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
