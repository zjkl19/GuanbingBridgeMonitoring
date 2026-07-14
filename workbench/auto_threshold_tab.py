from __future__ import annotations

import math
import os
from pathlib import Path
from typing import Any, Callable

from PySide6.QtCore import Qt, QTimer, QUrl, Signal
from PySide6.QtGui import QDesktopServices
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDoubleSpinBox,
    QDialog,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QListWidget,
    QListWidgetItem,
    QMessageBox,
    QPushButton,
    QSplitter,
    QSpinBox,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .auto_threshold import (
    DEFAULT_MODULE_KEYS,
    AutoThresholdRun,
    PreviewSeries,
    launch,
    load_result,
    load_preview_artifact,
    prepare_request,
    read_status,
)
from .auto_threshold_preview import (
    MODULE_LABELS,
    AutoThresholdCurvePreview,
    algorithm_label,
    module_label,
    proposal_kind_label,
)
from .config_editor import CleaningConfigEditorSession, ConfigEditorError


class AutoThresholdProposalWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(
        self,
        project_root: Path,
        context_provider: Callable[[], dict[str, Any]],
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.project_root = project_root.resolve()
        self.context_provider = context_provider
        self.current_run: AutoThresholdRun | None = None
        self.result: dict[str, Any] | None = None
        self.preview_series: dict[tuple[str, str], PreviewSeries] = {}
        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(1000)
        self.poll_timer.timeout.connect(self._poll)
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("自动清洗建议（草稿与人工复核）")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "由内置数据分析服务读取当前数据生成草稿；不会自动修改配置。"
            "仅勾选的全时段阈值或局部时段阈值会在二次确认后写入，并核对生成时的配置版本。"
        )
        hint.setWordWrap(True)
        hint.setToolTip(
            "内部服务：MATLAB AutoThresholdProposalService；"
            "建议类型：range / window_range；配置版本使用 SHA256 校验。"
        )
        outer.addWidget(hint)

        settings_row = QHBoxLayout()
        module_group = QGroupBox("参与模块")
        module_layout = QVBoxLayout(module_group)
        self.module_list = QListWidget()
        self.module_list.setMaximumHeight(150)
        for key in DEFAULT_MODULE_KEYS:
            item = QListWidgetItem(MODULE_LABELS.get(key, key))
            item.setData(Qt.UserRole, key)
            item.setToolTip(f"内部模块键：{key}")
            item.setFlags(item.flags() | Qt.ItemIsUserCheckable)
            item.setCheckState(Qt.Checked)
            self.module_list.addItem(item)
        module_layout.addWidget(self.module_list)
        settings_row.addWidget(module_group, 2)

        options_group = QGroupBox("建议参数")
        options = QGridLayout(options_group)
        self.auto_cut = QCheckBox("智能切线")
        self.auto_cut.setChecked(True)
        self.auto_cut_mode = QComboBox()
        self.auto_cut_mode.addItem("标准", "standard")
        self.auto_cut_mode.addItem("保守", "conservative")
        self.auto_cut_mode.addItem("激进", "aggressive")
        self.quantile = QCheckBox("分位数")
        self.q_low = self._double(0.5, 0, 50, 3)
        self.q_high = self._double(99.5, 50, 100, 3)
        self.padding = self._double(0.05, 0, 10, 3)
        self.mad = QCheckBox("MAD")
        self.mad_factor = self._double(6, 0.1, 100, 2)
        self.iqr = QCheckBox("IQR")
        self.iqr_factor = self._double(3, 0.1, 100, 2)
        self.spike = QCheckBox("局部尖峰时间窗")
        self.spike_factor = self._double(8, 0.1, 100, 2)
        self.zero_flat = QCheckBox("零值/固定值提示")
        self.zero_flat.setChecked(True)
        self.min_valid = QSpinBox()
        self.min_valid.setRange(1, 2_000_000_000)
        self.min_valid.setValue(30)
        self.max_removed = self._double(0.20, 0, 1, 3)
        self.ignore_existing = QCheckBox("生成时忽略现有清洗阈值")
        self.ignore_existing.setChecked(True)
        options.setColumnStretch(0, 1)
        options.setColumnStretch(1, 2)
        options.setColumnStretch(2, 1)
        options.setColumnStretch(3, 2)
        options.addWidget(self.auto_cut, 0, 0)
        options.addWidget(QLabel("切线模式"), 0, 1)
        options.addWidget(self.auto_cut_mode, 0, 2, 1, 2)
        options.addWidget(self.quantile, 1, 0)
        options.addWidget(self._inline("低分位", self.q_low), 1, 1)
        options.addWidget(self._inline("高分位", self.q_high), 1, 2)
        options.addWidget(self._inline("范围外扩", self.padding), 1, 3)
        options.addWidget(self.mad, 2, 0)
        options.addWidget(self._inline("MAD系数", self.mad_factor), 2, 1)
        options.addWidget(self.iqr, 2, 2)
        options.addWidget(self._inline("IQR系数", self.iqr_factor), 2, 3)
        options.addWidget(self.spike, 3, 0)
        options.addWidget(self._inline("尖峰系数", self.spike_factor), 3, 1)
        options.addWidget(self.zero_flat, 3, 2, 1, 2)
        options.addWidget(self._inline("最少有效点", self.min_valid), 4, 0, 1, 2)
        options.addWidget(self._inline("最大剔除比例", self.max_removed), 4, 2, 1, 2)
        options.addWidget(self.ignore_existing, 5, 0, 1, 4)
        settings_row.addWidget(options_group, 5)
        outer.addLayout(settings_row)

        self.table = QTableWidget(0, 14)
        self.table.setHorizontalHeaderLabels(
            [
                "采用",
                "模块",
                "测点",
                "类型",
                "算法",
                "下限",
                "上限",
                "开始时间",
                "结束时间",
                "有效点",
                "剔除点",
                "剔除比例",
                "评分",
                "原因",
            ]
        )
        header_tooltips = {
            1: "内部字段：module_key",
            2: "内部字段：point_id",
            3: "内部字段：kind（range / window_range）",
            4: "内部字段：algorithm",
            5: "内部字段：min",
            6: "内部字段：max",
        }
        for column, tooltip in header_tooltips.items():
            self.table.horizontalHeaderItem(column).setToolTip(tooltip)
        self.table.setAlternatingRowColors(True)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeToContents)
        header.setSectionResizeMode(2, QHeaderView.Stretch)
        header.setSectionResizeMode(13, QHeaderView.Stretch)
        self.table.currentCellChanged.connect(self._refresh_preview)
        self.table.itemChanged.connect(lambda _item: self._refresh_preview())

        splitter = QSplitter(Qt.Horizontal)
        splitter.addWidget(self.table)
        preview_group = QGroupBox("建议曲线预览")
        preview_layout = QVBoxLayout(preview_group)
        self.preview = AutoThresholdCurvePreview()
        preview_layout.addWidget(self.preview, 1)
        self.preview_info = QLabel(self.preview.summary_text())
        self.preview_info.setWordWrap(True)
        self.preview_info.setMinimumHeight(72)
        self.preview_info.setStyleSheet("color: #334155; background: #f8fafc; padding: 6px;")
        preview_layout.addWidget(self.preview_info)
        self.popup_preview_button = QPushButton("弹出大图预览")
        self.popup_preview_button.setEnabled(False)
        self.popup_preview_button.clicked.connect(self._open_preview_dialog)
        preview_layout.addWidget(self.popup_preview_button)
        splitter.addWidget(preview_group)
        splitter.setStretchFactor(0, 3)
        splitter.setStretchFactor(1, 2)
        outer.addWidget(splitter, 1)

        actions = QHBoxLayout()
        self.generate_button = QPushButton("生成建议（后台分析）")
        self.generate_button.setToolTip("使用独立分析进程生成建议，不会阻塞主界面")
        self.generate_button.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 6px 12px;"
        )
        self.generate_button.clicked.connect(self.generate)
        actions.addWidget(self.generate_button)
        self.stop_button = QPushButton("终止建议任务")
        self.stop_button.setEnabled(False)
        self.stop_button.clicked.connect(self.stop)
        actions.addWidget(self.stop_button)
        self.apply_button = QPushButton("应用勾选到配置（自动备份）")
        self.apply_button.setEnabled(False)
        self.apply_button.clicked.connect(self.apply_selected)
        actions.addWidget(self.apply_button)
        self.open_button = QPushButton("打开任务目录")
        self.open_button.setEnabled(False)
        self.open_button.clicked.connect(self.open_run_folder)
        actions.addWidget(self.open_button)
        actions.addStretch(1)
        self.status_label = QLabel("尚未生成建议。")
        actions.addWidget(self.status_label)
        outer.addLayout(actions)

    @staticmethod
    def _double(value: float, minimum: float, maximum: float, decimals: int) -> QDoubleSpinBox:
        widget = QDoubleSpinBox()
        widget.setRange(minimum, maximum)
        widget.setDecimals(decimals)
        widget.setValue(value)
        return widget

    @staticmethod
    def _inline(label: str, control: QWidget) -> QWidget:
        container = QWidget()
        layout = QHBoxLayout(container)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(QLabel(label))
        layout.addWidget(control, 1)
        return container

    def _selected_modules(self) -> list[str]:
        return [
            str(item.data(Qt.UserRole))
            for index in range(self.module_list.count())
            if (item := self.module_list.item(index)).checkState() == Qt.Checked
        ]

    def _options(self) -> dict[str, Any]:
        return {
            "module_keys": self._selected_modules(),
            "min_valid_count": self.min_valid.value(),
            "max_removed_ratio": self.max_removed.value(),
            "use_auto_cut": self.auto_cut.isChecked(),
            "auto_cut_mode": self.auto_cut_mode.currentData(),
            "use_quantile": self.quantile.isChecked(),
            "quantile_low": self.q_low.value(),
            "quantile_high": self.q_high.value(),
            "padding_factor": self.padding.value(),
            "use_mad": self.mad.isChecked(),
            "mad_factor": self.mad_factor.value(),
            "use_iqr": self.iqr.isChecked(),
            "iqr_factor": self.iqr_factor.value(),
            "use_spike_window": self.spike.isChecked(),
            "spike_mad_factor": self.spike_factor.value(),
            "use_zero_or_flat": self.zero_flat.isChecked(),
            "load_without_existing_cleaning": self.ignore_existing.isChecked(),
            "capture_preview_series": True,
            "preview_sample_count": 20_000,
        }

    def generate(self) -> None:
        if self.current_run is not None and self.current_run.process.poll() is None:
            return
        modules = self._selected_modules()
        if not modules:
            QMessageBox.warning(self, "无法生成", "请至少勾选一个模块。")
            return
        try:
            context = self.context_provider()
            paths, payload = prepare_request(
                data_root=Path(context["data_root"]),
                config_path=Path(context["config_path"]),
                start_date=str(context["start_date"]),
                end_date=str(context["end_date"]),
                options=self._options(),
            )
            self.current_run = launch(
                self.project_root, paths, str(payload["config_sha256"])
            )
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "自动建议启动失败", str(exc))
            return
        self.result = None
        self.preview_series = {}
        self.preview.clear()
        self.preview_info.setText(self.preview.summary_text())
        self.popup_preview_button.setEnabled(False)
        self.table.setRowCount(0)
        self.generate_button.setEnabled(False)
        self.stop_button.setEnabled(True)
        self.apply_button.setEnabled(False)
        self.open_button.setEnabled(True)
        self.status_label.setText(f"运行中；PID {self.current_run.process.pid}")
        self.poll_timer.start()

    def _poll(self) -> None:
        run = self.current_run
        if run is None:
            self.poll_timer.stop()
            return
        status = read_status(run.paths.status)
        state = str(status.get("status") or "unknown").lower()
        self.status_label.setText(
            f"{state}；建议 {status.get('proposal_count', '…')}；任务 {run.paths.root.name}"
        )
        if state == "completed":
            self.poll_timer.stop()
            try:
                self.result = load_result(run.paths.result)
                preview_path_text = str(self.result.get("preview_path") or "")
                preview_hash = str(self.result.get("preview_sha256") or "")
                if not preview_path_text or len(preview_hash) != 64:
                    raise ConfigEditorError("后台分析结果缺少固定的预览文件位置或完整性校验码")
                preview_path = Path(preview_path_text)
                self.preview_series = load_preview_artifact(
                    preview_path,
                    expected_sha256=preview_hash,
                    expected_request_id=str(self.result.get("request_id") or ""),
                    expected_config_sha256=str(self.result.get("config_sha256") or ""),
                    expected_series_count=int(self.result.get("preview_series_count") or 0),
                )
                self._populate(self.result.get("proposals", []))
            except Exception as exc:  # noqa: BLE001
                QMessageBox.critical(self, "建议结果读取失败", str(exc))
            self.generate_button.setEnabled(True)
            self.stop_button.setEnabled(False)
            self.apply_button.setEnabled(bool(self.result and self.result.get("proposals")))
        elif state == "failed":
            self.poll_timer.stop()
            self.generate_button.setEnabled(True)
            self.stop_button.setEnabled(False)
            QMessageBox.critical(
                self,
                "自动建议失败",
                f"{status.get('error_id', '')}\n{status.get('message', '')}\n\n{run.paths.stderr}",
            )
        elif run.process.poll() not in (None, 0):
            self.poll_timer.stop()
            self.generate_button.setEnabled(True)
            self.stop_button.setEnabled(False)
            QMessageBox.critical(self, "自动建议进程退出", f"请检查：{run.paths.stderr}")

    def _populate(self, proposals: list[dict[str, Any]]) -> None:
        columns = (
            "module_key",
            "point_id",
            "kind",
            "algorithm",
            "min",
            "max",
            "t_range_start",
            "t_range_end",
            "valid_count",
            "removed_count",
            "removed_ratio",
            "score",
            "reason",
        )
        self.table.blockSignals(True)
        try:
            self.table.setRowCount(0)
            for proposal in proposals:
                row = self.table.rowCount()
                self.table.insertRow(row)
                selected = QTableWidgetItem()
                selected.setFlags(selected.flags() | Qt.ItemIsUserCheckable)
                selected.setCheckState(Qt.Checked if proposal.get("selected") else Qt.Unchecked)
                selected.setData(Qt.UserRole, dict(proposal))
                self.table.setItem(row, 0, selected)
                for column, key in enumerate(columns, 1):
                    value = proposal.get(key)
                    raw_text = "" if value is None else str(value)
                    if key == "module_key":
                        text = module_label(value)
                    elif key == "kind":
                        text = proposal_kind_label(value)
                    elif key == "algorithm":
                        text = algorithm_label(value)
                    else:
                        text = raw_text
                    item = QTableWidgetItem(text)
                    if key in {"module_key", "kind", "algorithm"} and raw_text:
                        item.setToolTip(f"内部值：{raw_text}")
                    if key not in {"min", "max", "t_range_start", "t_range_end", "reason"}:
                        item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                    self.table.setItem(row, column, item)
        finally:
            self.table.blockSignals(False)
        if self.table.rowCount():
            self.table.setCurrentCell(0, 2)
        self._refresh_preview()

    def _proposal_at(self, row: int) -> dict[str, Any] | None:
        if row < 0 or row >= self.table.rowCount():
            return None
        first = self.table.item(row, 0)
        if first is None:
            return None
        proposal = dict(first.data(Qt.UserRole) or {})
        try:
            proposal["min"] = self._optional_number(self.table.item(row, 5).text())
            proposal["max"] = self._optional_number(self.table.item(row, 6).text())
        except (AttributeError, ValueError, ConfigEditorError):
            return proposal
        proposal["t_range_start"] = self.table.item(row, 7).text().strip()
        proposal["t_range_end"] = self.table.item(row, 8).text().strip()
        proposal["reason"] = self.table.item(row, 13).text().strip()
        return proposal

    def _refresh_preview(self, *_args: Any) -> None:
        proposal = self._proposal_at(self.table.currentRow())
        if proposal is None:
            self.preview.clear()
            self.popup_preview_button.setEnabled(False)
        else:
            key = (str(proposal.get("module_key") or ""), str(proposal.get("point_id") or ""))
            self.preview.set_preview(proposal, self.preview_series.get(key))
            self.popup_preview_button.setEnabled(key in self.preview_series)
        self.preview_info.setText(self.preview.summary_text())

    def _open_preview_dialog(self) -> None:
        proposal = self._proposal_at(self.table.currentRow())
        if proposal is None:
            return
        key = (str(proposal.get("module_key") or ""), str(proposal.get("point_id") or ""))
        series = self.preview_series.get(key)
        if series is None:
            return
        dialog = QDialog(self)
        dialog.setWindowTitle("自动清洗建议曲线预览")
        dialog.resize(1120, 680)
        layout = QVBoxLayout(dialog)
        chart = AutoThresholdCurvePreview(dialog)
        chart.set_preview(proposal, series)
        layout.addWidget(chart, 1)
        info = QLabel(chart.summary_text(), dialog)
        info.setWordWrap(True)
        info.setStyleSheet("background: #f8fafc; padding: 8px;")
        layout.addWidget(info)
        dialog.exec()

    def load_preview_demo(self) -> None:
        """Populate deterministic visual-only data for packaged screenshot QA."""
        proposal = {
            "selected": True,
            "module_key": "dynamic_strain",
            "apply_key": "dynamic_strain",
            "point_id": "SX-5",
            "safe_id": "SX_5",
            "kind": "window_range",
            "algorithm": "auto_cut",
            "min": -86.0,
            "max": 94.0,
            "t_range_start": "2026-06-18 01:40:00",
            "t_range_end": "2026-06-18 02:00:00",
            "valid_count": 1440,
            "removed_count": 9,
            "removed_ratio": 0.00625,
            "score": 8.2,
            "reason": "局部尖峰与主体数据带明显分离，仅供人工复核",
        }
        values = [12 * math.sin(index / 17) for index in range(240)]
        values[105:109] = [132, -118, 145, -102]
        times = tuple(
            f"2026-06-18 {index // 60:02d}:{index % 60:02d}:00" for index in range(240)
        )
        series = PreviewSeries("dynamic_strain", "SX-5", "strain", times, tuple(values))
        self.preview_series = {series.key: series}
        self._populate([proposal])

    @staticmethod
    def _optional_number(text: str) -> float | None:
        if not text.strip():
            return None
        value = float(text)
        if not math.isfinite(value):
            raise ConfigEditorError("建议上下限必须是有限数值或留空")
        return int(value) if value.is_integer() else value

    def proposals(self) -> list[dict[str, Any]]:
        proposals: list[dict[str, Any]] = []
        for row in range(self.table.rowCount()):
            first = self.table.item(row, 0)
            proposal = dict(first.data(Qt.UserRole) or {})
            proposal["selected"] = first.checkState() == Qt.Checked
            proposal["min"] = self._optional_number(self.table.item(row, 5).text())
            proposal["max"] = self._optional_number(self.table.item(row, 6).text())
            proposal["t_range_start"] = self.table.item(row, 7).text().strip()
            proposal["t_range_end"] = self.table.item(row, 8).text().strip()
            proposal["reason"] = self.table.item(row, 13).text().strip()
            proposals.append(proposal)
        return proposals

    def apply_selected(self) -> None:
        if self.result is None or self.current_run is None:
            return
        try:
            proposals = self.proposals()
            selected = [
                item
                for item in proposals
                if item.get("selected") and item.get("kind") in {"range", "window_range"}
            ]
            if not selected:
                raise ConfigEditorError("没有勾选可写入的全时段阈值或局部时段阈值建议")
            config_path = Path(str(self.result.get("config_path") or ""))
            expected = str(self.result.get("config_sha256") or "")
            answer = QMessageBox.question(
                self,
                "确认写入自动清洗建议",
                f"将把 {len(selected)} 条人工勾选建议写入：\n{config_path}\n\n"
                "配置会自动备份；建议写入后必须重新运行相应模块并审核图件。是否继续？",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.No,
            )
            if answer != QMessageBox.Yes:
                return
            result = CleaningConfigEditorSession(config_path).save_proposals(
                proposals, expected_sha256=expected
            )
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "建议写入失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无"
        self.status_label.setText(
            f"建议已写入；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "建议写入完成", self.status_label.text())

    def stop(self) -> None:
        run = self.current_run
        if run is None or run.process.poll() is not None:
            return
        answer = QMessageBox.question(
            self,
            "终止建议任务",
            "确认终止当前自动建议后台分析任务？已生成的完整结果文件不会被伪造或补写。",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer == QMessageBox.Yes:
            run.process.terminate()
            self.poll_timer.stop()
            self.generate_button.setEnabled(True)
            self.stop_button.setEnabled(False)
            self.status_label.setText("任务已由用户终止")

    def open_run_folder(self) -> None:
        if self.current_run is None:
            return
        path = self.current_run.paths.root
        if os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(path)))
