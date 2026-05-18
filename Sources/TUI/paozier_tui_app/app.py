from textual import on, work
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.reactive import reactive
from textual.timer import Timer
from textual.widgets import Footer, Header, Input, Label, ListView, Rule, Static
from textual.containers import VerticalScroll

import httpx

from .api import PaozierAPI
from .constants import get_ext
from .formatting import compact_path, escape_markup, file_badge, format_size, highlight_all
from .styles import TUI_CSS
from .widgets import ResultItem


class PaozierTUI(App):
    """Paozier TUI - Terminal client for document search."""

    CSS = TUI_CSS
    TITLE = "Paozier TUI"
    SUB_TITLE = "Document Search Engine"

    BINDINGS = [
        Binding("ctrl+q", "quit", "Quit"),
        Binding("ctrl+f", "focus_search", "Search"),
        Binding("ctrl+r", "refresh", "Refresh"),
        Binding("ctrl+o", "open_selected", "Open"),
        Binding("ctrl+e", "reveal_selected", "Reveal"),
        Binding("j", "cursor_down", "Down", show=False),
        Binding("k", "cursor_up", "Up", show=False),
        Binding("escape", "esc", "Clear/Back", show=False),
    ]

    connected: reactive[bool] = reactive(False)
    doc_count: reactive[int] = reactive(0)
    folder_count: reactive[int] = reactive(0)

    def __init__(self) -> None:
        super().__init__()
        self._api = PaozierAPI()
        self._debounce_timer: Timer | None = None
        self._results: list[dict] = []
        self._current_query: str = ""
        self._selected_result: dict | None = None

    def compose(self) -> ComposeResult:
        yield Header()
        with VerticalScroll(id="search-pane"):
            yield Static("[bold] Search[/]", classes="pane-title")
            yield Input(placeholder="Type to search...", id="search-input")
            yield Rule()
            yield Label("", id="result-count")
            yield ListView(id="results-list")
            yield Static("", id="results-status")
        with VerticalScroll(id="preview-pane"):
            yield Static("[bold] Preview[/]", classes="pane-title")
            yield Static("", id="preview-meta")
            yield Static("", id="preview-status")
            with VerticalScroll(id="preview-scroll"):
                yield Static("Select a result to preview", id="preview-content")
        yield Static("Connecting...", id="status-bar")
        yield Footer()

    def on_mount(self) -> None:
        self.check_status()

    def watch_connected(self, _: bool) -> None:
        self._update_status_bar()

    def watch_doc_count(self, _: int) -> None:
        self._update_status_bar()

    def watch_folder_count(self, _: int) -> None:
        self._update_status_bar()

    def _update_status_bar(self) -> None:
        dot = "[green]●[/]" if self.connected else "[red]●[/]"
        bar = self.query_one("#status-bar", Static)
        if self.connected:
            bar.update(
                f"{dot} Connected  |  📂 {self.folder_count} folders  "
                f"|  📄 {self.doc_count} docs  "
                f"|  📡 localhost:9880"
            )
        else:
            bar.update(f"{dot} Disconnected — start Paozier app first")

    @on(Input.Changed, "#search-input")
    def on_search_changed(self, event: Input.Changed) -> None:
        if self._debounce_timer:
            self._debounce_timer.stop()
        self._debounce_timer = self.set_timer(0.3, lambda: self._do_search(event.value))

    def _do_search(self, query: str) -> None:
        query = query.strip()
        self._current_query = query
        if query:
            self._perform_search(query)
        else:
            self._clear_results()

    @work(exclusive=True)
    async def _perform_search(self, query: str) -> None:
        list_view = self.query_one("#results-list", ListView)
        status_label = self.query_one("#results-status", Static)
        try:
            status_label.update("[italic]Searching...[/]")
            data = await self._api.search(query)
            self._results = data.get("results", [])
            total = data.get("total", len(self._results))

            self.query_one("#result-count", Label).update(f"Found {total} results")
            await list_view.clear()

            terms = query.split()
            for result in self._results:
                await list_view.append(ResultItem(result, terms))

            if not self._results:
                status_label.update("[italic]No results found[/]")
            else:
                status_label.update("[dim]j/k navigate · Enter preview[/]")
        except httpx.ConnectError:
            self.connected = False
            status_label.update("[bold red]Cannot connect to Paozier[/]")
        except Exception as exc:
            status_label.update(f"[red]Error: {exc}[/]")

    def _clear_results(self) -> None:
        self.query_one("#results-list", ListView).clear()
        self.query_one("#result-count", Label).update("")
        self.query_one("#results-status", Static).update("")
        self._results = []
        self._clear_preview()

    @on(ListView.Selected, "#results-list")
    def on_result_selected(self, event: ListView.Selected) -> None:
        item = event.item
        if isinstance(item, ResultItem):
            self._selected_result = item.result
            self._show_preview(item.result)

    @work(exclusive=True)
    async def _show_preview(self, result: dict) -> None:
        meta = self.query_one("#preview-meta", Static)
        status = self.query_one("#preview-status", Static)
        pane = self.query_one("#preview-content", Static)

        path = result.get("filePath", "")
        name = result.get("fileName", "?")
        ext = get_ext(path)
        badge = file_badge(ext)
        terms = self._current_query.split()
        size = format_size(result.get("fileSize", 0))
        snippet = result.get("snippet", "") or ""

        meta.update(
            f"{badge} [bold]{escape_markup(name)}[/]  [dim]{size}[/]\n"
            f"[dim]{compact_path(path)}[/]"
        )
        status.update("[dim]Fetching extracted preview text...[/]")
        pane.update("[italic]Loading file content...[/]")

        try:
            response = await self._api.content(path)
            if response.status_code >= 400:
                raise RuntimeError(response.text.strip() or f"HTTP {response.status_code}")
            content = response.text
            preview_body = highlight_all(content, terms)
            if not preview_body.strip():
                raise RuntimeError("Empty preview")
            status.update("[dim]Enter/selection auto-preview · Ctrl+O open · Ctrl+E reveal[/]")
            pane.update(preview_body)
        except Exception as exc:
            fallback = highlight_all(snippet, terms, max_len=1200)
            reason = escape_markup(str(exc) or "Preview unavailable")
            status.update(f"[yellow]Preview fallback[/] [dim]{reason}[/]")
            pane.update(
                "[bold]Match excerpt[/]\n"
                f"{fallback or '[dim]No snippet available[/]'}\n\n"
                "[bold]Tips[/]\n"
                "[dim]Use Ctrl+O to open the file or Ctrl+E to reveal it in Finder.[/]"
            )

    def _clear_preview(self) -> None:
        self._selected_result = None
        self.query_one("#preview-meta", Static).update("")
        self.query_one("#preview-status", Static).update("")
        self.query_one("#preview-content", Static).update("Select a result to preview")

    @work(exclusive=True)
    async def check_status(self) -> None:
        try:
            data = await self._api.status()
            self.connected = data.get("ok", False)
            self.doc_count = data.get("documents", 0)
            self.folder_count = len(data.get("folders", []))
        except Exception:
            self.connected = False

    def action_focus_search(self) -> None:
        self.query_one("#search-input", Input).focus()

    def action_refresh(self) -> None:
        self.check_status()
        if self._current_query:
            self._perform_search(self._current_query)

    @work
    async def action_open_selected(self) -> None:
        if not self._selected_result:
            return
        path = self._selected_result.get("filePath", "")
        if path:
            try:
                await self._api.open_file(path)
            except Exception:
                pass

    @work
    async def action_reveal_selected(self) -> None:
        if not self._selected_result:
            return
        path = self._selected_result.get("filePath", "")
        if path:
            try:
                await self._api.reveal_file(path)
            except Exception:
                pass

    def action_cursor_down(self) -> None:
        list_view = self.query_one("#results-list", ListView)
        if list_view.index is None:
            list_view.index = 0
        else:
            list_view.index = min(list_view.index + 1, len(self._results) - 1)

    def action_cursor_up(self) -> None:
        list_view = self.query_one("#results-list", ListView)
        if list_view.index is None or list_view.index <= 0:
            list_view.index = 0
        else:
            list_view.index = list_view.index - 1

    def action_esc(self) -> None:
        search_input = self.query_one("#search-input", Input)
        if search_input.value:
            search_input.value = ""
            search_input.focus()
        else:
            self._clear_preview()
