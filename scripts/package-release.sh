#!/bin/bash
# Package an already-built universal Pumpkin.app without private state or caches.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="dist/Pumpkin.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCHS=$(lipo -archs "$APP/Contents/MacOS/Pumpkin")
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || { echo 'A release requires both arm64 and x86_64.' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
mkdir -p release
ditto -c -k --sequesterRsrc --keepParent "$APP" "release/Pumpkin-$VERSION-macOS.zip"
(cd release && shasum -a 256 "Pumpkin-$VERSION-macOS.zip" > SHA256SUMS)
echo "release/Pumpkin-$VERSION-macOS.zip"
