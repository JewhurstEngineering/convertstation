# ADR-001: FFmpeg is located, not vendored, in this build

**Status:** Accepted
**Date:** 2026-10-08

## Context

MOV to animated WebP needs `ffmpeg` and `ffprobe` with the `libwebp_anim` encoder. The app must not shell out, and it must not pretend a conversion exists when the encoder is missing.

## Decision

The development app looks for a bundled `ffmpeg` / `ffprobe` first, then `/opt/homebrew/bin`, then `/usr/local/bin`. Startup runs `ffmpeg -encoders` and only offers Animated WebP when `libwebp_anim` is present. No binary is committed.

On this machine the located build is Homebrew FFmpeg 7.1.1 (`--prefix=/opt/homebrew/Cellar/ffmpeg/7.1.1_1`). That build is GPL (`--enable-gpl`, including libx264, libx265, and others) and also links libwebp. It is fine for local development. It is not cleared here for redistribution. A later release needs a pinned build, its `ffmpeg -buildconf`, notices, and a license review before anyone ships it.

This FFmpeg's own WebP decoder skips ANIM/ANMF chunks, so `ffprobe` reports `webp_pipe` and zero dimensions for a valid animation. Output checks read the RIFF WebP header (VP8X canvas, ANIM loop count, ANMF frame count) instead of trusting that probe for dimensions. `ffprobe` is still used to confirm the output has no audio stream.

## Consequences

A Mac without a suitable FFmpeg can inspect nothing and shows why conversion is unavailable. Release bundling, signing, and notarization stay out of this pass.
