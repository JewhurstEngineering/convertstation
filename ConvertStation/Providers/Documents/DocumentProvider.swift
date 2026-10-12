import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

enum DocumentInspector {
    private static let extensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "txt", "text",
        "rtf", "rtfd", "html", "htm", "doc", "docx"
    ]

    static func isDocument(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }

    static func normalizedExtension(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "markdown", "mdown", "mkd": "md"
        case "htm": "html"
        case "text": "txt"
        default: url.pathExtension.lowercased()
        }
    }

    static func inspect(url: URL) throws -> SourceDescriptor {
        _ = try DocumentFile.load(url)
        let ext = normalizedExtension(url)
        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64)
        var warnings: [String] = []
        if ext == "doc" || ext == "docx" || ext == "rtf" || ext == "html" {
            warnings.append("Tables, images, comments, and complex layout are left out.")
        }
        return SourceDescriptor(
            url: url,
            detectedUTType: typeIdentifier(url),
            durationSeconds: nil,
            width: nil,
            height: nil,
            rotationDegrees: 0,
            hasVideo: false,
            hasAudio: false,
            hasAlpha: false,
            isHDR: false,
            codecName: label(for: ext),
            averageFrameRate: nil,
            fileSizeBytes: bytes,
            formatName: ext,
            warnings: warnings,
            kind: .document
        )
    }

    static func previewText(_ url: URL) -> String {
        guard let loaded = try? DocumentFile.load(url) else { return "" }
        let text = loaded.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        if text.count <= 6_000 { return text }
        return String(text.prefix(6_000)) + "\n…"
    }

    private static func typeIdentifier(_ url: URL) -> String {
        UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.plainText.identifier
    }

    private static func label(for ext: String) -> String {
        switch ext {
        case "md": "Markdown"
        case "rtf", "rtfd": "Rich Text"
        case "html": "HTML"
        case "doc": "Word"
        case "docx": "Word"
        default: "Text"
        }
    }
}

struct DocumentProvider: ConversionProvider {
    var id: String { "appkit-document" }

    func canRead(_ source: SourceDescriptor) -> Bool {
        source.kind == .document
    }

    func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor] {
        guard canRead(source) else { return [] }
        let current = DocumentInspector.normalizedExtension(source.url)
        return Self.catalog.filter { target in
            target.fileExtension != current && (target.id != OutputID.docx || DocumentFile.canWriteDocx)
        }
    }

    func validate(_ request: ConversionRequest, source: SourceDescriptor) throws {
        guard availableTargets(for: source).contains(where: { $0.id == request.targetFormatID }) else {
            throw ConversionError.invalidOptions("That document format isn't available for this file.")
        }
    }

    func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan {
        throw ConversionError.invalidOptions("Documents are written by AppKit.")
    }

    private static let catalog: [TargetDescriptor] = [
        target(OutputID.rtf, "Rich Text (.rtf)", "rtf", "Pictures and layout that rich text cannot hold are left out."),
        target(OutputID.pdfText, "PDF (.pdf)", "pdf", "This is a visual copy for reading and printing, not an editable Word file."),
        target(OutputID.markdown, "Markdown (.md)", "md", "Tables, images, and layout are left out. Headings are guessed from text size."),
        target(OutputID.html, "HTML (.html)", "html", "This is a simple HTML file, not a designed web page."),
        target(OutputID.docx, "Word (.docx)", "docx", "Comments, tracked changes, and complex layout are left out."),
        target(OutputID.plainText, "Plain Text (.txt)", "txt", "Formatting is removed. You get the words only.")
    ]

    private static func target(_ id: String, _ name: String, _ ext: String, _ notice: String) -> TargetDescriptor {
        TargetDescriptor(
            id: id,
            displayName: name,
            fileExtension: ext,
            supportsAnimation: false,
            supportsAlpha: false,
            supportsAudio: false,
            providerID: "appkit-document",
            family: .document,
            lossNotice: notice
        )
    }
}

enum DocumentConversion {
    static func convert(
        request: ConversionRequest,
        source: SourceDescriptor,
        resolvedDestination: URL,
        replacing: Bool
    ) throws -> ConversionResult {
        try DocumentProvider().validate(request, source: source)
        let started = Date()
        let loaded = try DocumentFile.load(source.url)
        let staging = try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: resolvedDestination.deletingLastPathComponent(),
            create: true
        )
        let temporary = staging.appendingPathComponent("document.partial.\(resolvedDestination.pathExtension)")
        do {
            try DocumentFile.write(loaded, format: request.targetFormatID, to: temporary)
            try DocumentFile.validate(temporary, format: request.targetFormatID)
            try OutputPublisher.publish(temporary: temporary, to: resolvedDestination, replacing: replacing)
            try? FileManager.default.removeItem(at: staging)
            let bytes = (try? FileManager.default.attributesOfItem(atPath: resolvedDestination.path)[.size] as? Int64) ?? 0
            return ConversionResult(
                outputURL: resolvedDestination,
                bytes: bytes,
                elapsedSeconds: Date().timeIntervalSince(started),
                width: 0,
                height: 0,
                frameCount: 0,
                loopForever: false,
                warnings: []
            )
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }
}

enum DocumentFile {
    static let canWriteDocx: Bool = {
        let sample = NSAttributedString(string: "Hi", attributes: [.font: NSFont.systemFont(ofSize: 13)])
        return (try? data(sample, type: .officeOpenXML)) != nil
    }()

    static func load(_ url: URL) throws -> NSAttributedString {
        let ext = DocumentInspector.normalizedExtension(url)
        if ext == "md" {
            let text = try readText(url)
            let rendered = MarkdownText.render(text)
            if rendered.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ConversionError.unreadable("This document is empty.")
            }
            return rendered
        }
        if ext == "txt" {
            let text = try readText(url)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ConversionError.unreadable("This document is empty.")
            }
            return NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        }
        let options = readingOptions(ext)
        guard let loaded = try? NSAttributedString(url: url, options: options, documentAttributes: nil),
              !loaded.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConversionError.unreadable("This document couldn't be opened.")
        }
        return loaded
    }

    static func write(_ string: NSAttributedString, format: String, to url: URL) throws {
        switch format {
        case OutputID.markdown:
            guard let encoded = MarkdownText.markdown(from: string).data(using: .utf8) else {
                throw ConversionError.destinationNotWritable
            }
            try encoded.write(to: url)
        case OutputID.plainText:
            guard let encoded = string.string.data(using: .utf8) else {
                throw ConversionError.destinationNotWritable
            }
            try encoded.write(to: url)
        case OutputID.rtf:
            try data(string, type: .rtf).write(to: url)
        case OutputID.html:
            try data(string, type: .html).write(to: url)
        case OutputID.docx:
            guard canWriteDocx else {
                throw ConversionError.invalidOptions("Word export isn't available on this Mac.")
            }
            try data(string, type: .officeOpenXML).write(to: url)
        case OutputID.pdfText:
            try writePDF(string, to: url)
        default:
            throw ConversionError.invalidOptions("That document format isn't available.")
        }
    }

    static func validate(_ url: URL, format: String) throws {
        switch format {
        case OutputID.pdfText:
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                throw ConversionError.validationFailed("The PDF couldn't be opened.")
            }
        case OutputID.markdown, OutputID.plainText:
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ConversionError.validationFailed("The document came out empty.")
            }
        default:
            _ = try load(url)
        }
    }

    private static func readText(_ url: URL) throws -> String {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        if let text = try? String(contentsOf: url, encoding: .utf16) { return text }
        throw ConversionError.unreadable("This document couldn't be opened.")
    }

    private static func readingOptions(_ ext: String) -> [NSAttributedString.DocumentReadingOptionKey: Any] {
        let type: NSAttributedString.DocumentType? = switch ext {
        case "rtf": .rtf
        case "rtfd": .rtfd
        case "html": .html
        case "doc": .docFormat
        case "docx": .officeOpenXML
        default: nil
        }
        guard let type else { return [:] }
        return [.documentType: type]
    }

    private static func data(_ string: NSAttributedString, type: NSAttributedString.DocumentType) throws -> Data {
        let range = NSRange(location: 0, length: string.length)
        return try string.data(from: range, documentAttributes: [.documentType: type])
    }

    private static func writePDF(_ string: NSAttributedString, to url: URL) throws {
        var media = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            throw ConversionError.destinationNotWritable
        }
        let margin: CGFloat = 72
        let textRect = CGRect(x: margin, y: margin, width: media.width - margin * 2, height: media.height - margin * 2)
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        var location = 0
        while location < string.length {
            context.beginPDFPage(nil)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)
            // A PDF page already has its origin at the bottom left, and Core Text
            // fills the path from the top. Flipping the context turns the page upside down.
            CTFrameDraw(frame, context)
            let visible = CTFrameGetVisibleStringRange(frame)
            context.endPDFPage()
            if visible.length <= 0 { break }
            location += visible.length
        }
        context.closePDF()
        if location == 0 {
            throw ConversionError.validationFailed("The PDF came out empty.")
        }
    }
}
