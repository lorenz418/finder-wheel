#!/bin/bash
# Builds "build/Finder Wheel.app" from the Swift package.
# Set SIGN_IDENTITY to a development certificate name to keep macOS permissions
# across rebuilds; the default ad-hoc signature makes macOS ask again after each rebuild.
# Set BUILD_DIR to a folder outside the repository if it lives in an iCloud-synced folder.
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="${BUILD_DIR:-.build}"
swift build -c release --scratch-path "$BUILD_DIR"
# Assembled and signed outside the repository: files in iCloud-synced folders pick up
# attributes that codesign rejects.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Finder Wheel.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/release/FinderWheel" "$APP/Contents/MacOS/FinderWheel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
mkdir -p build
rm -rf "build/Finder Wheel.app"
ditto --norsrc --noextattr "$APP" "build/Finder Wheel.app"
echo "Built build/Finder Wheel.app"
