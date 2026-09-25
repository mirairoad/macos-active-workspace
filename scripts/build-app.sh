#!/usr/bin/env bash
#
# Build Workit.app from this checkout.
#
#   bash scripts/build-app.sh [output dir]    (default: build/)
#
# install.sh uses this, and it is handy for trying a change without installing it:
#
#   bash scripts/build-app.sh && open build/Workit.app

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/build}"

NAME="Workit"
BUNDLE_ID="com.mirairoad.workit"
VERSION="1.0.0"

APP="$OUT/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

xcrun swiftc -O -o "$APP/Contents/MacOS/$NAME" "$ROOT"/src/*.swift -framework AppKit
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/"

# LSUIElement keeps it out of the Dock and the app switcher: it lives in the menu bar only
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# An ad-hoc signature: enough for a Mac to run an app it built itself, not for handing it to others
codesign --force --sign - "$APP" 2>/dev/null

echo "$APP"
