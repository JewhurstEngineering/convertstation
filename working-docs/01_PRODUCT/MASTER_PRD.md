# Universal Converter for macOS
## Product Requirements Document + Architecture + Implementation Handoff

**Version:** 1.0 (planning)  
**Date:** October 8, 2026  
**Status:** Proposed  
**Initial platform:** macOS 14+; Apple Silicon primary, Intel where dependencies permit  
**First supported conversion:** MOV -> animated WebP

---

## 1. Executive summary

Build a polished, privacy-preserving macOS application that converts locally stored files between compatible formats. Users import by drag and drop or file picker, select a supported output format and conversion preset, optionally adjust type-specific settings, choose an output directory, preview results, and execute queued jobs. The first fully implemented path is MOV -> animated WebP; the conversion engine and type system must be reusable for later video -> video, image -> image, video -> image, and other carefully scoped file families.

**North star:** "Drop it. Choose a format. Convert it."

**Product principles:** local-first and offline; honest compatibility; excellent defaults; advanced control when wanted; nondestructive and deterministic outputs; extensibility without exposing implementation details; macOS-native fit and finish.

**Important boundary:** Universal means broad **supported** conversion capabilities, not that arbitrary formats can be converted to arbitrary others. A capability registry explicitly determines valid source -> target pairs and available options.

## 2. Problem and opportunity

Converting a QuickTime screen recording to an animated WebP should take seconds of interaction, not a trip through a terminal, a web upload service, or an unfamiliar professional editor. Existing conversion workflows can be hard to configure, opaque about output size, and awkward for batches. A self-contained native application can make common transformations predictable, visible, repeatable, and private.

**Target users:** (1) developers and designers producing website/app assets; (2) makers sharing demos and screen recordings; (3) content creators resizing/compressing media; (4) everyday Mac users needing quick conversion; (5) power users with recurring batch jobs.

**Primary jobs:** MOV screen recording -> looping animated WebP; HEIC -> PNG/JPEG; PNG/JPEG -> WebP/AVIF; MOV/MKV -> MP4; MP4 -> WebM; animated GIF -> animated WebP; video -> still frame(s).

## 3. Goals, non-goals, metrics

### Goals
1. Convert a compatible local MOV to animated WebP in <= 5 user interactions after opening the app, using a remembered output destination.
2. Provide reliable metadata, conversion constraints, sensible defaults, a clear progress state, usable errors, and accessible previews.
3. Support multiple files in a persistent queue and prevent accidental replacement or deletion of originals.
4. Make new conversions installable at the code level through format and converter registration, without rewriting the core workflow.
5. Work offline, without telemetry by default, cloud accounts, or automatic uploading.

### Non-goals for v0.1
- Arbitrary document conversions (DOCX/PDF/EPUB), OCR, or audio editing.
- Full nonlinear video editor, timeline effects, subtitles editor, or screen recorder.
- Uploading files to a cloud backend.
- Plugin marketplace or downloading third-party executables at runtime.
- Promise of universal codec compatibility or DRM conversion.
- Folder monitoring or automation rules (future phase).

### Success criteria (targets, not measured data)
- 100% of 20 curated, compatible MOV fixtures result in valid WebP or a clear unsupported-codec error.
- At least 95% of deliberately supported fixture conversions pass unattended.
- No original source file is modified or deleted by conversion.
- User can cancel any queued or active job, with partial outputs cleaned up.
- Output selection and settings have keyboard and VoiceOver support.
- Baseline sample output validated for dimensions, nonzero duration, frame count, loop behavior and decodability.
- Cold-start target < 2 sec on a recent Apple Silicon Mac (measure after implementation).

## 4. Product experience and navigation

### Main window
Use a macOS native three-region composition:
- **Top toolbar:** Add Files, Add Folder (later), Presets, History, Settings.
- **Main area:** empty-state drag/drop; once files exist, a queue/list with thumbnail, filename, type, size, duration/dimensions, output format, per-file status, progress, and actions.
- **Inspector sidebar:** selected file's conversion format, preset, setting groups, trim range, output settings, preview, estimated output size (when available; otherwise label unknown).
- **Bottom action bar:** destination folder picker, conflict policy summary, Convert All, Cancel, completed counts.

### Empty state
"Drop files to convert"; Browse Files action; short explanation "Everything happens on your Mac". Do not show output format controls until an input exists (or user chooses a saved preset).

### Import
- Drag and drop one or many files, use `NSOpenPanel`/SwiftUI importer, optionally Open With (later).
- Analyze each file asynchronously without blocking the UI.
- Show unsupported files with exact reasons, not silent exclusion.
- Detect type by content/probing and Uniform Type Identifiers when applicable; never trust extension alone.
- Dragging an input twice should display a duplicate indicator; offer keep both or skip based on preference.

### Format picker
- Group output formats by result: Animation, Video, Image/Frames (later Audio, Document).
- Filter destinations based on registered capabilities and input media characteristics.
- Examples MOV -> animated WebP, MP4, GIF, APNG, PNG/JPEG frame; PNG -> JPEG, WebP, AVIF, HEIC when encoder exists.
- "Why unavailable?" explains missing codec, alpha restrictions, unsupported media, etc.
- Mixed batch: offer "Apply where supported" and flag nonmatching jobs rather than forcing unsafe guesses.

### Output
- Default last-used destination; optional same folder or custom folder.
- Name template (phase 2): `{name}.{ext}`, `{name}-{preset}.{ext}`, `{name}-{index}.{ext}`.
- Conflict policies: Ask (default), Keep Both / auto-increment, Skip, Replace explicitly (with confirmation and safe staging). Never overwrite source; forbid source/output same path.
- Write to a temporary file on destination volume where possible; verify; atomically publish/rename when possible; preserve partial original on failures.
- Reveal in Finder, Quick Look, Copy Path, Convert Again.

### Preview
- Show source media playback and metadata before run.
- For MOV -> WebP, allow preview of the trimmed interval; generated WebP preview after first conversion. Pre-run preview may show approximate frames/quality and must not claim to exactly match final compressed output.
- Original vs converted side-by-side or before/after on completed jobs (phase 2).
- Output size can be "Unknown until encoded"; optionally run a bounded preview sample for a labeled **estimate** (later).

## 5. MOV -> animated WebP: launch capability

### Inputs
- MOV container when video stream is readable by bundled engine; video orientation honored; variable frame-rate supported; optional alpha when decoder/encoder supports it; input may contain audio (audio removed because WebP has none).
- Capture supported stream resolution, video duration, frame rate (average and nominal if different), pixel aspect ratio, rotation, audio presence, and color information where practical.
- Reject audio-only MOVs and DRM/protected/unreadable inputs with clear explanations.

### Output options
| Option | Default | Allowed range / meaning |
|---|---|---|
| Destination | Last selected directory | Any user-authorized writable folder |
| Preset | Balanced | Small File / Balanced / High Quality / Custom |
| Frame rate | 12 FPS | 5, 8, 10, 12, 15, 20, 24, 30; do not exceed source effective frame rate by default |
| Width | 800 px max | Original, 320, 480, 640, 800, 1024, 1280, custom |
| Aspect ratio | Preserve | Always default preserve; crop/stretch later |
| Trim start/end | Full video, subject to guardrails | Interactive time controls, start < end |
| Loop | Forever | Forever or finite loop count where supported |
| Quality | 75 | 0..100; mapped through tested engine settings |
| Lossless | Off | On/off; warn large output and slow encoding |
| Compression effort | Balanced | Fast / Balanced / Best; mapped to encoder knobs |
| Transparency | Preserve when compatible | Warn when input/codec cannot retain alpha |
| Metadata | Strip unnecessary metadata | Explicit privacy-forward default |
| Audio | Drop | Informational; animated WebP does not include audio |

These defaults are proposals to validate with real fixtures, not an established optimum.

### Resource guardrails
- Warn for videos > 30 s in initial UI; default cap 30 s for animated WebP v0.1, with an explicit override only if benchmarked safely.
- Warn on > 1280 px width, > 20 FPS, lossless, or high frame counts.
- Show predicted frame count = selected clip duration x FPS (approximate for varying timestamps); reject truly unsupported values.
- Cap output dimensions and frame count through explicit, configurable policies to prevent memory/CPU exhaustion, with human-readable explanations.
- Confirm whether a clip exceeds a configurable resource budget; reject jobs safely rather than crashing.

### Presets
| Preset | FPS | Max width | Quality | Use case |
|---|---:|---:|---:|---|
| Small File | 8 | 480 | 60 | Chat and README demos |
| Balanced | 12 | 800 | 75 | Web UI previews |
| High Quality | 20 | 1280 | 85 | Detailed polished demos |
| Custom | User | User | User | Fine tuning |

### Sample initial FFmpeg invocation (illustrative; verify exact bundled build)
```bash
ffmpeg -hide_banner -nostdin -y -i input.mov \
  -an -sn -dn -vf "fps=12,scale=800:-2:flags=lanczos,setsar=1" \
  -c:v libwebp_anim -lossless 0 -quality 75 \
  -compression_level 4 -loop 0 \
  -progress pipe:1 -stats_period 0.25 output.partial.webp
```

**Implementation caveats:** use an explicit WebP muxer/output format (`-f webp`) if using an intermediate `.partial` filename; otherwise FFmpeg may fail to infer the format. For MVP, construct a filter chain that respects encoded display orientation, preserves aspect ratio and alpha when supported, and uses a legal pixel format. Test actual animated WebP output: encoder behavior, looping, timestamps, transparency and playback vary by build. Consider `scale=800:-2` only when intended to enforce a fixed width; for max width without upscaling choose a conditional scale expression and validate positive even dimensions. Use direct `Process` argument arrays, not a shell string.

**Canonical application command shape:**
```bash
ffmpeg -hide_banner -nostdin -y -ss START -i INPUT -t DURATION \
  -an -sn -dn -vf FILTER_CHAIN \
  -c:v libwebp_anim -lossless 0 -quality 75 -compression_level 4 \
  -loop 0 -f webp -progress pipe:1 -stats_period 0.25 OUTPUT_TEMP
```
`-ss` placement impacts accuracy/performance, so test the chosen seek strategy and prefer frame-accurate trim results. Never use `-y` against the final destination before conflict handling; only target an isolated temporary file. Avoid applying a non-alpha-compatible filter or pixel format to alpha inputs if alpha preservation is promised.

### MVP acceptance criteria (MOV/WebP)
1. Given a 12-second MOV, when user chooses Balanced, then output is a valid animated WebP at configured dimensions and target FPS.
2. Given audio in MOV, then exported WebP has no audio and UI identifies that limitation before conversion.
3. Given portrait/rotated MOV, output orientation and aspect ratio display correctly.
4. Given user trim 2s..6s, output animation duration is ~4s within frame-timing tolerance.
5. Given a default looping preset, animation loops in common compatible viewers.
6. Given cancellation, running engine terminates, staged output is removed, and original remains unchanged.
7. Given a preexisting output filename, Ask / Keep Both / Skip / Replace behavior matches selected policy.
8. Given an unsupported codec, the UI provides filename, what failed, and a useful next action.
9. Given two conversions, queue performs them in order (v0.1 concurrency one) without UI blocking.
10. Given app restart, chosen destination/presets persist where access remains authorized; interrupted work is marked interrupted and retryable.

## 6. Supported-format rollout and explicit matrix

**Legend:** V0.1 first deliverable; V0.2 next; V0.3 later; Research requires feasibility and licensing investigation.

| Input | Output | Phase | Engine candidate | Notes |
|---|---|---|---|---|
| MOV | animated WebP | V0.1 | FFmpeg + libwebp_anim | First vertical slice |
| MP4/MKV/WebM | animated WebP | V0.2 | FFmpeg | Reuse same recipe if decoders supported |
| MOV/MP4/MKV | MP4 (H.264/AAC) | V0.2 | FFmpeg or AVFoundation | Codec support/license review |
| MOV/MP4 | WebM (VP9/Opus) | V0.3 | FFmpeg | Additional encoder configuration |
| MOV/MP4 | GIF | V0.2 | FFmpeg | Palette generation for quality |
| Video | PNG/JPEG still image | V0.2 | FFmpeg | Select timestamp |
| Video | PNG image sequence | V0.3 | FFmpeg | Folder output; naming and count control |
| HEIC/JPEG/PNG | PNG/JPEG | V0.2 | ImageIO/CGImageSource | Honor ICC profile and orientation |
| PNG/JPEG/HEIC | WebP | V0.2 | ImageMagick/libwebp | Static image recipe |
| PNG/JPEG/HEIC | AVIF | V0.3 | ImageMagick/libavif | Test runtime codec build |
| GIF | animated WebP | V0.3 | FFmpeg/ImageMagick | Preserve frame timing and loop semantics |
| WebP | GIF/APNG | V0.3 | FFmpeg/ImageMagick | Preserve animation where possible |
| SVG | PNG/WebP | Research | resvg / CoreGraphics bridge | SVG renderer/security required |
| PDF | image pages | Research | PDFKit + ImageIO | Per-page output; separate category |
| WAV/FLAC/AIFF | MP3/M4A/OGG | Research | FFmpeg | Distinct audio UI, licensing |
| DOCX/PDF/etc. | Other docs | Outside current scope | separate providers | Semantic fidelity concerns |

Never advertise a conversion unless the installed engine reports it can perform it. Validate encoder/decode capability at startup or from a packaged capability manifest tied to build.

## 7. Functional requirements (prioritized)

| ID | Requirement | Priority | Completion evidence |
|---|---|---|---|
| FR-01 | Multi-file drag/drop and file picker | P0 | Multiple files enter queue |
| FR-02 | Async probing and metadata display | P0 | Duration, dimensions, source type shown |
| FR-03 | Capability-based valid output picker | P0 | Invalid pairs unavailable and explained |
| FR-04 | MOV -> animated WebP preset engine | P0 | Valid playable output |
| FR-05 | User-selectable output directory | P0 | Output saved with sandbox access |
| FR-06 | Trim/FPS/size/quality/loop controls | P0 | Controls reflected in output |
| FR-07 | Queue, progress, cancel, retry | P0 | Jobs independently track states |
| FR-08 | File conflict handling | P0 | Zero accidental overwrites |
| FR-09 | Errors and engine diagnostic access | P0 | User-facing error plus redactable log |
| FR-10 | Open/Reveal output in Finder | P0 | Finder opens correct file |
| FR-11 | Persist last destination and recent presets | P1 | Settings survive restart |
| FR-12 | Output preview and size reporting | P1 | Result view after conversion |
| FR-13 | Batch same settings and per-file override | P1 | Overrides persist per queued job |
| FR-14 | Saved named presets | P1 | Create/edit/delete/recall |
| FR-15 | Conversion history | P1 | Stored without retaining source bytes |
| FR-16 | More video/image conversions | P1 | Registry expands, same UX |
| FR-17 | Finder Quick Action / Share extension | P2 | Convert from Finder |
| FR-18 | Folder watch and auto-convert rules | P2 | Permissioned/background, clear opt-in |
| FR-19 | CLI/headless conversion interface | P2 | Shared conversion service and recipes |
| FR-20 | Optional user-installable plugin SDK | P3 | Threat model and isolation first |

## 8. Nonfunctional requirements

**Privacy/security:** zero network use required for conversion; no file telemetry; no covert upload; sandbox access limited to user-picked input/output; limit memory/CPU/frame count; handle maliciously crafted media; no shell evaluation; treat paths as opaque Unicode; normalize for conflict checks without mangling; avoid leaking full file paths in telemetry; logs redact paths on export; verify engine integrity and code signing.

**Reliability:** async UI always responsive; bounded queues; no corrupt final files after crash; atomic publish where possible; per-job retry; on launch detect interrupted items and pending temp files; no automatic deletion of inputs.

**Performance:** bounded concurrent conversions (start at one video conversion; explore two for small image jobs); low-priority thumbnails; cancellation within 2 seconds target for responsive engine; do not load full video into RAM; system power/thermal impact documented.

**Accessibility:** VoiceOver labels for file rows, format selector, controls, and progress; full keyboard path; Dynamic Type where practical on macOS, reduced-motion support, sufficient contrast.

**Distribution:** signed and notarized direct-download build first. Assess Mac App Store separately, especially FFmpeg bundling/sandbox compatibility, codecs, GPL/LGPL obligations, and content licensing.

## 9. Technology and architecture

### Recommended implementation
- **UI:** Swift 6, SwiftUI, select AppKit APIs for file pickers, previews, advanced table/drag/drop behavior.
- **System services:** Foundation, UniformTypeIdentifiers, AVFoundation/VideoToolbox where practical, ImageIO/CoreGraphics for image operations.
- **Conversion:** FFmpeg + ffprobe as a **bundled, version-pinned, vetted** engine for first implementation; ImageIO native for common images; optional ImageMagick/libwebp/libavif later for specialty formats.
- **Persistence:** Codable JSON/UserDefaults for preferences; SwiftData or SQLite for queued/history jobs when needs grow. Keep schema migrations explicit.
- **Concurrency:** Swift structured concurrency for orchestration; `Process` for tool invocation with piped progress and diagnostic output, hard timeouts and cancellation.
- **Packaging:** Xcode, signed embedded helper/engine with licensing notices and source/build information; CI verifies architectures, signatures, hashes and capabilities.

### Design rule: pluggable *converter providers*, not arbitrary files
Providers are compiled-in, audited adapters selected through an explicit registry. The user must never be able to inject raw FFmpeg arguments in v0.1. Later advanced settings may be validated structured options; never shell interpolation.

### Conceptual components
```
SwiftUI screens / ViewModels
          |
ImportCoordinator ---- FileAccessManager (security-scoped URLs/bookmarks)
          |
MediaProbeService ---- FileTypeDetector
          |
CapabilityRegistry ---- ConversionPresetStore
          |
ConversionPlanner (validation + deterministic output plan)
          |
JobQueue / Scheduler ---- JobStore
          |
ConversionExecutor / ProcessSupervisor
          |                      |
FFmpegProvider           ImageIOProvider (later)
          |
StagingOutputManager -> OutputVerifier -> AtomicPublisher
          |
History / Diagnostics / Finder actions
```

### Candidate protocols (Swift-like pseudocode)
```swift
struct FormatID: Hashable, Codable { let rawValue: String }
struct InputDescriptor: Codable {
    let url: URL
    let detectedFormat: FormatID
    let durationSeconds: Double?
    let width: Int?
    let height: Int?
    let hasAudio: Bool
    let hasAlpha: Bool?
}
struct ConversionRecipe: Codable {
    let source: FormatID
    let destination: FormatID
    let providerID: String
    let options: [String: CodableValue] // define tagged Codable enum
}
struct ConversionRequest {
    let input: InputDescriptor
    let recipe: ConversionRecipe
    let outputDirectory: URL
    let namingPolicy: NamingPolicy
    let conflictPolicy: ConflictPolicy
}
protocol ConversionProvider {
    var id: String { get }
    func capabilities() async throws -> [ConversionCapability]
    func validate(_ request: ConversionRequest) async throws
    func execute(_ request: ConversionRequest,
                 progress: @escaping (ConversionProgress) -> Void) async throws -> URL
    func cancel(jobID: UUID) async
}
```
**Note:** this illustrates boundaries, not compile-ready Swift. Use versioned, type-safe option models per recipe rather than unstructured dictionaries when implementing. A data model should distinguish path/bookmark handles from serializable jobs.

### Core domain models
- `MediaType`: video, stillImage, animatedImage, audio, document (future)
- `FormatDefinition`: format ID, extensions, UTTypes, MIME types, container/codec constraints, canRead/canWrite
- `ConversionCapability`: accepted source constraints, target, provider, options schema, compatible preset IDs
- `MediaProbe`: streams, frame data, color/alpha, orientation, source properties and warnings
- `ConversionRecipe`: selected format + typed parameters and version
- `ConversionJob`: UUID, source security reference, output folder security reference, recipe snapshot, state, created/started/completed timestamps, progress, result location, diagnostics
- `JobState`: importing, probing, ready, queued, running, verifying, completed, failed, cancelled, interrupted, blockedByPermission
- `Preset`: ID, name, format pairing or generic media family, typed options, schema version
- `OutputPlan`: filename/extension, staging path, final destination, conflict resolution, resource estimate

### Job state machine
`importing -> probing -> ready -> queued -> running -> verifying -> completed`
Alternative terminal paths: `failed`, `cancelled`, `blockedByPermission`; stale `running` on next boot becomes `interrupted`, never silently resumed to produce duplicates. The user can retry after revalidation. Job transitions must be validated and persisted.

### Security-scoped file access
Open panels and drag/drop grant access under Apple's sandbox rules. Persist permissions for last-used folders and history via security-scoped bookmarks as needed; reacquire and handle stale bookmarks. Request only necessary entitlements. Access tokens must remain valid for the lifetime of the external conversion helper; test helper access explicitly under actual app sandbox and signed release packaging. For v0.1, prioritize predictable, user-approved paths. Optional fallback: copy selected source into the app's sandbox temporary directory if external process access fails or bookmarks cannot be reliably shared, but warn about disk use and clean afterward. Confirm external helper execution is permitted from inside the signed bundle and App Sandbox.

### Progress and cancellation
Use FFmpeg's `-progress pipe:1` output (key=value frames, time, speed, end). Normalize displayed percentage against *selected trim duration*, clamp 0..100, and use indeterminate progress when duration unknown. Drain stdout and stderr concurrently to avoid pipe deadlocks. Keep ring-buffer logs with size limits. On cancel: request graceful termination, escalate if unresponsive, reap process, remove staging artifacts, persist cancelled state. Never guess completion from only `progress=end`; verify exit code and output.

### Output verification
For animated WebP, confirm non-empty file, decode/probe at least metadata, expected width/height bounds, expected duration tolerance, animation frames > 1 for multi-frame input, loop settings, and optional alpha preservation if requested. Treat metadata anomalies as explicit verification failures; don't promote staged file to final path.

### Build and licenses
FFmpeg license depends on build configuration, linked libraries, and codecs. FFmpeg core is usually LGPL; enabling certain optional components can make a binary GPL; other nonfree restrictions may apply. Record exact configure flags and per-dependency licenses; publish required notices and sources/build instructions as applicable; have release counsel or licensing specialist review distribution obligations before public shipping. Do not assume a Homebrew-installed binary can be redistributed unchanged or that commercial distribution is automatically forbidden. Relevant sources: https://ffmpeg.org/legal.html and https://www.ffmpeg.org/ffmpeg-codecs.html .

## 10. Detailed epic breakdown and milestones

### Phase 0 — Foundation and feasibility (2–4 working days, estimate)
**Outputs:** fresh Xcode repo, CI, app shell, engine feasibility spike, sample MOV -> animated WebP validated with real binaries.
- Decide provisional name/bundle ID/target OS and architecture.
- Create representative fixture set (screen recording, portrait, variable FPS, alpha, bad codec, zero-length, 4K, very short clip).
- Produce MOV -> WebP with pinned FFmpeg build. Verify duration, loop, size, alpha and different players.
- Determine packaging of FFmpeg in signed app, helper sandbox access, notarization expectations and licensing checklist.
- Write capability/recipe contracts and ADR-001 (why adapters instead of one universal command builder).
**Exit:** successful repeatable conversion via CLI, successful code signing plan, feasible distribution strategy.

### Phase 1 — Functional MVP (5–10 working days, estimate)
**Outputs:** macOS GUI delivering reliable conversion from local MOV to animated WebP.
- Build drop zone, file picker, queue rows, metadata probe, format selector, inspector.
- Build preset engine, trim, FPS, max width, quality, loop, destination folder.
- Build `ConversionPlanner`, job queue, FFmpeg provider, safe output/staging/publish.
- Build progress, cancellation, retry, clear errors and Finder reveal.
- Create unit + integration + first UI tests; validate error flows.
**Exit:** all v0.1 acceptance criteria on fixtures, no source modification.

### Phase 2 — Beta polish + first image conversions (5–10 working days, estimate)
- Post-conversion WebP preview and original/result comparison.
- Persistent job history, bookmark migration, restart handling, presets.
- HEIC/JPEG/PNG -> JPEG/PNG/WebP; MP4 -> WebP; MOV -> MP4 as engines permit.
- Batch apply/override settings, conflict policy UX, accessibility pass.
- CPU/memory benchmark, warnings, signing/notarization and release checklist.
**Exit:** usable daily-driver beta with 6+ verified paths, not an unbounded format claim.

### Phase 3 — Expanded formats and workflow (variable)
- MP4/WebM/GIF/APNG/AVIF and image sequences according to QA matrix.
- Batch output naming templates; conversion recipe import/export.
- Finder Quick Action/Services, open-with handling, optional CLI using same engine.
- Optional advanced compression profiles, last-used recent folders.
- Evaluate background conversion, concurrency by resource budget, power handling.

### Phase 4 — Automation & ecosystem (optional)
- Watched folders with opt-in and robust access lifecycle.
- Repeatable workflows, rules and preset pipelines (e.g., downscale -> WebP).
- Optional open-source provider SDK after sandbox/security design.
- Investigate document/audio conversion as separate feature families, not automatically included.

## 11. Prioritized engineering backlog

| ID | Work item | Estimate | Dependency | Definition of done |
|---|---|---|---|---|
| CONV-001 | Bootstrap SwiftUI app + macOS target | S | - | Runs on clean macOS environment |
| CONV-002 | Pin/bundle FFmpeg + ffprobe | M | 001 | Reproducible signed helper, documented licenses |
| CONV-003 | Conversion fixture suite | M | 002 | Fixture manifest and expected properties |
| CONV-004 | Type/capability registry | M | 001 | Tests for valid/invalid pairs |
| CONV-005 | File import, DnD, permissions | M | 001 | Multi-import and security test |
| CONV-006 | Media probe and metadata | M | 002,005 | Typed descriptor with reliable failures |
| CONV-007 | Main queue + selected inspector | M | 004,005 | Keyboard/VoiceOver navigation |
| CONV-008 | MOV -> WebP recipe and presets | M | 002,004 | Validated arguments, preset tests |
| CONV-009 | Destination/bookmark/conflicts | M | 005 | No source overwrite; folder access robust |
| CONV-010 | Process supervision and progress | L | 002 | No pipe deadlocks; progress, cancel, logs |
| CONV-011 | Queue states/persistence | M | 010 | Crash/restart marks interrupted |
| CONV-012 | Staging/verification/publish | L | 009,010 | No invalid final output |
| CONV-013 | Errors, retry, Finder reveal | S | 011,012 | Recoverable flows explained |
| CONV-014 | Automated unit/integration/UI tests | L | 006-013 | Tests run in CI with fixture assertions |
| CONV-015 | Preview and postconversion compare | M | 012 | Animated WebP playback verified |
| CONV-016 | ImageIO provider + static images | L | 004,012 | Color/orientation QA matrix |
| CONV-017 | Beta distribution and licensing audit | L | 002,014 | Signed, notarized, notices included |

**Estimate legend:** S ~ 0.5–1.5 days, M ~ 2–4 days, L ~ 4–8 days. These are planning estimates, not commitments; work can overlap and depend heavily on codec packaging and macOS sandbox testing.

## 12. Testing plan

### Unit
- Format detection, capability registration, option validation, preset schema versioning.
- FPS/frame estimate, aspect ratio/size logic, trim validation, safe output naming.
- Job state transitions, failure mapping, conflict decisions, history serialization.

### Integration
- Short/long MOV, VFR, 30/60fps, 4K, portrait, rotation, alpha, color profiles, audio, damaged source, no video stream.
- Spaces, Unicode, parentheses, apostrophes, non-ASCII and long paths.
- Large files and insufficient disk space; read-only destination; revoked bookmarks.
- Fail midway, cancel midway, kill app/engine, retry, concurrent file import.
- User selects same file with two distinct recipes; duplicate source remains intact.
- File with misleading extension, malformed data, nonseekable/restricted file.

### Output assertions
- File signature and decodability; output format matches target; dimensions and pixel aspect; frame count; duration; repeat count; audio absence; expected file size limits where reasonable.
- For still image conversions: orientation, alpha, color profiles, EXIF privacy policy and visual diff/regression.

### Release QA
- Fresh machine without Homebrew/FFmpeg installed.
- Notarized release package on Apple Silicon; Intel build if supported.
- Sandbox access to Desktop/Documents/external drives and permission denial.
- VoiceOver, keyboard-only, dark/light appearance, offline use.
- Thermal/load smoke tests; data retention and no-network claims verified.

## 13. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| FFmpeg licensing/build combinations | High | Pinned audited build, BOM, notices, legal review |
| Bundled FFmpeg + sandbox/file access | High | Phase 0 signed spike, helper permissions test |
| Animated WebP encoder quirks | High | Fixture validation of timestamps, loop, alpha, muxer |
| Output enormous or conversion too slow | High | Defaults, caps, resource estimates, warnings |
| Wrong orientation/color/alpha | High | Media probe and golden output QA |
| User input modified/overwritten | Critical | Stage + validate + deliberate publish; destructive actions never implicit |
| Malformed media exploits native decoder | High | Update cadence, sandbox, resource limits, restricted helpers |
| Format promise exceeds installed codecs | Medium | Per-build capability manifest, exact unsupported explanations |
| Long-running app hangs | Medium | Async queue, timeouts, bounded logs, monitoring |
| Duplicate output names in batch | Medium | deterministic conflict resolver and reservations |

## 14. Decisions to make (recommended defaults supplied)

1. **Name:** working title **ConvertKit for Mac** is descriptive but may conflict with established trademarks; use internal codename `ForgeConvert` until clearance, or choose another original name. Do not publish branding before screening.
2. **Target:** macOS 14+, native SwiftUI, Apple Silicon-first, Intel best-effort after feasibility tests.
3. **Distribution:** direct signed/notarized `.dmg` first; revisit App Store after licensing/sandbox checks.
4. **Privacy:** all conversions local; no account, no ads, no telemetry by default.
5. **Bundling:** bundled pinned FFmpeg rather than user-installed prerequisite; audited distribution.
6. **First conversion:** MOV -> **animated** WebP (not single still frame).
7. **Conversion defaults:** Balanced 12 FPS, 800 px maximum width, Q75, infinite loop.
8. **Batch mode:** one active video job, unlimited queued jobs within reasonable storage limits.
9. **Presets:** Small/Balanced/High/Custom, versioned and recipe-specific.
10. **Permissions:** user-approved source/output, security-scoped bookmark persistence.
11. **Output handling:** never modify input; stage, validate, then publish with explicit conflict behavior.
12. **CLI and Finder actions:** after beta, reuse same application-layer services.

## 15. Suggested repository structure

```
UniversalConverter/
  App/
    UniversalConverterApp.swift
    AppDependencies.swift
  Features/
    Import/
    Queue/
    Inspector/
    Presets/
    History/
    Settings/
  Core/
    Models/
    Capabilities/
    ConversionPlanning/
    JobQueue/
    FileAccess/
    OutputManagement/
    Diagnostics/
  Providers/
    FFmpeg/
      FFmpegProvider.swift
      FFprobeService.swift
      FFmpegProgressParser.swift
      FFmpegCommandBuilder.swift
    ImageIO/
  Resources/
    ConversionPresets/
    EngineManifest.json
  Helpers/
    ffmpeg
    ffprobe
  Tests/
    Unit/
    Integration/
    UI/
    Fixtures/
  docs/
    PRD.md
    Architecture.md
    ConversionMatrix.md
    Decisions.md
    QA.md
    Licenses.md
  .github/workflows/
```

Use a dedicated Swift Package for the Core and Provider protocols where appropriate; do not couple SwiftUI to FFmpeg flags. Binary/helper locations may need to follow valid Xcode bundle and code-signing conventions rather than the example tree verbatim.

## 16. Implementation handoff prompt for Cursor / Codex

> Build a production-minded, local-first, native macOS SwiftUI application using the supplied PRD as the product authority. Start with **only one supported end-to-end conversion: MOV -> animated WebP**. The code architecture must support providers/capabilities and typed format-specific option schemas for future file families, but do not implement unrelated conversions before first-path tests pass.
>
> First: inspect the repo and current macOS target; document constraints. Then create a Phase 0 ADR for conversion engine packaging and license compliance; pin an auditable FFmpeg+ffprobe build; prove a signed/sandboxed app can import a MOV, launch the bundled engine, write to a user-chosen destination, and validate the output on a clean Mac. If anything is uncertain, note an explicit blocker rather than simulating success.
>
> Next implement in vertical slices: import/probe -> capability picker -> preset inspector -> output location/conflict policy -> queue and Process supervision -> progress/cancel -> staging/verification -> Finder reveal and user-friendly errors. Keep file reading/writing isolated to FileAccessManager and OutputManager. Protect originals in every code path. Do not concatenate shell commands: invoke `Process` with absolute binary URL and sanitized argument arrays. Concurrently consume stdout and stderr and enforce cancellation/timeouts. Include versioned preset and recipe models and unit tests of command construction.
>
> Validate using synthetic and real fixture MOVs covering portrait orientation, variable FPS, embedded audio, damaged files, odd filenames, duration trimming, looping, unusual color/alpha, disk errors, and cancel/retry. Ensure no conversions require network access or Homebrew. Use accessible SwiftUI components, clear failure details and keyboard support.
>
> Deliver (1) working Xcode project, (2) tests and fixture generation instructions, (3) README build/run/install steps, (4) exact pinned engine versions and third-party licenses, (5) updated conversion capability matrix, (6) a record of decisions and limitations, and (7) screenshots or short demo of the complete MOV -> WebP interaction. Never claim a feature is done without demonstrating a passing test or human-verifiable outcome. Implement subsequent phases only after acceptance criteria pass.

## 17. Documentation and source references

These official sources inform technology choices; they do not establish that the finished app has been implemented:
- Apple: Accessing files from macOS App Sandbox — https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- Apple: SwiftUI fileImporter — https://developer.apple.com/documentation/swiftui/view/fileimporter(isPresented:allowedContentTypes:onCompletion:)
- FFmpeg: codec reference (`libwebp` options) — https://ffmpeg.org/ffmpeg-codecs.html
- FFmpeg: command-line progress — https://www.ffmpeg.org/ffmpeg.html
- FFmpeg: legal and license considerations — https://www.ffmpeg.org/legal.html
- ImageMagick: supported input/output formats (delegates matter) — https://imagemagick.org/formats/
- ImageMagick: WebP controls — https://imagemagick.org/webp/

---

## 18. What I would actually ship first

Deliver a small, *excellent* tool that converts screen recordings: drag/drop MOV, choose Animated WebP, select Small/Balanced/High preset, optional trim, choose output folder, click Convert, see progress, view result, reveal in Finder. Underneath, implement type/option registry, safe output publishing, robust queue, and a provider abstraction from day one. Then add MP4 -> WebP and HEIC/PNG/JPEG conversions without altering the app's core workflow. This keeps scope manageable while proving the architecture.
