# ADR-002: The development app is sandboxed

**Status:** Accepted
**Date:** 2026-10-08

## Context

The first build left the sandbox off so a Homebrew FFmpeg outside the app could run. A sandboxed Mac app cannot execute that binary, and it cannot read `~/Downloads` or other user folders unless the person picked them.

## Decision

App Sandbox is on. The entitlements are user-selected read/write and app-scoped bookmarks. Drag and drop, the file picker, and the output folder are the only file access.

`scripts/bundle-ffmpeg.py` copies the local `ffmpeg` and `ffprobe`, plus the non-system libraries they link, into `Contents/Helpers` and `Contents/Frameworks` at build time. Those copies are not committed. Homebrew's SDL2 is sdl2-compat: it is not linked to SDL3, it dlopens `libSDL3.dylib` from the same Frameworks directory, and a missing library shows a fatal dialog plus a Dock icon for every launch. The script copies that library beside it. The tools are signed with the sandbox inherit entitlement so they stay inside the app's sandbox and can read the files the app was given. The app itself is ad-hoc signed by that script.

This is still the Homebrew 7.1.1 GPL build on this Mac. Bundling it into a local debug app is not clearance to distribute it.

Direct distribution is `scripts/release.sh` (Developer ID, notarization, Sparkle). The GPL FFmpeg gate is unchanged. The Mac App Store is still later, and it would need a license review of whatever FFmpeg actually ships.

## Consequences

Relaunching after this change can forget access to files chosen by the unsandboxed build. Drop them again, or pick the output folder again. If FFmpeg is missing at build time, the app still opens and says the engine is unavailable.
