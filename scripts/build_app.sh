#!/bin/bash
set -euo pipefail

APP_NAME="Paozier"
BUNDLE_ID="com.openspring.paozier"
VERSION="${1:-1.0.0}"
BUILD_NUMBER="${2:-1}"
MIN_OS="14.0"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$PROJECT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "==> Building $APP_NAME v$VERSION ($BUILD_NUMBER)..."

cd "$PROJECT_DIR"

# Build release binary (universal if possible, fallback to native arch)
if swift build -c release --arch arm64 --arch x86_64 2>/dev/null; then
    BINARY=".build/apple/Products/Release/$APP_NAME"
    if [ ! -f "$BINARY" ]; then
        BINARY=".build/release/$APP_NAME"
    fi
else
    echo "    Universal build failed, building native arch..."
    swift build -c release
    BINARY=".build/release/$APP_NAME"
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Packaging .app bundle..."

rm -rf "$APP_PATH"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$BINARY" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_OS}</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Paozier runs local HTTP and MCP servers for search access.</string>
</dict>
</plist>
PLIST

# Entitlements (network server + file access)
ENTITLEMENTS="$DIST_DIR/entitlements.plist"
cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
ENT

# PkgInfo
echo -n "APPL????" > "$CONTENTS/PkgInfo"

# Placeholder app icon (empty icns — Finder will show generic app icon)
# To add a real icon, replace Resources/AppIcon.icns
touch "$RESOURCES/AppIcon.icns"

# Ad-hoc codesign (no Apple Developer ID needed for local use)
echo "==> Signing..."
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_PATH"
rm -f "$ENTITLEMENTS"

echo "==> Done: $APP_PATH"
echo "    Version: $VERSION ($BUILD_NUMBER)"
echo "    Size: $(du -sh "$APP_PATH" | cut -f1)"
echo ""
echo "    Run:     open $APP_PATH"
echo "    Install: bash scripts/install.sh"
