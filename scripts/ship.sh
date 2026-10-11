#!/usr/bin/env bash
#
# ship.sh — archive the iOS app and hand it to TestFlight.
#
#   scripts/ship.sh              # bump build, archive, export, upload
#   scripts/ship.sh --no-upload  # archive and export only, for a dry run
#
# Signing uses the Lingonberry account signed into Xcode (automatic signing,
# -allowProvisioningUpdates). The upload and the build-number lookup use the
# App Store Connect API key at ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8,
# which is the path Apple's tools look in by default.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="VoiceHole-iOS"
PRODUCT="VoiceHole"
PROJECT="VoiceHole.xcodeproj"
TEAM_ID="HFYS9XNM5B"
ASC_KEY_ID="${ASC_KEY_ID:-L7V5YSAY53}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-c78ac3f0-011a-464e-8710-d101fa9031d8}"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0

BUILD_DIR="$ROOT/build/ship"
ARCHIVE="$BUILD_DIR/$PRODUCT.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"

if [[ ! -f "$ASC_KEY_PATH" ]]; then
  echo "✗ no App Store Connect key at $ASC_KEY_PATH"
  echo "  make one under Users and Access → Integrations, or set ASC_KEY_ID."
  exit 1
fi

MARKETING_VERSION="$(awk '/MARKETING_VERSION/ {print $2; exit}' project.yml | tr -d '"')"

# Build numbers climb within a marketing version. App Store Connect is the
# source of truth for what it has already seen, so ask it rather than keep a
# counter in the repo.
BUILD_NUMBER="$(ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" \
  node "$ROOT/scripts/next-build.mjs" "$MARKETING_VERSION")" || {
  echo "✗ couldn't work out the next build number"
  exit 1
}

echo "▸ VoiceHole iOS $MARKETING_VERSION ($BUILD_NUMBER)"

echo "▸ regenerating the project"
xcodegen generate >/dev/null

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "▸ archiving"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  | grep -E '^(\*\*|.*error:|.*warning: no |Signing Identity)' || true

if [[ ! -d "$ARCHIVE" ]]; then
  echo "✗ no archive produced"
  exit 1
fi

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "▸ exporting for the App Store"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates \
  | grep -E '^(\*\*|.*error:|Exported)' || true

IPA="$EXPORT_DIR/$PRODUCT.ipa"
[[ -f "$IPA" ]] || { echo "✗ no ipa at $IPA"; exit 1; }

if [[ $UPLOAD == 0 ]]; then
  echo "✓ exported to $IPA (not uploaded)"
  exit 0
fi

echo "▸ uploading to App Store Connect"
xcrun altool --upload-app -f "$IPA" -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" 2>&1 | tail -20

echo "✓ $MARKETING_VERSION ($BUILD_NUMBER) is with Apple."
echo "  It takes a few minutes to finish processing before TestFlight shows it."

git tag -f "ship-ios-$MARKETING_VERSION-$BUILD_NUMBER" >/dev/null 2>&1 || true
