#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
"$PROJECT_DIR/Scripts/build-shaders.sh"
swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION"
BIN_DIR="$(swift build --package-path "$PROJECT_DIR" -c "$CONFIGURATION" --show-bin-path)"
PACKAGE_DIR="$(mktemp -d "$PROJECT_DIR/.build/package.XXXXXX")"
trap 'rm -rf "$PACKAGE_DIR"' EXIT
APP_PATH="$PACKAGE_DIR/Majdata Mac.app"
DESTINATION="$PROJECT_DIR/dist/Majdata Mac.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/MajdataMac" "$APP_PATH/Contents/MacOS/MajdataMac.new"
mv -f "$APP_PATH/Contents/MacOS/MajdataMac.new" "$APP_PATH/Contents/MacOS/MajdataMac"
for RESOURCE_BUNDLE in "$BIN_DIR"/*.bundle; do
    ditto "$RESOURCE_BUNDLE" "$APP_PATH/Contents/Resources/$(basename "$RESOURCE_BUNDLE")"
done
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/LICENSE" "$APP_PATH/Contents/Resources/LICENSE"
cp "$PROJECT_DIR/NOTICE.txt" "$PROJECT_DIR/README.txt" "$APP_PATH/Contents/Resources/"
ditto "$PROJECT_DIR/Documentation" "$APP_PATH/Contents/Resources/Documentation"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MajdataMac</string>
<key>CFBundleIdentifier</key><string>local.majdata.mac</string>
<key>CFBundleName</key><string>Majdata Mac</string>
<key>CFBundleDisplayName</key><string>Majdata Mac</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.5</string>
<key>CFBundleVersion</key><string>9</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Based on Majdata by bbben and contributors. GPL-3.0.</string>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Simai Chart</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSItemContentTypes</key><array><string>public.plain-text</string></array><key>LSHandlerRank</key><string>Alternate</string></dict></array>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP_PATH"
mkdir -p "$PROJECT_DIR/dist"
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$PACKAGE_DIR/previous.app"; fi
mv "$APP_PATH" "$DESTINATION"
printf '%s\n' "$DESTINATION"
