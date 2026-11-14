#!/bin/bash
# Builds the app and zips it for a release: build/Finder-Wheel-<version>.zip
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
ZIP="build/Finder-Wheel-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent "build/Finder Wheel.app" "$ZIP"
echo "Packaged $ZIP"
