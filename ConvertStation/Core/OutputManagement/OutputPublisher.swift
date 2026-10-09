import Foundation

enum PublishPlan: Equatable, Sendable {
    case write(URL)
    case replace(URL)
    case skip
    case ask(existing: URL, proposed: URL)
}

enum OutputPublisher {
    static func proposedURL(source: URL, directory: URL) -> URL {
        directory.appendingPathComponent(fileName(for: source))
    }

    static func fileName(for source: URL) -> String {
        let base = sanitize(source.deletingPathExtension().lastPathComponent)
        return base + ".webp"
    }

    static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\")
        let cleanedScalars = name.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? "-" : Character(scalar)
        }
        var cleaned = String(cleanedScalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned == "." || cleaned == ".." || cleaned.isEmpty {
            cleaned = "output"
        }
        if cleaned.count > 180 {
            cleaned = String(cleaned.prefix(180))
        }
        return cleaned
    }

    static func assertDistinct(source: URL, destination: URL) throws {
        let left = source.standardizedFileURL.resolvingSymlinksInPath().path
        let right = destination.standardizedFileURL.resolvingSymlinksInPath().path
        if left == right {
            throw ConversionError.samePathAsSource
        }
    }

    static func plan(
        proposed: URL,
        source: URL,
        policy: CollisionPolicy,
        fileExists: (URL) -> Bool
    ) throws -> PublishPlan {
        try assertDistinct(source: source, destination: proposed)
        let exists = fileExists(proposed)
        switch policy {
        case .ask:
            return exists ? .ask(existing: proposed, proposed: proposed) : .write(proposed)
        case .keepBoth:
            return .write(uniqueURL(proposed, fileExists: fileExists))
        case .skip:
            return exists ? .skip : .write(proposed)
        case .replace:
            return exists ? .replace(proposed) : .write(proposed)
        }
    }

    static func uniqueURL(_ url: URL, fileExists: (URL) -> Bool) -> URL {
        guard fileExists(url) else { return url }
        let directory = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        for index in 2...999 {
            let candidate = directory
                .appendingPathComponent("\(base)-\(index)")
                .appendingPathExtension(ext)
            if !fileExists(candidate) {
                return candidate
            }
        }
        return directory
            .appendingPathComponent("\(base)-\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    static func publish(temporary: URL, to destination: URL, replacing: Bool) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            guard replacing else {
                throw ConversionError.validationFailed("A file already exists at the destination.")
            }
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }
}
