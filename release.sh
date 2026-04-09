#!/usr/bin/env bash
# release.sh — build, sign, notarize, and package DeployBar as a DMG.
#
# Usage:
#   ./release.sh 1.0.0
#
# Requirements:
#   - Developer ID Application cert in Keychain (team PH63999XMX)
#   - notarytool credentials stored as profile "DeployBar" in Keychain
#   - create-dmg (brew install create-dmg)

set -euo pipefail

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
  echo "Usage: $0 <version>  e.g. $0 1.0.0" >&2
  exit 1
fi

cd "$(dirname "$0")"

ROOT="$(pwd)"
BUILD_DIR="${ROOT}/build/release"
ARCHIVE_PATH="${BUILD_DIR}/DeployBar.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
DMG_DIR="${BUILD_DIR}/dmg"
DMG_PATH="${ROOT}/DeployBar-${VERSION}.dmg"
APP_PATH="${EXPORT_DIR}/DeployBar.app"

# ── 0. Clean ────────────────────────────────────────────────
echo "▶ Cleaning previous build…"
rm -rf "${BUILD_DIR}" "${DMG_PATH}"
mkdir -p "${BUILD_DIR}" "${EXPORT_DIR}" "${DMG_DIR}"

# ── 1. Regenerate Xcode project ─────────────────────────────
echo "▶ Regenerating project (xcodegen)…"
xcodegen generate >/dev/null

# Strip Finder-added extended attributes that break codesigning.
echo "▶ Stripping extended attributes from sources…"
xattr -cr DeployBar/ 2>/dev/null || true

# ── 2. Bump version ─────────────────────────────────────────
echo "▶ Bumping version to ${VERSION}…"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" DeployBar/Info.plist 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${VERSION}" DeployBar/Info.plist
BUILD_NUM=$(date +%Y%m%d%H%M)
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUM}" DeployBar/Info.plist 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${BUILD_NUM}" DeployBar/Info.plist

# ── 3. Archive (Release config, signed with Developer ID) ───
echo "▶ Archiving…"
xcodebuild \
  -project DeployBar.xcodeproj \
  -scheme DeployBar \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "${ARCHIVE_PATH}" \
  archive | xcpretty || {
    echo "✗ Archive failed" >&2
    exit 1
  }

# ── 4. Export the .app from the archive ─────────────────────
cat > "${BUILD_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>PH63999XMX</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF

echo "▶ Exporting .app…"
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" | xcpretty

if [[ ! -d "${APP_PATH}" ]]; then
  echo "✗ Export did not produce ${APP_PATH}" >&2
  exit 1
fi

# ── 5. Verify the signature ─────────────────────────────────
echo "▶ Verifying signature…"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
spctl --assess --type execute --verbose "${APP_PATH}" || true

# ── 6. Zip for notarization ─────────────────────────────────
ZIP_PATH="${BUILD_DIR}/DeployBar.zip"
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

# ── 7. Submit to Apple notary service ───────────────────────
echo "▶ Submitting to notary (this can take 5–15 minutes)…"
xcrun notarytool submit "${ZIP_PATH}" \
  --keychain-profile DeployBar \
  --wait

# ── 8. Staple the ticket to the .app ────────────────────────
echo "▶ Stapling notarization ticket…"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

# ── 9. Build DMG ────────────────────────────────────────────
cp -R "${APP_PATH}" "${DMG_DIR}/DeployBar.app"
echo "▶ Creating DMG…"
create-dmg \
  --volname "DeployBar ${VERSION}" \
  --window-size 540 360 \
  --icon-size 96 \
  --icon "DeployBar.app" 140 170 \
  --app-drop-link 400 170 \
  --hide-extension "DeployBar.app" \
  "${DMG_PATH}" \
  "${DMG_DIR}/" >/dev/null

# Sign the DMG with the same Developer ID so spctl recognizes it.
echo "▶ Signing DMG…"
codesign --sign "Developer ID Application: Vincenzo Belpiede (PH63999XMX)" \
  --timestamp \
  "${DMG_PATH}"

# Notarize the DMG too so users don't get prompted on the disk image itself
echo "▶ Notarizing DMG…"
xcrun notarytool submit "${DMG_PATH}" --keychain-profile DeployBar --wait
xcrun stapler staple "${DMG_PATH}"
xcrun stapler validate "${DMG_PATH}"

# ── 10. Sign update for Sparkle appcast ─────────────────────
echo "▶ Signing update for Sparkle appcast…"
SIGN_OUTPUT="$(./tools/sparkle/bin/sign_update "${DMG_PATH}")"
DMG_SIZE=$(stat -f%z "${DMG_PATH}")
APPCAST_ITEM="${BUILD_DIR}/appcast-item-${VERSION}.xml"
RELEASE_DATE="$(LC_TIME=en_US.UTF-8 date -u "+%a, %d %b %Y %H:%M:%S +0000")"
cat > "${APPCAST_ITEM}" <<APPCASTEOF
        <item>
            <title>Version ${VERSION}</title>
            <pubDate>${RELEASE_DATE}</pubDate>
            <sparkle:version>${BUILD_NUM}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h3>What's new in ${VERSION}</h3>
                <ul><li>See changelog at https://vincenzobelpiede.com/deploybar</li></ul>
            ]]></description>
            <enclosure
                url="https://vincenzobelpiede.com/deploybar/DeployBar-${VERSION}.dmg"
                length="${DMG_SIZE}"
                type="application/octet-stream"
                ${SIGN_OUTPUT} />
        </item>
APPCASTEOF

echo
echo "✅ Done."
echo "   App:        ${APP_PATH}"
echo "   DMG:        ${DMG_PATH}"
echo "   Version:    ${VERSION} (build ${BUILD_NUM})"
echo "   Appcast:    ${APPCAST_ITEM}"
echo
echo "Next: paste the contents of ${APPCAST_ITEM} into your hosted appcast.xml"
echo "      and upload ${DMG_PATH} to https://vincenzobelpiede.com/deploybar/"
