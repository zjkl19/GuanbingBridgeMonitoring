from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices, QKeySequence
from PySide6.QtWidgets import (
    QAbstractItemView,
    QApplication,
    QDialog,
    QDialogButtonBox,
    QMenu,
    QPlainTextEdit,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
)


PATH_ROLE = int(Qt.UserRole) + 101
FAILED_ROLE = int(Qt.UserRole) + 102
GAP_ROLE = int(Qt.UserRole) + 103


class CellDetailDialog(QDialog):
    def __init__(self, title: str, text: str, parent=None) -> None:
        super().__init__(parent)
        # Detail windows are intentionally short lived.  Without this flag Qt
        # keeps every closed dialog as a child of the table, so repeated
        # inspection of long paths slowly retains widgets for the whole task.
        self.setAttribute(Qt.WA_DeleteOnClose, True)
        self.setWindowTitle(title)
        self.resize(720, 360)
        layout = QVBoxLayout(self)
        self.text_edit = QPlainTextEdit(self)
        self.text_edit.setReadOnly(True)
        self.text_edit.setLineWrapMode(QPlainTextEdit.WidgetWidth)
        self.text_edit.setPlainText(text)
        layout.addWidget(self.text_edit)
        buttons = QDialogButtonBox(QDialogButtonBox.Close, parent=self)
        buttons.rejected.connect(self.close)
        layout.addWidget(buttons)


class CopyableTableWidget(QTableWidget):
    """Read-only table with inspect, copy and local-path actions."""

    def __init__(self, rows: int = 0, columns: int = 0, parent=None) -> None:
        super().__init__(rows, columns, parent)
        self.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.setSelectionBehavior(QAbstractItemView.SelectItems)
        self.setAlternatingRowColors(True)
        self.itemChanged.connect(self._ensure_tooltip)
        self.cellDoubleClicked.connect(self.show_cell_detail)
        self._detail_dialogs: list[CellDetailDialog] = []
        self._failed_only = False
        self._gap_only = False

    @staticmethod
    def _ensure_tooltip(item: QTableWidgetItem) -> None:
        if not item.toolTip():
            item.setToolTip(item.text())

    def set_copyable_item(
        self,
        row: int,
        column: int,
        value: object,
        *,
        path: Path | str | None = None,
        user_data: object | None = None,
    ) -> QTableWidgetItem:
        item = QTableWidgetItem(str(value))
        item.setToolTip(item.text())
        if path is not None and str(path).strip():
            item.setData(PATH_ROLE, str(Path(path).expanduser().resolve(strict=False)))
        if user_data is not None:
            item.setData(Qt.UserRole, user_data)
        self.setItem(row, column, item)
        return item

    def set_row_flags(self, row: int, *, failed: bool = False, gap: bool = False) -> None:
        for column in range(self.columnCount()):
            item = self.item(row, column)
            if item is None:
                item = self.set_copyable_item(row, column, "")
            item.setData(FAILED_ROLE, bool(failed))
            item.setData(GAP_ROLE, bool(gap))
        self._apply_row_filter(row)

    def set_filters(self, *, failed_only: bool = False, gap_only: bool = False) -> None:
        self._failed_only = bool(failed_only)
        self._gap_only = bool(gap_only)
        for row in range(self.rowCount()):
            self._apply_row_filter(row)

    def _apply_row_filter(self, row: int) -> None:
        marker = self.item(row, 0)
        failed = bool(marker and marker.data(FAILED_ROLE))
        gap = bool(marker and marker.data(GAP_ROLE))
        self.setRowHidden(
            row,
            (self._failed_only and not failed) or (self._gap_only and not gap),
        )

    def copy_selected_as_tsv(self) -> str:
        blocks: list[str] = []
        for selected_range in self.selectedRanges():
            lines: list[str] = []
            for row in range(selected_range.topRow(), selected_range.bottomRow() + 1):
                values = []
                for column in range(
                    selected_range.leftColumn(), selected_range.rightColumn() + 1
                ):
                    item = self.item(row, column)
                    values.append(item.text() if item is not None else "")
                lines.append("\t".join(values))
            blocks.append("\n".join(lines))
        text = "\n".join(blocks)
        if text:
            QApplication.clipboard().setText(text)
        return text

    def copy_cell(self, row: int, column: int) -> str:
        item = self.item(row, column)
        text = item.text() if item is not None else ""
        QApplication.clipboard().setText(text)
        return text

    def copy_row(self, row: int) -> str:
        text = "\t".join(
            self.item(row, column).text() if self.item(row, column) is not None else ""
            for column in range(self.columnCount())
        )
        QApplication.clipboard().setText(text)
        return text

    def path_for_cell(self, row: int, column: int) -> str:
        item = self.item(row, column)
        direct = str(item.data(PATH_ROLE) or "") if item is not None else ""
        if direct:
            return direct
        # The context menu is row-oriented: users should be able to copy/open
        # the row's full path even when they right-click its status or message
        # cell instead of the visually long path cell.
        for candidate_column in range(self.columnCount()):
            candidate = self.item(row, candidate_column)
            if candidate is None:
                continue
            path = str(candidate.data(PATH_ROLE) or "")
            if path:
                return path
        return ""

    def copy_full_path(self, row: int, column: int) -> str:
        path = self.path_for_cell(row, column)
        if path:
            QApplication.clipboard().setText(path)
        return path

    def open_path(self, row: int, column: int) -> bool:
        path = self.path_for_cell(row, column)
        return bool(path and QDesktopServices.openUrl(QUrl.fromLocalFile(path)))

    def open_containing_directory(self, row: int, column: int) -> bool:
        path_text = self.path_for_cell(row, column)
        if not path_text:
            return False
        path = Path(path_text)
        directory = path if path.is_dir() else path.parent
        return bool(QDesktopServices.openUrl(QUrl.fromLocalFile(str(directory))))

    def show_cell_detail(self, row: int, column: int) -> CellDetailDialog | None:
        item = self.item(row, column)
        if item is None:
            return None
        header = self.horizontalHeaderItem(column)
        label = header.text() if header is not None else f"第 {column + 1} 列"
        dialog = CellDetailDialog(f"{label}详情", item.text(), self)
        self._detail_dialogs.append(dialog)
        dialog.finished.connect(lambda _result: self._discard_dialog(dialog))
        dialog.show()
        return dialog

    def _discard_dialog(self, dialog: CellDetailDialog) -> None:
        if dialog in self._detail_dialogs:
            self._detail_dialogs.remove(dialog)

    def keyPressEvent(self, event) -> None:  # noqa: N802 - Qt API
        if event.matches(QKeySequence.Copy):
            self.copy_selected_as_tsv()
            event.accept()
            return
        super().keyPressEvent(event)

    def context_menu_for_cell(self, row: int, column: int) -> QMenu:
        """Build the row-aware menu separately so its actions are testable."""

        menu = QMenu(self)
        menu.addAction("复制选中区域（TSV）", self.copy_selected_as_tsv)
        menu.addAction("复制单元格", lambda: self.copy_cell(row, column))
        menu.addAction("复制整行", lambda: self.copy_row(row))
        path = self.path_for_cell(row, column)
        menu.addSeparator()
        copy_path = menu.addAction("复制完整路径", lambda: self.copy_full_path(row, column))
        open_file = menu.addAction("打开文件", lambda: self.open_path(row, column))
        open_dir = menu.addAction(
            "打开所在目录", lambda: self.open_containing_directory(row, column)
        )
        copy_path.setEnabled(bool(path))
        open_file.setEnabled(bool(path))
        open_dir.setEnabled(bool(path))
        menu.addSeparator()
        menu.addAction("查看只读详情", lambda: self.show_cell_detail(row, column))
        return menu

    def contextMenuEvent(self, event) -> None:  # noqa: N802 - Qt API
        index = self.indexAt(event.pos())
        if not index.isValid():
            return
        row, column = index.row(), index.column()
        clicked_item = self.item(row, column)
        if clicked_item is None:
            return
        if not clicked_item.isSelected():
            self.clearSelection()
            self.setCurrentCell(row, column)
            clicked_item.setSelected(True)

        menu = self.context_menu_for_cell(row, column)
        menu.exec(event.globalPos())
