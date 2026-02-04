#!/usr/bin/env python3
import json
import sys
from pathlib import Path

from PySide6 import QtCore, QtGui, QtWidgets

try:
    from appdirs import user_log_dir
except ImportError as exc:
    raise SystemExit("Missing dependency: appdirs. Install it to resolve user log dir.") from exc

APP_NAME = "space"
LOG_SUBDIR = "openai"
LOG_FILE = "requests.jsonl"

COLUMNS = ["entry"]


def log_path() -> Path:
    base = Path(user_log_dir(APP_NAME))
    return base / LOG_SUBDIR / LOG_FILE


def safe_str(value) -> str:
    if value is None:
        return ""
    if isinstance(value, (str, int, float, bool)):
        return str(value)
    try:
        return json.dumps(value, ensure_ascii=True)
    except Exception:
        return str(value)


def load_entries(path: Path) -> list[dict]:
    entries: list[dict] = []
    if not path.exists():
        return entries
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                entries.append({"timestamp": "", "event": "parse_error", "error": line})
    return entries


def group_entries(entries: list[dict]) -> tuple[dict[str, list[dict]], list[dict]]:
    grouped: dict[str, list[dict]] = {}
    ungrouped: list[dict] = []
    for entry in entries:
        request_id = safe_str(entry.get("request_id"))
        if request_id:
            grouped.setdefault(request_id, []).append(entry)
        else:
            ungrouped.append(entry)
    return grouped, ungrouped


class RequestsModel(QtGui.QStandardItemModel):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setHorizontalHeaderLabels(COLUMNS)

    def clear_rows(self) -> None:
        self.removeRows(0, self.rowCount())

    def add_entry(self, entry: dict) -> None:
        row_items = [QtGui.QStandardItem(self._format_entry_label(entry))]
        row_items[0].setEditable(False)
        row_items[0].setData(entry, QtCore.Qt.UserRole)
        self.appendRow(row_items)
        self._append_json_children(row_items[0], entry)

    def add_group(self, request_id: str, entries: list[dict]) -> None:
        group_items = [QtGui.QStandardItem(request_id)]
        group_items[0].setEditable(False)
        group_items[0].setFont(self._bold_font())
        self.appendRow(group_items)
        for entry in entries:
            row_items = [QtGui.QStandardItem(self._format_entry_label(entry))]
            row_items[0].setEditable(False)
            row_items[0].setData(entry, QtCore.Qt.UserRole)
            group_items[0].appendRow(row_items)
            self._append_json_children(row_items[0], entry)

    def _bold_font(self) -> QtGui.QFont:
        font = QtGui.QFont()
        font.setBold(True)
        return font

    def _append_json_children(self, parent: QtGui.QStandardItem, value) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                self._append_json_node(parent, str(key), child)
        elif isinstance(value, list):
            if self._looks_like_kv_pairs(value):
                for pair in value:
                    key = pair[0]
                    val = pair[1] if len(pair) > 1 else None
                    self._append_json_node(parent, safe_str(key), val)
            else:
                for idx, child in enumerate(value):
                    self._append_json_node(parent, f"[{idx}]", child)

    def _append_json_node(self, parent: QtGui.QStandardItem, key: str, value) -> None:
        label = f"{key}: {self._format_json_value(value)}"
        key_item = QtGui.QStandardItem(label)
        key_item.setEditable(False)
        parent.appendRow([key_item])
        if isinstance(value, dict):
            for child_key, child_value in value.items():
                self._append_json_node(key_item, str(child_key), child_value)
        elif isinstance(value, list):
            if self._looks_like_kv_pairs(value):
                for pair in value:
                    child_key = pair[0]
                    child_val = pair[1] if len(pair) > 1 else None
                    self._append_json_node(key_item, safe_str(child_key), child_val)
            else:
                for idx, child_value in enumerate(value):
                    self._append_json_node(key_item, f"[{idx}]", child_value)

    def _format_json_value(self, value) -> str:
        if isinstance(value, dict):
            return "{...}"
        if isinstance(value, list):
            return f"[{len(value)}]"
        return safe_str(value)

    def _looks_like_kv_pairs(self, value) -> bool:
        if not value:
            return False
        for item in value:
            if not isinstance(item, (list, tuple)):
                return False
            if len(item) == 0:
                return False
            if not isinstance(item[0], str):
                return False
        return True

    def _format_entry_label(self, entry: dict) -> str:
        timestamp = safe_str(entry.get("timestamp"))
        event = safe_str(entry.get("event"))
        label = event if event else safe_str(entry.get("request_id"))
        if timestamp:
            return f"[{timestamp}] {label}"
        return label


class Viewer(QtWidgets.QMainWindow):
    def __init__(self, log_path_override: Path | None = None) -> None:
        super().__init__()
        self.setWindowTitle("OpenAI Requests Viewer")
        self.resize(1200, 720)
        self._log_path_override = log_path_override

        self.model = RequestsModel(self)
        self.proxy = QtCore.QSortFilterProxyModel(self)
        self.proxy.setSourceModel(self.model)
        self.proxy.setFilterKeyColumn(-1)

        self.tree = QtWidgets.QTreeView()
        self.tree.setModel(self.proxy)
        self.tree.setSortingEnabled(True)
        self.tree.setUniformRowHeights(True)
        self.tree.setAlternatingRowColors(True)
        self.tree.setEditTriggers(QtWidgets.QAbstractItemView.NoEditTriggers)
        self.tree.setSelectionBehavior(QtWidgets.QAbstractItemView.SelectRows)
        self.tree.setSelectionMode(QtWidgets.QAbstractItemView.SingleSelection)
        self.tree.header().setStretchLastSection(True)

        self.details = QtWidgets.QPlainTextEdit()
        self.details.setReadOnly(True)
        self.details.setWordWrapMode(QtGui.QTextOption.NoWrap)

        self.status = QtWidgets.QLabel()
        self.refresh_button = QtWidgets.QPushButton("Refresh")
        self.refresh_button.clicked.connect(self.load_logs)

        self.filter_input = QtWidgets.QLineEdit()
        self.filter_input.setPlaceholderText("Filter…")
        self.filter_input.textChanged.connect(self.on_filter)
        self.hide_offline_checkbox = QtWidgets.QCheckBox("Hide offline test entries")
        self.hide_offline_checkbox.setChecked(False)
        self.hide_offline_checkbox.stateChanged.connect(lambda _state: self.load_logs())

        top_bar = QtWidgets.QHBoxLayout()
        top_bar.addWidget(QtWidgets.QLabel("Log file:"))
        self.path_label = QtWidgets.QLabel("")
        self.path_label.setTextInteractionFlags(QtCore.Qt.TextSelectableByMouse)
        top_bar.addWidget(self.path_label, 1)
        top_bar.addWidget(self.filter_input)
        top_bar.addWidget(self.hide_offline_checkbox)
        top_bar.addWidget(self.refresh_button)

        splitter = QtWidgets.QSplitter()
        splitter.addWidget(self.tree)
        splitter.addWidget(self.details)
        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 2)

        central = QtWidgets.QWidget()
        layout = QtWidgets.QVBoxLayout(central)
        layout.addLayout(top_bar)
        layout.addWidget(splitter, 1)
        layout.addWidget(self.status)
        self.setCentralWidget(central)

        self.tree.selectionModel().selectionChanged.connect(self.update_details)
        self.load_logs()

    def on_filter(self, text: str) -> None:
        self.proxy.setFilterFixedString(text)

    def load_logs(self) -> None:
        self.model.clear_rows()
        path = self._log_path_override or log_path()
        self.path_label.setText(str(path))
        if not path.exists():
            self.status.setText(f"No log file found at {path}")
            return

        entries = load_entries(path)
        if self.hide_offline_checkbox.isChecked():
            offline_ids = set()
            for entry in entries:
                if self._is_offline_request(entry):
                    offline_ids.add(safe_str(entry.get("request_id")))
            if offline_ids:
                entries = [entry for entry in entries
                           if safe_str(entry.get("request_id")) not in offline_ids]
        for entry in entries:
            self.model.add_entry(entry)

        for idx in range(len(COLUMNS)):
            self.tree.resizeColumnToContents(idx)
        self.status.setText(f"Loaded {len(entries)} entries")

    def update_details(self) -> None:
        indexes = self.tree.selectionModel().selectedRows()
        if not indexes:
            self.details.setPlainText("")
            return
        proxy_index = indexes[0]
        source_index = self.proxy.mapToSource(proxy_index)
        payload = None
        current = source_index
        while current.isValid() and payload is None:
            item = self.model.itemFromIndex(current)
            if item is not None:
                payload = item.data(QtCore.Qt.UserRole)
            current = current.parent()
        if payload is None:
            item = self.model.itemFromIndex(source_index)
            payload = {"entry": item.text() if item else ""}
        self.details.setPlainText(json.dumps(payload, indent=2, ensure_ascii=True))

    def _is_offline_request(self, entry: dict) -> bool:
        if entry.get("event") != "openai.request":
            return False
        user_agent = entry.get("user_agent")
        if isinstance(user_agent, str) and "offline" in user_agent:
            return True
        return False


def main() -> None:
    app = QtWidgets.QApplication(sys.argv)
    viewer = Viewer()
    viewer.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
