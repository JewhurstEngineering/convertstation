# Security, Privacy, Licensing and Release

**Status:** Implementation planning | **Date:** 2026-10-08 | **Working title:** Universal Converter

## Files and consent
Files are opened via deliberate user picker/drop. No backend, remote analytics or uploading. Require explicit permission for destination; store security-scoped bookmarks only if persistent folder access is needed. Balance startAccessing/stopAccessing even on cancellation. For direct distribution versus sandbox/App Store, test the actual binary launching rules under hardened runtime and sandbox entitlements.

## Execution protections
Pin executable path to signed bundled resources. Use Foundation Process argument array: no shell, no command interpolation. Limit inputs and inspect files before launching converters. Treat files as hostile: malformed codecs may exploit native libraries; maintain patch cadence and security updates. Restrict process concurrency, avoid unbounded logs and check disk capacity. Debug logs must exclude personal file paths or be easily redactable.

## Legal/licensing release checklist
- Review official FFmpeg and linked libraries' LGPL/GPL obligations based on *actual build configuration*, not a blanket FFmpeg claim.
- Maintain generated `ffmpeg -buildconf`, license attribution, third-party notices, checksums, architecture support and any object/relinking materials that license terms require.
- Do not use a GPL-enabled build without documenting how distribution obligations are met.
- Review WebP encoder/libwebp notices and codec patent concerns with counsel as needed.
- Decide: Mac App Store vs Developer ID direct distribution before packaging binary executables; verify Apple's current rules and notarization.
- Trademark/domain/App Store name clearance is separate from search engine lookup.

## Release workflow
1. CI builds and unit/integration suite.
2. Independent fixture suite verifies binary conversion after bundling.
3. Package signs app and embedded tools; checks all architectures.
4. Notarize if direct distribution; verify ticket and Gatekeeper on clean device.
5. Publish release notes, versioned formats supported, privacy statement, third-party notices.
6. Keep rollback build and dependency-update process.

## Support boundaries
Never claim any format can be converted to any other: semantic incompatibilities exist (video→JPEG requires frame selection, JPEG cannot contain animation or sound, PDFs need document-aware conversion). Unsupported paths must be explained.
