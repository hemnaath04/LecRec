#!/bin/bash
# Builds Lectern and assembles a .app bundle. No Xcode required.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/Lectern.app"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/Lectern"
[ -x "$BIN" ] || { echo "build produced no executable at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lectern"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature. The hash changes every build, so macOS may re-ask for
# microphone access after a rebuild. Acceptable for a personal tool.
echo "==> codesign (ad-hoc)"
codesign --force --sign - --identifier tech.hemnaath.lectern \
  --options runtime "$APP" 2>&1 | sed 's/^/    /' || true

echo "==> done: $APP"
echo "    run:     open $APP"
echo "    install: cp -R $APP /Applications/"
