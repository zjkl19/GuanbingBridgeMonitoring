from __future__ import annotations

import os
from pathlib import Path
from typing import Iterable

from PySide6.QtCore import Qt, QUrl
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QGridLayout,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .threshold_curve import (
    ThresholdCurveRecordMetadata,
    discover_threshold_curve_history,
)
from .threshold_labels import threshold_module_label


class ThresholdCurveHistoryDialog(QDialog):
    """Select a validated workbench curve by ordinary task identity fields."""

    def __init__(
        self,
        data_roots: Iterable[str | Path],
        *,
        target_module: str = "",
        target_point_ids: Iterable[str] = (),
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self._roots = list(
            dict.fromkeys(
                Path(value).expanduser().resolve(strict=False)
                for value in data_roots
                if str(value or "").strip()
            )
        )
        self._target_module = str(target_module or "").strip()
        self._target_points = tuple(
            dict.fromkeys(
                str(value or "").strip()
                for value in target_point_ids
                if str(value or "").strip()
            )
        )
        self._records: tuple[ThresholdCurveRecordMetadata, ...] = ()
        self._visible_records: list[ThresholdCurveRecordMetadata] = []
        self.setWindowTitle("导入其他任务的工作平台曲线记录")
        self.resize(1120, 650)
        self._build_ui()
        self.refresh()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("从历史任务选择工作平台曲线")
        title.setStyleSheet("font-size: 19px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "按桥梁、月份、模块和测点选择；普通操作不需要辨认 JSON 文件。"
            "导入的是跨任务数值参考，不会冒充当前任务身份校验通过。"
        )
        hint.setWordWrap(True)
        outer.addWidget(hint)

        root_row = QHBoxLayout()
        self.root_label = QLabel()
        self.root_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.root_label.setWordWrap(True)
        root_row.addWidget(self.root_label, 1)
        add_root = QPushButton("选择其他任务数据目录…")
        add_root.clicked.connect(self._add_root)
        root_row.addWidget(add_root)
        refresh_button = QPushButton("刷新列表")
        refresh_button.clicked.connect(self.refresh)
        root_row.addWidget(refresh_button)
        outer.addLayout(root_row)

        filters = QGridLayout()
        self.bridge_filter = QComboBox()
        self.month_filter = QComboBox()
        self.module_filter = QComboBox()
        self.point_filter = QComboBox()
        for combo in (
            self.bridge_filter,
            self.month_filter,
            self.module_filter,
            self.point_filter,
        ):
            combo.currentIndexChanged.connect(self._apply_filters)
        filters.addWidget(QLabel("桥梁"), 0, 0)
        filters.addWidget(self.bridge_filter, 0, 1)
        filters.addWidget(QLabel("月份/日期范围"), 0, 2)
        filters.addWidget(self.month_filter, 0, 3)
        filters.addWidget(QLabel("模块"), 0, 4)
        filters.addWidget(self.module_filter, 0, 5)
        filters.addWidget(QLabel("测点"), 0, 6)
        filters.addWidget(self.point_filter, 0, 7)
        outer.addLayout(filters)

        self.table = QTableWidget(0, 8)
        self.table.setHorizontalHeaderLabels(
            ["桥梁", "月份/日期范围", "模块", "测点", "预览点", "源样本", "记录类型", "任务"]
        )
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SingleSelection)
        self.table.setAlternatingRowColors(True)
        self.table.doubleClicked.connect(self._accept_selected)
        header = self.table.horizontalHeader()
        for column in range(7):
            header.setSectionResizeMode(column, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(7, QHeaderView.Stretch)
        outer.addWidget(self.table, 1)

        footer = QHBoxLayout()
        self.summary_label = QLabel()
        footer.addWidget(self.summary_label, 1)
        open_folder = QPushButton("打开所选任务目录")
        open_folder.clicked.connect(self.open_selected_folder)
        footer.addWidget(open_folder)
        outer.addLayout(footer)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        self.accept_button = buttons.button(QDialogButtonBox.Ok)
        self.accept_button.setText("导入所选曲线")
        self.accept_button.setEnabled(False)
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self._accept_selected)
        buttons.rejected.connect(self.reject)
        self.table.itemSelectionChanged.connect(
            lambda: self.accept_button.setEnabled(self.table.currentRow() >= 0)
        )
        outer.addWidget(buttons)

    def _add_root(self) -> None:
        selected = QFileDialog.getExistingDirectory(
            self,
            "选择包含 run_logs 的任务数据目录",
            str(self._roots[0]) if self._roots else "",
        )
        if not selected:
            return
        root = Path(selected).expanduser().resolve(strict=False)
        if root not in self._roots:
            self._roots.append(root)
        self.refresh()

    @staticmethod
    def _month_label(record: ThresholdCurveRecordMetadata) -> str:
        if record.start_date[:7] == record.end_date[:7]:
            return record.start_date[:7]
        return record.date_label

    def refresh(self) -> None:
        self._records = discover_threshold_curve_history(self._roots)
        self.root_label.setText(
            "历史目录：" + ("；".join(str(path) for path in self._roots) or "尚未选择")
        )
        self._populate_filters()
        self._apply_filters()

    def _populate_filters(self) -> None:
        combos = (
            (self.bridge_filter, [(row.bridge_id, row.bridge_id) for row in self._records], "全部桥梁"),
            (self.month_filter, [(self._month_label(row), self._month_label(row)) for row in self._records], "全部月份"),
            (
                self.module_filter,
                [(threshold_module_label(row.module_key), row.module_key) for row in self._records],
                "全部模块",
            ),
            (self.point_filter, [(row.point_id, row.point_id) for row in self._records], "全部测点"),
        )
        for combo, values, all_label in combos:
            previous = combo.currentData()
            combo.blockSignals(True)
            combo.clear()
            combo.addItem(all_label, "")
            for label, value in sorted(set(values), key=lambda item: item[0]):
                combo.addItem(label, value)
            preferred = previous
            if combo is self.module_filter and self._target_module:
                preferred = self._target_module
            elif combo is self.point_filter and self._target_points:
                preferred = self._target_points[0]
            index = combo.findData(preferred)
            combo.setCurrentIndex(index if index >= 0 else 0)
            combo.blockSignals(False)

    def _apply_filters(self) -> None:
        bridge = str(self.bridge_filter.currentData() or "")
        month = str(self.month_filter.currentData() or "")
        module = str(self.module_filter.currentData() or "")
        point = str(self.point_filter.currentData() or "")
        self._visible_records = [
            row
            for row in self._records
            if (not bridge or row.bridge_id == bridge)
            and (not month or self._month_label(row) == month)
            and (not module or row.module_key == module)
            and (not point or row.point_id == point)
        ]
        self.table.setRowCount(0)
        for record in self._visible_records:
            row = self.table.rowCount()
            self.table.insertRow(row)
            values = (
                record.bridge_id,
                record.date_label,
                threshold_module_label(record.module_key),
                record.point_id,
                str(record.sample_count),
                str(record.source_sample_count),
                "独立曲线记录",
                record.request_id,
            )
            for column, value in enumerate(values):
                item = QTableWidgetItem(value)
                item.setToolTip(str(record.preview_path))
                item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.table.setItem(row, column, item)
        if self.table.rowCount():
            self.table.selectRow(0)
        self.summary_label.setText(
            f"已验证 {len(self._records)} 条记录；当前显示 {len(self._visible_records)} 条。"
        )
        self.accept_button.setEnabled(bool(self._visible_records))

    def selected_record(self) -> ThresholdCurveRecordMetadata:
        row = self.table.currentRow()
        if row < 0 or row >= len(self._visible_records):
            raise ValueError("请先选择一条曲线记录")
        return self._visible_records[row]

    def selected_preview_path(self) -> Path:
        return self.selected_record().preview_path

    def _accept_selected(self) -> None:
        try:
            self.selected_record()
        except ValueError as exc:
            QMessageBox.information(self, "尚未选择曲线", str(exc))
            return
        self.accept()

    def open_selected_folder(self) -> None:
        try:
            path = self.selected_preview_path().parent
        except ValueError as exc:
            QMessageBox.information(self, "尚未选择曲线", str(exc))
            return
        if os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))


__all__ = ["ThresholdCurveHistoryDialog"]
