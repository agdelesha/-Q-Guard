#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
APP="$ROOT/CmdQ Guard 4.app"
IDENTITY="${CMDQGUARD_SIGNING_IDENTITY:-CmdQ Guard Local}"
if ! security find-identity -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null; then
  echo "Missing code-signing identity '$IDENTITY' in the macOS login keychain." >&2
  exit 1
fi
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
swift "$ROOT/make-icon.swift" "$APP/Contents/Resources/CmdQGuardMenuIcon.png"
python3 "$ROOT/make-icns.py" "$APP/Contents/Resources/CmdQGuardMenuIcon.png" "$APP/Contents/Resources/CmdQGuard.icns"
swiftc -parse-as-library -O -framework AppKit -framework ApplicationServices -framework CoreGraphics \
  "$ROOT/CmdQGuard.swift" -o "$APP/Contents/MacOS/CmdQGuard"
codesign --force --deep --sign "$IDENTITY" "$APP"
echo "Built: $APP"
