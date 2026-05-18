TUI_CSS = """
Screen {
    layout: horizontal;
    background: black;
    color: white;
}

#search-pane {
    width: 2fr;
    min-width: 30;
    border-right: solid cyan;
    background: black;
}

#preview-pane {
    width: 3fr;
    min-width: 40;
    background: black;
}

.pane-title {
    padding: 1;
    text-style: bold;
    color: ansi_bright_white;
    background: blue;
}

#search-input {
    margin: 1;
    dock: top;
    background: black;
    border: tall white;
    color: white;
}

#result-count {
    padding: 0 1;
    text-style: italic;
    color: ansi_bright_black;
}

#results-list {
    height: 1fr;
    background: black;
}

ResultItem.-highlight .result-row {
    background: blue;
    color: ansi_bright_white;
}

.result-row {
    padding: 0 1;
    margin: 0 0 1 0;
    color: white;
}

.result-row:hover {
    background: ansi_bright_black;
}

#preview-scroll {
    height: 1fr;
    background: black;
}

#preview-meta {
    padding: 1 1 0 1;
    color: white;
    border-bottom: solid cyan;
    background: black;
}

#preview-status {
    padding: 0 1 1 1;
    color: ansi_bright_black;
    background: black;
}

#preview-content {
    padding: 1;
    height: 1fr;
    color: white;
    background: black;
}

#results-status {
    padding: 0 1;
    color: ansi_bright_black;
    text-align: center;
}

#status-bar {
    dock: bottom;
    height: 1;
    padding: 0 1;
    color: white;
    background: black;
}

Footer {
    dock: bottom;
    background: black;
    color: white;
}
"""
