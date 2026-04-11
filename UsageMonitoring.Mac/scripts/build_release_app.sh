#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="UsageMonitoringMac"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"
GENERATED_ICON="$BUILD_DIR/AppIcon-1024.png"
INFO_PLIST_SOURCE="$ROOT_DIR/Packaging/Info.plist"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"

mkdir -p "$DIST_DIR"

echo "Building release executable..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --package-path "$ROOT_DIR"
BIN_DIR="$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --package-path "$ROOT_DIR" --show-bin-path)"

echo "Preparing app bundle..."
rm -rf "$APP_BUNDLE" "$ICONSET_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR"

cp "$BIN_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
cp "$INFO_PLIST_SOURCE" "$CONTENTS_DIR/Info.plist"

echo "Rendering icon source..."
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift "$ROOT_DIR/scripts/generate_app_icon.swift" "$GENERATED_ICON" >/dev/null

echo "Generating AppIcon.icns..."
for size in 16 32 64 128 256 512; do
  sips -z "$size" "$size" "$GENERATED_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
done

for size in 16 32 128 256 512; do
  double_size=$((size * 2))
  sips -z "$double_size" "$double_size" "$GENERATED_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
/usr/bin/touch "$CONTENTS_DIR/Info.plist" "$ICON_PATH" "$APP_BUNDLE"

echo "Signing app bundle..."
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null

echo "Creating zip archive..."
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo
echo "Done."
echo "App bundle: $APP_BUNDLE"
echo "Zip archive: $ZIP_PATH"
