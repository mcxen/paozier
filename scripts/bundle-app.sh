#!/bin/bash
set -e
cd "$(dirname "$0")/.."

echo "Building Paozier..."
swift build -c release

PRODUCT=".build/release/Paozier"
APP_DIR=".build/Paozier.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

# Copy binary
cp "$PRODUCT" "$MACOS/Paozier"

# Copy Solr (minimal: bin + server/solr-webapp + modules/extraction + server/solr/paozier)
SOLR_DEST="$RESOURCES/solr"
mkdir -p "$SOLR_DEST/bin" "$SOLR_DEST/server/solr/paozier/conf" "$SOLR_DEST/server/lib" "$SOLR_DEST/server/solr-webapp"

cp solr/bin/solr "$SOLR_DEST/bin/"
cp -R solr/server/solr-webapp "$SOLR_DEST/server/"
cp -R solr/server/lib "$SOLR_DEST/server/"
cp -R solr/server/etc "$SOLR_DEST/server/" 2>/dev/null || true
cp -R solr/server/contexts "$SOLR_DEST/server/" 2>/dev/null || true
cp -R solr/server/modules "$SOLR_DEST/server/" 2>/dev/null || true
cp -R solr/server/resources "$SOLR_DEST/server/" 2>/dev/null || true
cp -R solr/server/start.jar "$SOLR_DEST/server/" 2>/dev/null || true
cp -R solr/modules "$SOLR_DEST/" 2>/dev/null || true

# Core config
cp scripts/schema.xml "$SOLR_DEST/server/solr/paozier/conf/"
cp scripts/solrconfig.xml "$SOLR_DEST/server/solr/paozier/conf/"
echo "name=paozier" > "$SOLR_DEST/server/solr/paozier/core.properties"

# Solr home marker
echo "" > "$SOLR_DEST/server/solr/solr.xml"

# Info.plist
cat > "$CONTENTS/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Paozier</string>
    <key>CFBundleIdentifier</key><string>com.openspring.paozier</string>
    <key>CFBundleName</key><string>Paozier</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><true/>
</dict>
</plist>
EOF

echo "✓ App bundle created at: $APP_DIR"
echo "  Size: $(du -sh "$APP_DIR" | cut -f1)"
