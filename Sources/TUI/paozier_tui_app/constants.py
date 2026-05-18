from pathlib import Path

BASE_URL = "http://localhost:9880"

FILE_TYPE_COLORS = {
    "pdf": "red",
    "doc": "cyan",
    "docx": "cyan",
    "xls": "green",
    "xlsx": "green",
    "pptx": "yellow",
    "md": "magenta",
    "txt": "white",
    "json": "yellow",
    "swift": "yellow",
    "py": "yellow",
    "js": "yellow",
    "ts": "yellow",
    "java": "yellow",
    "c": "yellow",
    "cpp": "yellow",
    "rs": "yellow",
    "go": "yellow",
    "html": "yellow",
    "css": "yellow",
    "xml": "yellow",
}

FILE_TYPE_BACKGROUNDS = {
    "pdf": "red",
    "doc": "blue",
    "docx": "blue",
    "xls": "green",
    "xlsx": "green",
    "pptx": "yellow",
    "md": "magenta",
    "txt": "black",
    "json": "yellow",
    "swift": "yellow",
    "py": "yellow",
    "js": "yellow",
    "ts": "yellow",
    "java": "yellow",
    "c": "yellow",
    "cpp": "yellow",
    "rs": "yellow",
    "go": "yellow",
    "html": "yellow",
    "css": "yellow",
    "xml": "yellow",
}

FILE_TYPE_ICONS = {
    "pdf": "PDF",
    "doc": "DOC",
    "docx": "DOC",
    "xls": "XLS",
    "xlsx": "XLS",
    "pptx": "PPT",
    "md": "MD",
    "txt": "TXT",
    "json": "{}",
    "swift": "<>",
    "py": "PY",
    "js": "JS",
    "ts": "TS",
    "java": "JV",
    "c": "C",
    "cpp": "CP",
    "rs": "RS",
    "go": "GO",
}


def get_ext(path: str) -> str:
    return Path(path).suffix.lstrip(".").lower()
