import AppKit

enum AppInstall {
    static var applicationsURL: URL {
        FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? URL(fileURLWithPath: "/Applications")
    }

    static var installedAppURL: URL {
        applicationsURL.appendingPathComponent("ConvertStation.app", isDirectory: true)
    }

    static func isApplicationsPath(_ path: String) -> Bool {
        path.hasPrefix("/Applications/")
    }

    static var isRunningFromApplications: Bool {
        isApplicationsPath(Bundle.main.bundleURL.path)
    }

    static var hasInstalledCopy: Bool {
        FileManager.default.fileExists(atPath: installedAppURL.path)
    }

    /// Copies the running bundle into `/Applications/ConvertStation.app`.
    /// Launch Services treats that path as the installed app.
    static func copyRunningAppToApplications() throws -> URL {
        let source = Bundle.main.bundleURL
        let destination = installedAppURL
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            registerLaunchServices(at: destination)
            return destination
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        do {
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            throw NSError(
                domain: "AppInstall",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Copy to Applications failed. \(error.localizedDescription)"
                ]
            )
        }
        registerLaunchServices(at: destination)
        return destination
    }

    static func revealInstalledApp() {
        NSWorkspace.shared.activateFileViewerSelecting([installedAppURL])
    }

    /// `NSWorkspace.open` reactivates this running copy because the bundle ID matches.
    /// Detach `open -n` so the Applications copy starts after this process quits.
    static func launchInstalledAndTerminate() {
        let escaped = installedAppURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = [
            "-c",
            "((sleep 1.2; /usr/bin/open -n '\(escaped)') &)"
        ]
        task.standardInput = FileHandle.nullDevice
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func registerLaunchServices(at appURL: URL) {
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        _ = run("/usr/bin/xattr", ["-cr", appURL.path])
        _ = run(lsregister, ["-f", appURL.path])
    }

    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String]) -> Int32 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }
}
