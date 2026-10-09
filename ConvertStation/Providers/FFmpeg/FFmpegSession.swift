import Foundation

struct CheckedMedia: Sendable {
    var width: Int
    var height: Int
    var frameCount: Int
    var loopForever: Bool
}

enum FFmpegSession {
    static func run(
        plan: ExecutionPlan,
        runner: ProcessRunner,
        resolvedDestination: URL,
        replacing: Bool,
        onProgress: @escaping @Sendable (Double) -> Void,
        validate: (URL) throws -> CheckedMedia
    ) async throws -> ConversionResult {
        let fileManager = FileManager.default
        let staging = plan.temporaryOutput.deletingLastPathComponent()
        let started = Date()
        let progress = ProgressBox()

        do {
            let output = try await runner.run(executable: plan.executableURL, arguments: plan.arguments) { line in
                if let fraction = progress.consume(line, expectedDuration: plan.expectedDuration) {
                    onProgress(fraction)
                }
            }
            if output.cancelled || Task.isCancelled {
                try? fileManager.removeItem(at: staging)
                throw ConversionError.cancelled
            }
            guard output.exitCode == 0 else {
                try? fileManager.removeItem(at: staging)
                throw ConversionError.processFailed(exitCode: output.exitCode, log: output.standardError)
            }
            let checked = try validate(plan.temporaryOutput)
            try OutputPublisher.publish(temporary: plan.temporaryOutput, to: resolvedDestination, replacing: replacing)
            try? fileManager.removeItem(at: staging)
            let publishedSize = (try? fileManager.attributesOfItem(atPath: resolvedDestination.path)[.size] as? Int64) ?? 0
            return ConversionResult(
                outputURL: resolvedDestination,
                bytes: publishedSize,
                elapsedSeconds: Date().timeIntervalSince(started),
                width: checked.width,
                height: checked.height,
                frameCount: checked.frameCount,
                loopForever: checked.loopForever,
                warnings: plan.warnings
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = FFmpegProgressParser()

    func consume(_ line: String, expectedDuration: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return parser.consume(line: line, expectedDuration: expectedDuration)
    }
}
