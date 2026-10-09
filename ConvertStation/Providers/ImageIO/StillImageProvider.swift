import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageIOSupport {
    static func writableIdentifiers() -> Set<String> {
        Set(CGImageDestinationCopyTypeIdentifiers() as? [String] ?? [])
    }
}

struct StillImageProvider: ConversionProvider {
    var writable: Set<String>

    init(writable: Set<String>? = nil) {
        self.writable = writable ?? ImageIOSupport.writableIdentifiers()
    }

    var id: String { "imageio-still" }

    func canRead(_ source: SourceDescriptor) -> Bool {
        source.kind == .still || source.kind == .video || source.kind == .animation
    }

    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor] {
        guard canRead(source) else { return [] }
        return Self.catalog.compactMap { candidate in
            guard writable.contains(candidate.type.identifier) else { return nil }
            var target = candidate.target
            target.lossNotice = Self.notice(for: candidate.target.id, source: source)
            return target
        }
    }

    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws {
        guard availableTargets(for: source).contains(where: { $0.id == request.targetFormatID }) else {
            throw ConversionError.invalidOptions("That image format isn't available for this file.")
        }
        guard (0...100).contains(request.stillOptions.quality) else {
            throw ConversionError.invalidOptions("Quality must be between 0 and 100.")
        }
    }

    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        throw ConversionError.invalidOptions("Still images are written by ImageIO.")
    }

    private struct Candidate {
        var target: TargetDescriptor
        var type: UTType
    }

    private static let catalog: [Candidate] = [
        Candidate(target: target(OutputID.jpeg, "JPEG Image (.jpg)", "jpg", alpha: false), type: .jpeg),
        Candidate(target: target(OutputID.png, "PNG Image (.png)", "png", alpha: true), type: .png),
        Candidate(target: target(OutputID.stillWebP, "WebP Image (.webp)", "webp", alpha: true), type: .webP),
        Candidate(target: target(OutputID.tiff, "TIFF Image (.tiff)", "tiff", alpha: true), type: .tiff),
        Candidate(target: target(OutputID.heic, "HEIC Image (.heic)", "heic", alpha: true), type: .heic),
        Candidate(target: target(OutputID.bmp, "BMP Image (.bmp)", "bmp", alpha: false), type: .bmp),
        Candidate(target: target(OutputID.stillGIF, "GIF Image (.gif)", "gif", alpha: false), type: .gif)
    ]

    private static func target(_ id: String, _ name: String, _ ext: String, alpha: Bool) -> TargetDescriptor {
        TargetDescriptor(
            id: id,
            displayName: name,
            fileExtension: ext,
            supportsAnimation: false,
            supportsAlpha: alpha,
            supportsAudio: false,
            providerID: "imageio-still",
            family: .image,
            lossNotice: ""
        )
    }

    private static func notice(for id: String, source: SourceDescriptor) -> String {
        var parts: [String] = []
        if source.kind == .video || source.kind == .animation {
            parts.append("Saves one frame from the start of the trim.")
        }
        switch id {
        case OutputID.jpeg:
            parts.append(source.hasAlpha
                ? "JPEG has no transparency. Transparent areas become white."
                : "JPEG is lossy, so fine detail can shift.")
        case OutputID.png:
            parts.append("PNG keeps transparency.")
        case OutputID.stillWebP:
            parts.append("This is a still image, not an animation.")
        case OutputID.stillGIF:
            parts.append("This is one frame, not an animation.")
        case OutputID.heic:
            parts.append("HEIC support depends on this Mac.")
        case OutputID.tiff:
            parts.append("TIFF is saved as a single page.")
        case OutputID.bmp:
            parts.append("BMP is usually uncompressed, so the file can get larger.")
        default:
            break
        }
        return parts.joined(separator: " ")
    }
}

enum StillImageConversion {
    static func convert(
        request: ConversionRequest,
        source: SourceDescriptor,
        resolvedDestination: URL,
        replacing: Bool
    ) async throws -> ConversionResult {
        let provider = StillImageProvider()
        try provider.validate(request, source: source)
        guard let type = utType(for: request.targetFormatID) else {
            throw ConversionError.invalidOptions("That image format isn't available.")
        }
        let started = Date()
        let loaded = try await loadImage(source: source, trimStart: request.options.trimStartSeconds)
        let fitted = scale(loaded, maxEdge: request.stillOptions.maxEdge)
        let image = request.targetFormatID == OutputID.jpeg ? flatten(fitted) : fitted
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: resolvedDestination.deletingLastPathComponent(),
            create: true
        )
        let temporary = staging.appendingPathComponent("\(request.id.uuidString).partial.\(resolvedDestination.pathExtension)")
        do {
            try write(image, to: temporary, type: type, quality: request.stillOptions.quality)
            let checked = try reopen(temporary, expecting: type)
            if let maxEdge = request.stillOptions.maxEdge, max(checked.width, checked.height) > maxEdge {
                throw ConversionError.validationFailed("Output is larger than the \(maxEdge)px limit.")
            }
            try OutputPublisher.publish(temporary: temporary, to: resolvedDestination, replacing: replacing)
            try? FileManager.default.removeItem(at: staging)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: resolvedDestination.path)[.size] as? Int64) ?? 0
            return ConversionResult(
                outputURL: resolvedDestination,
                bytes: bytes,
                elapsedSeconds: Date().timeIntervalSince(started),
                width: checked.width,
                height: checked.height,
                frameCount: 1,
                loopForever: false,
                warnings: request.targetFormatID == OutputID.jpeg && source.hasAlpha
                    ? ["JPEG has no transparency. Transparent areas were filled with white."]
                    : []
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private static func utType(for profileID: String) -> UTType? {
        switch profileID {
        case OutputID.jpeg: .jpeg
        case OutputID.png: .png
        case OutputID.stillWebP: .webP
        case OutputID.tiff: .tiff
        case OutputID.heic: .heic
        case OutputID.bmp: .bmp
        case OutputID.stillGIF: .gif
        default: nil
        }
    }

    private static func loadImage(source: SourceDescriptor, trimStart: Double) async throws -> CGImage {
        if source.kind == .video || source.kind == .animation {
            return try await frame(from: source.url, at: trimStart)
        }
        guard let imageSource = CGImageSourceCreateWithURL(source.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ConversionError.unreadable("This image couldn't be opened.")
        }
        return image
    }

    private static func frame(from url: URL, at seconds: Double) async throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        do {
            let (image, _) = try await generator.image(at: time)
            return image
        } catch {
            throw ConversionError.unreadable("A frame couldn't be read from this video.")
        }
    }

    private static func scale(_ image: CGImage, maxEdge: Int?) -> CGImage {
        guard let maxEdge, maxEdge > 0 else { return image }
        let longSide = max(image.width, image.height)
        guard longSide > maxEdge else { return image }
        let ratio = Double(maxEdge) / Double(longSide)
        let width = max(1, Int((Double(image.width) * ratio).rounded()))
        let height = max(1, Int((Double(image.height) * ratio).rounded()))
        return draw(image, width: width, height: height, opaque: false) ?? image
    }

    private static func flatten(_ image: CGImage) -> CGImage {
        draw(image, width: image.width, height: image.height, opaque: true) ?? image
    }

    private static func draw(_ image: CGImage, width: Int, height: Int, opaque: Bool) -> CGImage? {
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alpha.rawValue
        ) else { return nil }
        if opaque {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func write(_ image: CGImage, to url: URL, type: UTType, quality: Int) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConversionError.destinationNotWritable
        }
        var properties: [CFString: Any] = [:]
        if type == .jpeg || type == .heic || type == .webP {
            properties[kCGImageDestinationLossyCompressionQuality] = Double(min(100, max(0, quality))) / 100
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConversionError.processFailed(exitCode: 1, log: "ImageIO could not write \(type.identifier).")
        }
    }

    private static func reopen(_ url: URL, expecting type: UTType) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConversionError.validationFailed("The image output couldn't be opened.")
        }
        let written = CGImageSourceGetType(source) as String?
        guard written == type.identifier else {
            throw ConversionError.validationFailed("Output type was \(written ?? "missing"), not \(type.identifier).")
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ConversionError.validationFailed("The image output has no pixel size.")
        }
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else {
            throw ConversionError.validationFailed("The image output has no pixel size.")
        }
        return (width, height)
    }
}

enum StillInspector {
    static func inspect(url: URL) -> SourceDescriptor? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        let type = (CGImageSourceGetType(source) as String?) ?? UTType.image.identifier
        let width = properties[kCGImagePropertyPixelWidth] as? Int
        let height = properties[kCGImagePropertyPixelHeight] as? Int
        let animated = count > 1 && (type == UTType.gif.identifier || type == UTType.webP.identifier)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        let hasAlpha = image.map { cgImage in
            switch cgImage.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: false
            default: true
            }
        } ?? false
        return SourceDescriptor(
            url: url,
            detectedUTType: type,
            durationSeconds: nil,
            width: width,
            height: height,
            rotationDegrees: 0,
            hasVideo: animated,
            hasAudio: false,
            hasAlpha: hasAlpha,
            isHDR: false,
            codecName: UTType(type)?.preferredFilenameExtension,
            averageFrameRate: nil,
            fileSizeBytes: bytes,
            formatName: type,
            warnings: [],
            kind: animated ? .animation : .still,
            audioCodecName: nil
        )
    }
}
