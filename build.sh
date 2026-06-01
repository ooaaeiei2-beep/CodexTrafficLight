#!/bin/bash
set -e
APP_DIR="$(cd "$(dirname "$0")" && pwd)/../CodexTrafficLight.app"
mkdir -p "$APP_DIR/Contents/MacOS"

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
CACHE=/tmp/swift-cache

rm -rf "$CACHE"
cp Sources/main.swift /private/tmp/
cd /private/tmp
swiftc -o CodexTrafficLight main.swift \
  -sdk "$SDK" \
  -framework AppKit \
  -framework UserNotifications \
  -module-cache-path "$CACHE"

cp /private/tmp/CodexTrafficLight "$APP_DIR/Contents/MacOS/CodexTrafficLight"
rm -f "$APP_DIR/Contents/MacOS/main.swift"
codesign -s - "$APP_DIR/Contents/MacOS/CodexTrafficLight"
echo "Build success: $APP_DIR"
