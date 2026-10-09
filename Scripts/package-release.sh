#!/bin/zsh
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/dist/Majdata Mac.app"
PLIST="$APP_PATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")
ARCH=$(lipo -archs "$APP_PATH/Contents/MacOS/MajdataMac")
if [[ "$ARCH" != "arm64" ]]; then
    print -u2 "This release recipe is verified for arm64 only; found: $ARCH"
    exit 1
fi
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
OUTPUT_DIR="${RELEASE_OUTPUT:-$PROJECT_DIR/dist/release-$VERSION}"
if [[ -e "$OUTPUT_DIR" ]]; then
    print -u2 "Refusing to overwrite existing release directory: $OUTPUT_DIR"
    exit 1
fi
TEMP_DIR=$(mktemp -d "$PROJECT_DIR/.build/release-package.XXXXXX")
MOUNT_PATH="$TEMP_DIR/mounted"
cleanup() {
    if mount | /usr/bin/grep -Fq " on $MOUNT_PATH "; then
        hdiutil detach "$MOUNT_PATH" >/dev/null
    fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT
mkdir -p "$TEMP_DIR/image" "$TEMP_DIR/output" "$TEMP_DIR/zip-check" "$MOUNT_PATH"
NAME="MajdataMac-$VERSION-macOS-arm64"
ditto "$APP_PATH" "$TEMP_DIR/image/Majdata Mac.app"
ln -s /Applications "$TEMP_DIR/image/Applications"
cp "$PROJECT_DIR/Documentation/Install.md" "$TEMP_DIR/image/安装说明.txt"
cp "$PROJECT_DIR/Documentation/Install.md" "$TEMP_DIR/output/INSTALL.txt"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$TEMP_DIR/output/$NAME.zip"
unzip -tq "$TEMP_DIR/output/$NAME.zip"
ditto -x -k "$TEMP_DIR/output/$NAME.zip" "$TEMP_DIR/zip-check"
codesign --verify --deep --strict --verbose=2 "$TEMP_DIR/zip-check/Majdata Mac.app"
hdiutil create -volname "Majdata Mac $VERSION" -srcfolder "$TEMP_DIR/image" \
    -format UDZO -ov "$TEMP_DIR/output/$NAME.dmg"
hdiutil verify "$TEMP_DIR/output/$NAME.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_PATH" "$TEMP_DIR/output/$NAME.dmg"
codesign --verify --deep --strict --verbose=2 "$MOUNT_PATH/Majdata Mac.app"
# Compare all ordinary file bytes, not only the executable, after both formats
# have been unpacked by the standard macOS tools.
python3 - "$APP_PATH" "$TEMP_DIR/zip-check/Majdata Mac.app" "$MOUNT_PATH/Majdata Mac.app" <<'PY'
import hashlib, pathlib, sys
def manifest(folder):
    root = pathlib.Path(folder)
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}
original = manifest(sys.argv[1])
for copy in sys.argv[2:]:
    if manifest(copy) != original:
        raise SystemExit('Packaged contents differ: ' + copy)
print(f'ZIP and DMG match all {len(original)} application files.')
PY
hdiutil detach "$MOUNT_PATH"
(
    cd "$TEMP_DIR/output"
    shasum -a 256 "$NAME.dmg" "$NAME.zip" INSTALL.txt > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)
mkdir -p "$(dirname "$OUTPUT_DIR")"
mv "$TEMP_DIR/output" "$OUTPUT_DIR"
printf 'Release files: %s\n' "$OUTPUT_DIR"
