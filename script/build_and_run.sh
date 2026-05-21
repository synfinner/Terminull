#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Terminull"
APP_VERSION="0.1.3b"
BUNDLE_SHORT_VERSION="0.1.3"
BUNDLE_BUILD_VERSION="0.1.3b1"
BUNDLE_ID="com.synfinner.Terminull"
MIN_SYSTEM_VERSION="14.0"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
CODE_SIGN_HARDENED_RUNTIME="${CODE_SIGN_HARDENED_RUNTIME:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon/terminull-app-icon-concept.png"
ICONSET_DIR="$DIST_DIR/$APP_NAME.iconset"
ICON_FILE="$APP_RESOURCES/$APP_NAME.icns"
RELEASE_ZIP="$DIST_DIR/$APP_NAME-$APP_VERSION-macOS-preview.zip"
CHECKSUM_FILE="$DIST_DIR/SHA256SUMS.txt"

cd "$ROOT_DIR"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

BUILD_CONFIGURATION="debug"
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  BUILD_CONFIGURATION="release"
fi

GITHUB_ACTIONS=true swift build -c "$BUILD_CONFIGURATION"
BUILD_DIR="$(GITHUB_ACTIONS=true swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_SOURCE" ]]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
  rm -rf "$ICONSET_DIR"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$BUNDLE_SHORT_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUNDLE_BUILD_VERSION</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

SIGN_FLAGS=(--force --deep --sign "$CODE_SIGN_IDENTITY")
if [[ "$CODE_SIGN_HARDENED_RUNTIME" == "1" ]]; then
  SIGN_FLAGS+=(--options runtime)
fi
codesign "${SIGN_FLAGS[@]}" "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package)
    ditto -c -k --keepParent "$APP_BUNDLE" "$RELEASE_ZIP"
    (cd "$DIST_DIR" && shasum -a 256 "$(basename "$RELEASE_ZIP")" >"$(basename "$CHECKSUM_FILE")")
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--verify|--package]" >&2
    exit 2
    ;;
esac
