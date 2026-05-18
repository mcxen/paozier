from textual.app import ComposeResult
from textual.widgets import ListItem, Static

from .constants import get_ext
from .formatting import file_badge, format_size, highlight_terms, escape_markup


class ResultItem(ListItem):
    """A search result row with highlighted terms."""

    def __init__(self, result: dict, search_terms: list[str]) -> None:
        super().__init__()
        self.result = result
        self.terms = search_terms

    def compose(self) -> ComposeResult:
        result = self.result
        ext = get_ext(result.get("filePath", ""))
        badge = file_badge(ext)
        name = result.get("fileName", "?")
        file_path = result.get("filePath", "")
        snippet = highlight_terms(result.get("snippet", "") or "", self.terms)
        size_str = format_size(result.get("fileSize", 0))

        yield Static(
            f"{badge} [bold]{escape_markup(name)}[/]  [dim]{size_str}[/]\n"
            f"[dim]{escape_markup(file_path)}[/]\n"
            f"{snippet}",
            markup=True,
            classes="result-row",
        )
