#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP_NAME="GoldFarmClicker"
APP_DIR="$ROOT/build/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building release binary..."
swift build -c release

BINARY="$(swift build -c release --show-bin-path)/${APP_NAME}"
if [[ ! -x "$BINARY" ]]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi

echo "Assembling ${APP_NAME}.app..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/${APP_NAME}"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$MACOS/${APP_NAME}"

echo "Ad-hoc signing..."
codesign --force --sign - "$APP_DIR"

echo "Done: $APP_DIR"
echo "Run with: open \"$APP_DIR\""
