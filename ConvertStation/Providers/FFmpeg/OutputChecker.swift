import Foundation

struct OutputFacts: Equatable, Sendable {
    var formatName: String
    var majorBrand: String?
    var videoCodec: String?
    var audioCodec: String?
    var width: Int
    var height: Int
    var frameCount: Int
}

enum OutputChecker {
    static func inspect(url: URL, ffprobe: URL) throws -> OutputFacts {
        let result = try SynchronousProcess.run(
            ffprobe,
            ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path]
        )
        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.validationFailed(detail.isEmpty ? "ffprobe could not read the output." : detail)
        }
        return try parse(json: Data(result.stdout.utf8))
    }

    static func parse(json: Data) throws -> OutputFacts {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ConversionError.validationFailed("ffprobe did not return JSON for the output.")
        }
        let streams = root["streams"] as? [[String: Any]] ?? []
        let format = root["format"] as? [String: Any] ?? [:]
        let video = streams.first { ($0["codec_type"] as? String) == "video" }
        let audio = streams.first { ($0["codec_type"] as? String) == "audio" }
        let tags = format["tags"] as? [String: Any]
        let brand = (tags?["major_brand"] as? String)?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return OutputFacts(
            formatName: (format["format_name"] as? String)?.lowercased() ?? "",
            majorBrand: brand,
            videoCodec: (video?["codec_name"] as? String)?.lowercased(),
            audioCodec: (audio?["codec_name"] as? String)?.lowercased(),
            width: video?["width"] as? Int ?? 0,
            height: video?["height"] as? Int ?? 0,
            frameCount: intValue(video?["nb_frames"]) ?? 0
        )
    }

    static func require(
        _ facts: OutputFacts,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        requiresAudio: Bool = false,
        forbidsAudio: Bool = false,
        formatContains: String? = nil,
        majorBrand: String? = nil,
        rejectsBrand: String? = nil,
        minimumFrames: Int? = nil
    ) throws -> CheckedMedia {
        if let formatContains, !facts.formatName.contains(formatContains) {
            throw ConversionError.validationFailed("Output format was \(facts.formatName), not \(formatContains).")
        }
        if let majorBrand, facts.majorBrand != majorBrand {
            throw ConversionError.validationFailed("Output brand was \(facts.majorBrand ?? "missing"), not \(majorBrand).")
        }
        if let rejectsBrand, facts.majorBrand == rejectsBrand {
            throw ConversionError.validationFailed("Output brand was \(rejectsBrand).")
        }
        if let videoCodec {
            guard facts.videoCodec == videoCodec else {
                throw ConversionError.validationFailed("Output video codec was \(facts.videoCodec ?? "missing"), not \(videoCodec).")
            }
        }
        if requiresAudio {
            guard facts.audioCodec != nil else {
                throw ConversionError.validationFailed("Output is missing its audio.")
            }
        }
        if forbidsAudio, facts.audioCodec != nil {
            throw ConversionError.validationFailed("Output still has an audio stream.")
        }
        if let audioCodec {
            guard facts.audioCodec == audioCodec else {
                throw ConversionError.validationFailed("Output audio codec was \(facts.audioCodec ?? "missing"), not \(audioCodec).")
            }
        }
        if let minimumFrames, facts.frameCount > 0, facts.frameCount < minimumFrames {
            throw ConversionError.validationFailed("Output did not contain enough frames.")
        }
        return CheckedMedia(
            width: facts.width,
            height: facts.height,
            frameCount: facts.frameCount,
            loopForever: false
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let string = value as? String { return Int(string) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
