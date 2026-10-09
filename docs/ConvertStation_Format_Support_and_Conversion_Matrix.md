# ConvertStation — Format Support & Conversion Matrix

**Version:** 1.0 planning specification  
**Date:** 2026-10-08  
**Status:** Proposed, not a claim of shipped functionality  
**Owner:** Product / Engineering  
**Related:** `02_TECH/CONVERSION_ENGINE.md`, `02_TECH/MOV_TO_WEBP.md`, master PRD

## 1. Executive decision

ConvertStation should ship as a **capability-driven** local Mac converter. Its promise is *supported conversions between compatible files*, not “every extension converts into every other extension.” The file picker should accept known media files for inspection, and the target picker should only show outputs the bundled engines can produce and validate for **that inspected file**.

**First customer journey:** drag a `.mov` into the app → pick **Animated WebP** → adjust trim, resolution, FPS, quality and looping → select destination → preview if requested → convert → inspect/open output. Product requirement: never silently remove audio, alpha or animation; show the tradeoff.

## 2. Terminology and status model

- **Extension** (e.g. `.mov`): filename hint, not proof of actual contents.
- **Container** (e.g. MOV, MKV, MP4): wraps streams and metadata.
- **Codec** (e.g. H.264, HEVC, VP9, AV1): actual compression. Input container support does **not** imply all codecs within are supported.
- **Still image vs animation:** `.webp`, `.avif`, `.png` can have format-specific animated variants depending on decoder/encoder implementation; treat animation as a distinct capability.
- **Recognized:** parser identifies the format; no conversion guarantee.
- **Readable/decodable:** actual sample successfully passes inspection and decode.
- **Writable/encodable:** installed build can produce the selected profile.
- **Validated:** conversion succeeds on the test corpus and output passes independent probe and representative playback checks.
- **Planned:** not yet shipped. All entries below are candidates until implemented and tested.

**Support tier key:** **P0** first milestone (MOV→animated WebP); **P1** core media; **P2** expanded media; **P3** specialist; **Hold** do not advertise without provider, legal and QA review.

## 3. Formats shown in the screenshot — complete inventory

| Family | Extension | Meaning / special considerations | Proposed tier | Direction priority |
|---|---|---|---|---|
| Video | 3g2 | 3GPP2 container; legacy mobile codecs | P3 | Import first |
| Video | 3gp | 3GPP mobile video container | P2 | Import first |
| Video | amv | AMV video; niche/legacy | P3 | Import only initially |
| Video | avi | AVI container; broad, often old codecs | P2 | Import; export later |
| Video | flv | Flash Video legacy format | P3 | Import first |
| Video | mkv | Matroska; flexible multi-stream container | P1 | Import/export |
| Video | mp4 | MPEG-4 container; H.264/H.265/AV1 etc. | P1 | Import/export |
| Video | mpg | MPEG Program Stream, `.mpeg` alias | P2 | Import first |
| Video | mxf | Broadcast/professional container | P3 | Import first |
| Video | ogg | Ogg; potentially video (Theora), audio or mixed | P2 | Detect streams, not extension |
| Video | vob | DVD Video Object; navigation and multiple streams possible | P3 | Import only initially |
| Video | webm | WebM; usually VP8/VP9/AV1 with Opus/Vorbis | P1 | Import/export |
| Video | wmv | Windows Media Video / ASF family | P2 | Import first |
| Audio | aac | Typically raw AAC, possibly ADTS | P2 | Import/export where valid |
| Audio | ac3 | Dolby Digital audio; license/compatibility review | P3 | Import; export review |
| Audio | aiff | Audio Interchange File Format, `.aif` alias | P1 | Import/export |
| Audio | flac | Lossless audio; metadata | P1 | Import/export |
| Audio | m4a | MPEG-4 audio container, AAC or ALAC | P1 | Import/export |
| Audio | mp3 | MPEG Layer III | P1 | Import/export |
| Audio | opus | Opus audio, often Ogg encapsulation | P1 | Import/export |
| Audio | wav | RIFF/WAVE with PCM or other codecs | P1 | Import/export |
| Audio | wma | Windows Media Audio / ASF family | P2 | Import first |
| Image | avif | AV1 image; still/animated depends on stack | P2 | Still import/export first |
| Image | bmp | Bitmap; large/uncompressed often | P1 | Import/export |
| Image | gif | Palette image or animated GIF | P1 | Import/export, separate animation |
| Image | ico | Windows icon container, multiple sizes | P2 | Import; explicit icon-export preset |
| Image | jpg | JPEG `.jpeg`, `.jpe` aliases | P1 | Import/export |
| Image | jxl | JPEG XL; verify bundled decoder/encoder | P3 | Hold until engine QA |
| Image | png | Lossless image with alpha; APNG separate | P1 | Import/export |
| Image | tiff | TIFF `.tif`, multipage/bit depth | P1 | Import/export |
| Image | webp | Still or animated WebP | P0 animated OUTPUT; P1 still/animated input | Both by profile |

**Missing high-value source format in screenshot:** **MOV** — this is our P0 input. Also add **HEIC/HEIF**, **JPEG**, **SVG**, **PDF**, **M4V**, **MPEG/TS**, **APNG**, **AIFF aliases**, and **RAW camera files** as clearly differentiated plans below.

## 4. Additional formats worth supporting

| Family | Extensions | Priority | Recommended handling |
|---|---|---|---|
| Video | mov, m4v | P0/P1 | MOV is first-class source; MP4/MOV/M4V output profiles |
| Video | mpeg, ts, mts, m2ts | P2 | Import; duration and timestamp edge cases |
| Video | ogv | P2 | Ogg-video compatibility profile |
| Video | prores-in-MOV | P2 | Codec is not an extension; large-file QA |
| Video | av1/h265/h264 streams | P3 | Avoid raw elementary stream output as default |
| Images | jpeg, jpe, tif, heic, heif | P1/P2 | Aliases and Apple camera formats |
| Images | apng | P2 | Animated PNG needs animation-aware provider |
| Images | svg | P2 | Safe rasterization to PNG/WebP; vector-to-vector is different |
| Images | pdf | P2 | Render selected PDF page(s) to image; not general document conversion |
| Images | dng, cr2, cr3, nef, arw, raf | P3 | RAW import if native/image providers support each camera model |
| Images | psd | P3 | Flattened import only if tested; layer preservation out-of-scope |
| Images | exr, hdr, tga | P3 | Specialist HDR/CG workflows |
| Audio | aif, alac-in-m4a, ogg, oga, caf | P1/P2 | macOS-friendly audio and open codecs |
| Audio | ape, wv, mid/midi | P3/Hold | MIDI isn't audio; needs synth renderer, not transcoding |
| Documents | pdf | P2 | PDF page rasterization, image→PDF, merge/split later |
| Documents | docx, odt, txt, md, html, epub | P3/Hold | Separate document provider and layout fidelity testing |
| Archives | zip, tar, gz, 7z | P3/Hold | Archive **repack/extract**, not ordinary transcoding; guard against path traversal |
| Fonts | ttf, otf, woff/woff2 | P3/Hold | Specialized licensing and metadata cases |

## 5. Recommended source → target matrix

Legend: **✓ P0** must build now; **P1/P2** intended for that release tier; **—** not default / not meaningful; **Conditional** inspect source and provider first. Target is a *profile*, not only an extension.

| Source | Animated WebP | Still WebP/PNG/JPEG | GIF/APNG | MP4/MOV/WebM | MP3/M4A/WAV/FLAC | PDF |
|---|---|---|---|---|---|---|
| MOV video | ✓ P0 | P1 (frame extraction) | P1/P2 | P1 | P1 (extract audio only) | P2 (contact sheet only) |
| MP4/MKV/WebM video | P1 | P1 (frame extraction) | P1/P2 | P1 | P1 (audio stream required) | P2 (contact sheet) |
| Other video family | P2/P3 conditional | P2/P3 | P2/P3 | P2/P3 | P2/P3 conditional | — |
| PNG/JPEG/HEIC still | P2 (single-frame WebP only unless assembled) | P1 | P2 (single-image GIF or frame sequence) | P2 (image→video with duration specified) | — | P2 |
| GIF/animated WebP/APNG | P1 | P1 (single selected frame) | P1/P2 | P1 | — | P2 contact sheet |
| AVIF/TIFF/BMP/ICO/JXL | P2/P3 conditional | P1/P2/P3 conditional | P2/P3 | P3 | — | P2/P3 |
| MP3/M4A/FLAC/WAV/etc. | — | — (cover art extraction is distinct) | — | P2 (audio + generated video is a special workflow) | P1 | — |
| PDF | — | P2 (render selected pages) | — | — | — | P2 (merge/split/optimize only) |
| Documents/archives | — | Conditional render only | — | — | — | P3 specialized provider |

**Critical note:** A video with no audio must not offer **Extract audio** as a valid target. A still JPEG does not magically become a moving animation. Direct remuxing (`MKV→MP4`) requires compatible streams; otherwise transcode and disclose recompression.

## 6. User-visible output profiles / knobs

### Video outputs
- MP4 (H.264 + AAC compatibility default; optional HEVC), MOV (compatible codec presets), WebM (VP9/Opus or AV1/Opus where built), MKV (codec-aware profile).
- Controls: size/preset, codec, constant-quality versus target bitrate, FPS, resolution, aspect, rotate/crop, trim, audio handling, subtitle/metadata policy, hardware/software encoder selection where available.
- Declare HDR→SDR tone mapping; color profile handling; transparency support; VFR→CFR; hardware-encoder fallback.

### Animated outputs
- Animated WebP, GIF, animated PNG (provider permitting), optional animated AVIF later.
- Controls: trim, width/height, FPS, quality, loop count, alpha handling, dithering/palette for GIF, duration/size estimate.
- Warn: **no audio in animated WebP or GIF**; FPS reductions change motion, GIF is limited to palette colors; output may be larger, not smaller.

### Still image outputs
- JPEG, PNG, WebP, TIFF, HEIC/HEIF, BMP, AVIF; ICO and JPEG XL only when verified.
- Controls: quality if lossy, resize, crop/fit, orientation, transparency flattening/background, preserve/remove metadata, ICC profile policy, bit depth, output color space.
- Warn: JPEG has no alpha; HEIC/JXL/AVIF support is OS/build dependent; TIFF may be multipage. Do not auto-flatten pages/frames without explaining.

### Audio outputs
- MP3, M4A (AAC or ALAC preset), WAV (PCM), FLAC, Opus, AIFF.
- Controls: bitrate/quality, channels/downmix, sample rate, bit depth for PCM, trim, normalization (later), retain/remove artwork/chapters.
- Warn: lossless→lossy loses quality; lossy→lossless does not restore quality.

### PDF / future outputs
- Images→PDF, PDF pages→PNG/JPEG/WebP; later merge/split/compress PDFs. Keep document conversions modular and explicitly scoped.

## 7. Format picker and queue UX

1. Import one or many files via drag/drop, Open dialog, Finder Quick Action (later).
2. Inspect **actual bytes and media streams** (UTType + magic numbers + ffprobe); show `Unknown` rather than trust extension alone.
3. Group **available targets** by *Video / Animation / Image / Audio / Document*; show only actionable combinations by default. An optional “All formats” catalog may label unavailable items with explanation.
4. Label profiles naturally: `Animated WebP (.webp)` versus `WebP Image (.webp)`, `MP4 (H.264 + AAC)` versus `MP4 (HEVC + AAC)`, `M4A (AAC)` versus `M4A (ALAC)`.
5. Advanced inspector shows codec, streams, rotation, alpha, duration, resolution, audio, metadata and expected losses.
6. Per-file overrides supported in mixed batch; batch preset applies only to compatible items. Summary shows N ready / N incompatible.
7. Destination: same folder, selected folder, or per-job destination; define collision policy (`Rename`, `Skip`, `Ask`; overwrite only after explicit confirmation).
8. Queue: progress, stage (inspect/decode/encode/verify), retry, cancel; preserve originals and write to temp files followed by verified atomic finalization.

## 8. Engine and capability registration contract

```swift
struct FormatCapability: Sendable {
    let sourcePredicate: SourcePredicate // container + codecs + stream types
    let outputProfileID: String         // e.g. "webp.animated.lossy"
    let requiredProvider: String        // e.g. "ffmpeg.libwebp_anim"
    let settingsSchemaID: String
    let constraints: [CapabilityConstraint]
    let lossNotices: [LossNotice]
    let verificationProfileID: String
}

enum SupportStatus {
    case unavailable(reason: String)
    case inspectable
    case convertible(profileIDs: [String])
    case verified(profileIDs: [String])
}
```

Implement canonical `FormatID`, `ContainerID`, `CodecID`, `ProfileID`, `ProviderID` rather than using filename extensions as identifiers. Runtime probe `ffmpeg -demuxers`, `-muxers`, `-decoders`, `-encoders`, and provider-specific capabilities; a muxer alone is insufficient to claim valid output. Export a diagnostic **Capabilities Report** with app, macOS, binary versions and detected encoders (no user paths). Cache per build signature.

## 9. Rollout and shipping gates

**P0 — Proof:** `.mov` (actually decodable QuickTime streams) → valid **animated WebP**. Test short/long, portrait, VFR, rotated, silent/audio-bearing, transparency, color profile and malformed inputs. Confirm genuine multi-frame output with timestamps and independently decoded playback.

**P1 — Core useful converter:** MP4, MOV, MKV, WebM reading/encoding; animated WebP↔GIF↔video where valid; image PNG/JPEG/WebP/BMP/TIFF/HEIC with verified provider support; audio MP3/M4A/WAV/FLAC/Opus/AIFF. Stage by tested path; do not mark P1 complete just because extensions appear in the picker.

**P2 — Expanded:** AVI/WMV/3GP/MPG/FLV legacy import; AVIF, ICO, APNG, Ogg variants, TS/MTS; PDF→images and images→PDF. Each behind tested capability flag.

**P3 — Specialist:** MXF, VOB, AMV, 3G2, JPEG XL, camera RAW variants, PSD/EXR, document conversions and archives as separate providers.

**Release gate per directed edge:** fixture corpus covers typical and adversarial input; conversion returns 0; output container/codec matches requested profile; opens in target viewer; metadata policy respected; output path collision handled; cancel leaves no partial final output; no crash or unbounded temp disk; licensing/distribution reviewed.

## 10. Test fixture matrix and acceptance criteria

Minimum corpus by family: video H.264/AAC, HEVC, VP9/Opus, AV1 when bundled, VFR phone recordings, ProRes/alpha when offered, rotated/silent/corrupt; images RGB/RGBA, grayscale, CMYK, wide gamut, EXIF-orientation, multi-frame GIF/WebP, large (>100 MP), bad extension, malicious/decompression-bomb-like content; audio mono/stereo/multichannel, odd sample rates, variable bitrate and tags; PDF multi-page/locked/malformed.

- Unsupported codecs produce clear error even if the extension is recognized.
- No unsupported format appears as an enabled destination.
- Every shown **conversion option** maps to a tested provider/profile and validation rule.
- The same extension can offer distinct still vs animated profiles.
- Output validator reopens the result and verifies expected streams, codec, dimensions, frame count/duration or alpha when applicable.
- All output stays local; no file contents uploaded.
- App persists only security-scoped access and minimal job history; respects user-controlled metadata policy.

## 11. Important constraints / open engineering choices

- Final bundled FFmpeg configuration and LGPL/GPL/nonfree linkage conditions require legal/distribution review; never assume every codec is bundled.
- macOS ImageIO/AVFoundation capabilities differ by OS version and actual file content; probe/test rather than promise from extension lists.
- HDR transfer, ICC color, EXIF/GPS metadata, animation loops and audio/subtitle streams all require explicit user-visible loss semantics.
- DRM/protected media is excluded; do not promise copy protection bypass.
- “File to any format” is not technically meaningful across unrelated semantics (MP3→JPEG, ZIP→MP4, etc.). Treat extracting embedded art, rendering pages and slideshow generation as named **workflows**, not simple format conversions.

## 12. Sources / verification references

- FFmpeg formats, demuxers and muxers: https://ffmpeg.org/ffmpeg-formats.html
- ffprobe capabilities and probing: https://ffmpeg.org/ffprobe.html
- FFmpeg documentation/version behavior: https://ffmpeg.org/documentation.html
- WebP reference animation encoder/decoder APIs: https://github.com/webmproject/libwebp/blob/main/doc/api.md
- Apple ImageIO developer documentation: https://developer.apple.com/documentation/imageio

This is the product **planned support matrix**, not a verified claim about a shipped binary. An implementation-generated runtime capability manifest and automated tests must determine what is advertised in each release.
