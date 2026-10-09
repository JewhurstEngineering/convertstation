import Foundation

/// Tracks security-scoped access so the same calls work once the app is sandboxed.
final class FileAccessManager: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [URL: Int] = [:]

    func beginAccess(_ url: URL) {
        let started = url.startAccessingSecurityScopedResource()
        guard started else { return }
        lock.lock()
        counts[url, default: 0] += 1
        lock.unlock()
    }

    func endAccess(_ url: URL) {
        lock.lock()
        guard let count = counts[url], count > 0 else {
            lock.unlock()
            return
        }
        if count == 1 {
            counts[url] = nil
        } else {
            counts[url] = count - 1
        }
        lock.unlock()
        url.stopAccessingSecurityScopedResource()
    }

    func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    func resolveBookmark(_ data: Data) throws -> URL {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        if stale {
            _ = try bookmark(for: url)
        }
        return url
    }
}
