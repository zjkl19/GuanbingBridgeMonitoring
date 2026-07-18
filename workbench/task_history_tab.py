from __future__ import annotations

import os
from pathlib import Path

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .task_history import TaskHistoryEntry, TaskHistoryIndex
from .operator_text import operator_state_label
from .models import JobContext
from .result_location import analysis_result_location


HEALTH_LABELS = {"ready": "正常", "warning": "需核对", "invalid": "记录损坏"}


class TaskHistoryWidget(QWidget):
    restore_requested = Signal(str)
    back_requested = Signal()

    def __init__(self, known_bridge_ids: tuple[str, ...], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.index = TaskHistoryIndex(known_bridge_ids)
        self.entries: tuple[TaskHistoryEntry, ...] = ()
        self._data_roots: tuple[Path, ...] = ()
        self._extra_paths: tuple[Path, ...] = ()
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        header = QHBoxLayout()
        title = QLabel("本机任务中心")
        title.setStyleSheet("font-size: 22px; font-weight: 700; color: #005eac;")
        header.addWidget(title)
        header.addStretch(1)
        back = QPushButton("返回任务配置")
        back.clicked.connect(self.back_requested.emit)
        header.addWidget(back)
        outer.addLayout(header)
        hint = QLabel(
            "只读索引当前数据根目录 run_logs/workbench 下的任务。状态文件优先于任务上下文；"
            "配置版本、数据目录、分析结果清单和报告文件会在重新打开前复核。"
        )
        hint.setWordWrap(True)
        outer.addWidget(hint)

        filters = QHBoxLayout()
        filters.addWidget(QLabel("状态"))
        self.state_filter = QComboBox()
        self.state_filter.addItem("全部状态", "")
        for state in ("running", "completed", "failed", "stopped", "draft", "warning", "invalid"):
            self.state_filter.addItem(operator_state_label(state), state)
        self.state_filter.currentIndexChanged.connect(self._apply_filters)
        filters.addWidget(self.state_filter)
        filters.addWidget(QLabel("搜索"))
        self.search_edit = QLineEdit()
        self.search_edit.setPlaceholderText("桥梁、任务ID、日期、状态、问题或路径")
        self.search_edit.setClearButtonEnabled(True)
        self.search_edit.textChanged.connect(self._apply_filters)
        filters.addWidget(self.search_edit, 1)
        self.summary_label = QLabel("尚未扫描")
        filters.addWidget(self.summary_label)
        refresh = QPushButton("刷新")
        refresh.clicked.connect(self.refresh)
        filters.addWidget(refresh)
        outer.addLayout(filters)

        self.table = QTableWidget(0, 8)
        self.table.setHorizontalHeaderLabels(
            ["更新时间", "桥梁", "监测周期", "分析状态", "报告状态", "记录状态", "任务ID", "问题/上下文路径"]
        )
        self.table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.SingleSelection)
        self.table.setAlternatingRowColors(True)
        self.table.itemSelectionChanged.connect(self._selection_changed)
        self.table.itemDoubleClicked.connect(lambda *_: self._restore())
        table_header = self.table.horizontalHeader()
        for column in range(7):
            table_header.setSectionResizeMode(column, QHeaderView.ResizeToContents)
        table_header.setSectionResizeMode(7, QHeaderView.Stretch)
        outer.addWidget(self.table, 1)

        actions = QHBoxLayout()
        self.restore_button = QPushButton("重新打开选中任务")
        self.restore_button.setEnabled(False)
        self.restore_button.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 6px 14px;"
        )
        self.restore_button.clicked.connect(self._restore)
        actions.addWidget(self.restore_button)
        self.open_button = QPushButton("打开任务目录")
        self.open_button.setEnabled(False)
        self.open_button.clicked.connect(self._open_directory)
        actions.addWidget(self.open_button)
        self.open_result_button = QPushButton("打开计算结果目录")
        self.open_result_button.setEnabled(False)
        self.open_result_button.clicked.connect(self._open_result_directory)
        actions.addWidget(self.open_result_button)
        actions.addStretch(1)
        self.detail_label = QLabel("请选择任务查看重新打开条件。")
        self.detail_label.setWordWrap(True)
        actions.addWidget(self.detail_label, 1)
        outer.addLayout(actions)

    def load_sources(self, data_roots: tuple[Path, ...], extra_paths: tuple[Path, ...] = ()) -> None:
        self._data_roots = data_roots
        self._extra_paths = extra_paths
        self.refresh()

    def refresh(self) -> None:
        self.entries = self.index.discover(data_roots=self._data_roots, extra_paths=self._extra_paths)
        self._apply_filters()

    def load_demo(self) -> None:
        base = Path("C:/BridgeMonitoring/demo")
        self.entries = (
            TaskHistoryEntry(base / "running/job_context.json", "hongtang_q2", "hongtang", "洪塘大桥", "2026-04-01 至 2026-06-30", "2026-07-13T08:12:00+08:00", "running", "索力加速度 7/11；64%", "blocked", "", "ready", (), True),
            TaskHistoryEntry(base / "done/job_context.json", "zhishan_april", "zhishan", "芝山大桥", "2026-04-01 至 2026-04-30", "2026-07-13T07:50:00+08:00", "completed", "11/11；100%", "completed", "质量检查：通过", "ready", (), True),
            TaskHistoryEntry(base / "drift/job_context.json", "guanbing_june", "guanbing", "管柄大桥", "2026-06-01 至 2026-06-30", "2026-07-12T23:10:00+08:00", "completed", "10/10；100%", "blocked", "", "warning", ("配置内容已变化",), True),
            TaskHistoryEntry(base / "bad/job_context.json", "broken_context", "", "不可读取", "", "2026-07-12T20:00:00+08:00", "invalid", "", "invalid", "", "invalid", ("任务方案不可读：JSON格式错误",), False),
        )
        self._apply_filters()

    def _filtered(self) -> list[TaskHistoryEntry]:
        state = str(self.state_filter.currentData() or "")
        query = self.search_edit.text().strip().casefold()
        rows = []
        for entry in self.entries:
            if state == "warning" and entry.health != "warning":
                continue
            if state == "invalid" and entry.health != "invalid":
                continue
            if state and state not in {"warning", "invalid"} and state not in {
                entry.analysis_state,
                entry.report_state,
            }:
                continue
            haystack = " ".join(
                (
                    entry.job_id,
                    entry.bridge_id,
                    entry.bridge_name,
                    entry.period_text,
                    entry.updated_at,
                    entry.analysis_state,
                    entry.analysis_detail,
                    entry.report_state,
                    entry.report_detail,
                    entry.health,
                    " ".join(entry.issues),
                    str(entry.context_path),
                )
            ).casefold()
            if query and query not in haystack:
                continue
            rows.append(entry)
        return rows

    def _apply_filters(self, *_args: object) -> None:
        rows = self._filtered()
        self.table.setRowCount(0)
        for entry in rows:
            row = self.table.rowCount()
            self.table.insertRow(row)
            analysis = operator_state_label(entry.analysis_state) + (
                f"；{entry.analysis_detail}" if entry.analysis_detail else ""
            )
            report = operator_state_label(entry.report_state) + (
                f"；{entry.report_detail}" if entry.report_detail else ""
            )
            detail = "；".join(entry.issues) if entry.issues else str(entry.context_path)
            values = (
                entry.updated_at.replace("T", " ")[:19],
                entry.bridge_name or entry.bridge_id,
                entry.period_text,
                analysis,
                report,
                HEALTH_LABELS.get(entry.health, entry.health),
                entry.job_id,
                detail,
            )
            for column, value in enumerate(values):
                item = QTableWidgetItem(value)
                item.setData(Qt.UserRole, str(entry.context_path))
                item.setToolTip(str(entry.context_path))
                if entry.health == "invalid":
                    item.setForeground(Qt.red)
                elif entry.health == "warning":
                    item.setForeground(Qt.darkYellow)
                self.table.setItem(row, column, item)
        ready = sum(entry.health == "ready" for entry in self.entries)
        warnings = sum(entry.health == "warning" for entry in self.entries)
        self.summary_label.setText(
            f"显示 {len(rows)}/{len(self.entries)}；正常可重新打开 {ready}；需核对 {warnings}"
        )
        self._selection_changed()

    def _selected(self) -> TaskHistoryEntry | None:
        row = self.table.currentRow()
        if row < 0 or self.table.item(row, 0) is None:
            return None
        path = Path(str(self.table.item(row, 0).data(Qt.UserRole)))
        return next((entry for entry in self.entries if entry.context_path == path), None)

    def _selection_changed(self) -> None:
        entry = self._selected()
        self.restore_button.setEnabled(bool(entry and entry.can_restore))
        self.open_button.setEnabled(bool(entry and entry.context_path.parent.is_dir()))
        result_location = self._selected_result_location()
        self.open_result_button.setEnabled(
            bool(result_location and result_location.root.is_dir())
        )
        if entry is None:
            self.detail_label.setText("请选择任务查看重新打开条件。")
        elif entry.issues:
            self.detail_label.setText("；".join(entry.issues))
        else:
            self.detail_label.setText(f"任务记录正常，可以重新打开：{entry.context_path}")

    def _restore(self) -> None:
        entry = self._selected()
        if entry is None or not entry.can_restore:
            QMessageBox.warning(
                self, "无法重新打开", "选中任务未通过重新打开前的完整性检查。"
            )
            return
        self.restore_requested.emit(str(entry.context_path))

    def _open_directory(self) -> None:
        entry = self._selected()
        if entry is None or not entry.context_path.parent.is_dir():
            return
        if os.name == "nt":
            os.startfile(entry.context_path.parent)  # type: ignore[attr-defined]

    def _selected_result_location(self):
        entry = self._selected()
        if entry is None or not entry.context_path.is_file():
            return None
        try:
            context = JobContext.read(entry.context_path)
        except (OSError, ValueError):
            return None
        return analysis_result_location(context=context)

    def _open_result_directory(self) -> None:
        location = self._selected_result_location()
        if location is None or not location.root.is_dir():
            QMessageBox.warning(
                self,
                "结果目录不可用",
                "选中任务记录的计算结果目录不存在；重新打开任务后可查看任务页上的实际结果位置。",
            )
            return
        if os.name == "nt":
            os.startfile(location.root)  # type: ignore[attr-defined]
