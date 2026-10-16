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
    /// The copy is done by an unsandboxed helper. A copy made by this app is
    /// tagged as sandbox data, and macOS then refuses to open it.
    static func copyRunningAppToApplications() async throws -> URL {
        let source = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let destination = installedAppURL
        guard source.standardizedFileURL != destination.standardizedFileURL else {
            registerLaunchServices(at: destination)
            return destination
        }
        try await install(from: source.path, to: destination.path)
        registerLaunchServices(at: destination)
        return destination
    }

    private static func install(from sourcePath: String, to destinationPath: String) async throws {
        let connection = NSXPCConnection(serviceName: InstallCopy.serviceName)
        connection.remoteObjectInterface = NSXPCInterface(with: InstallHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }

        let once = OnceResume()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(continuation, .failure(error))
            } as? InstallHelperProtocol
            guard let proxy else {
                once.resume(continuation, .failure(InstallCopyError("ConvertStation couldn't start the installer.")))
                return
            }
            proxy.install(from: sourcePath, to: destinationPath) { message in
                if let message, !message.isEmpty {
                    once.resume(continuation, .failure(InstallCopyError(message)))
                } else {
                    once.resume(continuation, .success(()))
                }
            }
        }
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

private final class OnceResume: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<Void, Error>, _ result: Result<Void, Error>) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        continuation.resume(with: result)
    }
}
