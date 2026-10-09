import Foundation
import UniformTypeIdentifiers

enum FFProbeParser {
    static func parse(json: Data, fileURL: URL) throws -> SourceDescriptor {
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String: Any] else {
            throw ConversionError.unreadable("ffprobe did not return JSON.")
        }
        let streams = root["streams"] as? [[String: Any]] ?? []
        let format = root["format"] as? [String: Any] ?? [:]
        let videos = streams.filter { ($0["codec_type"] as? String) == "video" }
        let audios = streams.filter { ($0["codec_type"] as? String) == "audio" }
        let video = videos.first

        let rotation = video.flatMap(rotationDegrees) ?? 0
        let width = video?["width"] as? Int
        let height = video?["height"] as? Int
        let pixFmt = (video?["pix_fmt"] as? String) ?? ""
        let transfer = (video?["color_transfer"] as? String)?.lowercased() ?? ""
        let primaries = (video?["color_primaries"] as? String)?.lowercased() ?? ""
        let codec = video?["codec_name"] as? String
        let fps = (video?["avg_frame_rate"] as? String).flatMap(parseFrameRate)
        let duration = doubleValue(format["duration"]) ?? video.flatMap { doubleValue($0["duration"]) }
        let size = (format["size"] as? String).flatMap(Int64.init)
            ?? (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64)
        let formatName = format["format_name"] as? String

        var warnings: [String] = []
        let alpha = hasAlpha(pixFmt)
        let hdr = transfer == "smpte2084" || transfer == "arib-std-b67" || primaries == "bt2020"
        let frameCount = video.flatMap { intValue($0["nb_frames"]) }
        let audioCodec = audios.first?["codec_name"] as? String
        let kind = mediaKind(
            codec: codec,
            formatName: formatName,
            frameCount: frameCount,
            hasVideoStream: video != nil,
            hasAudioStream: !audios.isEmpty
        )
        let playsAsVideo = kind == .video || kind == .animation

        if alpha {
            warnings.append("This file has transparency.")
        }
        if hdr {
            warnings.append("This file is HDR. It will be mapped to standard color, so it may look different.")
        }
        if videos.count > 1 {
            warnings.append("Only the first video stream is converted.")
        }

        return SourceDescriptor(
            url: fileURL,
            detectedUTType: typeIdentifier(formatName: formatName, fileURL: fileURL, hasVideo: playsAsVideo),
            durationSeconds: duration,
            width: width,
            height: height,
            rotationDegrees: rotation,
            hasVideo: playsAsVideo,
            hasAudio: !audios.isEmpty && kind != .still,
            hasAlpha: alpha,
            isHDR: hdr,
            codecName: codec,
            averageFrameRate: fps,
            fileSizeBytes: size,
            formatName: formatName,
            warnings: warnings,
            kind: kind,
            audioCodecName: audioCodec
        )
    }

    static func mediaKind(
        codec: String?,
        formatName: String?,
        frameCount: Int?,
        hasVideoStream: Bool,
        hasAudioStream: Bool
    ) -> MediaKind {
        let format = formatName?.lowercased() ?? ""
        if format.contains("heif") || format.contains("heic") {
            return .still
        }
        guard hasVideoStream else {
            return hasAudioStream ? .audio : .still
        }
        let name = codec?.lowercased() ?? ""
        let frames = frameCount ?? 1
        if name == "gif" || format.contains("gif") {
            return frames > 1 ? .animation : .still
        }
        if name == "webp" || format.contains("webp") {
            return frames > 1 ? .animation : .still
        }
        if name == "apng" {
            return frames > 1 ? .animation : .still
        }
        let stillCodecs: Set<String> = ["png", "mjpeg", "bmp", "tiff", "ppm", "pcx"]
        if stillCodecs.contains(name), frames <= 1 {
            return .still
        }
        if format.contains("image2"), frames <= 1 {
            return .still
        }
        return .video
    }

    static func inspect(url: URL, ffprobe: URL) throws -> SourceDescriptor {
        let result = try SynchronousProcess.run(
            ffprobe,
            ["-v", "error", "-print_format", "json", "-show_format", "-show_streams", url.path]
        )
        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.unreadable(detail.isEmpty ? "ffprobe exited \(result.exitCode)." : detail)
        }
        return try parse(json: Data(result.stdout.utf8), fileURL: url)
    }

    private static func typeIdentifier(formatName: String?, fileURL: URL, hasVideo: Bool) -> String {
        let format = formatName?.lowercased() ?? ""
        if format.contains("webp") { return UTType.webP.identifier }
        if let type = UTType(filenameExtension: fileURL.pathExtension),
           type.conforms(to: .movie) || type.conforms(to: .video) || type.conforms(to: .audiovisualContent) {
            return type.identifier
        }
        if format.contains("webm") { return UTType("org.webmproject.webm")?.identifier ?? UTType.movie.identifier }
        if hasVideo { return UTType.movie.identifier }
        if let type = UTType(filenameExtension: fileURL.pathExtension) {
            return type.identifier
        }
        return UTType.data.identifier
    }

    private static func hasAlpha(_ pixFmt: String) -> Bool {
        let value = pixFmt.lowercased()
        if value.isEmpty { return false }
        return value.contains("yuva")
            || value.contains("rgba")
            || value.contains("argb")
            || value.contains("bgra")
            || value.contains("abgr")
            || value.contains("gbra")
    }

    private static func rotationDegrees(_ stream: [String: Any]) -> Int {
        if let tags = stream["tags"] as? [String: Any], let rotate = tags["rotate"] as? String, let value = Int(rotate) {
            return value
        }
        if let sideData = stream["side_data_list"] as? [[String: Any]] {
            for entry in sideData {
                if let rotation = entry["rotation"] as? Double {
                    return Int(rotation.rounded())
                }
                if let rotation = entry["rotation"] as? Int {
                    return rotation
                }
            }
        }
        return 0
    }

    private static func parseFrameRate(_ value: String) -> Double? {
        let parts = value.split(separator: "/")
        guard parts.count == 2, let numerator = Double(parts[0]), let denominator = Double(parts[1]), denominator != 0 else {
            return nil
        }
        let rate = numerator / denominator
        return rate > 0 ? rate : nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let string = value as? String { return Int(string) }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? Double { return number }
        if let string = value as? String { return Double(string) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}
