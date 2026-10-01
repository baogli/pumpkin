#!/bin/bash
# Run AppKit QA with an app identity (the plain CLI does not have the same
# WindowServer focus behavior). Temporary files and preferences only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift build --product PumpkinQA
BIN="$(swift build --show-bin-path)"
QA_ROOT="$(mktemp -d /tmp/pumpkin-qa-bundle.XXXXXX)"
trap 'rm -rf "$QA_ROOT"' EXIT
QA_APP="$QA_ROOT/PumpkinQA.app"
mkdir -p "$QA_APP/Contents/MacOS"
cp "$BIN/PumpkinQA" "$QA_APP/Contents/MacOS/PumpkinQA"
cat > "$QA_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>PumpkinQA</string>
<key>CFBundleIdentifier</key><string>app.pumpkin.QA</string>
<key>CFBundleExecutable</key><string>PumpkinQA</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$QA_APP"
"$QA_APP/Contents/MacOS/PumpkinQA" "$@"
