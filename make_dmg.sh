#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_DIR="$(dirname "$PROJECT_DIR")"
APP_NAME="CodexTrafficLight"
VERSION="1.0"
BUNDLE="$WORKSPACE_DIR/${APP_NAME}.app"
SOURCES="$PROJECT_DIR/Sources/main.swift"
TMPDIR="/private/tmp/swift-cache"
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
STAGING="/tmp/dmg_staging"

echo "=== 1. 编译 ==="
mkdir -p "$TMPDIR"
cp "$SOURCES" "$TMPDIR/main.swift"
swiftc -o "$TMPDIR/$APP_NAME" "$TMPDIR/main.swift" \
    -sdk "$SDK" \
    -framework AppKit -framework UserNotifications \
    -module-cache-path "$TMPDIR"

echo "=== 2. 部署到 Bundle ==="
cp -f "$TMPDIR/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
codesign -s - --force "$BUNDLE/Contents/MacOS/$APP_NAME"

echo "=== 3. 准备 DMG ==="
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "=== 4. 创建 DMG ==="
rm -f "$PROJECT_DIR/$DMG_NAME"
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$PROJECT_DIR/$DMG_NAME" 2>&1

echo "=== 5. 清理 ==="
rm -rf "$STAGING"

echo ""
echo "✅ 完成: $PROJECT_DIR/$DMG_NAME"
ls -lh "$PROJECT_DIR/$DMG_NAME"
