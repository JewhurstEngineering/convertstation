# System Architecture

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Tech stack
Native Swift 6, SwiftUI, Foundation, AppKit (Finder/open panels), AVFoundation for preview and supplemental metadata where useful, FFprobe for reliable stream inspection, FFmpeg with `libwebp_anim` for the first provider; SQLite or Codable-backed storage for history, UserDefaults for small preferences. macOS 14+; Apple Silicon primary. Decide Intel support after validating distribution of bundled binaries.

## Component map
```text
SwiftUI Views -> AppViewModel -> ConversionCoordinator actor
                          |-> FileAccessManager (security scoped URLs)
                          |-> MediaInspector (ffprobe JSON)
                          |-> CapabilityRegistry (providers/formats/settings)
                          |-> JobStore (state and history)
                          |-> ProcessRunner (child process; progress stderr/stdout)
                          |-> OutputPublisher (validate, move, conflicts)
                          |-> PreviewService (AVKit/QuickLook, when supported)
```

## Boundaries
Presentation layer knows only capabilities and typed view models. ConversionCoordinator enforces state transitions and concurrency. Provider supplies input predicates, target metadata, setting schema, command construction and output validation. ProcessRunner is the only location that starts binaries. FileAccessManager owns scope start/stop with balanced lifetime. JobStore saves serializable metadata, never raw sandbox handles.

## Domain models
```swift
enum JobState: Codable { case queued, inspecting, ready, converting, validating, completed, failed, cancelled }
struct SourceDescriptor: Codable { let url: URL; let detectedUTType: String; let durationSeconds: Double?; let width: Int?; let height: Int?; let hasVideo: Bool; let hasAudio: Bool }
struct ConversionRequest: Codable { let id: UUID; let sourceURL: URL; let targetFormatID: String; let presetID: String?; let options: [String: CodableValue]; let destinationURL: URL; let collisionPolicy: CollisionPolicy }
struct ConversionResult: Codable { let outputURL: URL; let bytes: Int64; let elapsedSeconds: Double; let warnings: [String] }
```
Typed option schemas should replace unsafe dictionary access at each provider boundary. `CodableValue` is an app-owned enum (string/int/double/bool) with validation; do not directly accept arbitrary flags.

## Lifecycle and persistence
On import detect rather than trust extensions. On Convert, capture immutable request, acquire URL access, create per-job temp location **on destination volume** where possible, run provider, validate, atomically publish, release access, write terminal job state. Persist queued metadata but after restart mark interrupted jobs as interrupted/retryable; never pretend a process continued. Handle sleep/wake, app termination, ejecting volumes, stale bookmarks and temp cleanup.

## Concurrency policy
Start with concurrency limit 1 by default; configurable 1–2 only after measured memory/thermal testing. Actor serializes mutation. Cancellation maps to SIGTERM with time-limited escalation to SIGKILL, waits for child exit, and removes partial temp files. All process events tagged with immutable job ID.

## ADRs needed
ADR-001 process executable packaging and codesigning; ADR-002 sandbox/App Store vs notarized direct distribution; ADR-003 animated preview rendering; ADR-004 job store implementation; ADR-005 output replacement transaction semantics.
