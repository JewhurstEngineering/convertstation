# Extensible Conversion Engine Specification

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Capability-based approach
Each provider registers `(source predicates, target format ID, option schema, output validator)`. The UI calls registry to obtain verified targets for an inspected source. Do not implement every input/output combination as a giant switch. Support capabilities as directed edges in a graph; do **not** automatically chain two lossy edges without explicit user consent.

## Proposed protocol
```swift
protocol ConversionProvider: Sendable {
  var id: String { get }
  func canRead(_ source: SourceDescriptor) -> Bool
  func availableTargets(for source: SourceDescriptor) -> [TargetDescriptor]
  func settingsSchema(for targetID: String) -> [OptionDescriptor]
  func validate(_ request: ConversionRequest, source: SourceDescriptor) throws
  func makePlan(_ request: ConversionRequest, source: SourceDescriptor, temporaryOutput: URL) throws -> ExecutionPlan
  func validateResult(at url: URL, request: ConversionRequest) async throws -> ValidationResult
}
```
`ExecutionPlan` contains executable location, argv array, expected progress time base, timeout policy, and redactable diagnostic settings. `TargetDescriptor` includes extension, MIME/UTType, supportsAnimation, supportsAlpha, supportsAudio, provider ID. Reject conflicting provider capabilities deterministically.

## Registry acceptance
- Cannot select output while source has not been inspected.
- Animated WebP is shown only with a decodable video stream.
- Provider errors become user messages with technical disclosure behind Details.
- Internal raw encoder parameters never leak into the view model.
- Unit tests register mock image and mock audio providers without touching SwiftUI.

## Future provider plan
| Phase | Family | Targets | Candidate engine |
|---|---|---|---|
| P0 | Video → animation | WebP | FFmpeg `libwebp_anim` |
| P2 | Video → video | MP4, MOV, WebM | FFmpeg |
| P2 | Image → image | PNG, JPEG, TIFF, HEIC | ImageIO / CoreImage |
| P2 | Animation ↔ video | GIF, WebP, MP4 | FFmpeg + webp tools |
| Later | Audio → audio | MP3, M4A, WAV, FLAC | FFmpeg / AVFoundation |
| Later | Documents | Selected PDF workflows | PDFKit / specialized libraries |

## Encoder support runtime checks
At installation/first launch, inspect embedded binary supported encoders and muxers (or build manifest); cache capability verification and fail gracefully if the expected `libwebp_anim` encoder is missing. Pin and audit all binary versions.
