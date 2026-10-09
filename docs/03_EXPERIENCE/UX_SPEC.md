# UX, Screens and Interaction Specification

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Screen inventory
**Drop Zone / Queue:** large drag/drop target, Add Files, per-file name/type/size/dimensions/duration, status, remove button, grouping and reorder. **Inspector:** source metadata, output format, presets, settings with contextual help. **Destination:** folder picker, last folder, output filename pattern, collision strategy. **Conversion:** single prominent start button, job-level progress, pause unsupported in v1 (show cancel), errors. **Result:** output size and percent delta (may be positive), preview, Finder reveal, Convert Again. **Preferences:** defaults, privacy explanation, licenses, advanced tool diagnostics.

## Guided workflow
1. User drops one or multiple files.
2. App checks each source; unsupported files stay visible with error state.
3. On choosing one item, app reveals valid output formats from registry.
4. User chooses format and preset; optional Advanced expands valid settings.
5. User chooses destination once or per-file; app validates permissions and collisions.
6. User starts; items update independently with accurate states.
7. Results show actual sizes and access to generated output; partial failures can be retried without redoing successful jobs.

## Detail interactions
- Multiple file selection: apply target settings to compatible files, leave incompatible ones unchanged and explain why.
- Mixed media batches: support per-row target and output location, with batch default overlay in P1.
- Output naming: `{originalName}.{targetExtension}`, with customizable suffix in later versions; prevent directory traversal and reserved names.
- App closes during conversion: confirm cancel, or define explicit policy before release; no invisible background claims.
- Keyboard: Cmd+O import, Cmd+Return convert, Delete remove selected, Space preview, Cmd+, preferences; verify conflicts with native behavior.
- Accessibility: all progress announced appropriately; respect Reduce Motion; VoiceOver labels are not inferred solely from filename icons.

## Edge states
Missing input, unsupported format, unreadable codec, source changes between inspection and run, stale folder bookmark, denied output folder, no disk space, overwritten output conflict, FFmpeg failure, validation failure, cancellation, external volume ejection. Every failure has a user-directed recovery action and optional technical details with private paths redacted for sharing.

## Design principle
A polished desktop utility, not a terminal wrapper. Default single-window layout, native macOS toolbar and sidebar only if it increases clarity. Use light/dark semantic colors; avoid designing for only one theme.
