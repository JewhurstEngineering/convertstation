import Foundation

struct AudioProfileProvider: ConversionProvider {
    var binaries: EngineBinaries
    var encoders: Set<String>

    var id: String { "ffmpeg-audio" }

    func canRead(_ source: SourceDescriptor) -> Bool {
        source.hasAudio
    }

    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor] {
        guard canRead(source) else { return [] }
        return Self.catalog.compactMap { profile in
            guard encoders.contains(profile.encoder) else { return nil }
            var target = profile.target
            target.lossNotice = Self.notice(for: profile.target.id, source: source)
            return target
        }
    }

    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws {
        guard source.hasAudio else {
            throw ConversionError.invalidOptions("This file has no audio to extract.")
        }
        guard availableTargets(for: source).contains(where: { $0.id == request.targetFormatID }) else {
            throw ConversionError.invalidOptions("That audio format isn't available for this file.")
        }
        guard AudioOptions.sampleRateChoices.contains(request.audioOptions.sampleRate) else {
            throw ConversionError.invalidOptions("Choose a sample rate of 22050, 44100, or 48000.")
        }
        if AudioOptions.lossyProfiles.contains(request.targetFormatID),
           !AudioOptions.bitrateChoices.contains(request.audioOptions.bitrateKbps) {
            throw ConversionError.invalidOptions("Choose a bitrate from the list.")
        }
    }

    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        try validate(request, source: source)
        guard let profile = Self.catalog.first(where: { $0.target.id == request.targetFormatID }) else {
            throw ConversionError.invalidOptions("That audio format isn't available.")
        }
        var warnings: [String] = []
        if source.hasVideo {
            warnings.append("Only the audio is saved. The picture is left out.")
        }
        if Self.lossless.contains(request.targetFormatID), Self.sourceIsLossy(source) {
            warnings.append("This does not bring back quality that was already lost.")
        }
        var arguments = ["-hide_banner", "-nostdin", "-y", "-i", request.sourceURL.path]
        arguments.append(contentsOf: ["-vn", "-sn", "-dn", "-map", "0:a:0", "-map_metadata", "-1"])
        arguments.append(contentsOf: ["-c:a", profile.encoder, "-ar", String(request.audioOptions.sampleRate)])
        if AudioOptions.lossyProfiles.contains(request.targetFormatID) {
            arguments.append(contentsOf: ["-b:a", "\(request.audioOptions.bitrateKbps)k"])
        }
        arguments.append(contentsOf: ["-f", profile.muxer, "-progress", "pipe:1", "-stats_period", "0.25", temporaryOutput.path])
        return ExecutionPlan(
            executableURL: binaries.ffmpeg,
            arguments: arguments,
            expectedDuration: source.durationSeconds ?? 0,
            temporaryOutput: temporaryOutput,
            warnings: warnings
        )
    }

    private struct Profile {
        var target: TargetDescriptor
        var encoder: String
        var muxer: String
        var audioCodec: String
        var formatHint: String
    }

    private static let lossless: Set<String> = [OutputID.wav, OutputID.aiff, OutputID.flac, OutputID.m4aALAC]

    private static let catalog: [Profile] = [
        profile(OutputID.wav, "WAV (PCM)", "wav", encoder: "pcm_s16le", muxer: "wav", codec: "pcm_s16le", format: "wav"),
        profile(OutputID.aiff, "AIFF (PCM)", "aiff", encoder: "pcm_s16be", muxer: "aiff", codec: "pcm_s16be", format: "aiff"),
        profile(OutputID.flac, "FLAC", "flac", encoder: "flac", muxer: "flac", codec: "flac", format: "flac"),
        profile(OutputID.m4aAAC, "M4A (AAC)", "m4a", encoder: "aac", muxer: "ipod", codec: "aac", format: "mp4"),
        profile(OutputID.m4aALAC, "M4A (ALAC)", "m4a", encoder: "alac", muxer: "ipod", codec: "alac", format: "mp4"),
        profile(OutputID.opus, "Opus", "opus", encoder: "libopus", muxer: "ogg", codec: "opus", format: "ogg"),
        profile(OutputID.mp3, "MP3", "mp3", encoder: "libmp3lame", muxer: "mp3", codec: "mp3", format: "mp3")
    ]

    private static func profile(
        _ id: String,
        _ name: String,
        _ ext: String,
        encoder: String,
        muxer: String,
        codec: String,
        format: String
    ) -> Profile {
        Profile(
            target: TargetDescriptor(
                id: id,
                displayName: name,
                fileExtension: ext,
                supportsAnimation: false,
                supportsAlpha: false,
                supportsAudio: true,
                providerID: "ffmpeg-audio",
                family: .audio,
                lossNotice: ""
            ),
            encoder: encoder,
            muxer: muxer,
            audioCodec: codec,
            formatHint: format
        )
    }

    static func expect(for profileID: String) -> (codec: String, format: String)? {
        guard let profile = catalog.first(where: { $0.target.id == profileID }) else { return nil }
        return (profile.audioCodec, profile.formatHint)
    }

    private static func sourceIsLossy(_ source: SourceDescriptor) -> Bool {
        let lossy: Set<String> = ["mp3", "aac", "opus", "vorbis", "wma", "ac3", "eac3"]
        return lossy.contains(source.audioCodecName?.lowercased() ?? "")
    }

    private static func notice(for id: String, source: SourceDescriptor) -> String {
        var parts: [String] = []
        if source.hasVideo {
            parts.append("Only the audio is saved. The picture is left out.")
        }
        if lossless.contains(id), sourceIsLossy(source) {
            parts.append("This does not bring back quality that was already lost.")
        } else if AudioOptions.lossyProfiles.contains(id) {
            parts.append("This encode is lossy.")
        }
        if parts.isEmpty {
            parts.append("Audio is re-encoded. The original file is left alone.")
        }
        return parts.joined(separator: " ")
    }
}
