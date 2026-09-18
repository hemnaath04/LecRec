#!/bin/bash
# Builds LecRec and packages it as a DMG for sharing.
#
# Ad-hoc signed by default, which works but makes the recipient go through
# System Settings once. Set DEVELOPER_ID to a "Developer ID Application: ..."
# identity and it signs and notarizes properly instead, and the DMG opens with
# no warning at all.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
APP="build/LecRec.app"
DMG="build/LecRec-$VERSION.dmg"
STAGING="build/dmg-staging"

./scripts/build.sh release

if [ -n "${DEVELOPER_ID:-}" ]; then
  echo "==> signing with $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> no DEVELOPER_ID set, keeping the ad-hoc signature"
  echo "    recipients will need: System Settings > Privacy and Security > Open Anyway"
fi

echo "==> staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp docs/INSTALL.md "$STAGING/Read me first.md" 2>/dev/null || true

echo "==> building $DMG"
hdiutil create -volname "LecRec $VERSION" -srcfolder "$STAGING" \
  -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

if [ -n "${DEVELOPER_ID:-}" ]; then
  codesign --force --sign "$DEVELOPER_ID" "$DMG"
  if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "==> notarizing (this takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "==> notarized and stapled"
  else
    echo "==> signed but not notarized; set NOTARY_PROFILE to finish the job"
  fi
fi

echo
echo "==> done: $DMG  ($(du -h "$DMG" | cut -f1))"
