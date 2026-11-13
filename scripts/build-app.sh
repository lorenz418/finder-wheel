#!/bin/bash
# Builds "build/Finder Wheel.app" from the Swift package.
# Set SIGN_IDENTITY to a development certificate name to keep macOS permissions
# across rebuilds; the default ad-hoc signature makes macOS ask again after each rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Finder Wheel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/FinderWheel "$APP/Contents/MacOS/FinderWheel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
