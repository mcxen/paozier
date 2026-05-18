#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [ "${TERM:-dumb}" = "dumb" ]; then
  export TERM=xterm-256color
fi
export COLORTERM=truecolor

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR="$SCRIPT_DIR/.venv"
REQ_FILE="$SCRIPT_DIR/requirements.txt"
STAMP_FILE="$VENV_DIR/.requirements.stamp"

echo "==> Preparing Paozier TUI..."

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "ERROR: python3 not found."
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

if [ ! -d "$VENV_DIR" ]; then
  echo "==> Creating local virtual environment..."
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

if [ ! -f "$STAMP_FILE" ] || ! cmp -s "$REQ_FILE" "$STAMP_FILE"; then
  echo "==> Installing TUI dependencies..."
  "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
  "$VENV_DIR/bin/python" -m pip install -r "$REQ_FILE"
  cp "$REQ_FILE" "$STAMP_FILE"
fi

if ! curl -sf "http://localhost:9880/api/status" >/dev/null 2>&1; then
  echo "==> Paozier app is not responding on :9880, trying to launch it..."
  open -a Paozier || true
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    if curl -sf "http://localhost:9880/api/status" >/dev/null 2>&1; then
      break
    fi
  done
fi

echo "==> Launching TUI..."
"$VENV_DIR/bin/python" "$SCRIPT_DIR/paozier_tui.py"

echo ""
echo "Paozier TUI exited. Close this window or press Cmd+Q."
read -n 1 -s -r -p "Press any key to close..."
