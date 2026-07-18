from __future__ import annotations

import math

from PySide6.QtCore import Qt
from PySide6.QtGui import QBrush, QColor
from PySide6.QtWidgets import QGroupBox, QHeaderView, QLabel, QVBoxLayout

from .copyable_table import CopyableTableWidget
from .module_progress import ModuleProgressSnapshot, ModuleProgressStep


STATUS_LABELS = {
    "pending": "○ 待运行",
    "running": "▶ 运行中",
    "completed": "✓ 已完成",
    "failed": "✕ 失败",
    "skipped": "— 跳过",
    "stopped": "■ 已停止",
}

STATUS_COLORS = {
    "pending": "#6b7280",
    "running": "#005eac",
    "completed": "#167c35",
    "failed": "#b42318",
    "skipped": "#946200",
    "stopped": "#6d4c7d",
}

STAGE_LABELS = {
    "module_start": "模块启动",
    "module_complete": "模块完成",
    "module_skipped_after_stop": "停止后跳过",
    "preflight": "预检查",
    "loading": "读取数据",
    "loading_data": "读取数据",
    "loading_date": "读取日期数据",
    "processing": "处理中",
    "processing_point": "处理测点",
    "processing_date": "处理日期",
    "writing": "写入结果",
    "finalizing": "收口清单",
    "stop_requested": "安全停止中",
}


def module_stage_label(stage: str) -> str:
    value = str(stage or "").strip()
    return STAGE_LABELS.get(value, value)


def _elapsed_text(seconds: float) -> str:
    try:
        value = max(0.0, float(seconds))
    except (TypeError, ValueError, OverflowError):
        return ""
    if not math.isfinite(value) or value <= 0:
        return ""
    total_seconds = round(value)
    if total_seconds < 60:
        return f"{total_seconds}秒"
    minutes, remainder = divmod(total_seconds, 60)
    if minutes < 60:
        return f"{minutes}分{remainder:02d}秒"
    hours, minutes = divmod(minutes, 60)
    return f"{hours}小时{minutes:02d}分{remainder:02d}秒"


def _step_location(step: ModuleProgressStep) -> str:
    parts: list[str] = []
    if step.current_point_id:
        parts.append(f"测点 {step.current_point_id}")
    if step.current_date:
        parts.append(f"日期 {step.current_date}")
    return "；".join(parts)


def _date_progress(step: ModuleProgressStep) -> str:
    total = step.total_dates if step.total_dates is not None else 0
    processed = step.processed_dates if step.processed_dates is not None else 0
    if total > 0:
        return f"{max(0, processed)}/{total}"
    if processed > 0:
        return str(processed)
    return ""


class ModuleProgressPanel(QGroupBox):
    """Compact, copyable view of the authoritative per-module run state."""

    def __init__(self, parent=None) -> None:
        super().__init__("模块进度明细", parent)
        self._last_snapshot: ModuleProgressSnapshot | None = None
        layout = QVBoxLayout(self)
        self.summary_label = QLabel("尚未收到模块进度。")
        self.summary_label.setStyleSheet("font-weight: 600;")
        self.summary_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        layout.addWidget(self.summary_label)

        self.table = CopyableTableWidget(0, 7, self)
        self.table.setHorizontalHeaderLabels(
            ("序号", "状态", "模块", "阶段", "当前测点/日期", "日期进度", "耗时/说明")
        )
        self.table.verticalHeader().setVisible(False)
        self.table.setMinimumHeight(118)
        self.table.setMaximumHeight(205)
        header = self.table.horizontalHeader()
        for column in (0, 1, 2, 3, 5):
            header.setSectionResizeMode(column, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.Stretch)
        header.setSectionResizeMode(6, QHeaderView.Stretch)
        layout.addWidget(self.table)

    def set_snapshot(self, snapshot: ModuleProgressSnapshot) -> None:
        if snapshot == self._last_snapshot:
            return
        self.summary_label.setText(self._summary_text(snapshot))
        self.table.blockSignals(True)
        try:
            self.table.clearContents()
            self.table.setRowCount(len(snapshot.steps))
            for row, step in enumerate(snapshot.steps):
                status = str(step.status or "pending").strip().casefold()
                values = (
                    step.index or row + 1,
                    STATUS_LABELS.get(status, step.status or "状态待确认"),
                    step.label or step.key,
                    module_stage_label(step.stage),
                    _step_location(step),
                    _date_progress(step),
                    "；".join(
                        part
                        for part in (_elapsed_text(step.elapsed_seconds), step.message)
                        if part
                    ),
                )
                for column, value in enumerate(values):
                    item = self.table.set_copyable_item(row, column, value)
                    if column == 1:
                        item.setForeground(
                            QBrush(QColor(STATUS_COLORS.get(status, "#374151")))
                        )
                self.table.set_row_flags(row, failed=status == "failed")
        finally:
            self.table.blockSignals(False)
        self._last_snapshot = snapshot

    @staticmethod
    def _summary_text(snapshot: ModuleProgressSnapshot) -> str:
        return snapshot.summary_text
