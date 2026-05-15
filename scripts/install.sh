#!/bin/bash
set -euo pipefail

APP_NAME="Paozier"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="$PROJECT_DIR/dist/$APP_NAME.app"
INSTALL_DIR="/Applications"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found. Run 'bash scripts/build_app.sh' first."
    exit 1
fi

echo "==> Installing $APP_NAME to $INSTALL_DIR..."

# Remove old version if present
if [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    echo "    Removing existing installation..."
    rm -rf "$INSTALL_DIR/$APP_NAME.app"
fi

cp -R "$APP_PATH" "$INSTALL_DIR/$APP_NAME.app"

echo "==> Installed: $INSTALL_DIR/$APP_NAME.app"
echo "    Launch: open -a $APP_NAME"
