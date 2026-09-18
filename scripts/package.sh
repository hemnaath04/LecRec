#!/bin/bash
# Builds LecRec and packages it as a designed, drag-to-install DMG.
#
# Ad-hoc signed by default, which works but makes the recipient approve it once
# in System Settings. Set DEVELOPER_ID to a "Developer ID Application: ..."
# identity and it signs and notarizes instead, and the DMG opens with no warning.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="build/LecRec.app"
DMG="build/LecRec-$VERSION.dmg"
STAGING="build/dmg-staging"
VOLUME="LecRec $VERSION"

./scripts/build.sh release
python3 scripts/make-dmg-background.py

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> signing with $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> no DEVELOPER_ID set, keeping the ad-hoc signature"
fi

echo "==> staging"
rm -rf "$STAGING" "$DMG" build/rw.dmg
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp build/dmg/background.png "$STAGING/.background/background.png"

# A read-write image first, so Finder can be told how to present it, then
# converted to a compressed read-only image for distribution.
echo "==> building writable image"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGING" \
  -ov -format UDRW -fs HFS+ build/rw.dmg >/dev/null
DEVICE="$(hdiutil attach -readwrite -noverify -noautoopen build/rw.dmg | grep '/dev/disk' | head -1 | awk '{print $1}')"
MOUNT="/Volumes/$VOLUME"
sleep 2

echo "==> arranging the install window"
osascript <<EOF >/dev/null 2>&1 || echo "    (Finder styling skipped)"
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- 720x480 artwork, plus the title bar Finder adds on top
    set the bounds of container window to {200, 140, 920, 642}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 12
    set background picture of opts to file ".background:background.png"
    set position of item "LecRec.app" of container window to {176, 288}
    set position of item "Applications" of container window to {544, 288}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

sync
hdiutil detach "$DEVICE" >/dev/null || true
sleep 1

echo "==> compressing"
hdiutil convert build/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f build/rw.dmg
rm -rf "$STAGING"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --sign "$DEVELOPER_ID" "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> notarizing"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo
echo "==> done: $DMG  ($(du -h "$DMG" | cut -f1))"
