#!/usr/bin/env bash
#
# release-mac.sh — build a notarized Mac zip and publish it as a GitHub release.
#
#   scripts/release-mac.sh              # build, notarize, zip, publish v<MARKETING_VERSION>
#   scripts/release-mac.sh --no-upload  # build, notarize and zip only
#
# Signs with the Lingonberry Developer ID through automatic signing. Hardened
# runtime and the mic entitlement are switched on here rather than in
# project.yml, so day-to-day builds keep their Apple Development signing and
# their privacy grants. Notarization uses the same App Store Connect API key
# as ship.sh. The zip lands in build/release/ and is attached to the release,
# so the site's download link (releases/latest/download/VoiceHole-mac.zip)
# always points at the newest build.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="VoiceHole"
PROJECT="VoiceHole.xcodeproj"
TEAM_ID="HFYS9XNM5B"
REPO="psql/voicehole"
ASC_KEY_ID="${ASC_KEY_ID:-L7V5YSAY53}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-c78ac3f0-011a-464e-8710-d101fa9031d8}"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0

BUILD_DIR="$ROOT/build/release"
ARCHIVE="$BUILD_DIR/VoiceHole.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/VoiceHole.app"
ZIP="$BUILD_DIR/VoiceHole-mac.zip"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "✗ no App Store Connect key at $ASC_KEY_PATH"
  exit 1
fi

AUTH=(-allowProvisioningUpdates
  -authenticationKeyPath "$ASC_KEY_PATH"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID")

VERSION="$(awk '/MARKETING_VERSION/ {print $2; exit}' project.yml | tr -d '"')"
TAG="v$VERSION"
echo "▸ VoiceHole for Mac $VERSION"

if [[ $UPLOAD == 1 ]] && gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "✗ release $TAG already exists; bump MARKETING_VERSION in project.yml first"
  exit 1
fi

echo "▸ regenerating the project"
xcodegen generate >/dev/null

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ archiving"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  "${AUTH[@]}" \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_ENTITLEMENTS="$ROOT/Support/VoiceHole-macOS-release.entitlements" \
  | grep -E '^(\*\*|.*error:)' || true

if [[ ! -d "$ARCHIVE" ]]; then
  echo "✗ no archive produced"
  exit 1
fi

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "▸ exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  "${AUTH[@]}" \
  | grep -E '^(\*\*|.*error:)' || true

if [[ ! -d "$APP" ]]; then
  echo "✗ export failed"
  exit 1
fi

echo "▸ notarizing (a few minutes)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/notarize.zip"
xcrun notarytool submit "$BUILD_DIR/notarize.zip" \
  --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" \
  --wait | tail -2
xcrun stapler staple "$APP" >/dev/null
rm "$BUILD_DIR/notarize.zip"

echo "▸ checking Gatekeeper"
spctl -a -t exec "$APP"

ditto -c -k --keepParent "$APP" "$ZIP"
echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"

if [[ $UPLOAD == 0 ]]; then
  exit 0
fi

echo "▸ publishing $TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" \
  --title "VoiceHole $VERSION for Mac" \
  --notes "Unzip, then drag VoiceHole to Applications. Needs macOS 14 or later, on Apple Silicon or Intel. Signed and notarized by Apple."
echo "✓ https://github.com/$REPO/releases/tag/$TAG"
