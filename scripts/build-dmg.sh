#!/bin/bash
set -e
cd "$(dirname "$0")/.."

echo "=== Building Paozier.app ==="
bash scripts/bundle-app.sh

APP=".build/Paozier.app"
DIST="dist"
DMG="$DIST/Paozier.dmg"

rm -rf "$DIST"
mkdir -p "$DIST"

echo "=== Creating DMG ==="
# Create temporary DMG folder
DMG_DIR=".build/dmg"
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

# Create DMG
hdiutil create -volname "Paozier" -srcfolder "$DMG_DIR" -ov -format UDZO "$DMG"
rm -rf "$DMG_DIR"

echo ""
echo "✓ DMG created: $DMG"
echo "  Size: $(du -sh "$DMG" | cut -f1)"
