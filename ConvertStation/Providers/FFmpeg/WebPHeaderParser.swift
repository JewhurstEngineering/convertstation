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
        let fps = options.resolvedFPS(sourceFPS: source.averageFrameRate).fps
        if interval.duration * Double(fps) >= 2, info.frameCount < 2 {
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
