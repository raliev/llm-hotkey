#!/bin/bash
# Builds a universal (Apple Silicon + Intel) "LLM Hotkey.app" and dist/LLM-Hotkey-<version>.zip
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
APP="dist/LLM Hotkey.app"
FRAMEWORKS="-framework Cocoa -framework Carbon -framework CoreGraphics -framework AVFoundation -framework NaturalLanguage"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist/obj

for arch in arm64 x86_64; do
    swiftc -O -target "$arch-apple-macos12" -o "dist/obj/text_hotkey-$arch" text_hotkey.swift $FRAMEWORKS
done
lipo -create -output "$APP/Contents/MacOS/llm-hotkey" dist/obj/text_hotkey-arm64 dist/obj/text_hotkey-x86_64

cp ticking.mp3 "$APP/Contents/Resources/"

# App icon: render 1024px PNG, then scale into an .iconset and pack as .icns
swiftc -O -o dist/obj/make_icon make_icon.swift -framework Cocoa
dist/obj/make_icon dist/obj/icon.png
ICONSET=dist/obj/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s dist/obj/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) dist/obj/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
rm -rf dist/obj

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>LLM Hotkey</string>
    <key>CFBundleDisplayName</key><string>LLM Hotkey</string>
    <key>CFBundleIdentifier</key><string>com.raliev.llm-hotkey</string>
    <key>CFBundleExecutable</key><string>llm-hotkey</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP"
(cd dist && ditto -c -k --keepParent "LLM Hotkey.app" "LLM-Hotkey-$VERSION.zip")
echo "Built: $APP"
echo "Zip:   dist/LLM-Hotkey-$VERSION.zip"
