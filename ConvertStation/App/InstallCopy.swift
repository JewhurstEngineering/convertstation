import Foundation

@objc(InstallHelperProtocol)
protocol InstallHelperProtocol {
    func install(from sourcePath: String, to destinationPath: String, withReply reply: @escaping (String?) -> Void)
}

enum InstallCopy {
    static let serviceName = "com.jewhurst.ConvertStation.InstallHelper"
    static let applicationsDestination = "/Applications/ConvertStation.app"

    static func isAllowedDestination(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.lastPathComponent == "ConvertStation.app" else { return false }
        if url.path == applicationsDestination { return true }
        // /tmp is /private/tmp. Tests copy here because this process cannot
        // write into the app container.
        if url.path.hasPrefix("/private/tmp/") { return true }
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        return url.path.hasPrefix(temporary + "/")
    }

    static func isAllowedSource(_ path: String) -> Bool {
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.lastPathComponent == "ConvertStation.app" else { return false }
        let info = url.appendingPathComponent("Contents/Info.plist")
        guard let plist = NSDictionary(contentsOf: info),
              let identifier = plist["CFBundleIdentifier"] as? String else {
            return false
        }
        return identifier == "com.jewhurst.ConvertStation"
    }

    /// Copies outside the app sandbox. A sandboxed copy is tagged so macOS
    /// refuses to launch it ("can't be opened").
    static func perform(from sourcePath: String, to destinationPath: String) throws {
        guard isAllowedSource(sourcePath) else {
            throw InstallCopyError("That isn't a ConvertStation app.")
        }
        guard isAllowedDestination(destinationPath) else {
            throw InstallCopyError("ConvertStation can only install to /Applications.")
        }
        let source = URL(fileURLWithPath: sourcePath).resolvingSymlinksInPath().standardizedFileURL
        let destination = URL(fileURLWithPath: destinationPath).resolvingSymlinksInPath().standardizedFileURL
        guard source.path != destination.path else { return }

        let fileManager = FileManager.default
        let parent = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = [source.path, destination.path]
        let dittoError = Pipe()
        ditto.standardError = dittoError
        ditto.standardOutput = FileHandle.nullDevice
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            let detail = String(data: dittoError.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw InstallCopyError(detail.isEmpty ? "The copy into Applications failed." : "The copy into Applications failed. \(detail)")
        }

        let quarantine = Process()
        quarantine.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        quarantine.arguments = ["-dr", "com.apple.quarantine", destination.path]
        try? quarantine.run()
        quarantine.waitUntilExit()
    }
}

struct InstallCopyError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
