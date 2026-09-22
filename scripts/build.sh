#!/bin/bash
# Builds LecRec and assembles a .app bundle. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/LecRec.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/LecRec"
[ -x "$BIN" ] || { echo "build produced no executable at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LecRec"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "==> generating app icon"
  python3 scripts/make-icon.py
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [ -d Resources/fonts ]; then
  cp -R Resources/fonts "$APP/Contents/Resources/fonts"
fi

# The bundled skill travels with the app so a new user needs no manual copy.
if [ -d Resources/skills ]; then
  cp -R Resources/skills "$APP/Contents/Resources/skills"
fi

# Ad-hoc signature. The hash changes every build, so macOS may re-ask for
# microphone access after a rebuild. Acceptable for a personal tool.
# A stable identity keeps the code signature constant across rebuilds, which is
# what lets a microphone grant survive an update. Ad-hoc changes hash every time.
SIGN_AS="${LECREC_SIGN_IDENTITY:--}"
if [ "$SIGN_AS" = "-" ]; then
  echo "==> codesign (ad-hoc, grant will not survive rebuilds)"
else
  echo "==> codesign as $SIGN_AS"
fi
# The entitlements are not optional: the hardened runtime blocks the microphone
# without com.apple.security.device.audio-input, and denies without prompting.
codesign --force --sign "$SIGN_AS" --identifier tech.hemnaath.lecrec \
  --entitlements Resources/LecRec.entitlements \
  --options runtime "$APP" 2>&1 | sed 's/^/    /' || true

if ! codesign -d --entitlements - "$APP" 2>&1 | grep -q "audio-input"; then
  echo "    ERROR: the audio-input entitlement did not apply, the mic will not work" >&2
  exit 1
fi
echo "    entitlements: audio-input present"

echo "==> done: $APP"
echo "    run:     open $APP"
echo "    install: cp -R $APP /Applications/"
