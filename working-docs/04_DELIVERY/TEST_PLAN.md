# Test Strategy and Fixture Matrix

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Automated test layers
Unit: registry matching, schema validation, filename sanitization, destination collision, state-machine transitions, progress parser, ffprobe parser. Integration: local pinned binaries with gold fixtures, malformed files, cancellation, permission, disk-full, duplicate destination. UI: SwiftUI journey (drop, select, preset, destination, convert, result) with test doubles. Release: launch on clean Mac and verify signature and bundled deps.

## Fixture list
| ID | Source | Challenge | Expected |
|---|---|---|---|
| V01 | 5-second 1080p H.264 MOV | baseline | playable animated WebP |
| V02 | 30-second 4K HEVC MOV | scale & memory | output constrained to preset width |
| V03 | variable-frame-rate MOV | sampling | stable selected FPS |
| V04 | 90-degree rotated phone MOV | orientation | upright result |
| V05 | MOV with audio | format loss | audio removed with explicit warning |
| V06 | high-dynamic-range source | color | documented mapping, no unexpected blackout |
| V07 | 0.1-second source | one frame | handled as WebP image or explained |
| V08 | malformed/truncated MOV | error | failed job; no published garbage |
| V09 | MOV with transparency | alpha | preserve when encoder/path allows or disclose loss |
| V10 | MOV in read-only dir | security | conversion succeeds if destination writable |
| V11 | destination not writable | error | no source mutation |
| V12 | destination filename already exists | collision | explicit policy applied |

## Exit assertions
- Animation decodes; generated dimensions, FPS sampling and loop inspected.
- Never a source hash change. Check before/after SHA-256 for selected cases.
- After cancellation, child process stopped and output temp removed.
- Force quit/restart does not misreport previous converting jobs as successful.
- Settings invalid values are rejected before conversion begins.
- All required components can be controlled with keyboard and accessibility labels.

## Benchmarks
Compare wall-clock time, CPU, memory peak, final bytes, visual quality on baseline Mac models. Collect locally and attach fixture/result metadata to issues; no speculative performance claims.
