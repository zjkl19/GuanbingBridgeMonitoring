from __future__ import annotations

import math
import statistics
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Iterable

from PySide6.QtCore import QDateTime, QPointF, QRectF, Qt, Signal
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
    QSizePolicy,
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
    TwoSidedThresholdDraft,
    UPPER_SIDE,
    estimate_one_sided_rule,
    estimate_two_sided_rule,
    select_preview_series,
)


def _timestamp(value: str) -> float | None:
    text = str(value or "").strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


def _timestamp_text(value: float) -> str:
    return datetime.fromtimestamp(float(value)).strftime("%Y-%m-%d %H:%M:%S")


def _series_axis_data(series: PreviewSeries) -> tuple[list[float], bool]:
    if len(series.times) != len(series.values):
        return [float(index) for index in range(len(series.values))], False
    parsed = [_timestamp(value) for value in series.times]
    use_time = all(value is not None for value in parsed) and len(set(parsed)) > 1
    if use_time:
        return [float(value) for value in parsed if value is not None], True
    return [float(index) for index in range(len(series.values))], False


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
        self.preview_path_label.setWordWrap(True)
        self.preview_path_label.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
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


class ThresholdBandCurveView(QWidget):
    """Curve preview with two draggable bounds and one shared time window."""

    bounds_changed = Signal(float, float)
    window_changed = Signal(str, str)

    _HANDLE_TOLERANCE = 12.0

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setMinimumSize(560, 320)
        self.setFocusPolicy(Qt.StrongFocus)
        self.setAccessibleName("双线设置上下限曲线")
        self.setAccessibleDescription(
            "拖动黄色下限线、红色上限线或紫色共同时间窗边界"
        )
        self._series: PreviewSeries | None = None
        self._lower = -1.0
        self._upper = 1.0
        self._start = ""
        self._end = ""
        self._drag_mode = ""

    def set_rule(
        self,
        series: PreviewSeries | None,
        *,
        lower: float,
        upper: float,
        start: str = "",
        end: str = "",
    ) -> None:
        self._series = series
        self._lower, self._upper = sorted((float(lower), float(upper)))
        self._start = str(start or "")
        self._end = str(end or "")
        self.update()

    def _frame(self) -> QRectF:
        return QRectF(62, 32, max(20, self.width() - 84), max(20, self.height() - 90))

    def _finite_values(self) -> list[float]:
        if self._series is None:
            return []
        return [
            float(value)
            for value in self._series.values
            if value is not None and math.isfinite(float(value))
        ]

    def _y_limits(self) -> tuple[float, float]:
        values = self._finite_values() + [self._lower, self._upper]
        if not values:
            return -1.0, 1.0
        low, high = min(values), max(values)
        if high <= low:
            low, high = low - 1.0, high + 1.0
        padding = max((high - low) * 0.08, max(abs(low), abs(high), 1.0) * 0.01)
        return low - padding, high + padding

    def _axis_data(self) -> tuple[list[float], bool]:
        if self._series is None:
            return [], False
        return _series_axis_data(self._series)

    def _x_limits(self) -> tuple[float, float, bool]:
        xs, use_time = self._axis_data()
        if not xs:
            return 0.0, 1.0, use_time
        low, high = min(xs), max(xs)
        if high <= low:
            high = low + 1.0
        return low, high, use_time

    def _pixel_y(self, value: float) -> float:
        frame = self._frame()
        low, high = self._y_limits()
        return frame.bottom() - (value - low) / (high - low) * frame.height()

    def _value_from_pixel_y(self, pixel_y: float) -> float:
        frame = self._frame()
        low, high = self._y_limits()
        ratio = (frame.bottom() - min(max(pixel_y, frame.top()), frame.bottom())) / frame.height()
        return low + ratio * (high - low)

    def _pixel_x(self, value: float) -> float:
        frame = self._frame()
        low, high, _ = self._x_limits()
        return frame.left() + (value - low) / (high - low) * frame.width()

    def _value_from_pixel_x(self, pixel_x: float) -> float:
        frame = self._frame()
        low, high, _ = self._x_limits()
        ratio = (min(max(pixel_x, frame.left()), frame.right()) - frame.left()) / frame.width()
        return low + ratio * (high - low)

    def _window_values(self) -> tuple[float, float, bool]:
        low, high, use_time = self._x_limits()
        if not use_time:
            return low, high, False
        start = _timestamp(self._start) if self._start else None
        end = _timestamp(self._end) if self._end else None
        if start is None or end is None:
            return low, high, True
        start = min(max(low, start), high)
        end = min(max(low, end), high)
        start, end = sorted((start, end))
        return start, end, True

    def mousePressEvent(self, event: Any) -> None:  # noqa: N802
        if event.button() != Qt.LeftButton or self._series is None:
            super().mousePressEvent(event)
            return
        point = event.position()
        frame = self._frame()
        if not frame.contains(point):
            super().mousePressEvent(event)
            return

        start, end, use_time = self._window_values()
        candidates: list[tuple[float, str]] = [
            (abs(point.y() - self._pixel_y(self._lower)), "lower"),
            (abs(point.y() - self._pixel_y(self._upper)), "upper"),
        ]
        if use_time:
            candidates.extend(
                [
                    (abs(point.x() - self._pixel_x(start)), "start"),
                    (abs(point.x() - self._pixel_x(end)), "end"),
                ]
            )
        distance, mode = min(candidates, key=lambda item: item[0])
        if distance > self._HANDLE_TOLERANCE:
            super().mousePressEvent(event)
            return
        self._drag_mode = mode
        self._update_from_mouse(point)
        event.accept()

    def mouseMoveEvent(self, event: Any) -> None:  # noqa: N802
        if self._drag_mode:
            self._update_from_mouse(event.position())
            event.accept()
            return
        super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event: Any) -> None:  # noqa: N802
        if self._drag_mode and event.button() == Qt.LeftButton:
            self._update_from_mouse(event.position())
            self._drag_mode = ""
            event.accept()
            return
        super().mouseReleaseEvent(event)

    def _update_from_mouse(self, point: QPointF) -> None:
        if self._drag_mode in {"lower", "upper"}:
            value = self._value_from_pixel_y(point.y())
            if self._drag_mode == "lower":
                first, second = value, self._upper
            else:
                first, second = self._lower, value
            lower, upper = sorted((first, second))
            if self._drag_mode == "lower" and value > self._upper:
                self._drag_mode = "upper"
            elif self._drag_mode == "upper" and value < self._lower:
                self._drag_mode = "lower"
            self._lower, self._upper = lower, upper
            self.bounds_changed.emit(lower, upper)
        elif self._drag_mode in {"start", "end"}:
            start, end, use_time = self._window_values()
            if not use_time:
                return
            value = self._value_from_pixel_x(point.x())
            if self._drag_mode == "start":
                first, second = value, end
            else:
                first, second = start, value
            new_start, new_end = sorted((first, second))
            if self._drag_mode == "start" and value > end:
                self._drag_mode = "end"
            elif self._drag_mode == "end" and value < start:
                self._drag_mode = "start"
            self._start = _timestamp_text(new_start)
            self._end = _timestamp_text(new_end)
            self.window_changed.emit(self._start, self._end)
        self.update()

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
                "加载当前测点的曲线预览后，可拖动上下限线和共用时间窗边界",
            )
            return

        series = self._series
        xs, use_time = self._axis_data()
        x_min, x_max, _ = self._x_limits()
        y_min, y_max = self._y_limits()
        start, end, _ = self._window_values()

        def px(value: float) -> float:
            return frame.left() + (value - x_min) / (x_max - x_min) * frame.width()

        def py(value: float) -> float:
            return frame.bottom() - (value - y_min) / (y_max - y_min) * frame.height()

        painter.save()
        painter.setClipRect(frame)
        if use_time:
            painter.fillRect(
                QRectF(px(start), frame.top(), max(1.0, px(end) - px(start)), frame.height()),
                QColor(255, 202, 40, 28),
            )
        band_top = py(self._upper)
        band_bottom = py(self._lower)
        painter.fillRect(
            QRectF(frame.left(), band_top, frame.width(), max(1.0, band_bottom - band_top)),
            QColor(76, 175, 80, 18),
        )

        path = QPainterPath()
        active = False
        removed_points: list[QPointF] = []
        for raw_x, raw_value in zip(xs, series.values):
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
            in_window = not use_time or start <= raw_x <= end
            if in_window and (value < self._lower or value > self._upper):
                removed_points.append(point)
        painter.setPen(QPen(QColor("#1769aa"), 1.0))
        painter.drawPath(path)
        painter.setPen(QPen(QColor("#d99800"), 1.8, Qt.DashLine))
        painter.drawLine(QPointF(frame.left(), py(self._lower)), QPointF(frame.right(), py(self._lower)))
        painter.setPen(QPen(QColor("#d32f2f"), 1.8, Qt.DashLine))
        painter.drawLine(QPointF(frame.left(), py(self._upper)), QPointF(frame.right(), py(self._upper)))
        if use_time:
            painter.setPen(QPen(QColor("#7b1fa2"), 1.5, Qt.DashLine))
            painter.drawLine(QPointF(px(start), frame.top()), QPointF(px(start), frame.bottom()))
            painter.drawLine(QPointF(px(end), frame.top()), QPointF(px(end), frame.bottom()))
        painter.setPen(QPen(QColor("#d32f2f"), 1.0))
        painter.setBrush(QColor("#d32f2f"))
        for point in removed_points:
            painter.drawEllipse(point, 2.5, 2.5)
        painter.restore()

        painter.setPen(QColor("#334155"))
        painter.drawText(QRectF(2, frame.top() - 8, 56, 18), Qt.AlignRight, f"{y_max:.5g}")
        painter.drawText(QRectF(2, frame.bottom() - 8, 56, 18), Qt.AlignRight, f"{y_min:.5g}")
        painter.drawText(
            QRectF(frame.left(), 4, frame.width(), 22),
            Qt.AlignCenter,
            f"{module_label(series.module_key)} / {series.point_id}  "
            f"下限={self._lower:.12g}  上限={self._upper:.12g}",
        )
        painter.drawText(
            QRectF(frame.left(), frame.bottom() + 8, frame.width(), 28),
            Qt.AlignCenter | Qt.TextWordWrap,
            "黄/红虚线为下/上限；紫色竖线是共用时间窗边界；红点是预计删除样本",
        )
        if use_time:
            painter.drawText(
                QRectF(frame.left(), frame.bottom() + 34, frame.width() / 2, 18),
                Qt.AlignLeft,
                _timestamp_text(x_min),
            )
            painter.drawText(
                QRectF(frame.center().x(), frame.bottom() + 34, frame.width() / 2, 18),
                Qt.AlignRight,
                _timestamp_text(x_max),
            )


class ThresholdBandDialog(QDialog):
    """Two-sided threshold editor compatible with the legacy MATLAB band workflow."""

    def __init__(
        self,
        target_row: CleaningThresholdRow,
        *,
        accepted_preview_point_ids: Iterable[str],
        preview_series: PreviewSeries | None = None,
        expected_config_sha256: str = "",
        expected_bridge_id: str = "",
        expected_data_root: str | Path = "",
        expected_start_date: str = "",
        expected_end_date: str = "",
        automatic_preview_resolver: Callable[[], Path] | None = None,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.target_row = target_row.validated()
        self.accepted_preview_point_ids = tuple(dict.fromkeys(accepted_preview_point_ids))
        self.preview_series = preview_series
        self.expected_config_sha256 = str(expected_config_sha256 or "").strip()
        self.expected_bridge_id = str(expected_bridge_id or "").strip()
        self.expected_data_root = str(expected_data_root or "").strip()
        self.expected_start_date = str(expected_start_date or "").strip()
        self.expected_end_date = str(expected_end_date or "").strip()
        self.automatic_preview_resolver = automatic_preview_resolver
        self.preview_identity_verified = False
        self.current_estimate: ThresholdEstimate | None = None
        self._lower_from_config = self.target_row.minimum is not None
        self._upper_from_config = self.target_row.maximum is not None
        self._initial_lower, self._initial_upper = self._default_pair()
        self._initial_window = (
            str(self.target_row.t_range_start or ""),
            str(self.target_row.t_range_end or ""),
        )
        self.setWindowTitle("拖动上下限（双边范围）")
        self._build_ui()
        _fit_dialog_to_available_screen(self)
        self._load_target_window()
        if preview_series is not None:
            self._apply_series(preview_series)
        else:
            self._refresh()
            self._load_automatic_preview(silent=True)

    def _default_pair(self) -> tuple[float, float]:
        lower = float(self.target_row.minimum) if self.target_row.minimum is not None else None
        upper = float(self.target_row.maximum) if self.target_row.maximum is not None else None
        if lower is None and upper is None:
            return -1.0, 1.0
        if lower is None:
            step = max(abs(upper) * 0.1, 1.0)
            return upper - step, upper
        if upper is None:
            step = max(abs(lower) * 0.1, 1.0)
            return lower, lower + step
        if lower == upper:
            return lower - 0.5, upper + 0.5
        return tuple(sorted((lower, upper)))

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("双边上下限：拖线保留区间内数据")
        title.setStyleSheet("font-size: 19px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        target = QLabel(
            f"目标：{module_label(self.target_row.module_key)} / {self.target_row.point_key}。"
            "黄色下限线以下和红色上限线以上的样本将被清洗；"
            "两条线使用同一时间窗。"
        )
        target.setWordWrap(True)
        outer.addWidget(target)

        controls = QGroupBox("精确上下限与共用时间窗")
        grid = QGridLayout(controls)
        validator = QDoubleValidator(self)
        validator.setNotation(QDoubleValidator.StandardNotation)
        grid.addWidget(QLabel("下限"), 0, 0)
        self.lower_edit = QLineEdit(f"{self._initial_lower:.15g}")
        self.lower_edit.setValidator(validator)
        self.lower_edit.setToolTip("可精确输入，也会随黄色下限线拖动同步")
        grid.addWidget(self.lower_edit, 0, 1)
        grid.addWidget(QLabel("上限"), 0, 2)
        self.upper_edit = QLineEdit(f"{self._initial_upper:.15g}")
        self.upper_edit.setValidator(validator)
        self.upper_edit.setToolTip("可精确输入，也会随红色上限线拖动同步")
        grid.addWidget(self.upper_edit, 0, 3)
        self.auto_load_preview_button = QPushButton("自动加载当前任务曲线")
        self.auto_load_preview_button.setToolTip(
            "按当前桥梁、数据目录、日期、配置版本、分析类型和测点自动匹配，不需要选择 JSON 文件"
        )
        self.auto_load_preview_button.clicked.connect(self._load_automatic_preview)
        grid.addWidget(self.auto_load_preview_button, 0, 4)
        self.preview_path_label = QLabel(
            "正在查找当前任务匹配的曲线；普通用户不需要选择 JSON 文件"
        )
        self.preview_path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.preview_path_label.setWordWrap(True)
        self.preview_path_label.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        grid.addWidget(self.preview_path_label, 0, 5)

        self.advanced_preview_toggle = QPushButton("高级：导入已有预览文件")
        self.advanced_preview_toggle.setCheckable(True)
        self.advanced_preview_toggle.setToolTip(
            "仅用于诊断或迁移旧任务；导入后仍会严格核对桥梁、目录、日期、配置版本和测点"
        )
        self.import_preview_button = QPushButton("选择 auto_threshold_preview JSON…")
        self.import_preview_button.setVisible(False)
        self.import_preview_button.clicked.connect(self._choose_preview)
        self.advanced_preview_toggle.toggled.connect(
            self.import_preview_button.setVisible
        )
        grid.addWidget(self.advanced_preview_toggle, 2, 0, 1, 2)
        grid.addWidget(self.import_preview_button, 2, 2, 1, 2)

        self.time_window_check = QCheckBox(
            "共同时间窗（旧 MATLAB 方式，必须；默认取当前预览范围）"
        )
        self.time_window_check.setChecked(True)
        self.time_window_check.setEnabled(False)
        grid.addWidget(self.time_window_check, 1, 0, 1, 2)
        self.start_edit = QDateTimeEdit()
        self.end_edit = QDateTimeEdit()
        for editor in (self.start_edit, self.end_edit):
            editor.setDisplayFormat("yyyy-MM-dd HH:mm:ss")
            editor.setCalendarPopup(True)
            editor.setEnabled(False)
        grid.addWidget(QLabel("开始"), 1, 2)
        grid.addWidget(self.start_edit, 1, 3)
        grid.addWidget(QLabel("结束"), 1, 4)
        grid.addWidget(self.end_edit, 1, 5)
        outer.addWidget(controls)

        self.curve = ThresholdBandCurveView(self)
        outer.addWidget(self.curve, 1)
        self.estimate_label = QLabel()
        self.estimate_label.setWordWrap(True)
        self.estimate_label.setMinimumHeight(58)
        outer.addWidget(self.estimate_label)

        actions = QHBoxLayout()
        reset_button = QPushButton("撤销本次调整")
        reset_button.clicked.connect(self._reset)
        actions.addWidget(reset_button)
        actions.addStretch(1)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        self.accept_button = buttons.button(QDialogButtonBox.Ok)
        self.accept_button.setText("采用此双边上下限")
        self.accept_button.setEnabled(False)
        buttons.button(QDialogButtonBox.Cancel).setText("取消")
        buttons.accepted.connect(self._accept_checked)
        buttons.rejected.connect(self.reject)
        actions.addWidget(buttons)
        outer.addLayout(actions)

        self.lower_edit.textChanged.connect(self._refresh)
        self.upper_edit.textChanged.connect(self._refresh)
        self.lower_edit.editingFinished.connect(self._normalize_edits)
        self.upper_edit.editingFinished.connect(self._normalize_edits)
        self.time_window_check.toggled.connect(self._time_window_toggled)
        self.start_edit.dateTimeChanged.connect(self._refresh)
        self.end_edit.dateTimeChanged.connect(self._refresh)
        self.curve.bounds_changed.connect(self._bounds_from_curve)
        self.curve.window_changed.connect(self._window_from_curve)

    def _load_target_window(self) -> None:
        start = _timestamp(self.target_row.t_range_start) if self.target_row.t_range_start else None
        end = _timestamp(self.target_row.t_range_end) if self.target_row.t_range_end else None
        if start is None or end is None:
            return
        self.start_edit.setDateTime(QDateTime.fromSecsSinceEpoch(int(start)))
        self.end_edit.setDateTime(QDateTime.fromSecsSinceEpoch(int(end)))

    def _numbers(self) -> tuple[float, float]:
        try:
            first = float(self.lower_edit.text().strip())
            second = float(self.upper_edit.text().strip())
        except ValueError as exc:
            raise ConfigEditorError("请填写有效的下限和上限") from exc
        if not math.isfinite(first) or not math.isfinite(second):
            raise ConfigEditorError("上下限必须是有限数值")
        return tuple(sorted((first, second)))

    def _time_texts(self) -> tuple[str, str]:
        return (
            self.start_edit.dateTime().toString("yyyy-MM-dd HH:mm:ss"),
            self.end_edit.dateTime().toString("yyyy-MM-dd HH:mm:ss"),
        )

    def draft(self) -> TwoSidedThresholdDraft:
        lower, upper = self._numbers()
        start, end = self._time_texts()
        return TwoSidedThresholdDraft(
            self.target_row.module_key,
            self.target_row.point_key,
            lower,
            upper,
            start,
            end,
        ).validated()

    def _choose_preview(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "加载已有曲线预览",
            str(Path(self.expected_data_root) / "run_logs")
            if self.expected_data_root
            else "",
            "自动清洗曲线预览 (auto_threshold_preview*.json);;JSON files (*.json)",
        )
        if not path:
            return
        try:
            self.load_preview_path(Path(path))
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "曲线预览无法使用", str(exc))

    def _load_automatic_preview(
        self, _checked: bool = False, *, silent: bool = False
    ) -> bool:
        if self.automatic_preview_resolver is None:
            message = (
                "当前窗口没有绑定任务信息。请关闭窗口，先在主任务页选择桥梁、数据目录和日期；"
                "或展开“高级”导入诊断预览。"
            )
            self.preview_path_label.setText(message)
            if not silent:
                QMessageBox.information(self, "无法自动加载曲线", message)
            return False
        try:
            path = self.automatic_preview_resolver()
            self.load_preview_path(path)
            return True
        except Exception as exc:  # noqa: BLE001
            message = str(exc)
            self.preview_path_label.setText(message)
            if not silent:
                QMessageBox.information(self, "尚无匹配曲线", message)
            return False

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
        verified_task = all(
            (self.expected_data_root, self.expected_start_date, self.expected_end_date)
        )
        checks = []
        if self.expected_config_sha256:
            checks.append("配置版本")
        if verified_task:
            checks.append("数据目录和日期范围")
        verification_text = "、".join(checks) + "已核对" if checks else "未绑定当前任务"
        bridge_text = f"；当前桥梁={self.expected_bridge_id}" if self.expected_bridge_id else ""
        self.preview_path_label.setText(
            f"抽样预览（{verification_text}）：{path.resolve()}{bridge_text}"
        )

    def _apply_series(self, series: PreviewSeries) -> None:
        selected = select_preview_series(
            {series.key: series},
            module_key=self.target_row.module_key,
            point_ids=self.accepted_preview_point_ids,
        )
        if len(selected.times) != len(selected.values):
            raise ConfigEditorError("曲线预览的时间和值数量不一致")
        valid_times = [_timestamp(value) for value in selected.times]
        if any(value is None for value in valid_times) or len(set(valid_times)) < 2:
            raise ConfigEditorError("旧 MATLAB 双线方式需要至少两个不同的有效时间点")
        self.preview_series = selected
        if self.preview_path_label.text() == "尚未加载曲线预览":
            self.preview_path_label.setText(
                "抽样预览由调用方直接提供；未从预览文件校验桥梁和任务范围"
            )
        finite = [
            float(value)
            for value in selected.values
            if value is not None and math.isfinite(float(value))
        ]
        if finite:
            q1 = float(statistics.quantiles(finite, n=4, method="inclusive")[0]) if len(finite) > 1 else finite[0]
            q3 = float(statistics.quantiles(finite, n=4, method="inclusive")[2]) if len(finite) > 1 else finite[0]
            lower = float(self.lower_edit.text()) if self._lower_from_config else min(q1, q3)
            upper = float(self.upper_edit.text()) if self._upper_from_config else max(q1, q3)
            if lower >= upper:
                padding = max((max(finite) - min(finite)) * 0.1, max(abs(lower), 1.0) * 0.01)
                lower, upper = min(lower, upper) - padding, max(lower, upper) + padding
            self._set_bound_edits(lower, upper)
        if not finite:
            raise ConfigEditorError("曲线预览没有可用于设置阈值的有限样本")
        sorted_times = sorted(float(value) for value in valid_times if value is not None)
        if not all(self._initial_window):
            self._initial_window = (
                _timestamp_text(sorted_times[0]),
                _timestamp_text(sorted_times[-1]),
            )
            self.start_edit.setDateTime(QDateTime.fromSecsSinceEpoch(int(sorted_times[0])))
            self.end_edit.setDateTime(QDateTime.fromSecsSinceEpoch(int(sorted_times[-1])))
        self.start_edit.setEnabled(True)
        self.end_edit.setEnabled(True)
        self.accept_button.setEnabled(True)
        self._refresh()

    def _set_bound_edits(self, lower: float, upper: float) -> None:
        for editor, value in ((self.lower_edit, lower), (self.upper_edit, upper)):
            blocked = editor.blockSignals(True)
            editor.setText(f"{value:.15g}")
            editor.blockSignals(blocked)

    def _normalize_edits(self) -> None:
        try:
            lower, upper = self._numbers()
        except ConfigEditorError:
            return
        self._set_bound_edits(lower, upper)
        self._refresh()

    def _bounds_from_curve(self, lower: float, upper: float) -> None:
        self._set_bound_edits(lower, upper)
        self._refresh()

    def _window_from_curve(self, start: str, end: str) -> None:
        start_number = _timestamp(start)
        end_number = _timestamp(end)
        if start_number is None or end_number is None:
            return
        blocked = self.time_window_check.blockSignals(True)
        self.time_window_check.setChecked(True)
        self.time_window_check.blockSignals(blocked)
        self.start_edit.setEnabled(True)
        self.end_edit.setEnabled(True)
        for editor, value in ((self.start_edit, start_number), (self.end_edit, end_number)):
            old = editor.blockSignals(True)
            editor.setDateTime(QDateTime.fromSecsSinceEpoch(int(value)))
            editor.blockSignals(old)
        self._refresh()

    def _time_window_toggled(self, checked: bool) -> None:
        self.start_edit.setEnabled(checked and self.preview_series is not None)
        self.end_edit.setEnabled(checked and self.preview_series is not None)
        self._refresh()

    def _reset(self) -> None:
        self._set_bound_edits(self._initial_lower, self._initial_upper)
        start, end = self._initial_window
        for editor, value in ((self.start_edit, start), (self.end_edit, end)):
            parsed = _timestamp(value) if value else None
            if parsed is not None:
                editor.setDateTime(QDateTime.fromSecsSinceEpoch(int(parsed)))
        self._refresh()

    def _preview_notice(self) -> str:
        if self.preview_identity_verified:
            return (
                "当前为抽样预览，已校验桥梁编号、数据目录、日期范围和配置版本；"
                "正式结果需使用完整缓存复算。"
            )
        return (
            "当前为抽样预览，未完成桥梁和任务范围的文件身份校验；"
            "正式结果需使用完整缓存复算。"
        )

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
            lower=draft.lower,
            upper=draft.upper,
            start=draft.t_range_start,
            end=draft.t_range_end,
        )
        if self.preview_series is None:
            self.current_estimate = None
            self.estimate_label.setText(
                f"精确上下限：[{draft.lower:.15g}, {draft.upper:.15g}]；"
                f"时间窗：{draft.time_window_text}。尚未加载曲线预览，无法估计删除数量。"
            )
        else:
            try:
                self.current_estimate = estimate_two_sided_rule(
                    self.preview_series,
                    draft,
                    accepted_preview_point_ids=self.accepted_preview_point_ids,
                )
                self.estimate_label.setText(
                    f"精确上下限：[{draft.lower:.15g}, {draft.upper:.15g}]；"
                    f"时间窗：{draft.time_window_text}。"
                    + self.current_estimate.summary_text()
                )
            except ConfigEditorError as exc:
                self.current_estimate = None
                self.estimate_label.setText(f"无法估计删除数量：{exc}")
            self.estimate_label.setText(
                f"{self.estimate_label.text()}\n{self._preview_notice()}"
            )
        self.estimate_label.setStyleSheet(
            "background: #f8fafc; border: 1px solid #cbd5e1; color: #334155; padding: 7px;"
        )

    def estimate_summary(self) -> str:
        if self.current_estimate is None:
            return "未加载完整曲线预览；需使用完整缓存复算删除数量"
        return f"{self.current_estimate.summary_text()} {self._preview_notice()}"

    def _accept_checked(self) -> None:
        if self.preview_series is None:
            QMessageBox.critical(self, "尚未加载曲线", "请先加载当前测点的曲线预览。")
            return
        try:
            self.draft()
        except (ValueError, ConfigEditorError) as exc:
            QMessageBox.critical(self, "双边上下限无效", str(exc))
            return
        self.accept()
