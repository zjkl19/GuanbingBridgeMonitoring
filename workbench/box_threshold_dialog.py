from __future__ import annotations

import math
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from .auto_threshold import PreviewSeries, load_preview_artifact
from .auto_threshold_preview import module_label
from .config_editor import CleaningThresholdRow, ConfigEditorError
from .manual_threshold import (
    LOWER_SIDE,
    UPPER_SIDE,
    BoxThresholdProposal,
    OneSidedThresholdDraft,
    ThresholdEstimate,
    ThresholdSelectionBox,
    TwoSidedThresholdDraft,
    apply_one_sided_to_selected_row,
    estimate_two_sided_rule,
    propose_box_threshold,
    select_preview_series,
)


def _timestamp(value: str) -> float | None:
    text = str(value or "").strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


def _timestamp_text(value: float) -> str:
    return datetime.fromtimestamp(float(value)).isoformat(
        sep=" ", timespec="microseconds"
    )


def _fit_dialog_to_available_screen(
    dialog: QDialog,
    *,
    preferred_width: int = 1080,
    preferred_height: int = 720,
) -> None:
    """Keep modal tools inside the current screen at high DPI."""

    screen = dialog.screen()
    if screen is None:
        dialog.resize(preferred_width, preferred_height)
        return
    available = screen.availableGeometry()
    width = min(preferred_width, max(640, available.width() - 48))
    height = min(preferred_height, max(520, available.height() - 48))
    dialog.resize(width, height)


class BoxThresholdCurveView(QWidget):
    """Curve view that derives a proposal from actual samples inside a rubber band."""

    selection_changed = Signal(object)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setMinimumSize(560, 330)
        self.setMouseTracking(True)
        self.setFocusPolicy(Qt.StrongFocus)
        self.setAccessibleName("框选实际样本设置清洗阈值")
        self.setAccessibleDescription(
            "按住鼠标左键拖出矩形框；下侧取最高值，上侧取最低值"
        )
        self._series: PreviewSeries | None = None
        self._side = LOWER_SIDE
        self._module_key = ""
        self._point_key = ""
        self._rule_start = ""
        self._rule_end = ""
        self._anchor: QPointF | None = None
        self._rubber_band: QRectF | None = None
        self._selection: ThresholdSelectionBox | None = None
        self._selected_indices: tuple[int, ...] = ()
        self._candidate: float | None = None

    def set_series(
        self,
        series: PreviewSeries | None,
        *,
        side: str,
        module_key: str,
        point_key: str,
        rule_start: str = "",
        rule_end: str = "",
    ) -> None:
        self._series = series
        self._side = side
        self._module_key = module_key
        self._point_key = point_key
        self._rule_start = str(rule_start or "")
        self._rule_end = str(rule_end or "")
        self.clear_selection(emit=False)

    def set_candidate(self, value: float | None) -> None:
        self._candidate = None if value is None else float(value)
        self.update()

    def clear_selection(self, *, emit: bool = True) -> None:
        self._anchor = None
        self._rubber_band = None
        self._selection = None
        self._selected_indices = ()
        self._candidate = None
        self.update()
        if emit:
            self.selection_changed.emit(None)

    def selection(self) -> ThresholdSelectionBox | None:
        return self._selection

    def selected_indices(self) -> tuple[int, ...]:
        return self._selected_indices

    def _frame(self) -> QRectF:
        return QRectF(64, 34, max(20, self.width() - 88), max(20, self.height() - 92))

    def _axis_data(self) -> tuple[list[float], bool]:
        if self._series is None:
            return [], False
        parsed = [_timestamp(value) for value in self._series.times]
        use_time = all(value is not None for value in parsed) and len(set(parsed)) > 1
        if use_time:
            return [float(value) for value in parsed if value is not None], True
        return [float(index) for index in range(len(self._series.values))], False

    def _finite_values(self) -> list[float]:
        if self._series is None:
            return []
        values: list[float] = []
        for raw in self._series.values:
            if raw is None:
                continue
            value = float(raw)
            if math.isfinite(value):
                values.append(value)
        return values

    def _limits(self) -> tuple[float, float, float, float, bool]:
        xs, use_time = self._axis_data()
        values = self._finite_values()
        if not xs or not values:
            return 0.0, 1.0, -1.0, 1.0, use_time
        x_low, x_high = min(xs), max(xs)
        if x_high <= x_low:
            x_high = x_low + 1.0
        y_low, y_high = min(values), max(values)
        if y_high <= y_low:
            y_low, y_high = y_low - 1.0, y_high + 1.0
        padding = max((y_high - y_low) * 0.08, max(abs(y_low), abs(y_high), 1.0) * 0.01)
        return x_low, x_high, y_low - padding, y_high + padding, use_time

    def _pixel_x(self, value: float) -> float:
        frame = self._frame()
        x_low, x_high, *_ = self._limits()
        return frame.left() + (value - x_low) / (x_high - x_low) * frame.width()

    def _pixel_y(self, value: float) -> float:
        frame = self._frame()
        _, _, y_low, y_high, _ = self._limits()
        return frame.bottom() - (value - y_low) / (y_high - y_low) * frame.height()

    def _value_x(self, pixel: float) -> float:
        frame = self._frame()
        x_low, x_high, *_ = self._limits()
        ratio = (min(max(pixel, frame.left()), frame.right()) - frame.left()) / frame.width()
        return x_low + ratio * (x_high - x_low)

    def _value_y(self, pixel: float) -> float:
        frame = self._frame()
        _, _, y_low, y_high, _ = self._limits()
        ratio = (frame.bottom() - min(max(pixel, frame.top()), frame.bottom())) / frame.height()
        return y_low + ratio * (y_high - y_low)

    def _sample_points(self) -> list[tuple[int, float, float, QPointF]]:
        if self._series is None:
            return []
        xs, _ = self._axis_data()
        points: list[tuple[int, float, float, QPointF]] = []
        for index, (x_value, raw_value) in enumerate(zip(xs, self._series.values)):
            if raw_value is None:
                continue
            value = float(raw_value)
            if not math.isfinite(value):
                continue
            points.append(
                (index, x_value, value, QPointF(self._pixel_x(x_value), self._pixel_y(value)))
            )
        return points

    def mousePressEvent(self, event: Any) -> None:  # noqa: N802
        if (
            event.button() == Qt.LeftButton
            and self._series is not None
            and self._frame().contains(event.position())
        ):
            self._anchor = event.position()
            self._rubber_band = QRectF(self._anchor, self._anchor)
            self._selection = None
            self._selected_indices = ()
            self._candidate = None
            self.update()
            self.selection_changed.emit(None)
            event.accept()
            return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event: Any) -> None:  # noqa: N802
        if self._anchor is not None:
            point = event.position()
            frame = self._frame()
            point = QPointF(
                min(max(point.x(), frame.left()), frame.right()),
                min(max(point.y(), frame.top()), frame.bottom()),
            )
            self._rubber_band = QRectF(self._anchor, point).normalized()
            self.update()
            event.accept()
            return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event: Any) -> None:  # noqa: N802
        if self._anchor is not None and event.button() == Qt.LeftButton:
            self.mouseMoveEvent(event)
            self._anchor = None
            rect = self._rubber_band
            if rect is None or rect.width() < 4 or rect.height() < 4:
                self.clear_selection()
                event.accept()
                return
            self._finish_selection(rect)
            event.accept()
            return
        super().mouseReleaseEvent(event)

    def keyPressEvent(self, event: Any) -> None:  # noqa: N802
        if event.key() in {Qt.Key_Escape, Qt.Key_Delete, Qt.Key_Backspace}:
            self.clear_selection()
            event.accept()
            return
        super().keyPressEvent(event)

    def _finish_selection(self, rect: QRectF) -> None:
        if self._series is None:
            self.clear_selection()
            return
        _, use_time = self._axis_data()
        if not use_time:
            self.clear_selection()
            return
        selected_points = [
            (index, x_value, value)
            for index, x_value, value, point in self._sample_points()
            if rect.contains(point)
        ]
        if not selected_points:
            self._selection = None
            self._selected_indices = ()
            self._candidate = None
            self.update()
            self.selection_changed.emit(None)
            return

        # Derive the serialized box from the actual samples hit by the rubber
        # band.  Using the drawn pixel bounds and rounding them to whole
        # seconds can pull neighbouring high-frequency samples into the box.
        # The sample extrema preserve the exact hit set (including sub-second
        # timestamps) and make the user-facing "actual samples" contract true.
        selected_times = [item[1] for item in selected_points]
        selected_values = [item[2] for item in selected_points]
        selection_start = _timestamp_text(min(selected_times))
        selection_end = _timestamp_text(max(selected_times))
        y0 = min(selected_values)
        y1 = max(selected_values)
        selection = ThresholdSelectionBox(
            self._module_key,
            self._point_key,
            self._side,
            selection_start,
            selection_end,
            y0,
            y1,
            self._rule_start,
            self._rule_end,
        ).validated()
        self._selected_indices = tuple(item[0] for item in selected_points)
        self._selection = selection
        self.update()
        self.selection_changed.emit(selection)

    def paintEvent(self, event: Any) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor("#ffffff"))
        frame = self._frame()
        painter.setPen(QPen(QColor("#b8c2cc"), 1))
        painter.drawRect(frame)
        if self._series is None or not self._finite_values():
            painter.setPen(QColor("#64748b"))
            painter.drawText(
                frame,
                Qt.AlignCenter | Qt.TextWordWrap,
                "加载当前测点的曲线预览后，按住鼠标左键拖出矩形框",
            )
            return

        painter.save()
        painter.setClipRect(frame)
        points = self._sample_points()
        painter.setPen(QPen(QColor("#1769aa"), 1.0))
        path = QPainterPath()
        active = False
        last_index = -2
        for index, _x, _value, point in points:
            if active and index == last_index + 1:
                path.lineTo(point)
            else:
                path.moveTo(point)
                active = True
            last_index = index
        painter.drawPath(path)

        if self._rubber_band is not None:
            painter.fillRect(self._rubber_band, QColor(255, 193, 7, 45))
            painter.setPen(QPen(QColor("#ef6c00"), 1.4, Qt.DashLine))
            painter.drawRect(self._rubber_band)
        selected = set(self._selected_indices)
        painter.setPen(QPen(QColor("#0f766e"), 1.0))
        painter.setBrush(QColor("#14b8a6"))
        for index, _x, _value, point in points:
            if index in selected:
                painter.drawEllipse(point, 3.2, 3.2)
        if self._candidate is not None:
            y = self._pixel_y(self._candidate)
            painter.setPen(QPen(QColor("#d32f2f"), 1.6, Qt.DashLine))
            painter.drawLine(QPointF(frame.left(), y), QPointF(frame.right(), y))
        painter.restore()

        side_text = "下侧框选：取框中最高值" if self._side == LOWER_SIDE else "上侧框选：取框中最低值"
        painter.setPen(QColor("#334155"))
        painter.drawText(
            QRectF(frame.left(), 5, frame.width(), 22),
            Qt.AlignCenter,
            f"{module_label(self._series.module_key)} / {self._series.point_id}　{side_text}",
        )
        painter.drawText(
            QRectF(frame.left(), frame.bottom() + 8, frame.width(), 26),
            Qt.AlignCenter,
            f"绿色点为框中实际样本（{len(self._selected_indices)} 个）；红色虚线为候选阈值",
        )
        xs, use_time = self._axis_data()
        if use_time and xs:
            painter.drawText(
                QRectF(frame.left(), frame.bottom() + 32, frame.width() / 2, 18),
                Qt.AlignLeft,
                _timestamp_text(min(xs)).split(".", 1)[0],
            )
            painter.drawText(
                QRectF(frame.center().x(), frame.bottom() + 32, frame.width() / 2, 18),
                Qt.AlignRight,
                _timestamp_text(max(xs)).split(".", 1)[0],
            )


class BoxThresholdDialog(QDialog):
    """Review a one-sided bound derived from actual samples inside a box."""

    def __init__(
        self,
        target_row: CleaningThresholdRow,
        *,
        side: str,
        accepted_preview_point_ids: Iterable[str],
        preview_series: PreviewSeries | None = None,
        expected_config_sha256: str = "",
        expected_bridge_id: str = "",
        expected_data_root: str | Path = "",
        expected_start_date: str = "",
        expected_end_date: str = "",
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.target_row = target_row.validated()
        if side not in {LOWER_SIDE, UPPER_SIDE}:
            raise ConfigEditorError(f"框选阈值方向无效：{side!r}")
        self.side = side
        self.accepted_preview_point_ids = tuple(dict.fromkeys(accepted_preview_point_ids))
        self.expected_config_sha256 = str(expected_config_sha256 or "")
        self.expected_bridge_id = str(expected_bridge_id or "").strip()
        self.expected_data_root = str(expected_data_root or "").strip()
        self.expected_start_date = str(expected_start_date or "").strip()
        self.expected_end_date = str(expected_end_date or "").strip()
        self.preview_identity_verified = False
        self.preview_series = preview_series
        self.current_proposal: BoxThresholdProposal | None = None
        self.current_final_estimate: ThresholdEstimate | None = None
        self.setWindowTitle(
            "框选设为下限（下侧取最高值）"
            if side == LOWER_SIDE
            else "框选设为上限（上侧取最低值）"
        )
        self._build_ui()
        _fit_dialog_to_available_screen(self)
        if preview_series is not None:
            self._apply_series(preview_series)

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel(self.windowTitle())
        title.setStyleSheet("font-size: 19px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        rule_text = (
            "下侧框选取框中实际有限样本的最高值作为下限；严格低于该值的数据会被清洗，等于该值的点保留。"
            if self.side == LOWER_SIDE
            else "上侧框选取框中实际有限样本的最低值作为上限；严格高于该值的数据会被清洗，等于该值的点保留。"
        )
        target = QLabel(
            f"目标：{module_label(self.target_row.module_key)} / {self.target_row.point_key}。"
            f"{rule_text} 框选横向范围只用于选取候选样本，不会暗中改变当前规则的时间窗。"
        )
        target.setWordWrap(True)
        target.setStyleSheet(
            "background: #edf6ff; border: 1px solid #9cc7e8; border-radius: 4px; padding: 7px;"
        )
        outer.addWidget(target)

        load_row = QHBoxLayout()
        load_button = QPushButton("加载当前测点的已有曲线预览…")
        load_button.clicked.connect(self._choose_preview)
        load_row.addWidget(load_button)
        self.preview_path_label = QLabel("尚未加载曲线预览；不能确认框选阈值")
        self.preview_path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.preview_path_label.setWordWrap(True)
        self.preview_path_label.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        load_row.addWidget(self.preview_path_label, 1)
        clear_button = QPushButton("清除框选")
        clear_button.clicked.connect(self._clear_selection)
        load_row.addWidget(clear_button)
        outer.addLayout(load_row)

        self.curve = BoxThresholdCurveView(self)
        self.curve.selection_changed.connect(self._selection_changed)
        outer.addWidget(self.curve, 1)
        self.summary_label = QLabel("尚未完成有效框选。请在图中拖出矩形框。")
        self.summary_label.setWordWrap(True)
        self.summary_label.setMinimumHeight(70)
        self.summary_label.setStyleSheet(
            "background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; padding: 7px;"
        )
        outer.addWidget(self.summary_label)

        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        self.accept_button = buttons.button(QDialogButtonBox.Ok)
        self.accept_button.setText("采用此框选阈值")
        self.accept_button.setEnabled(False)
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self._accept_checked)
        buttons.rejected.connect(self.reject)
        outer.addWidget(buttons)

    def _rule_window(self) -> tuple[str, str]:
        return self.target_row.t_range_start, self.target_row.t_range_end

    def _choose_preview(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "加载当前测点的已有曲线预览",
            "",
            "自动清洗曲线预览 (auto_threshold_preview*.json);;JSON files (*.json)",
        )
        if not path:
            return
        try:
            self.load_preview_path(Path(path))
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "曲线预览无法使用", str(exc))

    def load_preview_path(self, path: Path) -> None:
        previews = load_preview_artifact(
            path,
            expected_config_sha256=self.expected_config_sha256,
            expected_bridge_id=self.expected_bridge_id,
            expected_data_root=self.expected_data_root,
            expected_start_date=self.expected_start_date,
            expected_end_date=self.expected_end_date,
        )
        series = select_preview_series(
            previews,
            module_key=self.target_row.module_key,
            point_ids=self.accepted_preview_point_ids,
        )
        self.preview_identity_verified = all(
            (
                self.expected_config_sha256,
                self.expected_bridge_id,
                self.expected_data_root,
                self.expected_start_date,
                self.expected_end_date,
            )
        )
        self._apply_series(series)
        checks = []
        if self.expected_config_sha256:
            checks.append("配置版本")
        if all((self.expected_data_root, self.expected_start_date, self.expected_end_date)):
            checks.append("数据目录和日期范围")
        checked_text = "、".join(checks)
        suffix = f"；{checked_text}已核对" if checks else "；未绑定当前任务"
        if self.expected_bridge_id:
            suffix += f"；当前桥梁={self.expected_bridge_id}"
        self.preview_path_label.setText(f"{path.resolve()}{suffix}")

    def _apply_series(self, series: PreviewSeries) -> None:
        selected = select_preview_series(
            {series.key: series},
            module_key=self.target_row.module_key,
            point_ids=self.accepted_preview_point_ids,
        )
        if len(selected.times) != len(selected.values):
            raise ConfigEditorError("曲线预览的时间和值数量不一致")
        if not all(_timestamp(value) is not None for value in selected.times):
            raise ConfigEditorError("曲线预览包含无法识别的时间，不能安全框选")
        self.preview_series = selected
        if self.preview_path_label.text().startswith("尚未加载"):
            self.preview_path_label.setText(
                "抽样预览由调用方直接提供；未从预览文件校验桥梁和任务范围"
            )
        start, end = self._rule_window()
        self.curve.set_series(
            selected,
            side=self.side,
            module_key=self.target_row.module_key,
            point_key=self.target_row.point_key,
            rule_start=start,
            rule_end=end,
        )
        self.current_proposal = None
        self.current_final_estimate = None
        self.accept_button.setEnabled(False)
        self.summary_label.setStyleSheet(
            "background: #f8fafc; border: 1px solid #cbd5e1; "
            "border-radius: 4px; padding: 7px;"
        )
        self.summary_label.setText(
            "曲线已加载。按住鼠标左键拖出矩形框；候选值只取框内实际有限样本。"
        )

    def _clear_selection(self) -> None:
        self.curve.clear_selection()

    def _selection_changed(self, selection: object) -> None:
        self.current_proposal = None
        self.current_final_estimate = None
        self.accept_button.setEnabled(False)
        self.curve.set_candidate(None)
        self.summary_label.setStyleSheet(
            "background: #f8fafc; border: 1px solid #cbd5e1; "
            "border-radius: 4px; padding: 7px;"
        )
        if selection is None:
            self.summary_label.setText("尚未完成有效框选。请在图中拖出矩形框。")
            return
        if self.preview_series is None or not isinstance(selection, ThresholdSelectionBox):
            self.summary_label.setText("当前框选无效；请重新加载曲线并框选。")
            return
        try:
            proposal = propose_box_threshold(
                self.preview_series,
                selection,
                accepted_preview_point_ids=self.accepted_preview_point_ids,
            )
            final_rows, _index, _replaced = apply_one_sided_to_selected_row(
                [self.target_row],
                selected_index=0,
                draft=proposal.draft,
            )
            final_row = final_rows[0]
            if final_row.minimum is not None and final_row.maximum is not None:
                final_estimate = estimate_two_sided_rule(
                    self.preview_series,
                    TwoSidedThresholdDraft(
                        final_row.module_key,
                        final_row.point_key,
                        final_row.minimum,
                        final_row.maximum,
                        final_row.t_range_start,
                        final_row.t_range_end,
                    ),
                    accepted_preview_point_ids=self.accepted_preview_point_ids,
                )
            else:
                final_estimate = proposal.estimate
        except ConfigEditorError as exc:
            self.summary_label.setText(f"当前框选不能生成阈值：{exc}")
            self.summary_label.setStyleSheet(
                "background: #fff2f0; border: 1px solid #ffccc7; color: #b42318; padding: 7px;"
            )
            return
        self.current_proposal = proposal
        self.current_final_estimate = final_estimate
        self.curve.set_candidate(proposal.threshold)
        self.accept_button.setEnabled(True)
        extreme = "最高值" if self.side == LOWER_SIDE else "最低值"
        operation = "低于" if self.side == LOWER_SIDE else "高于"
        selection_box = selection.validated()
        self.summary_label.setText(
            f"框中选中 {proposal.selected_sample_count} 个有限预览点；候选"
            f"{'下限' if self.side == LOWER_SIDE else '上限'}={proposal.threshold:.15g}"
            f"（框中{extreme}）。严格{operation}该值的点预计删除，等于该值的点保留。"
            f"框选命中时段：{selection_box.selection_start} ～ {selection_box.selection_end}。"
            f"按与当前另一侧阈值组合后的最终规则估算：{final_estimate.summary_text()} "
            f"当前规则时间窗："
            f"{proposal.draft.time_window_text}。确认后仍只修改内存表格，需另点保存才写配置。"
        )
        self.summary_label.setStyleSheet(
            "background: #f0fdf4; border: 1px solid #86d19a; color: #14532d; padding: 7px;"
        )

    def proposal(self) -> BoxThresholdProposal:
        if self.current_proposal is None:
            raise ConfigEditorError("请先完成一个命中实际样本的有效框选")
        return self.current_proposal

    def draft(self) -> OneSidedThresholdDraft:
        return self.proposal().draft

    def estimate_summary(self) -> str:
        if self.current_proposal is None or self.current_final_estimate is None:
            return "尚未生成框选候选阈值"
        return self.current_final_estimate.summary_text()

    def _accept_checked(self) -> None:
        try:
            self.proposal()
        except ConfigEditorError as exc:
            QMessageBox.critical(self, "框选阈值无效", str(exc))
            return
        self.accept()
