#!/bin/bash
# Build DepotBar and (re)install it as /Applications/DepotBar.app.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building release binary..."
swift build -c release

BIN=".build/release/DepotBar"
APP="DepotBar.app"

echo "==> Bundling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DepotBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc signing..."
codesign --force --deep -s - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
    echo "==> Installing to /Applications..."
    pkill -x DepotBar 2>/dev/null || true
    rm -rf "/Applications/DepotBar.app"
    cp -R "$APP" "/Applications/DepotBar.app"
    echo "Installed. Launching..."
    open "/Applications/DepotBar.app"
fi

echo "Done."
