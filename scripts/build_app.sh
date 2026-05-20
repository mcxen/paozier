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
SIDECAR_DEST_DIR="$RESOURCES/bin"
SIDECAR_DEST="$SIDECAR_DEST_DIR/paozier-tantivy-sidecar"
APP_ICON_SOURCE="$PROJECT_DIR/Assets/AppIcon.png"
SIDECAR_MANIFEST="$PROJECT_DIR/rust/paozier-tantivy-sidecar/Cargo.toml"
HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" = "arm64" ]; then
    DEFAULT_SIDECAR_TARGET_TRIPLE="aarch64-apple-darwin"
else
    DEFAULT_SIDECAR_TARGET_TRIPLE="x86_64-apple-darwin"
fi
SIDECAR_TARGET_TRIPLE="${SIDECAR_TARGET_TRIPLE:-$DEFAULT_SIDECAR_TARGET_TRIPLE}"
SIDECAR_TARGET_DIR="$PROJECT_DIR/rust/paozier-tantivy-sidecar/target"
SIDECAR_BINARY="$SIDECAR_TARGET_DIR/$SIDECAR_TARGET_TRIPLE/release/paozier-tantivy-sidecar"

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
mkdir -p "$MACOS" "$RESOURCES" "$SIDECAR_DEST_DIR"

# Copy binary
cp "$BINARY" "$MACOS/$APP_NAME"
chmod +x "$MACOS/$APP_NAME"

# Copy SwiftPM resource bundles used by packaged previews/resources
BUILD_PRODUCT_DIR="$(dirname "$BINARY")"
find "$BUILD_PRODUCT_DIR" -maxdepth 1 -name "*.bundle" -type d -exec cp -R {} "$RESOURCES/" \;

if [ -f "$SIDECAR_MANIFEST" ]; then
    if ! command -v cargo >/dev/null 2>&1; then
        echo "ERROR: cargo is required to build the bundled Tantivy sidecar."
        exit 1
    fi

    echo "==> Building bundled Tantivy sidecar ($SIDECAR_TARGET_TRIPLE)..."
    cargo build \
        --manifest-path "$SIDECAR_MANIFEST" \
        --release \
        --target "$SIDECAR_TARGET_TRIPLE"

    if [ ! -f "$SIDECAR_BINARY" ]; then
        echo "ERROR: Tantivy sidecar not found at $SIDECAR_BINARY"
        exit 1
    fi

    cp "$SIDECAR_BINARY" "$SIDECAR_DEST"
    chmod +x "$SIDECAR_DEST"
fi

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
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

# App icon
if [ -f "$APP_ICON_SOURCE" ]; then
    ICONSET="$DIST_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"

    sips -z 16 16     "$APP_ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32     "$APP_ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$APP_ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64     "$APP_ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$APP_ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256   "$APP_ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$APP_ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512   "$APP_ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$APP_ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$APP_ICON_SOURCE" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

    iconutil -c icns "$ICONSET" -o "$RESOURCES/AppIcon.icns"
    rm -rf "$ICONSET"
else
    echo "WARNING: $APP_ICON_SOURCE not found; using generic app icon."
fi

# Ad-hoc codesign (no Apple Developer ID needed for local use)
echo "==> Signing..."
if [ -f "$SIDECAR_DEST" ]; then
    codesign --force --sign - "$SIDECAR_DEST"
fi
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$APP_PATH"
rm -f "$ENTITLEMENTS"

echo "==> Done: $APP_PATH"
echo "    Version: $VERSION ($BUILD_NUMBER)"
echo "    Size: $(du -sh "$APP_PATH" | cut -f1)"
echo ""
echo "    Run:     open $APP_PATH"
echo "    Install: bash scripts/install.sh"
