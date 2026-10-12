import CoreGraphics
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum PDFInspector {
    static func isPDF(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return true }
        return UTType(filenameExtension: ext)?.conforms(to: .pdf) == true
    }

    static func inspect(url: URL) throws -> SourceDescriptor {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.unreadable("This PDF couldn't be opened.")
        }
        if document.isLocked {
            throw ConversionError.unreadable("This PDF is locked. ConvertStation doesn't ask for a password.")
        }
        guard document.pageCount > 0, let page = document.page(at: 0) else {
            throw ConversionError.unreadable("This PDF has no pages.")
        }
        let bounds = page.bounds(for: .mediaBox)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
        var warnings: [String] = []
        if document.pageCount > 1 {
            warnings.append("Each of the \(document.pageCount) pages is saved as its own image.")
        }
        return SourceDescriptor(
            url: url,
            detectedUTType: UTType.pdf.identifier,
            durationSeconds: nil,
            width: Int(bounds.width.rounded()),
            height: Int(bounds.height.rounded()),
            rotationDegrees: 0,
            hasVideo: false,
            hasAudio: false,
            hasAlpha: false,
            isHDR: false,
            codecName: "PDF",
            averageFrameRate: nil,
            fileSizeBytes: bytes,
            formatName: "pdf",
            warnings: warnings,
            kind: .still,
            audioCodecName: nil,
            pageCount: document.pageCount
        )
    }

    static func renderPages(url: URL) throws -> [CGImage] {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.unreadable("This PDF couldn't be opened.")
        }
        if document.isLocked {
            throw ConversionError.unreadable("This PDF is locked. ConvertStation doesn't ask for a password.")
        }
        guard document.pageCount > 0 else {
            throw ConversionError.unreadable("This PDF has no pages.")
        }
        var images: [CGImage] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else {
                throw ConversionError.unreadable("Page \(index + 1) couldn't be read.")
            }
            guard let image = draw(page) else {
                throw ConversionError.unreadable("Page \(index + 1) couldn't be drawn.")
            }
            images.append(image)
        }
        return images
    }

    private static func draw(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let longSide = max(bounds.width, bounds.height)
        let scale = min(2, 4096 / longSide)
        let width = max(1, Int((bounds.width * scale).rounded()))
        let height = max(1, Int((bounds.height * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
