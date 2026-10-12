import AppKit

/// A small Markdown reader and writer for headings, emphasis, links, lists, and code.
/// Tables and images are left out on purpose.
enum MarkdownText {
    static func render(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                append(inline(code.joined(separator: "\n"), bodySize: 12, mono: true), style: .code, to: result)
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }
            if let level = headingLevel(line) {
                let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                append(inline(String(text), bodySize: headingSize(level)), style: .heading(level), to: result)
                index += 1
                continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                append(inline(String(line.dropFirst(2))), style: .bullet, to: result)
                index += 1
                continue
            }
            if let item = orderedItem(line) {
                append(inline(item.text), style: .number(item.number), to: result)
                index += 1
                continue
            }
            if line.hasPrefix("> ") {
                append(inline(String(line.dropFirst(2))), style: .quote, to: result)
                index += 1
                continue
            }
            var paragraph = [line]
            index += 1
            while index < lines.count, !isBlockStart(lines[index]) {
                paragraph.append(lines[index])
                index += 1
            }
            append(inline(paragraph.joined(separator: " ")), style: .body, to: result)
        }
        return result
    }

    static func markdown(from string: NSAttributedString) -> String {
        let raw = string.string.replacingOccurrences(of: "\u{FFFC}", with: "")
        let pieces = raw.components(separatedBy: "\n")
        var lines: [String] = []
        var code: [String] = []
        func flushCode() {
            guard !code.isEmpty else { return }
            lines.append("```")
            lines.append(contentsOf: code)
            lines.append("```")
            code.removeAll()
        }
        var location = 0
        for piece in pieces {
            let range = NSRange(location: location, length: (piece as NSString).length)
            location += range.length + 1
            if range.length > 0, paragraphIsCode(string, range: range) {
                code.append(piece)
                continue
            }
            flushCode()
            if piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            lines.append(markdownLine(string, range: range, text: piece))
        }
        flushCode()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private enum Block: Equatable {
        case body
        case heading(Int)
        case bullet
        case number(Int)
        case quote
        case code
    }

    private static func append(_ text: NSAttributedString, style: Block, to result: NSMutableAttributedString) {
        let block = NSMutableAttributedString(attributedString: text)
        let font = font(for: style)
        if block.length > 0, style != .body {
            block.addAttribute(.font, value: font, range: NSRange(location: 0, length: block.length))
        } else if block.length > 0 {
            block.enumerateAttribute(.font, in: NSRange(location: 0, length: block.length)) { value, range, _ in
                if value == nil {
                    block.addAttribute(.font, value: font, range: range)
                }
            }
        }
        if case .heading(let level) = style {
            let paragraph = NSMutableParagraphStyle()
            paragraph.headerLevel = level
            block.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: block.length))
        }
        switch style {
        case .bullet:
            block.insert(NSAttributedString(string: "• ", attributes: [.font: font]), at: 0)
        case .number(let number):
            block.insert(NSAttributedString(string: "\(number). ", attributes: [.font: font]), at: 0)
        case .quote:
            block.insert(NSAttributedString(string: "“", attributes: [.font: font]), at: 0)
            block.append(NSAttributedString(string: "”", attributes: [.font: font]))
        default:
            break
        }
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        result.append(block)
    }

    private static func font(for style: Block) -> NSFont {
        switch style {
        case .heading(let level):
            return NSFont.systemFont(ofSize: headingSize(level), weight: .bold)
        case .code:
            return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        case .body, .bullet, .number, .quote:
            return NSFont.systemFont(ofSize: 13)
        }
    }

    private static func headingSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: 26
        case 2: 20
        default: 16
        }
    }

    private static func headingLevel(_ line: String) -> Int? {
        var count = 0
        for character in line {
            if character == "#" { count += 1 } else { break }
        }
        guard (1...6).contains(count) else { return nil }
        let next = line.index(line.startIndex, offsetBy: count, limitedBy: line.endIndex) ?? line.endIndex
        guard next < line.endIndex, line[next] == " " else { return nil }
        return min(count, 3)
    }

    private static func orderedItem(_ line: String) -> (number: Int, text: String)? {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].hasSuffix(".") else { return nil }
        let digits = parts[0].dropLast()
        guard let number = Int(digits), number > 0 else { return nil }
        return (number, String(parts[1]))
    }

    private static func isBlockStart(_ line: String) -> Bool {
        if line.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if line.hasPrefix("```") || line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("> ") { return true }
        if headingLevel(line) != nil || orderedItem(line) != nil { return true }
        return false
    }

    private static func inline(_ text: String, bodySize: CGFloat = 13, mono: Bool = false) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var index = text.startIndex
        while index < text.endIndex {
            if !mono, text[index...].hasPrefix("**"), let end = closing("**", in: text, from: text.index(index, offsetBy: 2)) {
                let body = text[text.index(index, offsetBy: 2)..<end]
                result.append(styled(String(body), size: bodySize, bold: true, italic: false, mono: false))
                index = text.index(end, offsetBy: 2)
                continue
            }
            if !mono, text[index] == "*", let end = closing("*", in: text, from: text.index(after: index)) {
                let body = text[text.index(after: index)..<end]
                result.append(styled(String(body), size: bodySize, bold: false, italic: true, mono: false))
                index = text.index(after: end)
                continue
            }
            if !mono, text[index] == "`", let end = closing("`", in: text, from: text.index(after: index)) {
                let body = text[text.index(after: index)..<end]
                result.append(styled(String(body), size: bodySize, bold: false, italic: false, mono: true))
                index = text.index(after: end)
                continue
            }
            if !mono, text[index] == "[", let link = link(in: text, from: index) {
                result.append(styled(link.label, size: bodySize, bold: false, italic: false, mono: false, url: link.url))
                index = link.next
                continue
            }
            let start = index
            index = text.index(after: index)
            while index < text.endIndex, mono || !isMarker(text[index]) {
                index = text.index(after: index)
            }
            result.append(styled(String(text[start..<index]), size: bodySize, bold: false, italic: false, mono: mono))
        }
        return result
    }

    private static func isMarker(_ character: Character) -> Bool {
        character == "*" || character == "`" || character == "["
    }

    private static func closing(_ marker: String, in text: String, from start: String.Index) -> String.Index? {
        guard start <= text.endIndex else { return nil }
        return text.range(of: marker, range: start..<text.endIndex)?.lowerBound
    }

    private static func link(in text: String, from start: String.Index) -> (label: String, url: URL, next: String.Index)? {
        guard let labelEnd = text[start...].firstIndex(of: "]"),
              text.index(after: labelEnd) < text.endIndex,
              text[text.index(after: labelEnd)] == "(" else { return nil }
        let urlStart = text.index(labelEnd, offsetBy: 2)
        guard let urlEnd = text[urlStart...].firstIndex(of: ")") else { return nil }
        let label = String(text[text.index(after: start)..<labelEnd])
        let raw = String(text[urlStart..<urlEnd])
        guard let url = URL(string: raw) else { return nil }
        return (label, url, text.index(after: urlEnd))
    }

    private static func styled(_ text: String, size: CGFloat, bold: Bool, italic: Bool, mono: Bool, url: URL? = nil) -> NSAttributedString {
        var font = mono
            ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
            : NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        if italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        var attributes: [NSAttributedString.Key: Any] = [.font: font]
        if let url {
            attributes[.link] = url
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func paragraphIsCode(_ string: NSAttributedString, range: NSRange) -> Bool {
        guard range.length > 0 else { return false }
        var code = true
        string.enumerateAttribute(.font, in: range) { value, _, stop in
            let font = value as? NSFont
            if font?.isMonospaced != true {
                code = false
                stop.pointee = true
            }
        }
        return code
    }

    private static func markdownLine(_ string: NSAttributedString, range: NSRange, text: String) -> String {
        let font = range.length > 0 ? string.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont : nil
        let size = font?.pointSize ?? 13
        let header = (string.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle)?.headerLevel ?? 0
        let marks: String
        if header == 1 || size >= 24 { marks = "# " }
        else if header == 2 || size >= 18 { marks = "## " }
        else if header >= 3 || (size >= 15.5 && font?.isBold == true) { marks = "### " }
        else { marks = "" }
        let body: String
        if text.hasPrefix("• ") {
            body = "- " + inlineMarkdown(string, range: NSRange(location: range.location + 2, length: max(0, range.length - 2)), includeBold: marks.isEmpty)
        } else if let item = orderedItem(text) {
            let prefix = "\(item.number). "
            let prefixLength = (prefix as NSString).length
            body = prefix + inlineMarkdown(string, range: NSRange(location: range.location + prefixLength, length: max(0, range.length - prefixLength)), includeBold: marks.isEmpty)
        } else {
            body = inlineMarkdown(string, range: range, includeBold: marks.isEmpty)
        }
        return marks + body
    }

    private static func inlineMarkdown(_ string: NSAttributedString, range: NSRange, includeBold: Bool = true) -> String {
        guard range.length > 0 else { return "" }
        var output = ""
        string.enumerateAttributes(in: range) { attributes, subrange, _ in
            let piece = (string.attributedSubstring(from: subrange).string)
            let font = attributes[.font] as? NSFont
            var wrapped = piece
            if font?.isMonospaced == true {
                wrapped = "`\(piece)`"
            } else {
                if includeBold, font?.isBold == true { wrapped = "**\(wrapped)**" }
                if font?.isItalic == true { wrapped = "*\(wrapped)*" }
            }
            if let url = attributes[.link] as? URL {
                wrapped = "[\(wrapped)](\(url.absoluteString))"
            } else if let url = attributes[.link] as? String {
                wrapped = "[\(wrapped)](\(url))"
            }
            output += wrapped
        }
        return output
    }
}

private extension NSFont {
    var isBold: Bool {
        if fontDescriptor.symbolicTraits.contains(.bold) { return true }
        return NSFontManager.shared.traits(of: self).contains(.boldFontMask)
    }

    var isItalic: Bool {
        fontDescriptor.symbolicTraits.contains(.italic)
    }

    var isMonospaced: Bool {
        fontDescriptor.symbolicTraits.contains(.monoSpace)
    }
}
