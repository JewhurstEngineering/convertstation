# MOV to Animated WebP Implementation

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Vertical slice
User imports `demo.mov`, selects Animated WebP, optional trim, FPS, max width, quality, loop and destination folder, starts conversion; output plays, is inspectable and can be revealed in Finder.

## Media behavior
- Default preset: width 800px (never upscale), FPS 12, quality 75/100, infinite loop, full duration; preserve aspect ratio, force even dimensions when encoder requires it.
- Presets: Compact (640px, 10fps, 60 quality); Balanced (800px, 12fps, 75); Quality (source up to 1280px, 20fps, 85). These are hypotheses pending visual benchmarks.
- Trim start/end inputs in seconds (end > start, positive duration). UI must say when audio is discarded (WebP is silent).
- For portrait videos width setting is max long edge, not always horizontal width; define dimension semantics precisely in UI.
- VFR inputs need deterministic sampling with `fps` filter; rotated sources must be normalized to displayed orientation; check pixel aspect ratio, colorspace, alpha and HDR→SDR tone mapping rather than silently clamping.
- Infinite loop flag encoded as loop count 0 **and verified** by inspecting output metadata. The `libwebp_anim` encoder muxing behavior must be tested against the pinned version.

## FFmpeg command concept (not a final universal command)
```bash
ffmpeg -hide_banner -nostdin -y -i INPUT.mov \
  -an -vf "fps=12,scale=800:-2:flags=lanczos" \
  -c:v libwebp_anim -quality 75 -loop 0 \
  -f webp TEMP.webp
```
Never build shell strings from user filenames. Use `Process.executableURL` and `arguments`; use `-progress pipe:1` where supported to parse time progress. Check build-specific `libwebp_anim` options and correct pix_fmt/filter path through experiments. Use a destination-local temp file and no `-y` against a final user output. Exact trimming flags must be verified on B-frame/VFR input.

## Progress
Compute monotonic percent from `out_time_* / effectiveDuration` with clamp below 100% until output validation. For unsupported progress fields use indeterminate spinner, never fake precise progress. Cancellation should be responsive and leave original untouched.

## Verification
Inspect output with `ffprobe`: WebP format, dimensions, duration estimate, animated frame count >1 (for adequate source), loop semantics, decode errors, file bytes >0; optionally decode frames via a known-good decoder. One-frame short videos may be valid WebP but UI must accurately label them.

## Known engineering risks
FFmpeg WebP animation support/options can differ by binary build. Rotation/alpha/HDR handling varies by codec. Converting to WebP can **increase** file size relative to MOV, so never promise compression. Duration may shift one frame at target FPS. Implement comparison via fixture-based acceptance thresholds rather than exact byte-for-byte parity.
