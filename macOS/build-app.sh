#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"
swift build -c release --disable-sandbox

APP_DIR="$SCRIPT_DIR/build/墨水屏提醒事项.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
mkdir -p "$BIN_DIR" "$RES_DIR"
cp "$SCRIPT_DIR/.build/release/EInkRemindersMac" "$BIN_DIR/EInkRemindersMac"
cp "$SCRIPT_DIR/AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$SCRIPT_DIR/AppBundle/AppIcon.icns" "$RES_DIR/AppIcon.icns"
cp "$SCRIPT_DIR/AppBundle/SourceHanSansSC-Regular.otf" "$RES_DIR/SourceHanSansSC-Regular.otf"
cp "$SCRIPT_DIR/AppBundle/SourceHanSansSC-Bold.otf" "$RES_DIR/SourceHanSansSC-Bold.otf"
cp "$SCRIPT_DIR/AppBundle/WenQuanYiBitmapSong16px.ttf" "$RES_DIR/WenQuanYiBitmapSong16px.ttf"
cp "$SCRIPT_DIR/AppBundle/WENQUANYI-FONT-NOTICE.txt" "$RES_DIR/WENQUANYI-FONT-NOTICE.txt"
cp "$SCRIPT_DIR/AppBundle/OFL-SourceHanSans.txt" "$RES_DIR/OFL-SourceHanSans.txt"
cp "$SCRIPT_DIR/AppBundle/SOURCE-HAN-NOTICE.txt" "$RES_DIR/SOURCE-HAN-NOTICE.txt"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
