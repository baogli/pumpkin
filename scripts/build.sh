#!/bin/bash
# Builds dist/Pumpkin.app (universal, release) and signs it.
#
#   scripts/build.sh                 # ad-hoc signature; not Apple notarized
#   SIGN_IDENTITY="Developer ID Application: …" scripts/build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/Pumpkin.app"
IDENTITY="${SIGN_IDENTITY:--}"
ARCHS=(--arch arm64 --arch x86_64)

echo "› Compiling (release, universal)…"
swift build -c release --product Pumpkin "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

if [ ! -f Resources/AppIcon.icns ] || [ ! -d Resources/AppIcon.icon ]; then
    echo "› Rendering icons…"
    swift scripts/make_icon.swift Resources
fi

echo "› Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Pumpkin" "$APP/Contents/MacOS/Pumpkin"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf "APPL????" > "$APP/Contents/PkgInfo"

# Layered Liquid Glass icon for macOS 26 and later.
ASSETS="$(mktemp -d)"
if xcrun actool Resources/AppIcon.icon --compile "$ASSETS" --platform macosx \
        --minimum-deployment-target 14.0 --app-icon AppIcon \
        --output-partial-info-plist "$ASSETS/partial.plist" >/dev/null 2>&1 \
        && [ -f "$ASSETS/Assets.car" ]; then
    cp "$ASSETS/Assets.car" "$APP/Contents/Resources/Assets.car"
else
    echo "  actool unavailable; using the flat icon only."
fi
rm -rf "$ASSETS"

echo "› Signing ($([ "$IDENTITY" = "-" ] && echo ad-hoc || echo "$IDENTITY"))…"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

echo "✓ $APP"
lipo -archs "$APP/Contents/MacOS/Pumpkin" | sed 's/^/  architectures: /'
