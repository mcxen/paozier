import re

from .constants import FILE_TYPE_BACKGROUNDS, FILE_TYPE_COLORS, FILE_TYPE_ICONS


def file_color(ext: str) -> str:
    return FILE_TYPE_COLORS.get(ext, "white")


def file_badge(ext: str) -> str:
    icon = FILE_TYPE_ICONS.get(ext, ext.upper()[:3])
    fg = file_color(ext)
    bg = FILE_TYPE_BACKGROUNDS.get(ext, "black")
    return f"[bold {fg} on {bg}] {icon} [/] "


def format_size(size: int) -> str:
    if size < 1024:
        return f"{size}B"
    if size < 1024 * 1024:
        return f"{size // 1024}KB"
    return f"{size / (1024 * 1024):.1f}MB"


def escape_markup(text: str) -> str:
    return text.replace("[", "\\[").replace("]", "\\]")


def compact_path(path: str, max_len: int = 96) -> str:
    if len(path) <= max_len:
        return escape_markup(path)
    keep = max_len - 3
    head = keep // 2
    tail = keep - head
    return f"{escape_markup(path[:head])}...{escape_markup(path[-tail:])}"


def highlight_terms(text: str, terms: list[str], max_len: int = 200) -> str:
    if not terms or not text:
        return escape_markup(text[:max_len])

    escaped = escape_markup(text[:max_len])
    for term in terms:
        if not term.strip():
            continue
        pattern = re.compile(re.escape(term), re.IGNORECASE)
        escaped = pattern.sub(lambda match: f"[bold black on bright_yellow]{match.group()}[/]", escaped)
    return escaped


def highlight_all(text: str, terms: list[str], max_len: int = 8000) -> str:
    if not terms or not text:
        return escape_markup(text[:max_len])

    escaped = escape_markup(text[:max_len])
    for term in terms:
        if not term.strip():
            continue
        pattern = re.compile(re.escape(term), re.IGNORECASE)
        escaped = pattern.sub(lambda match: f"[bold black on bright_yellow]{match.group()}[/]", escaped)
    return escaped
