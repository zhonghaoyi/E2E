#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="E2E"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
MODULE_CACHE_DIR="$BUILD_DIR/ModuleCache"
TMP_BUILD_DIR="$BUILD_DIR/tmp"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE_DIR" "$TMP_BUILD_DIR"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
ARCH="$(uname -m)"

SOURCES=()
while IFS= read -r file; do
  SOURCES+=("$file")
done < <(find "$ROOT_DIR/Sources" -name '*.swift' | sort)

env CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR" TMPDIR="$TMP_BUILD_DIR" \
  swiftc \
    -target "$ARCH-apple-macosx14.0" \
    -sdk "$SDK_PATH" \
    -parse-as-library \
    -O \
    -framework AppKit \
    -framework SwiftUI \
    -framework Security \
    -framework ApplicationServices \
    -o "$MACOS_DIR/$APP_NAME" \
    "${SOURCES[@]}"

chmod +x "$MACOS_DIR/$APP_NAME"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP_DIR" >/dev/null
fi
echo "$APP_DIR"
