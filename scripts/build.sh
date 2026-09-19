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
echo "==> codesign (ad-hoc)"
codesign --force --sign - --identifier tech.hemnaath.lecrec \
  --options runtime "$APP" 2>&1 | sed 's/^/    /' || true

echo "==> done: $APP"
echo "    run:     open $APP"
echo "    install: cp -R $APP /Applications/"
