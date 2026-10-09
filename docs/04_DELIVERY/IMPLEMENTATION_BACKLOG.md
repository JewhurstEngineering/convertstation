# Phased Milestones and Executable Backlog

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Sequencing and gates
### M0 — Skeleton & binary research
- Xcode target, swiftformat/swiftlint decision, unit test target, CI on macOS.
- Spike pinned FFmpeg build with MOV→animated WebP. Document binary architecture, signing, encoder availability, license consequences.
- Define ADRs for distribution/sandbox before committing integration.
**Gate:** manually produced animation can be decoded and looped; test sample documented.

### M1 — Source ingestion
- [ ] Drag/drop and NSOpenPanel imports
- [ ] source descriptor + ffprobe JSON parser
- [ ] unsupported file and permission states
- [ ] previews for MOV inputs
**Gate:** valid metadata for fixture set; UI remains responsive.

### M2 — Provider + request pipeline
- [ ] provider and capability registry
- [ ] request validation and option descriptors
- [ ] process runner (no shell interpolation)
- [ ] job state actor and monotonic progress
- [ ] temp output, validate, atomic publish
**Gate:** one MOV converts end-to-end from app with cancellation.

### M3 — Product-complete MOV → WebP
- [ ] presets and advanced controls
- [ ] destination chooser, output conflicts
- [ ] resulting preview and Finder reveal
- [ ] empty/failure/cancel/success polish
- [ ] keyboard accessibility and VoiceOver
**Gate:** all P0 FR acceptance criteria with recorded fixture evidence.

### M4 — Reliability and ship
- [ ] input fixture regression suite + automation
- [ ] leak/resource test, large input, thermal observation
- [ ] pin binaries + SBOM/license notices
- [ ] hardened runtime, signing, notarization or App Store submission plan
- [ ] accessibility and privacy review
**Gate:** clean install on supported Mac, works offline, signed release tested.

### M5 — Expansion (post v1)
ImageIO provider for PNG/JPEG/HEIC/TIFF, video→MP4, animated GIF, audio extraction, batch processing, saved workflows, Finder Quick Actions. Deliver one new provider per pull request with fixtures; refuse generalized conversion claims until verified.

## Task sizing and ownership
Organize issues by milestones and dependencies, not frontend/backend teams. Each issue includes description, non-goals, source/target fixtures, measurable acceptance, tests and demo proof. Estimate after an M0 spike; avoid invented calendar promises.
