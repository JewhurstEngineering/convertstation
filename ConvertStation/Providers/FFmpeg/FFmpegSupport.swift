import Foundation
import os

struct EngineStatus: Equatable, Sendable {
    var ffmpegURL: URL?
    var ffprobeURL: URL?
    var versionSummary: String
    var supportsAnimatedWebP: Bool
    var detail: String

    static let checking = EngineStatus(
        ffmpegURL: nil,
        ffprobeURL: nil,
        versionSummary: "Checking…",
        supportsAnimatedWebP: false,
        detail: "Checking the conversion engine…"
    )

    static let missing = EngineStatus(
        ffmpegURL: nil,
        ffprobeURL: nil,
        versionSummary: "Not found",
        supportsAnimatedWebP: false,
        detail: "Install FFmpeg with libwebp, or bundle ffmpeg and ffprobe in the app."
    )

    var binaries: EngineBinaries? {
        guard let ffmpegURL, let ffprobeURL, supportsAnimatedWebP else { return nil }
        return EngineBinaries(ffmpeg: ffmpegURL, ffprobe: ffprobeURL, versionSummary: versionSummary)
    }
}

struct EngineBinaries: Equatable, Sendable {
    var ffmpeg: URL
    var ffprobe: URL
    var versionSummary: String
}

enum FFmpegLocator {
    static func locate(bundle: Bundle = .main, fileManager: FileManager = .default) -> EngineStatus {
        var candidates: [URL] = [
            bundle.bundleURL.appendingPathComponent("Contents/Helpers/ffmpeg")
        ]
        if let bundled = bundle.url(forResource: "ffmpeg", withExtension: nil) {
            candidates.append(bundled)
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/ffmpeg"))

        var lastFailure = "Install FFmpeg with libwebp, or bundle ffmpeg and ffprobe in the app."
        for ffmpeg in candidates where fileManager.isExecutableFile(atPath: ffmpeg.path) {
            let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
            guard fileManager.isExecutableFile(atPath: ffprobe.path) else { continue }
            guard let encoders = try? SynchronousProcess.run(ffmpeg, ["-hide_banner", "-encoders"]), encoders.exitCode == 0 else {
                lastFailure = "FFmpeg at \(ffmpeg.path) did not run."
                continue
            }
            let version = ((try? SynchronousProcess.run(ffmpeg, ["-version"]))?.stdout
                .split(separator: "\n")
                .first
                .map(String.init)) ?? "Unknown FFmpeg"
            if encoders.stdout.contains("libwebp_anim") {
                return EngineStatus(
                    ffmpegURL: ffmpeg,
                    ffprobeURL: ffprobe,
                    versionSummary: version,
                    supportsAnimatedWebP: true,
                    detail: "libwebp_anim is available."
                )
            }
            lastFailure = "This FFmpeg build has no libwebp_anim encoder."
        }
        var missing = EngineStatus.missing
        missing.detail = lastFailure
        return missing
    }
}

enum EngineProcess {
    /// Homebrew FFmpeg links sdl2-compat, which loads AppKit. Keep every helper
    /// in the background so a probe or a conversion cannot take a Dock tile.
    static func configure(_ process: Process) {
        var environment = ProcessInfo.processInfo.environment
        environment["SDL_MAC_BACKGROUND_APP"] = "1"
        environment["SDL_VIDEODRIVER"] = "dummy"
        environment["SDL_AUDIODRIVER"] = "dummy"
        process.environment = environment
    }
}

struct SynchronousProcess {
    struct Result: Sendable {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    static func run(_ executable: URL, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        EngineProcess.configure(process)

        let outBox = OSAllocatedUnfairLock(initialState: Data())
        let errBox = OSAllocatedUnfairLock(initialState: Data())
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            outBox.withLock { $0 = data }
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            errBox.withLock { $0 = data }
            group.leave()
        }
        try process.run()
        process.waitUntilExit()
        group.wait()
        let outData = outBox.withLock { $0 }
        let errData = errBox.withLock { $0 }
        return Result(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: capped(errData), encoding: .utf8) ?? ""
        )
    }

    private static func capped(_ data: Data) -> Data {
        guard data.count > 64_000 else { return data }
        return data.suffix(64_000)
    }
}

struct ProcessOutput: Sendable, Equatable {
    var exitCode: Int32
    var standardError: String
    var cancelled: Bool
}

final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        let running: Process?
        lock.lock()
        cancelled = true
        running = process
        lock.unlock()
        guard let running else { return }
        running.terminate()
        let pid = running.processIdentifier
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2) {
            if running.isRunning {
                kill(pid, SIGKILL)
            }
        }
    }

    func run(
        executable: URL,
        arguments: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice
        EngineProcess.configure(process)

        let alreadyCancelled = store(process)

        let stderrTask = Task.detached { Self.readPipe(stderr) }
        let stdoutTask = Task.detached {
            do {
                for try await line in stdout.fileHandleForReading.bytes.lines {
                    onLine(line)
                }
            } catch {
                // The pipe closes when the process exits or is killed.
            }
        }

        let gate = ResumeOnce()
        let exitCode: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { proc in
                    gate.resume(continuation, .success(proc.terminationStatus))
                }
                do {
                    try process.run()
                    if alreadyCancelled {
                        process.terminate()
                    }
                } catch {
                    gate.resume(continuation, .failure(error))
                }
            }
        } onCancel: {
            self.cancel()
        }

        _ = await stdoutTask.value
        let err = await stderrTask.value
        return ProcessOutput(exitCode: exitCode, standardError: err, cancelled: wasCancelled())
    }

    private func store(_ process: Process) -> Bool {
        lock.lock()
        self.process = process
        let alreadyCancelled = cancelled
        lock.unlock()
        return alreadyCancelled
    }

    private func wasCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private static func readPipe(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let capped = data.count > 64_000 ? data.suffix(64_000) : data
        return String(data: capped, encoding: .utf8) ?? ""
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<Int32, Error>, _ result: Result<Int32, Error>) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        guard shouldResume else { return }
        switch result {
        case .success(let code):
            continuation.resume(returning: code)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
