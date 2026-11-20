#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
buildDirectory=$(mktemp -d "${TMPDIR:-/tmp}/MacThermal-build.XXXXXX")
trap 'rm -rf "$buildDirectory"' EXIT
appPath="$buildDirectory/MacThermal.app"
mkdir -p "$appPath/Contents/MacOS" "$appPath/Contents/Resources"
cp Resources/*.sh "$appPath/Contents/Resources/"
xcrun clang -O2 -mmacosx-version-min=12.0 -c Sources/SMC.c -o build/SMC.o
xcrun swiftc -swift-version 5 -O -target x86_64-apple-macosx12.0 -import-objc-header Sources/SMC.h Sources/main.swift Sources/ThermalModel.swift build/SMC.o -framework AppKit -framework IOKit -framework Metal -o "$appPath/Contents/MacOS/MacThermal"
xcrun clang -O2 -mmacosx-version-min=12.0 Sources/FanAssist.c build/SMC.o -framework IOKit -o "$appPath/Contents/MacOS/FanAssist"
xattr -cr "$appPath"
codesign --force --sign - "$appPath/Contents/MacOS/FanAssist"
cat > "$appPath/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MacThermal</string>
<key>CFBundleIdentifier</key><string>fr.local.MacThermal</string>
<key>CFBundleName</key><string>MacThermal</string>
<key>CFBundleDisplayName</key><string>MacThermal</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>1.3</string>
<key>LSMinimumSystemVersion</key><string>12.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$appPath"
codesign --force --sign - "$appPath"

codesign --verify --deep --strict "$appPath"
ditto --norsrc "$appPath" MacThermal.app
