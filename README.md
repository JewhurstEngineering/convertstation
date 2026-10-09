# ConvertStation

Local-first macOS app that converts a MOV to animated WebP. Files stay on the Mac. This build does not upload anything, and Animated WebP is the only output.

## Requirements

- macOS 14 or later
- Xcode 16 or later (this tree was built with Xcode 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you need to regenerate the project
- FFmpeg and ffprobe with `libwebp_anim` on `/opt/homebrew/bin` or `/usr/local/bin`

The app is sandboxed. A build script copies the local FFmpeg into the app so the sandbox can launch it. A Homebrew FFmpeg built with `--enable-gpl` is for this Mac only and is not cleared for redistribution. See `docs/adr/ADR-001-engine-packaging.md` and `docs/adr/ADR-002-distribution-sandbox.md`.

## Build and run

```bash
xcodegen generate
xcodebuild -scheme ConvertStation -destination 'platform=macOS' test
open build/Build/Products/Debug/ConvertStation.app
```

`xcodebuild test` writes the app under DerivedData unless `-derivedDataPath` is set. To run the app from a known folder:

```bash
xcodebuild -scheme ConvertStation -destination 'platform=macOS' -derivedDataPath build build
open build/Build/Products/Debug/ConvertStation.app
```

Drop a MOV, pick Balanced (or another preset), choose a folder, and convert. The original file is not modified. Finished WebP files open in Quick Look.

## Limits of this build

- Sandboxed and ad-hoc signed, not notarized
- FFmpeg is copied at build time and is not committed
- No formats besides MOV (or any file ffprobe can read as video) to animated WebP
- Animated WebP preview uses Quick Look, because this FFmpeg build cannot decode its own ANIM chunks
- Jobs that were converting when the app quit come back as Interrupted
- Files chosen before the sandbox was turned on may need to be picked again
