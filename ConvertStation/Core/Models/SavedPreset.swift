import Foundation

/// Settings the user saved under a name of their own.
/// Trim stays with each file, so it isn't part of a preset.
struct SavedPreset: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var framesPerSecond: Int
    var maxPixelWidth: Int?
    var quality: Int
    var loopForever: Bool

    init(id: UUID = UUID(), name: String, options: WebPOptions) {
        self.id = id
        self.name = name
        framesPerSecond = options.framesPerSecond
        maxPixelWidth = options.maxPixelWidth
        quality = options.quality
        loopForever = options.loopForever
    }

    func matches(_ options: WebPOptions) -> Bool {
        options.framesPerSecond == framesPerSecond
            && options.maxPixelWidth == maxPixelWidth
            && options.quality == quality
            && options.loopForever == loopForever
    }

    func applied(to options: WebPOptions) -> WebPOptions {
        var copy = options
        copy.framesPerSecond = framesPerSecond
        copy.maxPixelWidth = maxPixelWidth
        copy.quality = quality
        copy.loopForever = loopForever
        copy.presetID = .custom
        return copy.matchingPresetIfPossible()
    }

    var summary: String {
        let width = maxPixelWidth.map { "\($0.formatted()) px" } ?? "original width"
        return "\(framesPerSecond) fps · \(width) · quality \(quality)"
    }
}
