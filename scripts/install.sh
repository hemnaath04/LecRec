#!/bin/bash
# Installs LecRec to /Applications, replacing any older copy.
#
# Why this exists: a stale copy in /Applications while development continues in
# the repo is invisible and silent. That is exactly what happened on 22 Sep,
# when the installed app was four days behind and nobody could tell.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh release

if pgrep -f "/Applications/LecRec.app" >/dev/null; then
  echo "==> quitting the running copy"
  osascript -e 'tell application "LecRec" to quit' 2>/dev/null || pkill -f "/Applications/LecRec.app" || true
  sleep 1
fi

echo "==> installing to /Applications"
rm -rf /Applications/LecRec.app
cp -R build/LecRec.app /Applications/LecRec.app

echo "==> installed build:"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/LecRec.app/Contents/Info.plist
stat -f "    built %Sm" /Applications/LecRec.app/Contents/MacOS/LecRec
codesign -dv /Applications/LecRec.app 2>&1 | grep -E "Signature" | sed 's/^/    /'

if [ -z "${LECREC_SIGN_IDENTITY:-}" ]; then
  cat <<'NOTE'

    Note: this build is ad-hoc signed, so its code signature changes on every
    rebuild and macOS may ask for microphone access again after each install.
    To make the grant stick, create a self-signed code signing identity once:

      Keychain Access > Certificate Assistant > Create a Certificate
        Name: LecRec Local
        Identity Type: Self Signed Root
        Certificate Type: Code Signing

    then rebuild with:  LECREC_SIGN_IDENTITY="LecRec Local" ./scripts/install.sh
NOTE
fi

echo
echo "==> open it with: open /Applications/LecRec.app"
