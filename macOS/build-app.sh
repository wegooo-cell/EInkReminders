#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"
swift build -c release

APP_DIR="$SCRIPT_DIR/build/墨水屏提醒事项.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$SCRIPT_DIR/.build/release/EInkRemindersMac" "$BIN_DIR/EInkRemindersMac"
cp "$SCRIPT_DIR/AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/AppBundle/AppIcon.icns" "$RES_DIR/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
