from __future__ import annotations

import math
from datetime import datetime
from typing import Any

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFontMetrics, QPainter, QPainterPath, QPen
from PySide6.QtWidgets import QWidget

from .auto_threshold import PreviewSeries


def _timestamp(value: str) -> float | None:
    text = value.strip().replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(text).timestamp()
    except ValueError:
        return None


class AutoThresholdCurvePreview(QWidget):
    """Small dependency-free Qt curve view for MATLAB proposal previews."""

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setMinimumSize(360, 260)
        self._proposal: dict[str, Any] | None = None
        self._series: PreviewSeries | None = None

    def clear(self) -> None:
        self._proposal = None
        self._series = None
        self.update()

    def set_preview(self, proposal: dict[str, Any], series: PreviewSeries | None) -> None:
        self._proposal = dict(proposal)
        self._series = series
        self.update()

    def summary_text(self) -> str:
        proposal, series = self._proposal, self._series
        if not proposal:
            return "选择一条建议后显示曲线、建议阈值和局部时间窗。"
        if series is None:
            return f"{proposal.get('module_key', '')}/{proposal.get('point_id', '')} 没有可用预览序列。"
        bounds = f"{self._number(proposal.get('min'))} ～ {self._number(proposal.get('max'))}"
        time_range = "全时段"
        if proposal.get("t_range_start") and proposal.get("t_range_end"):
            time_range = f"{proposal['t_range_start']} ～ {proposal['t_range_end']}"
        return (
            f"{series.module_key} / {series.point_id}　算法：{proposal.get('algorithm', '')}　"
            f"类型：{proposal.get('kind', '')}\n建议范围：{bounds}　时间范围：{time_range}　"
            f"预览点数：{len(series.values)}\n原因：{proposal.get('reason', '')}"
        )

    @staticmethod
    def _number(value: Any) -> str:
        try:
            number = float(value)
        except (TypeError, ValueError):
            return "无"
        return f"{number:.6g}" if math.isfinite(number) else "无"

    def paintEvent(self, event: Any) -> None:  # noqa: N802
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)
        painter.fillRect(self.rect(), QColor("#ffffff"))
        frame = QRectF(58, 28, max(20, self.width() - 78), max(20, self.height() - 76))
        painter.setPen(QPen(QColor("#b8c2cc"), 1))
        painter.drawRect(frame)
        if self._proposal is None or self._series is None or not self._series.values:
            painter.setPen(QColor("#64748b"))
            painter.drawText(frame, Qt.AlignCenter | Qt.TextWordWrap, "选择建议后显示原始曲线预览")
            return

        series = self._series
        x_values = [_timestamp(value) for value in series.times]
        use_time = all(value is not None for value in x_values) and len(set(x_values)) > 1
        xs = [float(value) for value in x_values] if use_time else [float(i) for i in range(len(series.values))]
        finite = [(x, value) for x, value in zip(xs, series.values) if value is not None]
        if not finite:
            painter.setPen(QColor("#64748b"))
            painter.drawText(frame, Qt.AlignCenter, "预览序列没有有限数值")
            return
        x_min, x_max = finite[0][0], finite[-1][0]
        if x_max <= x_min:
            x_max = x_min + 1
        y_candidates = [value for _, value in finite]
        for key in ("min", "max"):
            try:
                value = float(self._proposal.get(key))
                if math.isfinite(value):
                    y_candidates.append(value)
            except (TypeError, ValueError):
                pass
        y_min, y_max = min(y_candidates), max(y_candidates)
        padding = max((y_max - y_min) * 0.08, max(abs(y_min), abs(y_max), 1.0) * 0.01)
        y_min, y_max = y_min - padding, y_max + padding

        def px(x: float) -> float:
            return frame.left() + (x - x_min) / (x_max - x_min) * frame.width()

        def py(y: float) -> float:
            return frame.bottom() - (y - y_min) / (y_max - y_min) * frame.height()

        start = _timestamp(str(self._proposal.get("t_range_start") or "")) if use_time else None
        end = _timestamp(str(self._proposal.get("t_range_end") or "")) if use_time else None
        if start is not None and end is not None:
            left, right = sorted((max(x_min, start), min(x_max, end)))
            if right >= left:
                painter.fillRect(QRectF(px(left), frame.top(), max(1, px(right) - px(left)), frame.height()), QColor(255, 202, 40, 42))
                painter.setPen(QPen(QColor("#64748b"), 1, Qt.DotLine))
                painter.drawLine(QPointF(px(left), frame.top()), QPointF(px(left), frame.bottom()))
                painter.drawLine(QPointF(px(right), frame.top()), QPointF(px(right), frame.bottom()))

        painter.save()
        painter.setClipRect(frame)
        painter.setPen(QPen(QColor("#1769aa"), 1.0))
        path = QPainterPath()
        active = False
        for x, value in zip(xs, series.values):
            if value is None:
                active = False
                continue
            point = QPointF(px(x), py(value))
            if active:
                path.lineTo(point)
            else:
                path.moveTo(point)
                active = True
        painter.drawPath(path)
        painter.setPen(QPen(QColor("#d32f2f"), 1.4, Qt.DashLine))
        for key in ("min", "max"):
            try:
                value = float(self._proposal.get(key))
            except (TypeError, ValueError):
                continue
            if math.isfinite(value):
                painter.drawLine(QPointF(frame.left(), py(value)), QPointF(frame.right(), py(value)))
        painter.restore()

        painter.setPen(QColor("#334155"))
        metrics = QFontMetrics(painter.font())
        painter.drawText(QRectF(2, frame.top() - 8, 52, 18), Qt.AlignRight | Qt.AlignVCenter, f"{y_max:.4g}")
        painter.drawText(QRectF(2, frame.bottom() - 9, 52, 18), Qt.AlignRight | Qt.AlignVCenter, f"{y_min:.4g}")
        first = series.times[0] if use_time else "1"
        last = series.times[-1] if use_time else str(len(series.values))
        painter.drawText(QRectF(frame.left(), frame.bottom() + 7, frame.width() / 2, 20), Qt.AlignLeft, metrics.elidedText(first, Qt.ElideRight, int(frame.width() / 2 - 8)))
        painter.drawText(QRectF(frame.center().x(), frame.bottom() + 7, frame.width() / 2, 20), Qt.AlignRight, metrics.elidedText(last, Qt.ElideLeft, int(frame.width() / 2 - 8)))
        title = f"{series.module_key} | {series.point_id} | {self._proposal.get('algorithm', '')}"
        painter.drawText(QRectF(frame.left(), 4, frame.width(), 20), Qt.AlignCenter, metrics.elidedText(title, Qt.ElideMiddle, int(frame.width())))
