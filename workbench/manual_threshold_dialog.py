from __future__ import annotations

import math
import statistics
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QDoubleValidator, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import (
    QCheckBox,
    QDateTimeEdit,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .auto_threshold import PreviewSeries, load_preview_artifact
from .auto_threshold_preview import module_label
from .config_editor import CleaningThresholdRow, ConfigEditorError
from .manual_threshold import (
    LOWER_SIDE,
    OneSidedThresholdDraft,
    ThresholdEstimate,
    estimate_one_sided_rule,
    select_preview_series,
)


def _timestamp(value: str) -> float | None:
    text = str(value or "").strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


class OneSidedThresholdCurveView(QWidget):
    """Dependency-free Qt curve view with a vertically draggable threshold."""

    threshold_changed = Signal(float)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setMinimumSize(520, 300)
        self._series: PreviewSeries | None = None
        self._side = LOWER_SIDE
        self._threshold = 0.0
        self._start = ""
        self._end = ""
        self._dragging = False

    def set_rule(
        self,
        series: PreviewSeries | None,
        *,
        side: str,
        threshold: float,
        start: str = "",
        end: str = "",
    ) -> None:
        self._series = series
        self._side = side
        self._threshold = float(threshold)
        self._start = str(start or "")
        self._end = str(end or "")
        self.update()

    def _frame(self) -> QRectF:
        return QRectF(62, 30, max(20, self.width() - 84), max(20, self.height() - 82))

    def _finite_values(self) -> list[float]:
        if self._series is None:
            return []
        return [
            float(value)
            for value in self._series.values
            if value is not None and math.isfinite(float(value))
        ]

    def _y_limits(self) -> tuple[float, float]:
        values = self._finite_values() + [self._threshold]
        if not values:
            return -1.0, 1.0
        low, high = min(values), max(values)
        if high <= low:
            low, high = low - 1.0, high + 1.0
        padding = max((high - low) * 0.08, max(abs(low), abs(high), 1.0) * 0.01)
        return low - padding, high + padding

    def value_from_pixel_y(self, pixel_y: float) -> float:
        frame = self._frame()
        low, high = self._y_limits()
        ratio = (frame.bottom() - min(max(pixel_y, frame.top()), frame.bottom())) / frame.height()
        return low + ratio * (high - low)

    def _set_from_mouse(self, event: Any) -> None:
        frame = self._frame()
        point = event.position()
        if not frame.contains(point):
            return
        self._threshold = self.value_from_pixel_y(point.y())
        self.threshold_changed.emit(self._threshold)
        self.update()

    def mousePressEvent(self, event: Any) -> None:  # noqa: N802
        if event.button() == Qt.LeftButton and self._series is not None:
            self._dragging = self._frame().contains(event.position())
            if self._dragging:
                self._set_from_mouse(event)
                event.accept()
                return
        super().mousePressEvent(event)

    def mouseMoveEvent(self, event: Any) -> None:  # noqa: N802
        if self._dragging:
            self._set_from_mouse(event)
            event.accept()
            return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event: Any) -> None:  # noqa: N802
        if self._dragging and event.button() == Qt.LeftButton:
            self._set_from_mouse(event)
            self._dragging = False
            event.accept()
            return
        super().mouseReleaseEvent(event)

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
                "加载当前测点的已有曲线预览后，可在图中单击或上下拖动阈值线",
            )
            return

        series = self._series
        parsed_x = [_timestamp(value) for value in series.times]
        use_time = all(value is not None for value in parsed_x) and len(set(parsed_x)) > 1
        xs = (
            [float(value) for value in parsed_x]
            if use_time
            else [float(i) for i in range(len(series.values))]
        )
        x_min, x_max = min(xs), max(xs)
        if x_max <= x_min:
            x_max = x_min + 1.0
        y_min, y_max = self._y_limits()

        def px(value: float) -> float:
            return frame.left() + (value - x_min) / (x_max - x_min) * frame.width()

        def py(value: float) -> float:
            return frame.bottom() - (value - y_min) / (y_max - y_min) * frame.height()

        start = _timestamp(self._start) if use_time and self._start else None
        end = _timestamp(self._end) if use_time and self._end else None
        if start is not None and end is not None:
            left, right = sorted((max(x_min, start), min(x_max, end)))
            if right >= left:
                painter.fillRect(
                    QRectF(px(left), frame.top(), max(1, px(right) - px(left)), frame.height()),
                    QColor(255, 202, 40, 36),
                )

        painter.save()
        painter.setClipRect(frame)
        painter.setPen(QPen(QColor("#1769aa"), 1.0))
        path = QPainterPath()
        active = False
        removed_points: list[QPointF] = []
        for raw_x, raw_time, raw_value in zip(xs, series.times, series.values):
            if raw_value is None or not math.isfinite(float(raw_value)):
                active = False
                continue
            value = float(raw_value)
            point = QPointF(px(raw_x), py(value))
            if active:
                path.lineTo(point)
            else:
                path.moveTo(point)
                active = True
            in_window = True
            if start is not None and end is not None:
                timestamp = _timestamp(raw_time)
                in_window = timestamp is not None and start <= timestamp <= end
            removed = in_window and (
                value < self._threshold if self._side == LOWER_SIDE else value > self._threshold
            )
            if removed:
                removed_points.append(point)
        painter.drawPath(path)
        painter.setPen(QPen(QColor("#d32f2f"), 1.6, Qt.DashLine))
        painter.drawLine(
            QPointF(frame.left(), py(self._threshold)),
            QPointF(frame.right(), py(self._threshold)),
        )
        painter.setPen(QPen(QColor("#d32f2f"), 1.0))
        painter.setBrush(QColor("#d32f2f"))
        for point in removed_points:
            painter.drawEllipse(point, 2.5, 2.5)
        painter.restore()

        painter.setPen(QColor("#334155"))
        painter.drawText(QRectF(2, frame.top() - 8, 56, 18), Qt.AlignRight, f"{y_max:.5g}")
        painter.drawText(QRectF(2, frame.bottom() - 8, 56, 18), Qt.AlignRight, f"{y_min:.5g}")
        direction = "下限" if self._side == LOWER_SIDE else "上限"
        painter.drawText(
            QRectF(frame.left(), 4, frame.width(), 22),
            Qt.AlignCenter,
            f"{module_label(series.module_key)} / {series.point_id}　"
            f"{direction}={self._threshold:.12g}",
        )
        painter.drawText(
            QRectF(frame.left(), frame.bottom() + 8, frame.width(), 22),
            Qt.AlignCenter,
            "红点为当前预览中预计被删除的数据；拖动红色虚线可调整阈值",
        )


class OneSidedThresholdDialog(QDialog):
    def __init__(
        self,
        target_row: CleaningThresholdRow,
        *,
        side: str,
        accepted_preview_point_ids: Iterable[str],
        preview_series: PreviewSeries | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.target_row = target_row.validated()
        self.side = side
        self.accepted_preview_point_ids = tuple(dict.fromkeys(accepted_preview_point_ids))
        self.preview_series = preview_series
        self.current_estimate: ThresholdEstimate | None = None
        initial = self.target_row.minimum if side == LOWER_SIDE else self.target_row.maximum
        self._initial_threshold = float(initial) if initial is not None else 0.0
        self._threshold_was_configured = initial is not None
        self.setWindowTitle(
            "设为下限（删除低于此值）" if side == LOWER_SIDE else "设为上限（删除高于此值）"
        )
        self.resize(1000, 720)
        self._build_ui()
        if preview_series is not None:
            self._apply_series(preview_series)
        else:
            self._refresh()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel(self.windowTitle())
        title.setStyleSheet("font-size: 19px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        target = QLabel(
            f"目标：{module_label(self.target_row.module_key)} / {self.target_row.point_key}。"
            "分析类型和测点必须与曲线预览完全一致；本窗口只生成一条单边清洗规则。"
        )
        target.setWordWrap(True)
        outer.addWidget(target)

        controls = QGroupBox("精确阈值与时间窗")
        grid = QGridLayout(controls)
        grid.addWidget(QLabel("阈值"), 0, 0)
        self.threshold_edit = QLineEdit(f"{self._initial_threshold:.15g}")
        validator = QDoubleValidator(self)
        validator.setNotation(QDoubleValidator.StandardNotation)
        self.threshold_edit.setValidator(validator)
        self.threshold_edit.setToolTip("可直接输入精确数值，也可在下方曲线中单击或上下拖动阈值线")
        self.threshold_edit.textEdited.connect(self._mark_threshold_edited)
        self.threshold_edit.textChanged.connect(self._refresh)
        grid.addWidget(self.threshold_edit, 0, 1)
        load_button = QPushButton("加载已有曲线预览…")
        load_button.setToolTip("读取自动清洗建议生成的 auto_threshold_preview.json，不读取旧 MATLAB FIG")
        load_button.clicked.connect(self._choose_preview)
        grid.addWidget(load_button, 0, 2)
        self.preview_path_label = QLabel("尚未加载曲线预览")
        self.preview_path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        grid.addWidget(self.preview_path_label, 0, 3)

        self.time_window_check = QCheckBox("仅在指定时间窗内应用")
        self.time_window_check.toggled.connect(self._time_window_toggled)
        grid.addWidget(self.time_window_check, 1, 0, 1, 2)
        self.start_edit = QDateTimeEdit()
        self.end_edit = QDateTimeEdit()
        for editor in (self.start_edit, self.end_edit):
            editor.setDisplayFormat("yyyy-MM-dd HH:mm:ss")
            editor.setCalendarPopup(True)
            editor.setEnabled(False)
            editor.dateTimeChanged.connect(self._refresh)
        grid.addWidget(QLabel("开始"), 1, 2)
        grid.addWidget(self.start_edit, 1, 3)
        grid.addWidget(QLabel("结束"), 2, 2)
        grid.addWidget(self.end_edit, 2, 3)
        outer.addWidget(controls)

        self.curve = OneSidedThresholdCurveView(self)
        self.curve.threshold_changed.connect(self._threshold_from_curve)
        outer.addWidget(self.curve, 1)

        self.estimate_label = QLabel()
        self.estimate_label.setWordWrap(True)
        self.estimate_label.setMinimumHeight(58)
        self.estimate_label.setStyleSheet(
            "background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px; padding: 7px;"
        )
        outer.addWidget(self.estimate_label)

        actions = QHBoxLayout()
        reset_button = QPushButton("撤销本次调整")
        reset_button.clicked.connect(self._reset)
        actions.addWidget(reset_button)
        actions.addStretch(1)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.button(QDialogButtonBox.Ok).setText("采用此单边阈值")
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self._accept_checked)
        buttons.rejected.connect(self.reject)
        actions.addWidget(buttons)
        outer.addLayout(actions)

    def _number(self) -> float:
        text = self.threshold_edit.text().strip()
        if not text:
            raise ConfigEditorError("请填写阈值")
        value = float(text)
        if not math.isfinite(value):
            raise ConfigEditorError("阈值必须是有限数值")
        return value

    def _time_texts(self) -> tuple[str, str]:
        if not self.time_window_check.isChecked():
            return "", ""
        return (
            self.start_edit.dateTime().toString("yyyy-MM-dd HH:mm:ss"),
            self.end_edit.dateTime().toString("yyyy-MM-dd HH:mm:ss"),
        )

    def draft(self) -> OneSidedThresholdDraft:
        start, end = self._time_texts()
        return OneSidedThresholdDraft(
            self.target_row.module_key,
            self.target_row.point_key,
            self.side,
            self._number(),
            start,
            end,
        ).validated()

    def _choose_preview(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "加载已有曲线预览",
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
        previews = load_preview_artifact(path)
        series = select_preview_series(
            previews,
            module_key=self.target_row.module_key,
            point_ids=self.accepted_preview_point_ids,
        )
        self.preview_path_label.setText(str(path.resolve()))
        self._apply_series(series)

    def _apply_series(self, series: PreviewSeries) -> None:
        selected = select_preview_series(
            {series.key: series},
            module_key=self.target_row.module_key,
            point_ids=self.accepted_preview_point_ids,
        )
        self.preview_series = selected
        finite = [
            float(value)
            for value in selected.values
            if value is not None and math.isfinite(float(value))
        ]
        if finite and not self._threshold_was_configured:
            self.threshold_edit.setText(f"{statistics.median(finite):.15g}")
        # Normalize every preview timestamp through epoch seconds before handing
        # it to Qt.  Preview artifacts can legitimately mix offset-aware values
        # (for example, a trailing ``Z``) and local values; comparing those as
        # Python datetimes raises ``TypeError`` even though each value is valid.
        valid_times = [
            datetime.fromtimestamp(parsed)
            for value in selected.times
            if (parsed := _timestamp(value)) is not None
        ]
        if valid_times:
            self.start_edit.setDateTime(min(valid_times))
            self.end_edit.setDateTime(max(valid_times))
        self._refresh()

    def _time_window_toggled(self, checked: bool) -> None:
        self.start_edit.setEnabled(checked)
        self.end_edit.setEnabled(checked)
        self._refresh()

    def _threshold_from_curve(self, value: float) -> None:
        self._threshold_was_configured = True
        self.threshold_edit.setText(f"{value:.15g}")

    def _mark_threshold_edited(self, _text: str) -> None:
        self._threshold_was_configured = True

    def _reset(self) -> None:
        initial = self.target_row.minimum if self.side == LOWER_SIDE else self.target_row.maximum
        self._threshold_was_configured = initial is not None
        self.threshold_edit.setText(f"{self._initial_threshold:.15g}")
        self.time_window_check.setChecked(False)
        self._refresh()

    def _refresh(self, *_args: Any) -> None:
        try:
            draft = self.draft()
        except (ValueError, ConfigEditorError) as exc:
            self.current_estimate = None
            self.estimate_label.setText(f"当前输入无效：{exc}")
            self.estimate_label.setStyleSheet(
                "background: #fff2f0; border: 1px solid #ffccc7; color: #b42318; padding: 7px;"
            )
            return
        self.curve.set_rule(
            self.preview_series,
            side=draft.side,
            threshold=draft.value,
            start=draft.t_range_start,
            end=draft.t_range_end,
        )
        if self.preview_series is None:
            self.current_estimate = None
            self.estimate_label.setText(
                f"精确阈值：{draft.value:.15g}；时间窗：{draft.time_window_text}。"
                "尚未加载当前测点的曲线预览，无法估计删除数量；保存后必须使用完整缓存复算并审核图件。"
            )
        else:
            try:
                self.current_estimate = estimate_one_sided_rule(
                    self.preview_series,
                    draft,
                    accepted_preview_point_ids=self.accepted_preview_point_ids,
                )
                self.estimate_label.setText(
                    f"精确阈值：{draft.value:.15g}；时间窗：{draft.time_window_text}。"
                    + self.current_estimate.summary_text()
                )
            except ConfigEditorError as exc:
                self.current_estimate = None
                self.estimate_label.setText(f"无法估计删除数量：{exc}")
        self.estimate_label.setStyleSheet(
            "background: #f8fafc; border: 1px solid #cbd5e1; color: #334155; padding: 7px;"
        )

    def estimate_summary(self) -> str:
        if self.current_estimate is None:
            return "未加载完整曲线预览；需使用完整缓存复算删除数量"
        return self.current_estimate.summary_text()

    def _accept_checked(self) -> None:
        try:
            self.draft()
        except (ValueError, ConfigEditorError) as exc:
            QMessageBox.critical(self, "单边阈值无效", str(exc))
            return
        self.accept()
