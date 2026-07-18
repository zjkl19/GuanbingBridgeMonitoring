from __future__ import annotations

import math
from datetime import datetime
from pathlib import Path
from typing import Any, Callable, Iterable

from PySide6.QtCore import QPointF, QRectF, Qt, Signal
from PySide6.QtGui import QColor, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import (
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QHBoxLayout,
    QInputDialog,
    QLabel,
    QMessageBox,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from .config_editor import CleaningThresholdRow, ConfigEditorError
from .fig_threshold import (
    FigThresholdCancelled,
    FigThresholdError,
    run_fig_threshold_interaction,
)
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
from .threshold_curve import (
    load_current_threshold_curve,
    load_threshold_curve_reference,
)
from .threshold_curve_history import ThresholdCurveHistoryDialog
from .threshold_labels import threshold_module_label as module_label
from .threshold_series import PreviewSeries
from .version import project_root as default_project_root


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
        curve_record_resolver: Callable[[], Path] | None = None,
        task_preview_enabled: bool = True,
        project_root: Path | None = None,
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
        self.curve_record_resolver = curve_record_resolver
        self.task_preview_enabled = bool(task_preview_enabled)
        self.project_root = (project_root or default_project_root()).resolve()
        self.preview_generation_requested = False
        self.curve_generation_requested = False
        self.external_reference_mode = False
        self.external_reference_source = ""
        self.direct_fig_mode = False
        self.direct_fig_source = ""
        self.direct_fig_summary = ""
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
        elif self.task_preview_enabled:
            self._load_current_curve(silent=True)

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
        self.auto_load_preview_button = QPushButton("自动加载当前任务曲线")
        self.auto_load_preview_button.setToolTip(
            "按当前桥梁、数据目录、日期、配置版本、分析类型和测点自动匹配"
        )
        self.auto_load_preview_button.clicked.connect(self._load_current_curve)
        self.auto_load_preview_button.setVisible(self.task_preview_enabled)
        load_row.addWidget(self.auto_load_preview_button)
        self.preview_path_label = QLabel(
            "正在查找当前任务匹配的曲线；正常操作无需选择任何文件"
            if self.task_preview_enabled
            else "滤波后二次清洗不自动采用滤波前预览；请选择任意可信 MATLAB FIG。"
        )
        self.preview_path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.preview_path_label.setWordWrap(True)
        self.preview_path_label.setSizePolicy(QSizePolicy.Ignored, QSizePolicy.Preferred)
        load_row.addWidget(self.preview_path_label, 1)
        clear_button = QPushButton("清除框选")
        clear_button.clicked.connect(self._clear_selection)
        load_row.addWidget(clear_button)
        outer.addLayout(load_row)

        advanced_row = QHBoxLayout()
        self.direct_fig_button = QPushButton("直接选择 MATLAB FIG…")
        self.direct_fig_button.setObjectName("directMatlabFigPrimaryButton")
        self.direct_fig_button.setMinimumHeight(38)
        self.direct_fig_button.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 7px 12px;"
        )
        self.direct_fig_button.setToolTip(
            "直接读取任意可信 FIG 中的真实曲线并框选；"
            "下侧框选取最高值，上侧框选取最低值，等于阈值的点保留"
        )
        self.direct_fig_button.clicked.connect(self._choose_fig)
        advanced_row.addWidget(self.direct_fig_button, 2)
        self.import_preview_button = QPushButton(
            "导入其他任务的工作平台曲线记录…"
        )
        self.import_preview_button.setToolTip(
            "按桥梁、月份、模块和测点从历史任务列表选择；框选仍取真实样本，但不冒充当前任务"
        )
        self.import_preview_button.clicked.connect(self._choose_preview)
        self.import_preview_button.setVisible(self.task_preview_enabled)
        advanced_row.addWidget(self.import_preview_button, 2)
        self.generate_preview_button = QPushButton(
            "生成当前测点曲线（轻量任务）"
        )
        self.generate_preview_button.setToolTip(
            "只处理当前模块和测点，优先读取 MAT 缓存，只生成曲线，不运行自动阈值算法"
        )
        self.generate_preview_button.clicked.connect(
            self._request_preview_generation
        )
        self.generate_preview_button.setVisible(self.task_preview_enabled)
        advanced_row.addWidget(self.generate_preview_button, 2)
        advanced_row.addStretch(1)
        outer.addLayout(advanced_row)

        json_row = QHBoxLayout()
        self.import_preview_json_button = QPushButton("高级：从 JSON 文件导入…")
        self.import_preview_json_button.setToolTip(
            "仅供排障：直接选择新版 threshold_curve_record 或 threshold_curve_preview JSON"
        )
        self.import_preview_json_button.clicked.connect(self._choose_preview_json)
        self.import_preview_json_button.setVisible(self.task_preview_enabled)
        json_row.addWidget(self.import_preview_json_button)
        json_row.addStretch(1)
        outer.addLayout(json_row)

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
        dialog = ThresholdCurveHistoryDialog(
            (self.expected_data_root,),
            target_module=self.target_row.module_key,
            target_point_ids=self.accepted_preview_point_ids,
            parent=self,
        )
        if dialog.exec() != QDialog.Accepted:
            return
        try:
            self.load_reference_preview_path(dialog.selected_preview_path())
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "曲线记录无法使用", str(exc))

    def _choose_preview_json(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "高级：直接选择工作平台曲线 JSON",
            str(Path(self.expected_data_root) / "run_logs")
            if self.expected_data_root
            else "",
            "工作平台曲线记录 (*.json)",
        )
        if not path:
            return
        try:
            self.load_reference_preview_path(Path(path))
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "曲线预览无法使用", str(exc))

    def _choose_fig(self) -> None:
        side_text = "下侧框选取最高值" if self.side == LOWER_SIDE else "上侧框选取最低值"
        path, _ = QFileDialog.getOpenFileName(
            self,
            f"直接选择 MATLAB FIG：{side_text}",
            self.expected_data_root or "",
            "MATLAB 图形 (*.fig)",
        )
        if not path:
            return
        previous_label = self.preview_path_label.text()
        self.preview_path_label.setText(
            "正在启动 MATLAB FIG 框选窗口；请在新窗口中选择坐标轴/曲线并框选…"
        )
        try:
            result = run_fig_threshold_interaction(
                self.project_root,
                Path(path),
                operation=("box_lower" if self.side == LOWER_SIDE else "box_upper"),
                target_module=self.target_row.module_key,
                target_point=self.target_row.point_key,
                parent=self,
            )
            self.apply_direct_fig_result(Path(path), result)
        except FigThresholdCancelled:
            self.preview_path_label.setText(
                f"{previous_label}\n已取消本次 MATLAB FIG 框选；此前曲线和候选值保持不变。"
            )
        except (FigThresholdError, OSError, ValueError) as exc:
            QMessageBox.critical(self, "MATLAB FIG 无法使用", str(exc))
            self.preview_path_label.setText(
                f"{previous_label}\n本次 MATLAB FIG 未能生成框选阈值：{exc}；此前状态保持不变。"
            )
        finally:
            self.raise_()
            self.activateWindow()

    def apply_direct_fig_result(self, path: Path, result: dict[str, Any]) -> None:
        candidate = result.get("candidate")
        if not isinstance(candidate, dict):
            raise ConfigEditorError("MATLAB FIG 结果缺少框选候选值")
        expected_side = LOWER_SIDE if self.side == LOWER_SIDE else UPPER_SIDE
        raw_side = str(candidate.get("side") or "").strip().casefold()
        result_side = {"lower": LOWER_SIDE, "upper": UPPER_SIDE}.get(
            raw_side, raw_side
        )
        if result_side != expected_side:
            raise ConfigEditorError("MATLAB FIG 框选方向与当前按钮不一致")
        try:
            value = float(candidate["value"])
            sample_count = int(candidate["selected_sample_count"])
        except (KeyError, TypeError, ValueError) as exc:
            raise ConfigEditorError("MATLAB FIG 框选候选格式无效") from exc
        if not math.isfinite(value) or sample_count < 1:
            raise ConfigEditorError("MATLAB FIG 框选必须命中至少一个有限样本")
        selection_start = str(candidate.get("selection_start") or "").strip()
        selection_end = str(candidate.get("selection_end") or "").strip()
        if (
            not selection_start
            or not selection_end
            or _timestamp(selection_start) is None
            or _timestamp(selection_end) is None
        ):
            raise ConfigEditorError("MATLAB FIG 框选返回的命中时间范围无效")

        draft = OneSidedThresholdDraft(
            self.target_row.module_key,
            self.target_row.point_key,
            expected_side,
            value,
            self.target_row.t_range_start,
            self.target_row.t_range_end,
        ).validated()
        placeholder_estimate = ThresholdEstimate(0, 0, 0, 0)
        self.current_proposal = BoxThresholdProposal(
            draft,
            sample_count,
            placeholder_estimate,
        )
        self.current_final_estimate = None
        self.direct_fig_mode = True
        self.external_reference_mode = True
        self.preview_identity_verified = False
        self.preview_series = None
        source = result.get("source_curve")
        source = source if isinstance(source, dict) else {}
        axis_title = str(source.get("axis_title") or "未命名坐标轴")
        curve_label = str(source.get("curve_label") or "未命名曲线")
        source_samples = int(source.get("sample_count") or 0)
        self.direct_fig_source = f"{axis_title}/{curve_label}"
        self.external_reference_source = self.direct_fig_source
        self.curve.set_series(
            None,
            side=self.side,
            module_key=self.target_row.module_key,
            point_key=self.target_row.point_key,
            rule_start=self.target_row.t_range_start,
            rule_end=self.target_row.t_range_end,
        )
        self.accept_button.setEnabled(True)
        extreme = "最高值" if self.side == LOWER_SIDE else "最低值"
        self.direct_fig_summary = (
            f"外部 FIG 框中命中 {sample_count} 个有限样本，取{extreme}得到"
            f"{'下限' if self.side == LOWER_SIDE else '上限'}={value:.15g}；"
            f"命中时段 {selection_start} ～ {selection_end}。"
            "结果写入当前选中的配置行并保留其原有时间窗；未据此估算当前任务删除量。"
        )
        self.summary_label.setText(
            f"{self.direct_fig_summary} 确认后仍只修改内存表格，需另点保存才写配置。"
        )
        self.summary_label.setStyleSheet(
            "background: #f0fdf4; border: 1px solid #86d19a; color: #14532d; padding: 7px;"
        )
        self.preview_path_label.setText(
            "外部 MATLAB FIG 参考（未绑定当前任务）："
            f"{path.resolve()}；坐标轴={axis_title}；曲线={curve_label}；"
            f"源曲线有效样本={source_samples}。"
        )

    def _request_preview_generation(self) -> None:
        self.preview_generation_requested = True
        self.curve_generation_requested = True
        self.reject()

    def _pick_reference_series(
        self, previews: dict[tuple[str, str], PreviewSeries]
    ) -> tuple[PreviewSeries, tuple[str, str]]:
        try:
            matched = select_preview_series(
                previews,
                module_key=self.target_row.module_key,
                point_ids=self.accepted_preview_point_ids,
            )
            return matched, matched.key
        except ConfigEditorError:
            pass
        if len(previews) == 1:
            key, series = next(iter(previews.items()))
            return series, key
        labels = [f"{module_label(key[0])} / {key[1]}" for key in previews]
        selected, ok = QInputDialog.getItem(
            self,
            "选择外部参考曲线",
            "该记录包含多条曲线；请选择仅用于参考当前配置行的一条：",
            labels,
            0,
            False,
        )
        if not ok:
            raise ConfigEditorError("已取消选择外部参考曲线")
        index = labels.index(selected)
        key = list(previews)[index]
        return previews[key], key

    def load_reference_preview_path(self, path: Path) -> None:
        previews = load_threshold_curve_reference(path)
        source, source_key = self._pick_reference_series(previews)
        rebound = PreviewSeries(
            self.target_row.module_key,
            self.target_row.point_key,
            source.sensor_type,
            source.times,
            source.values,
        )
        self.external_reference_mode = True
        self.external_reference_source = f"{source_key[0]}/{source_key[1]}"
        self.direct_fig_mode = False
        self.direct_fig_source = ""
        self.direct_fig_summary = ""
        self.preview_identity_verified = False
        self._apply_series(rebound)
        self.preview_path_label.setText(
            "外部参考曲线（未绑定当前任务）："
            f"{path.resolve()}；来源={self.external_reference_source}。"
            "框选取参考曲线的真实样本，结果写入当前选中的配置行。"
        )

    def _load_current_curve(
        self, _checked: bool = False, *, silent: bool = False
    ) -> bool:
        if self.curve_record_resolver is None:
            message = (
                "当前窗口没有绑定任务信息。请关闭窗口，先在主任务页选择桥梁、数据目录和日期；"
                "也可直接选择 MATLAB FIG，或从其他任务的工作平台曲线列表导入。"
            )
            self.preview_path_label.setText(message)
            if not silent:
                QMessageBox.information(self, "无法自动加载曲线", message)
            return False
        try:
            path = self.curve_record_resolver()
            self.load_preview_path(path)
            return True
        except Exception as exc:  # noqa: BLE001
            if self.external_reference_mode and self.preview_series is not None:
                message = (
                    f"当前任务曲线未能通过校验：{exc}；"
                    "已继续保留外部参考曲线（未绑定当前任务）。"
                )
            else:
                message = str(exc)
            self.preview_path_label.setText(message)
            if not silent:
                QMessageBox.information(self, "尚无匹配曲线", message)
            return False

    def load_preview_path(self, path: Path) -> None:
        previews = load_current_threshold_curve(
            path,
            expected_config_sha256=self.expected_config_sha256,
            expected_bridge_id=self.expected_bridge_id,
            expected_data_root=self.expected_data_root,
            expected_start_date=self.expected_start_date,
            expected_end_date=self.expected_end_date,
            expected_module_key=self.target_row.module_key,
            expected_point_ids=self.accepted_preview_point_ids,
        )
        series = select_preview_series(
            previews,
            module_key=self.target_row.module_key,
            point_ids=self.accepted_preview_point_ids,
        )
        identity_verified = all(
            (
                self.expected_config_sha256,
                self.expected_bridge_id,
                self.expected_data_root,
                self.expected_start_date,
                self.expected_end_date,
            )
        )
        self._apply_series(series)
        # Switch from external-reference identity only after the strict
        # current-task artifact and its selected curve both validate.
        self.external_reference_mode = False
        self.external_reference_source = ""
        self.direct_fig_mode = False
        self.direct_fig_source = ""
        self.direct_fig_summary = ""
        self.preview_identity_verified = identity_verified
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
        self.direct_fig_mode = False
        self.direct_fig_source = ""
        self.direct_fig_summary = ""
        self.current_proposal = None
        self.current_final_estimate = None
        self.accept_button.setEnabled(False)
        self.curve.clear_selection()

    def _selection_changed(self, selection: object) -> None:
        self.direct_fig_mode = False
        self.direct_fig_source = ""
        self.direct_fig_summary = ""
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
        if self.direct_fig_mode:
            return self.direct_fig_summary
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
