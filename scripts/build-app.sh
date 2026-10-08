#!/bin/bash
# Builds build/Screenshot+.app from the Swift package.
#   scripts/build-app.sh            release build
#   scripts/build-app.sh debug      debug build (enables test hooks)
#   scripts/build-app.sh --install  release build, copied to /Applications and launched
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    debug) CONFIG=debug ;;
    --install) INSTALL=1 ;;
  esac
done

swift build -c "$CONFIG"

APP="build/Screenshot+.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/ScreenshotPlus" "$APP/Contents/MacOS/ScreenshotPlus"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [ ! -f build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: required for Launch at Login (SMAppService) and keeps Gatekeeper calm locally.
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "$INSTALL" = 1 ]; then
  DEST=/Applications
  pkill -x ScreenshotPlus 2>/dev/null || true
  rm -rf "$DEST/Screenshot+.app"
  cp -R "$APP" "$DEST/"
  open "$DEST/Screenshot+.app"
  echo "Installed to $DEST/Screenshot+.app"
fi
