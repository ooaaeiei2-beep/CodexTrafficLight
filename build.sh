#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/../CodexTrafficLight.app"
mkdir -p "$APP_DIR/Contents/MacOS"

# 自动找 SDK
SDK=""
for d in /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk; do
    if [ -d "$d" ]; then SDK="$d"; break; fi
done
if [ -z "$SDK" ]; then echo "macOS SDK not found"; exit 1; fi
echo "Using SDK: $SDK"

CACHE=/tmp/swift-cache
rm -rf "$CACHE"
cp "$SCRIPT_DIR/Sources/main.swift" /private/tmp/
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
echo ""
echo "Next steps:"
echo "  1. cd $SCRIPT_DIR"
echo '  2. sed -i "" "s|REPO_DIR|$(pwd)|g" hooks.json'
echo '  3. cp hooks.json ~/.codex/hooks.json'
echo '  4. 在 ~/.codex/config.toml 的 [features] 下加: hooks = true'
echo '  5. 重启 Codex'
