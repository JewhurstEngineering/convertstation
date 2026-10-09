import Foundation

@MainActor
final class PreferencesStore {
    private let defaults: UserDefaults
    private let policyKey = "collisionPolicy"
    private let bookmarkKey = "destinationBookmark"
    private let presetKey = "lastPreset"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var collisionPolicy: CollisionPolicy {
        get {
            defaults.string(forKey: policyKey).flatMap(CollisionPolicy.init(rawValue:)) ?? .ask
        }
        set { defaults.set(newValue.rawValue, forKey: policyKey) }
    }

    var destinationBookmark: Data? {
        get { defaults.data(forKey: bookmarkKey) }
        set { defaults.set(newValue, forKey: bookmarkKey) }
    }

    var lastPreset: PresetID {
        get { defaults.string(forKey: presetKey).flatMap(PresetID.init(rawValue:)) ?? .balanced }
        set { defaults.set(newValue.rawValue, forKey: presetKey) }
    }
}

enum JobStore {
    static func load() -> [ConversionJob] {
        guard let data = try? Data(contentsOf: fileURL()) else { return [] }
        guard var jobs = try? JSONDecoder().decode([ConversionJob].self, from: data) else { return [] }
        let bookmarks = (try? Data(contentsOf: bookmarksURL())).flatMap { data in
            try? JSONDecoder().decode([String: Data].self, from: data)
        } ?? [:]
        for index in jobs.indices {
            jobs[index].progress = nil
            jobs[index].sourceBookmark = bookmarks[jobs[index].id.uuidString]
            switch jobs[index].state {
            case .importing, .probing, .queued, .running, .verifying:
                jobs[index].state = .interrupted
                jobs[index].errorMessage = "Stopped when ConvertStation quit. You can convert it again."
            default:
                break
            }
        }
        return jobs
    }

    static func save(_ jobs: [ConversionJob]) {
        guard let data = try? JSONEncoder().encode(jobs) else { return }
        let url = fileURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        let bookmarks = Dictionary(uniqueKeysWithValues: jobs.compactMap { job -> (String, Data)? in
            guard let bookmark = job.sourceBookmark else { return nil }
            return (job.id.uuidString, bookmark)
        })
        if let bookmarkData = try? JSONEncoder().encode(bookmarks) {
            try? bookmarkData.write(to: bookmarksURL(), options: .atomic)
        }
    }

    private static func fileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base
            .appendingPathComponent("ConvertStation", isDirectory: true)
            .appendingPathComponent("jobs.json")
    }

    private static func bookmarksURL() -> URL {
        fileURL().deletingLastPathComponent().appendingPathComponent("bookmarks.json")
    }
}
