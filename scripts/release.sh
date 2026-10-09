#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-Release}"
DERIVED="$ROOT/build"
ARTIFACTS="$ROOT/artifacts"
APP="$DERIVED/Build/Products/$CONFIGURATION/ConvertStation.app"

DEVELOPER_ID="${DEVELOPER_ID:-Developer ID Application: James Jewhurst (6998422DKP)}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-6998422DKP}"
NOTARY_PROFILE="${NOTARY_PROFILE:-notary}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-ConvertStation}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-JewhurstEngineering/convertstation}"

fail() {
  print -u2 "error: $1"
  exit 1
}

VERSION="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
match = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
print(match.group(1) if match else "")
PY
)"
BUILD_NUMBER="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
match = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text)
print(match.group(1) if match else "")
PY
)"
[[ -n "$VERSION" && -n "$BUILD_NUMBER" ]] || fail "Could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml."
RELEASE_TAG="${RELEASE_TAG:-v$VERSION}"

if [[ "$CONFIGURATION" == "Release" ]]; then
  IDENTITIES="$(security find-identity -v -p codesigning)"
  [[ "$IDENTITIES" == *"$DEVELOPER_ID"* ]] || fail \
    "Missing signing identity '$DEVELOPER_ID'. Install the Developer ID Application certificate in Keychain Access."

  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    fail "Missing or invalid notarytool profile '$NOTARY_PROFILE'.
Create it locally (never commit the credentials):
  xcrun notarytool store-credentials \"$NOTARY_PROFILE\""
  fi
fi

xcodegen generate

xcodebuild \
  -project ConvertStation.xcodeproj \
  -scheme ConvertStation \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  build

[[ -d "$APP" ]] || fail "Build succeeded but $APP was not produced."

if [[ "$CONFIGURATION" != "Release" ]]; then
  print "Built $APP"
  exit 0
fi

sign_item() {
  codesign --force --sign "$DEVELOPER_ID" --options runtime --timestamp "$@"
}

FRAMEWORKS="$APP/Contents/Frameworks"
setopt null_glob
for library in "$FRAMEWORKS"/*.dylib; do
  sign_item "$library"
done
unsetopt null_glob

HELPER_ENTITLEMENTS="$ROOT/ConvertStation/Helper.entitlements"
for name in ffmpeg ffprobe; do
  tool="$APP/Contents/Helpers/$name"
  [[ -e "$tool" ]] || fail "Missing bundled $name at $tool."
  sign_item --entitlements "$HELPER_ENTITLEMENTS" "$tool"
done

SPARKLE_FRAMEWORK="$FRAMEWORKS/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"
[[ -d "$SPARKLE_FRAMEWORK" ]] || fail "Sparkle.framework was not embedded in $APP."

sign_item "$SPARKLE_VERSION/XPCServices/Installer.xpc"
sign_item --preserve-metadata=entitlements "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
sign_item "$SPARKLE_VERSION/Autoupdate"
sign_item "$SPARKLE_VERSION/Updater.app"
sign_item "$SPARKLE_FRAMEWORK"
sign_item --entitlements "$ROOT/ConvertStation/ConvertStation-Release.entitlements" "$APP"

SIGNING_AUTHORITY="$(codesign -dvv "$APP" 2>&1)"
[[ "$SIGNING_AUTHORITY" == *"Authority=$DEVELOPER_ID"* ]] || fail \
  "Release app was not signed with '$DEVELOPER_ID'."
[[ "$SIGNING_AUTHORITY" == *"Timestamp="* ]] || fail \
  "Release app signature is missing a secure timestamp."

APP_ENTITLEMENTS="$(codesign -d --entitlements - "$APP" 2>/dev/null)"
[[ "$APP_ENTITLEMENTS" != *"com.apple.security.get-task-allow"* ]] || fail \
  "Release app still contains the development-only get-task-allow entitlement."

codesign --verify --deep --strict --verbose=2 "$APP"

SPARKLE_BIN="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
GENERATE_KEYS="$SPARKLE_BIN/generate_keys"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
[[ -x "$GENERATE_KEYS" && -x "$GENERATE_APPCAST" ]] || fail \
  "Sparkle release tools were not found under $SPARKLE_BIN."

EXPECTED_PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/Contents/Info.plist")"
LOCAL_PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p)"
[[ "$LOCAL_PUBLIC_KEY" == "$EXPECTED_PUBLIC_KEY" ]] || fail \
  "The local Sparkle key '$SPARKLE_ACCOUNT' does not match SUPublicEDKey in the app."

mkdir -p "$ARTIFACTS"
STAGING="$(mktemp -d "$DERIVED/ConvertStation-release.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

NOTARY_ZIP="$STAGING/ConvertStation-notary.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"

print "Submitting ConvertStation $VERSION ($BUILD_NUMBER) for notarization…"
NOTARY_RESULT="$STAGING/notary-result.json"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait \
  --output-format json > "$NOTARY_RESULT"

NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
SUBMISSION_ID="$(plutil -extract id raw -o - "$NOTARY_RESULT")"
if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
  fail "Apple notarization returned '$NOTARY_STATUS' for submission $SUBMISSION_ID."
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP"

ARCHIVE_NAME="ConvertStation-$VERSION.zip"
FINAL_ZIP="$ARTIFACTS/$ARCHIVE_NAME"
[[ ! -e "$FINAL_ZIP" || "${ALLOW_OVERWRITE:-0}" == "1" ]] || fail \
  "$FINAL_ZIP already exists. Bump MARKETING_VERSION or run with ALLOW_OVERWRITE=1."
ditto -c -k --sequesterRsrc --keepParent "$APP" "$FINAL_ZIP"

APPCAST_DIR="$STAGING/appcast"
mkdir -p "$APPCAST_DIR"
cp "$FINAL_ZIP" "$APPCAST_DIR/$ARCHIVE_NAME"
"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/" \
  --link "https://github.com/$GITHUB_REPOSITORY" \
  --maximum-versions 1 \
  --maximum-deltas 0 \
  "$APPCAST_DIR"
cp "$APPCAST_DIR/appcast.xml" "$ARTIFACTS/appcast.xml"

print
print "Release ready:"
print "  App:     $APP"
print "  ZIP:     $FINAL_ZIP"
print "  Appcast: $ARTIFACTS/appcast.xml"
print "  Tag:     $RELEASE_TAG"
