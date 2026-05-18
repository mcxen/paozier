# Paozier TUI

Terminal client for Paozier's HTTP search API.

## Files

- `paozier_tui.py`: thin entrypoint
- `paozier_tui_app/app.py`: Textual app and actions
- `paozier_tui_app/api.py`: HTTP client wrapper
- `paozier_tui_app/widgets.py`: result list widgets
- `paozier_tui_app/formatting.py`: badges, path compression, highlighting
- `paozier_tui_app/constants.py`: API URL and file-type mappings
- `paozier_tui_app/styles.py`: Textual CSS

## Run

```bash
cd Sources/TUI
python3 paozier_tui.py
```

## One-click launch

Double-click `run_tui.command`, or run:

```bash
cd Sources/TUI
./run_tui.command
```

What the launcher does:

- creates a local `.venv` on first run
- installs dependencies from `requirements.txt`
- tries to open the main `Paozier` app if `localhost:9880` is not ready
- starts the TUI with the venv Python

## Shortcuts

- `Ctrl+F`: focus search
- `Ctrl+R`: refresh status and rerun the current query
- `Ctrl+O`: open selected file
- `Ctrl+E`: reveal selected file in Finder
- `j` / `k`: move in the result list
- `Esc`: clear search or clear preview
- `Ctrl+Q`: quit
