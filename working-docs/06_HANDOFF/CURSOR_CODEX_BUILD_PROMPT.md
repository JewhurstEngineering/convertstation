# Implementation Agent Handoff

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Paste into Cursor or Codex
You are the engineering agent for a native macOS SwiftUI conversion app. The docs in this folder are authoritative, starting with `README.md` and `01_PRODUCT/MASTER_PRD.md`. Implement the milestones sequentially. Start with a repository audit: current structure, targets, Swift toolchain, existing binaries, tests and outstanding ADRs. Do not invent finished functionality.

### Non-negotiable rules
1. First deliver a tested MOV→animated WebP vertical slice; do not introduce extra output formats as placeholders.
2. Keep conversion execution out of SwiftUI views; provider capability registry is mandatory.
3. Use security-scoped file handling where needed; source untouched; destination atomic publish after validation.
4. Use `Process` with argv, never interpolated shell commands. FFmpeg and FFprobe locations must be pinned or validated.
5. Unit/integration tests accompany every feature; build and test on supported macOS environment. If macOS toolchain unavailable, explicitly report untested steps.
6. All supported choices must be driven by registry and inspected source; unsupported codecs/alpha/HDR behavior must be surfaced.
7. Any changed requirement must update docs and ADR; do not silently expand scope.

### First deliverable
Implement M0 spike and M1 ingestion with the main window, drag/drop, file picker, source inspection parser and a mock provider registry. Add Swift tests and sample fixtures documentation. After build/test, report changed files, demonstrated behavior, known limitations and the next milestone. Proceed toward M2 once blockers are resolved.

### Completion definition
User can import MOV; inspect; select Animated WebP, preset, FPS, dimensions, trim and quality; choose destination; convert; monitor genuine progress; cancel; see output stats; preview result; reveal in Finder. Fixture suite confirms playable WebP and clean error/cancellation handling.
