import Foundation

struct WebPAnimationInfo: Equatable, Sendable {
    var canvasWidth: Int
    var canvasHeight: Int
    var hasAnimation: Bool
    var loopCount: Int?
    var frameCount: Int
}

enum WebPHeaderParser {
    static func parse(file url: URL) throws -> WebPAnimationInfo {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try read(handle, count: 12)
        guard header.prefix(4) == Data("RIFF".utf8), header.dropFirst(8).prefix(4) == Data("WEBP".utf8) else {
            throw ConversionError.validationFailed("Output is not a WebP file.")
        }

        var canvasWidth = 0
        var canvasHeight = 0
        var hasAnimation = false
        var loopCount: Int?
        var frameCount = 0

        while let chunk = try? read(handle, count: 8) {
            let tag = String(data: chunk.prefix(4), encoding: .ascii) ?? ""
            let sizeBytes = [UInt8](chunk.dropFirst(4).prefix(4))
            let size = Int(UInt32(sizeBytes[0])
                | (UInt32(sizeBytes[1]) << 8)
                | (UInt32(sizeBytes[2]) << 16)
                | (UInt32(sizeBytes[3]) << 24))
            if tag == "VP8X" || tag == "ANIM" {
                let payload = try read(handle, count: size)
                if tag == "VP8X", payload.count >= 10 {
                    let flags = payload[payload.startIndex]
                    hasAnimation = flags & 0x10 != 0
                    canvasWidth = little24(payload, offset: 4) + 1
                    canvasHeight = little24(payload, offset: 7) + 1
                } else if tag == "ANIM", payload.count >= 6 {
                    loopCount = Int(payload[payload.startIndex + 4]) | (Int(payload[payload.startIndex + 5]) << 8)
                }
            } else {
                if tag == "ANMF" {
                    frameCount += 1
                }
                let skip = UInt64(size)
                let current = try handle.offset()
                try handle.seek(toOffset: current + skip)
            }
            if size % 2 == 1 {
                _ = try? read(handle, count: 1)
            }
        }

        guard canvasWidth > 0, canvasHeight > 0 else {
            throw ConversionError.validationFailed("Output WebP has no canvas size.")
        }
        return WebPAnimationInfo(
            canvasWidth: canvasWidth,
            canvasHeight: canvasHeight,
            hasAnimation: hasAnimation,
            loopCount: loopCount,
            frameCount: frameCount
        )
    }

    private static func read(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let remaining = count - data.count
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                throw ConversionError.validationFailed("Output WebP ended early.")
            }
            data.append(chunk)
        }
        return data
    }

    private static func little24(_ data: Data, offset: Int) -> Int {
        let start = data.startIndex + offset
        return Int(data[start]) | (Int(data[start + 1]) << 8) | (Int(data[start + 2]) << 16)
    }
}

enum WebPAnimationJoiner {
    /// Each piece is a whole animated WebP. The result keeps the first file's
    /// canvas and loop, and plays every frame in order.
    static func join(_ parts: [URL], to destination: URL) throws {
        guard let first = parts.first else {
            throw ConversionError.validationFailed("Animated WebP produced no frames.")
        }
        if parts.count == 1 {
            if first.standardizedFileURL != destination.standardizedFileURL {
                try FileManager.default.copyItem(at: first, to: destination)
            }
            return
        }
        let firstInfo = try WebPHeaderParser.parse(file: first)
        let firstData = try Data(contentsOf: first)
        var payload = try preamble(firstData)
        for part in parts {
            let info = try WebPHeaderParser.parse(file: part)
            guard info.canvasWidth == firstInfo.canvasWidth, info.canvasHeight == firstInfo.canvasHeight else {
                throw ConversionError.validationFailed("Animated WebP pieces did not match in size.")
            }
            guard info.frameCount > 0 else {
                throw ConversionError.validationFailed("Animated WebP produced no frames.")
            }
            let data = part == first ? firstData : try Data(contentsOf: part)
            payload.append(try frameChunks(data))
        }
        var file = Data()
        file.append(contentsOf: Array("RIFF".utf8))
        file.append(little32(UInt32(payload.count + 4)))
        file.append(contentsOf: Array("WEBP".utf8))
        file.append(payload)
        try file.write(to: destination, options: .atomic)
    }

    private static func preamble(_ data: Data) throws -> Data {
        let end = try firstFrameOffset(data)
        return data.subdata(in: 12..<end)
    }

    private static func frameChunks(_ data: Data) throws -> Data {
        let start = try firstFrameOffset(data)
        return data.subdata(in: start..<data.count)
    }

    private static func firstFrameOffset(_ data: Data) throws -> Int {
        guard data.count >= 12,
              data.prefix(4) == Data("RIFF".utf8),
              data.subdata(in: 8..<12) == Data("WEBP".utf8) else {
            throw ConversionError.validationFailed("Output is not a WebP file.")
        }
        var index = 12
        while index + 8 <= data.count {
            let tag = data.subdata(in: index..<index + 4)
            let size = Int(read32(data, at: index + 4))
            if tag == Data("ANMF".utf8) {
                return index
            }
            index += 8 + size + (size & 1)
        }
        throw ConversionError.validationFailed("Animated WebP produced no frames.")
    }

    private static func read32(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }

    private static func little32(_ value: UInt32) -> Data {
        Data([
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff)
        ])
    }
}

enum OutputValidator {
    static func validate(
        info: WebPAnimationInfo,
        fileSize: Int64,
        options: WebPOptions,
        source: SourceDescriptor,
        interval: TrimInterval
    ) throws {
        guard fileSize > 0 else {
            throw ConversionError.validationFailed("Output file is empty.")
        }
        guard info.hasAnimation else {
            throw ConversionError.validationFailed("Output is not an animated WebP.")
        }
        if let maxWidth = options.maxPixelWidth, info.canvasWidth > maxWidth {
            throw ConversionError.validationFailed("Output is wider than the \(maxWidth)px limit.")
        }
        if let sourceWidth = source.displayWidth, info.canvasWidth > sourceWidth {
            throw ConversionError.validationFailed("Output was upscaled, which this preset does not do.")
        }
        let fps = options.playbackFPS(sourceFPS: source.averageFrameRate)
        if interval.duration * fps >= 2, info.frameCount < 2 {
            throw ConversionError.validationFailed("Output did not contain an animation.")
        }
        if options.loopForever, info.loopCount != 0 {
            throw ConversionError.validationFailed("Output is not set to loop forever.")
        }
        if !options.loopForever, info.loopCount != 1 {
            throw ConversionError.validationFailed("Output loop count was \(info.loopCount.map(String.init) ?? "missing").")
        }
    }
}
