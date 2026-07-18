from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Mapping

from PySide6.QtCore import QTimer, Qt, QUrl, Signal
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (
    QDialog,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QProgressBar,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from .operator_text import operator_friendly_text, operator_state_label
from .threshold_curve import (
    ThresholdCurveRun,
    launch,
    load_result,
    prepare_threshold_curve_request,
    read_status,
    request_stop,
)
from .threshold_labels import threshold_module_label
from .ui_styles import apply_danger_action_style


_STAGE_LABELS = {
    "prepared": "任务已准备",
    "loading_config": "读取配置",
    "load_curve": "读取当前测点曲线",
    "load_date": "读取日期数据",
    "load_cache_date": "读取 MAT 缓存日期",
    "load_source_date": "读取源数据日期",
    "build_preview": "生成轻量曲线预览",
    "write_preview": "写入曲线预览",
    "write_record": "写入曲线记录",
    "completed": "完成",
    "stop_requested": "正在安全停止",
    "stopped": "已安全停止",
    "failed": "失败",
}


def threshold_curve_stage_label(value: object) -> str:
    raw = str(value or "").strip()
    return _STAGE_LABELS.get(raw.casefold(), operator_friendly_text(raw) or "等待状态")


class ThresholdCurveTaskDialog(QDialog):
    """Run and truthfully monitor one cache-first curve-generation task."""

    curve_ready = Signal(str)

    def __init__(
        self,
        project_root: Path,
        context: Mapping[str, Any],
        module_key: str,
        point_id: str,
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.project_root = project_root.resolve()
        self.context = dict(context)
        self.module_key = str(module_key or "").strip()
        self.point_id = str(point_id or "").strip()
        self.current_run: ThresholdCurveRun | None = None
        self.result: dict[str, Any] | None = None
        self._terminal = False
        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(500)
        self.poll_timer.timeout.connect(self._poll)
        self.setWindowTitle("生成当前测点曲线")
        self.setModal(True)
        self.resize(760, 430)
        self._build_ui()
        QTimer.singleShot(0, self.start)

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("生成当前测点曲线（轻量任务）")
        title.setStyleSheet("font-size: 19px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "仅处理当前模块和测点，优先读取有效 MAT 缓存；不运行自动阈值算法，"
            "也不采用现有清洗阈值。进度来自后台实际阶段和已处理日期。"
        )
        hint.setWordWrap(True)
        outer.addWidget(hint)

        identity = QGroupBox("任务范围")
        identity_grid = QGridLayout(identity)
        identity_grid.addWidget(QLabel("模块"), 0, 0)
        identity_grid.addWidget(QLabel(threshold_module_label(self.module_key)), 0, 1)
        identity_grid.addWidget(QLabel("测点"), 0, 2)
        identity_grid.addWidget(QLabel(self.point_id), 0, 3)
        identity_grid.addWidget(QLabel("日期"), 1, 0)
        identity_grid.addWidget(
            QLabel(
                f"{self.context.get('start_date', '')} 至 {self.context.get('end_date', '')}"
            ),
            1,
            1,
            1,
            3,
        )
        outer.addWidget(identity)

        self.progress = QProgressBar()
        self.progress.setRange(0, 1000)
        self.progress.setValue(0)
        self.progress.setFormat("真实进度 0.0%")
        outer.addWidget(self.progress)

        details = QGroupBox("真实进度")
        grid = QGridLayout(details)
        self.state_label = QLabel("准备启动")
        self.stage_label = QLabel("任务已准备")
        self.current_date_label = QLabel("—")
        self.date_count_label = QLabel("0/0")
        self.elapsed_label = QLabel("0 秒")
        self.message_label = QLabel("尚未启动后台任务。")
        self.message_label.setWordWrap(True)
        self.message_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        grid.addWidget(QLabel("状态"), 0, 0)
        grid.addWidget(self.state_label, 0, 1)
        grid.addWidget(QLabel("阶段"), 0, 2)
        grid.addWidget(self.stage_label, 0, 3)
        grid.addWidget(QLabel("当前日期"), 1, 0)
        grid.addWidget(self.current_date_label, 1, 1)
        grid.addWidget(QLabel("已处理/总日期"), 1, 2)
        grid.addWidget(self.date_count_label, 1, 3)
        grid.addWidget(QLabel("耗时"), 2, 0)
        grid.addWidget(self.elapsed_label, 2, 1)
        grid.addWidget(self.message_label, 3, 0, 1, 4)
        outer.addWidget(details)

        actions = QHBoxLayout()
        self.open_button = QPushButton("打开任务目录")
        self.open_button.setEnabled(False)
        self.open_button.clicked.connect(self.open_run_folder)
        actions.addWidget(self.open_button)
        actions.addStretch(1)
        self.stop_button = QPushButton("请求安全停止")
        apply_danger_action_style(self.stop_button)
        self.stop_button.setEnabled(False)
        self.stop_button.clicked.connect(self.stop)
        actions.addWidget(self.stop_button)
        self.close_button = QPushButton("关闭")
        self.close_button.setEnabled(False)
        self.close_button.clicked.connect(self.accept)
        actions.addWidget(self.close_button)
        outer.addLayout(actions)

    def start(self) -> None:
        if self.current_run is not None:
            return
        try:
            paths, payload = prepare_threshold_curve_request(
                bridge_id=str(self.context.get("bridge_id") or ""),
                data_root=Path(str(self.context.get("data_root") or "")),
                config_path=Path(str(self.context.get("config_path") or "")),
                start_date=str(self.context.get("start_date") or ""),
                end_date=str(self.context.get("end_date") or ""),
                module_key=self.module_key,
                point_id=self.point_id,
            )
            self.current_run = launch(
                self.project_root, paths, str(payload["config_sha256"])
            )
        except Exception as exc:  # noqa: BLE001
            self._finish_failure(f"曲线任务启动失败：{operator_friendly_text(exc)}")
            return
        self.open_button.setEnabled(True)
        self.stop_button.setEnabled(True)
        self.state_label.setText("正在处理")
        self.message_label.setText(
            f"后台任务 PID {self.current_run.process.pid}；任务 {self.current_run.request_id}"
        )
        self.poll_timer.start()

    @staticmethod
    def _number(payload: Mapping[str, Any], field: str, fallback: float = 0.0) -> float:
        try:
            return float(payload.get(field, fallback))
        except (TypeError, ValueError):
            return fallback

    def _update_status(self, status: Mapping[str, Any]) -> str:
        state = str(status.get("status") or "unknown").casefold()
        self.state_label.setText(operator_state_label(state))
        self.stage_label.setText(threshold_curve_stage_label(status.get("stage")))
        self.current_date_label.setText(str(status.get("current_date") or "—"))
        processed = max(0, int(self._number(status, "processed_dates")))
        total = max(0, int(self._number(status, "total_dates")))
        self.date_count_label.setText(f"{processed}/{total}")
        elapsed = max(
            0.0,
            self._number(status, "elapsed_seconds", self._number(status, "elapsed_sec")),
        )
        self.elapsed_label.setText(f"{round(elapsed)} 秒")
        fraction = self._number(status, "progress_fraction", -1.0)
        if fraction < 0:
            fraction = self._number(status, "progress_percent") / 100.0
        fraction = min(1.0, max(0.0, fraction))
        self.progress.setValue(round(fraction * 1000))
        self.progress.setFormat(f"真实进度 {fraction * 100:.1f}%")
        message = str(status.get("message") or "").strip()
        if message:
            self.message_label.setText(operator_friendly_text(message))
        return state

    def _poll(self) -> None:
        run = self.current_run
        if run is None or self._terminal:
            self.poll_timer.stop()
            return
        status = read_status(run.paths.status, expected_request_id=run.request_id)
        state = self._update_status(status)
        if state == "completed":
            try:
                self.result = load_result(
                    run.paths.result,
                    expected_request_id=run.request_id,
                    expected_config_sha256=run.config_sha256,
                )
            except Exception as exc:  # noqa: BLE001
                self._finish_failure(f"曲线结果校验失败：{operator_friendly_text(exc)}")
                return
            metadata = self.result["record_metadata"]
            self.progress.setValue(1000)
            self.progress.setFormat("真实进度 100.0%")
            self.message_label.setText(
                f"完成：源样本 {metadata.source_sample_count}，有限样本 "
                f"{metadata.finite_sample_count}，曲线预览点 {metadata.sample_count}。"
                f"记录：{metadata.record_path}"
            )
            self.curve_ready.emit(str(metadata.preview_path))
            self._finish_terminal()
        elif state == "stopped":
            self.message_label.setText("任务已在安全边界停止；未发布不完整的最终曲线记录。")
            self._finish_terminal()
        elif state == "failed":
            self._finish_failure(
                f"曲线任务失败：{operator_friendly_text(status.get('message') or '请检查任务日志')}"
            )
        elif run.process.poll() not in (None, 0):
            self._finish_failure(f"曲线后台进程异常退出；请检查：{run.paths.stderr}")

    def _finish_terminal(self) -> None:
        self._terminal = True
        self.poll_timer.stop()
        self.stop_button.setEnabled(False)
        self.close_button.setEnabled(True)

    def _finish_failure(self, message: str) -> None:
        self.state_label.setText("失败")
        self.stage_label.setText("失败")
        self.message_label.setText(message)
        self.message_label.setStyleSheet("color: #9b1c1c; font-weight: 600;")
        self._finish_terminal()

    def stop(self) -> None:
        run = self.current_run
        if run is None or self._terminal or run.process.poll() is not None:
            return
        try:
            request_stop(run.paths, reason="用户在工作平台请求安全停止当前测点曲线任务")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "安全停止请求失败", operator_friendly_text(exc))
            return
        self.stop_button.setEnabled(False)
        self.state_label.setText("正在停止")
        self.stage_label.setText("正在安全停止")
        self.message_label.setText("已写入本任务专属停止标志，正在等待后台到达安全边界。")

    def open_run_folder(self) -> None:
        if self.current_run is None:
            return
        path = self.current_run.paths.root
        if os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))

    def reject(self) -> None:
        if not self._terminal:
            QMessageBox.information(
                self,
                "任务仍在运行",
                "请等待任务完成，或先点击“请求安全停止”并等待安全停止完成。",
            )
            return
        super().reject()

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt API
        if not self._terminal:
            event.ignore()
            QMessageBox.information(
                self,
                "任务仍在运行",
                "请等待任务完成，或先请求安全停止。窗口不会粗暴结束后台进程。",
            )
            return
        super().closeEvent(event)


__all__ = ["ThresholdCurveTaskDialog", "threshold_curve_stage_label"]
