from __future__ import annotations

import os
import traceback
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QDate, QSize, QTimer, Qt, QUrl
from PySide6.QtGui import QDesktopServices, QFont
from PySide6.QtWidgets import (
    QCheckBox,
    QComboBox,
    QDateEdit,
    QFileDialog,
    QFormLayout,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QPlainTextEdit,
    QProgressBar,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .analysis import AnalysisLauncher, ExecutorResolver, read_analysis_status
from .config_tab import AlarmBoundsEditorWidget
from .manifest import ManifestSummary, find_latest_manifest, load_manifest_summary, manifest_context_issues
from .module_icons import module_icon
from .models import JobContext, file_sha256
from .modules import MODULE_SPECS, options_for_modules
from .profiles import WorkbenchProfile, load_profiles, profile_by_id
from .report_bridge import launch_report_gui
from .update_ui import UpdateController
from .version import app_version, project_root as default_project_root


SUCCESS_STATES = {"ok", "success", "completed"}


def _set_line_edit_path(edit: QLineEdit, value: Path | str) -> None:
    edit.setText(str(value))
    edit.setCursorPosition(0)


class WorkbenchWindow(QMainWindow):
    def __init__(self, project_root: Path | None = None) -> None:
        super().__init__()
        self.project_root = (project_root or default_project_root()).resolve()
        self.profiles = load_profiles(self.project_root)
        self.current_context: JobContext | None = None
        self.current_context_path: Path | None = None
        self.current_manifest: ManifestSummary | None = None
        self.current_manifest_missing_selected: tuple[str, ...] = ()
        self.module_checks: dict[str, QCheckBox] = {}
        self.setFont(QFont("Microsoft YaHei UI", 9))
        self.setWindowTitle(f"桥梁健康监测工作台 {app_version(self.project_root)}")
        # The four-column module grid and the update action are designed for
        # the 1600 px workbench layout used by the legacy GUI.
        self.resize(1600, 860)
        self._build_ui()
        self._apply_profile(self.profiles[0])
        self.update_controller = UpdateController(self, self.update_btn, self.project_root)
        self.update_controller.schedule_auto_check()
        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(2000)
        self.poll_timer.timeout.connect(self._poll_status)
        self.poll_timer.start()

    def _build_ui(self) -> None:
        tabs = QTabWidget(self)
        tabs.addTab(self._build_analysis_tab(), "项目与数据分析")
        self.alarm_editor = AlarmBoundsEditorWidget()
        self.alarm_editor.config_saved.connect(self._on_alarm_config_saved)
        tabs.addTab(self.alarm_editor, "配置与预警值")
        tabs.addTab(self._build_review_tab(), "结果与图件审核")
        tabs.addTab(self._build_report_tab(), "报告生成")
        self.setCentralWidget(tabs)
        self.tabs = tabs

    def _build_analysis_tab(self) -> QWidget:
        page = QWidget()
        outer = QVBoxLayout(page)
        title = QLabel("桥梁健康监测统一任务")
        title.setStyleSheet("font-size: 22px; font-weight: 700; color: #005eac;")
        title_row = QHBoxLayout()
        title_row.addWidget(title)
        title_row.addStretch(1)
        self.update_btn = QPushButton("检查更新")
        self.update_btn.setToolTip("从 GitHub Release 检查工作台正式更新")
        title_row.addWidget(self.update_btn)
        outer.addLayout(title_row)

        form_group = QGroupBox("任务上下文")
        form = QFormLayout(form_group)
        self.profile_combo = QComboBox()
        for profile in self.profiles:
            self.profile_combo.addItem(profile.bridge_name, profile.bridge_id)
        self.profile_combo.currentIndexChanged.connect(self._on_profile_changed)
        form.addRow("桥梁项目", self.profile_combo)

        self.data_root_edit = QLineEdit()
        form.addRow("数据根目录", self._path_row(self.data_root_edit, self._browse_data_root, directory=True))
        self.config_edit = QLineEdit()
        form.addRow("配置文件", self._path_row(self.config_edit, self._browse_config))

        date_row = QWidget()
        date_layout = QHBoxLayout(date_row)
        date_layout.setContentsMargins(0, 0, 0, 0)
        self.start_date_edit = QDateEdit(calendarPopup=True)
        self.start_date_edit.setDisplayFormat("yyyy-MM-dd")
        self.end_date_edit = QDateEdit(calendarPopup=True)
        self.end_date_edit.setDisplayFormat("yyyy-MM-dd")
        date_layout.addWidget(QLabel("开始"))
        date_layout.addWidget(self.start_date_edit)
        date_layout.addSpacing(16)
        date_layout.addWidget(QLabel("结束"))
        date_layout.addWidget(self.end_date_edit)
        date_layout.addStretch(1)
        form.addRow("监测日期", date_row)
        outer.addWidget(form_group)

        module_group = QGroupBox("处理与分析模块")
        module_layout = QGridLayout(module_group)
        for index, spec in enumerate(MODULE_SPECS):
            checkbox = QCheckBox(spec.label)
            checkbox.setProperty("module_key", spec.key)
            checkbox.setToolTip(f"{spec.label}（{spec.key}）")
            checkbox.setIcon(module_icon(self.project_root, spec.icon_asset))
            checkbox.setIconSize(QSize(22, 22))
            self.module_checks[spec.key] = checkbox
            module_layout.addWidget(checkbox, index // 4, index % 4)
        outer.addWidget(module_group)

        action_row = QHBoxLayout()
        self.validate_btn = QPushButton("检查任务")
        self.validate_btn.clicked.connect(self._validate_inputs_dialog)
        action_row.addWidget(self.validate_btn)
        self.open_context_btn = QPushButton("打开已有任务")
        self.open_context_btn.clicked.connect(self._open_context_dialog)
        action_row.addWidget(self.open_context_btn)
        self.save_btn = QPushButton("保存任务上下文")
        self.save_btn.clicked.connect(self._save_context)
        action_row.addWidget(self.save_btn)
        self.start_btn = QPushButton("启动本机分析")
        self.start_btn.setStyleSheet("font-weight: 700; background: #005eac; color: white; padding: 6px 16px;")
        self.start_btn.clicked.connect(self._start_analysis)
        action_row.addWidget(self.start_btn)
        self.stop_btn = QPushButton("请求停止")
        self.stop_btn.setEnabled(False)
        self.stop_btn.clicked.connect(self._request_stop)
        action_row.addWidget(self.stop_btn)
        action_row.addStretch(1)
        outer.addLayout(action_row)

        self.analysis_status_label = QLabel("状态：尚未建立任务")
        self.analysis_status_label.setStyleSheet("font-weight: 600;")
        outer.addWidget(self.analysis_status_label)
        progress_row = QHBoxLayout()
        self.analysis_progress = QProgressBar()
        self.analysis_progress.setRange(0, 1000)
        self.analysis_progress.setValue(0)
        self.analysis_progress.setFormat("%p%")
        progress_row.addWidget(self.analysis_progress, 1)
        self.analysis_progress_label = QLabel("等待任务")
        self.analysis_progress_label.setMinimumWidth(360)
        progress_row.addWidget(self.analysis_progress_label)
        outer.addLayout(progress_row)
        self.analysis_log = QPlainTextEdit()
        self.analysis_log.setReadOnly(True)
        self.analysis_log.setPlaceholderText("工作台操作、启动信息和状态变化会显示在这里。")
        outer.addWidget(self.analysis_log, 1)
        return page

    def _build_review_tab(self) -> QWidget:
        page = QWidget()
        outer = QVBoxLayout(page)
        header = QHBoxLayout()
        self.manifest_label = QLabel("Manifest：未加载")
        self.manifest_label.setWordWrap(True)
        self.manifest_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        header.addWidget(self.manifest_label, 1)
        refresh = QPushButton("刷新当前任务")
        refresh.clicked.connect(self._poll_status)
        header.addWidget(refresh)
        load_latest = QPushButton("显式加载数据目录最新Manifest")
        load_latest.clicked.connect(self._load_latest_manifest)
        header.addWidget(load_latest)
        outer.addLayout(header)

        self.manifest_summary_label = QLabel("等待分析完成。")
        outer.addWidget(self.manifest_summary_label)
        self.module_table = QTableWidget(0, 6)
        self.module_table.setHorizontalHeaderLabels(["模块", "状态", "耗时", "统计文件", "消息", "Key"])
        self.module_table.setAlternatingRowColors(True)
        self.module_table.setEditTriggers(QTableWidget.NoEditTriggers)
        self.module_table.horizontalHeader().setStretchLastSection(False)
        header_view = self.module_table.horizontalHeader()
        header_view.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        header_view.setSectionResizeMode(1, QHeaderView.ResizeToContents)
        header_view.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        header_view.setSectionResizeMode(3, QHeaderView.Interactive)
        header_view.setSectionResizeMode(4, QHeaderView.Stretch)
        header_view.setSectionResizeMode(5, QHeaderView.ResizeToContents)
        self.module_table.setColumnWidth(3, 300)
        outer.addWidget(self.module_table, 1)

        approval_group = QGroupBox("正式报告门禁")
        approval_layout = QVBoxLayout(approval_group)
        approval_layout.addWidget(QLabel("请先检查关键图件、统计工作簿和 provenance。审核只对当前任务及其绑定的 manifest 生效。"))
        self.approval_check = QCheckBox("我已审核当前任务图件，允许进入正式报告阶段")
        self.approval_check.stateChanged.connect(self._on_approval_changed)
        approval_layout.addWidget(self.approval_check)
        outer.addWidget(approval_group)
        return page

    def _build_report_tab(self) -> QWidget:
        page = QWidget()
        outer = QVBoxLayout(page)
        form = QFormLayout()
        self.template_edit = QLineEdit()
        form.addRow("报告模板", self._path_row(self.template_edit, self._browse_template))
        self.output_dir_edit = QLineEdit()
        form.addRow("输出目录", self._path_row(self.output_dir_edit, self._browse_output_dir, directory=True))
        self.period_label_edit = QLineEdit()
        form.addRow("报告期", self.period_label_edit)
        self.monitoring_range_edit = QLineEdit()
        form.addRow("监测时间文字", self.monitoring_range_edit)
        self.report_date_edit = QLineEdit(datetime.now().strftime("%Y年%m月%d日"))
        form.addRow("报告日期", self.report_date_edit)
        outer.addLayout(form)

        self.report_gate_label = QLabel("报告生成已锁定：需要成功的分析 manifest 和图件审核。")
        self.report_gate_label.setWordWrap(True)
        outer.addWidget(self.report_gate_label)
        buttons = QHBoxLayout()
        self.open_report_btn = QPushButton("打开已带入任务上下文的报告生成器")
        self.open_report_btn.setEnabled(False)
        self.open_report_btn.clicked.connect(self._open_report_generator)
        buttons.addWidget(self.open_report_btn)
        open_output = QPushButton("打开输出目录")
        open_output.clicked.connect(self._open_output_dir)
        buttons.addWidget(open_output)
        buttons.addStretch(1)
        outer.addLayout(buttons)
        info = QLabel(
            "第一轮MVP先复用现有报告生成器，但桥梁、数据目录、配置、周期、模板和manifest由工作台自动传递。"
            "下一阶段将把报告构建进度和最终QC直接嵌入本页。"
        )
        info.setWordWrap(True)
        info.setStyleSheet("color: #6b7280;")
        outer.addWidget(info)
        outer.addStretch(1)
        return page

    def _path_row(self, edit: QLineEdit, callback, *, directory: bool = False) -> QWidget:
        container = QWidget()
        layout = QHBoxLayout(container)
        layout.setContentsMargins(0, 0, 0, 0)
        layout.addWidget(edit, 1)
        button = QPushButton("浏览")
        button.setProperty("directory", directory)
        button.clicked.connect(callback)
        layout.addWidget(button)
        return container

    def _on_profile_changed(self, index: int) -> None:
        bridge_id = str(self.profile_combo.itemData(index) or "")
        if bridge_id:
            self._apply_profile(profile_by_id(self.profiles, bridge_id))

    def _apply_profile(self, profile: WorkbenchProfile) -> None:
        self.current_profile = profile
        _set_line_edit_path(self.data_root_edit, profile.default_data_root)
        _set_line_edit_path(self.config_edit, profile.config_path(self.project_root))
        try:
            self.alarm_editor.load_path(profile.config_path(self.project_root))
        except Exception as exc:  # noqa: BLE001
            self.alarm_editor.message_label.setText(f"配置加载失败：{exc}")
            self.alarm_editor.message_label.setStyleSheet("color: #a33;")
        _set_line_edit_path(self.template_edit, profile.template_path(self.project_root) if profile.report_template else "")
        output = Path(profile.default_data_root) / "自动报告" if profile.default_data_root else self.project_root / "output" / "doc"
        _set_line_edit_path(self.output_dir_edit, output)
        self.period_label_edit.setText(profile.default_period_label)
        self.monitoring_range_edit.setText(profile.default_monitoring_range)
        self.report_date_edit.setText(profile.default_report_date or datetime.now().strftime("%Y年%m月%d日"))
        self._set_date(self.start_date_edit, profile.default_start_date)
        self._set_date(self.end_date_edit, profile.default_end_date)
        enabled = set(profile.enabled_modules)
        for key, checkbox in self.module_checks.items():
            checkbox.setChecked(key in enabled)
        self._append_log(f"已切换项目：{profile.bridge_name}")

    @staticmethod
    def _set_date(widget: QDateEdit, value: str) -> None:
        parsed = QDate.fromString(value, "yyyy-MM-dd")
        widget.setDate(parsed if parsed.isValid() else QDate.currentDate())

    def _selected_modules(self) -> list[str]:
        return [key for key, checkbox in self.module_checks.items() if checkbox.isChecked()]

    def _validate_inputs(self) -> list[str]:
        errors: list[str] = []
        data_root = Path(self.data_root_edit.text().strip()).expanduser()
        config = Path(self.config_edit.text().strip()).expanduser()
        if not data_root.is_dir():
            errors.append(f"数据根目录不存在：{data_root}")
        if not config.is_file():
            errors.append(f"配置文件不存在：{config}")
        if self.end_date_edit.date() < self.start_date_edit.date():
            errors.append("结束日期不能早于开始日期")
        if not self._selected_modules():
            errors.append("至少选择一个处理或分析模块")
        return errors

    def _validate_inputs_dialog(self) -> None:
        errors = self._validate_inputs()
        if errors:
            QMessageBox.critical(self, "任务检查失败", "\n".join(f"- {item}" for item in errors))
        else:
            QMessageBox.information(self, "任务检查通过", "数据目录、配置、日期和模块检查通过。")

    def _build_context(self) -> JobContext:
        profile = self.current_profile
        selected = self._selected_modules()
        context = JobContext.create(
            project_root=self.project_root,
            bridge_id=profile.bridge_id,
            bridge_name=profile.bridge_name,
            data_root=Path(self.data_root_edit.text().strip()),
            start_date=self.start_date_edit.date().toString("yyyy-MM-dd"),
            end_date=self.end_date_edit.date().toString("yyyy-MM-dd"),
            config_path=Path(self.config_edit.text().strip()),
            selected_modules=selected,
            options=options_for_modules(selected),
            report_type=profile.report_gui_type,
            template_path=Path(self.template_edit.text().strip()) if self.template_edit.text().strip() else None,
            output_dir=Path(self.output_dir_edit.text().strip()),
            period_label=self.period_label_edit.text().strip(),
            monitoring_range=self.monitoring_range_edit.text().strip(),
            report_date=self.report_date_edit.text().strip(),
        )
        self.current_context = context
        return context

    def _save_context(self) -> None:
        errors = self._validate_inputs()
        if errors:
            QMessageBox.critical(self, "无法保存", "\n".join(f"- {item}" for item in errors))
            return
        try:
            context = self._build_context()
            self._reset_review_state()
            self.current_context_path = context.write()
            self._append_log(f"任务上下文已保存：{self.current_context_path}")
            self.analysis_status_label.setText(f"状态：draft；任务 {context.job_id}")
        except Exception as exc:  # noqa: BLE001
            self._show_exception("保存任务失败", exc)

    def _open_context_dialog(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "打开工作台任务上下文",
            str(self.project_root / "run_logs"),
            "Workbench context (job_context.json);;JSON files (*.json)",
        )
        if path:
            try:
                self.load_context(Path(path))
            except Exception as exc:  # noqa: BLE001
                self._show_exception("打开任务失败", exc)

    def load_context(self, path: Path) -> None:
        context = JobContext.read(path.expanduser().resolve())
        profile = profile_by_id(self.profiles, context.bridge_id)
        index = self.profile_combo.findData(profile.bridge_id)
        if index >= 0:
            self.profile_combo.setCurrentIndex(index)
        _set_line_edit_path(self.data_root_edit, context.data_root)
        _set_line_edit_path(self.config_edit, context.config_path)
        self._set_date(self.start_date_edit, context.start_date)
        self._set_date(self.end_date_edit, context.end_date)
        selected = set(context.selected_modules)
        for key, checkbox in self.module_checks.items():
            checkbox.setChecked(key in selected)
        _set_line_edit_path(self.template_edit, context.report.template_path)
        _set_line_edit_path(self.output_dir_edit, context.report.output_dir)
        self.period_label_edit.setText(context.period_label)
        self.monitoring_range_edit.setText(context.monitoring_range)
        self.report_date_edit.setText(context.report_date)
        self.current_context = context
        self.current_context_path = path.resolve()
        self._reset_review_state()
        if context.analysis.manifest_path and Path(context.analysis.manifest_path).is_file():
            self._load_manifest(Path(context.analysis.manifest_path))
            if context.report.plots_approved and self.approval_check.isEnabled():
                self.approval_check.blockSignals(True)
                self.approval_check.setChecked(True)
                self.approval_check.blockSignals(False)
        self._append_log(f"已恢复任务：{context.job_id}；上下文={path}")
        self._poll_status()

    def _start_analysis(self) -> None:
        errors = self._validate_inputs()
        if errors:
            QMessageBox.critical(self, "无法启动", "\n".join(f"- {item}" for item in errors))
            return
        try:
            context = self._build_context()
            self._reset_review_state()
            resolver = ExecutorResolver(self.project_root)
            executor = resolver.resolve()
            result = AnalysisLauncher(self.project_root).launch(context, executor)
            self.current_context_path = context.context_path
            self.start_btn.setEnabled(False)
            self.stop_btn.setEnabled(True)
            self.analysis_status_label.setText(f"状态：launched；PID {result.pid}")
            self._append_log(f"已启动分析：{executor.kind}，PID={result.pid}")
            self._append_log(f"请求文件：{context.analysis.request_path}")
        except Exception as exc:  # noqa: BLE001
            self._show_exception("启动分析失败", exc)

    def _request_stop(self) -> None:
        if self.current_context is None:
            return
        try:
            path = AnalysisLauncher.request_stop(self.current_context)
            self.stop_btn.setEnabled(False)
            self._append_log(f"已写入停止标志：{path}")
        except Exception as exc:  # noqa: BLE001
            self._show_exception("请求停止失败", exc)

    def _poll_status(self) -> None:
        context = self.current_context
        if context is None:
            return
        status = read_analysis_status(context)
        state = str(status.get("status") or "unknown").lower()
        changed = context.analysis.state != state
        context.analysis.state = state
        manifest_path = str(status.get("manifest_path") or "")
        if manifest_path and context.analysis.manifest_path != manifest_path:
            context.analysis.manifest_path = manifest_path
            changed = True
        self.analysis_status_label.setText(f"状态：{state}；任务 {context.job_id}")
        fraction = status.get("progress_fraction")
        try:
            progress_value = max(0, min(1000, round(float(fraction) * 1000)))
        except (TypeError, ValueError, OverflowError):
            progress_value = 1000 if state == "completed" else self.analysis_progress.value()
        self.analysis_progress.setValue(progress_value)
        current_label = str(status.get("current_module_label") or status.get("current_module_key") or "")
        completed = status.get("completed_modules")
        total = status.get("module_total")
        remaining = self._duration_text(status.get("estimated_remaining_sec"))
        progress_bits = [current_label or state]
        if completed is not None and total is not None:
            progress_bits.append(f"{completed}/{total}")
        if remaining:
            progress_bits.append(f"预计剩余 {remaining}")
        self.analysis_progress_label.setText("；".join(progress_bits))
        terminal = state in {"completed", "failed", "stopped", "launch_failed"}
        self.start_btn.setEnabled(terminal or state in {"draft", "unknown", "status_read_failed"})
        self.stop_btn.setEnabled(not terminal and state not in {"draft", "prepared", "unknown"})
        if changed:
            context.write()
            self._append_log(f"分析状态更新：{state}")
        if context.analysis.manifest_path:
            path = Path(context.analysis.manifest_path)
            if path.is_file() and (self.current_manifest is None or self.current_manifest.path != path.resolve()):
                self._load_manifest(path)
        self._update_report_gate()

    def _load_latest_manifest(self) -> None:
        data_root = Path(self.data_root_edit.text().strip()).expanduser()
        path = find_latest_manifest(data_root)
        if path is None:
            QMessageBox.warning(self, "未找到", f"未在 {data_root / 'run_logs'} 找到 analysis_manifest。")
            return
        answer = QMessageBox.question(
            self,
            "绑定最新Manifest",
            "这会把数据目录中最新的Manifest显式绑定到当前工作台任务。请确认它与当前桥梁和监测周期一致。\n\n"
            f"{path}",
        )
        if answer != QMessageBox.Yes:
            return
        if self.current_context is None:
            errors = self._validate_inputs()
            if errors:
                QMessageBox.critical(self, "无法建立任务", "\n".join(f"- {item}" for item in errors))
                return
            self.current_context = self._build_context()
        self.current_context.analysis.manifest_path = str(path.resolve())
        summary = load_manifest_summary(path)
        issues = manifest_context_issues(
            summary,
            bridge_id=self.current_context.bridge_id,
            data_root=Path(self.current_context.data_root),
            start_date=self.current_context.start_date,
            end_date=self.current_context.end_date,
        )
        if issues:
            QMessageBox.critical(self, "Manifest与任务不一致", "\n".join(f"- {item}" for item in issues))
            self.current_context.analysis.manifest_path = ""
            return
        self.current_context.analysis.state = "completed" if summary.status.lower() in SUCCESS_STATES else summary.status.lower()
        self.current_context_path = self.current_context.write()
        self._load_manifest(path)

    def _load_manifest(self, path: Path) -> None:
        try:
            summary = load_manifest_summary(path)
        except Exception as exc:  # noqa: BLE001
            self._show_exception("读取Manifest失败", exc)
            return
        if self.current_context is not None:
            issues = manifest_context_issues(
                summary,
                bridge_id=self.current_context.bridge_id,
                data_root=Path(self.current_context.data_root),
                start_date=self.current_context.start_date,
                end_date=self.current_context.end_date,
            )
            if issues:
                self._reset_review_state()
                self._append_log("Manifest上下文校验失败：" + "; ".join(issues))
                return
            actual_hash = file_sha256(path)
            pinned_hash = self.current_context.analysis.manifest_sha256
            if pinned_hash and pinned_hash != actual_hash:
                self._reset_review_state()
                self._append_log(
                    f"Manifest哈希变化，拒绝沿用审核：expected={pinned_hash}, actual={actual_hash}"
                )
                return
            self.current_context.analysis.manifest_path = str(path.resolve())
            self.current_context.analysis.manifest_sha256 = actual_hash
            self.current_context.write()
        self.current_manifest = summary
        selected = self.current_context.selected_modules if self.current_context is not None else []
        self.current_manifest_missing_selected = summary.missing_selected_modules(selected)
        self.manifest_label.setText(f"Manifest：{summary.path}")
        failed = len(summary.failed_modules)
        self.manifest_summary_label.setText(
            f"运行状态：{summary.status}；模块记录：{len(summary.modules)}；失败/异常：{failed}；"
            f"所选模块未记录：{len(self.current_manifest_missing_selected)}；产物：{summary.artifact_count}"
        )
        self.module_table.setRowCount(len(summary.modules))
        for row, item in enumerate(summary.modules):
            values = (item.label, item.status, item.elapsed_sec, item.stats_path, item.message, item.key)
            for column, value in enumerate(values):
                self.module_table.setItem(row, column, QTableWidgetItem(value))
        self.module_table.resizeColumnsToContents()
        self.module_table.setColumnWidth(3, 300)
        self.approval_check.setEnabled(
            summary.status.lower() in SUCCESS_STATES
            and failed == 0
            and not self.current_manifest_missing_selected
            and bool(selected)
        )
        if failed or self.current_manifest_missing_selected:
            self.approval_check.setChecked(False)
        self._update_report_gate()

    def _reset_review_state(self) -> None:
        self.current_manifest = None
        self.current_manifest_missing_selected = ()
        self.approval_check.blockSignals(True)
        self.approval_check.setChecked(False)
        self.approval_check.setEnabled(False)
        self.approval_check.blockSignals(False)
        self.module_table.setRowCount(0)
        self.manifest_label.setText("Manifest：未加载")
        self.manifest_summary_label.setText("等待分析完成。")
        self._update_report_gate()

    def _on_approval_changed(self) -> None:
        if self.current_context is None:
            self.approval_check.setChecked(False)
            return
        self.current_context.report.plots_approved = self.approval_check.isChecked()
        self.current_context.report.state = "ready" if self.current_context.report_ready else "blocked"
        self.current_context.write()
        self._update_report_gate()

    def _update_report_gate(self) -> None:
        ready = self._report_gate_ready()
        self.open_report_btn.setEnabled(ready)
        if ready:
            self.report_gate_label.setText("报告门禁已通过：当前manifest成功，且图件已审核。")
            self.report_gate_label.setStyleSheet("color: #167c35; font-weight: 600;")
        else:
            self.report_gate_label.setText("报告生成已锁定：需要成功的分析manifest和图件审核。")
            self.report_gate_label.setStyleSheet("color: #a33; font-weight: 600;")

    def _report_gate_ready(self) -> bool:
        return bool(
            self.current_context
            and self.current_context.report_ready
            and self.current_manifest is not None
            and self.current_manifest.status.lower() in SUCCESS_STATES
            and not self.current_manifest.failed_modules
            and not self.current_manifest_missing_selected
        )

    def _open_report_generator(self) -> None:
        context = self.current_context
        if context is None or not self._report_gate_ready():
            QMessageBox.warning(self, "报告门禁未通过", "请先完成分析、加载成功manifest并审核图件。")
            return
        try:
            config_path = Path(context.config_path)
            if not config_path.is_file():
                raise FileNotFoundError(f"任务配置不存在：{config_path}")
            if file_sha256(config_path) != context.config_sha256:
                raise RuntimeError("任务配置在分析后发生变化，不能继续生成报告")
            context.report.template_path = self.template_edit.text().strip()
            template_path = Path(context.report.template_path)
            if not template_path.is_file():
                raise FileNotFoundError(f"报告模板不存在：{template_path}")
            context.report.template_sha256 = file_sha256(template_path)
            context.report.output_dir = self.output_dir_edit.text().strip()
            context.period_label = self.period_label_edit.text().strip()
            context.monitoring_range = self.monitoring_range_edit.text().strip()
            context.report_date = self.report_date_edit.text().strip()
            manifest_path = Path(context.analysis.manifest_path)
            if not manifest_path.is_file():
                raise FileNotFoundError(f"分析Manifest不存在：{manifest_path}")
            actual_manifest_hash = file_sha256(manifest_path)
            if context.analysis.manifest_sha256 != actual_manifest_hash:
                raise RuntimeError("分析Manifest在图件审核后发生变化，必须重新审核")
            self.current_context_path = context.write()
            process = launch_report_gui(context, self.current_context_path)
            self._append_log(f"已打开报告生成器，PID={process.pid}；上下文={self.current_context_path}")
        except Exception as exc:  # noqa: BLE001
            self._show_exception("打开报告生成器失败", exc)

    def _open_output_dir(self) -> None:
        path = Path(self.output_dir_edit.text().strip()).expanduser()
        path.mkdir(parents=True, exist_ok=True)
        if os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(path.resolve())))

    def _browse_data_root(self) -> None:
        self._browse_directory_into(self.data_root_edit, "选择数据根目录")

    def _browse_output_dir(self) -> None:
        self._browse_directory_into(self.output_dir_edit, "选择报告输出目录")

    def _browse_directory_into(self, edit: QLineEdit, title: str) -> None:
        path = QFileDialog.getExistingDirectory(self, title, edit.text() or str(self.project_root))
        if path:
            _set_line_edit_path(edit, path)

    def _browse_config(self) -> None:
        self._browse_file_into(self.config_edit, "选择配置文件", "JSON files (*.json)")
        path = Path(self.config_edit.text().strip())
        if path.is_file():
            try:
                self.alarm_editor.load_path(path)
            except Exception as exc:  # noqa: BLE001
                self._show_exception("加载预警值配置失败", exc)

    def _on_alarm_config_saved(self, path: str, sha256: str, backup: str) -> None:
        saved_path = Path(path).resolve()
        selected_path = Path(self.config_edit.text().strip()).expanduser().resolve()
        if saved_path == selected_path:
            self.current_context = None
            self.current_context_path = None
            self._reset_review_state()
            self.analysis_status_label.setText("状态：配置已修改，请重新保存任务上下文")
            self._append_log(
                f"预警值配置已保存；SHA256={sha256[:16]}…；备份={backup}。旧任务上下文已失效。"
            )

    def _browse_template(self) -> None:
        self._browse_file_into(self.template_edit, "选择报告模板", "Word files (*.docx)")

    def _browse_file_into(self, edit: QLineEdit, title: str, pattern: str) -> None:
        path, _ = QFileDialog.getOpenFileName(self, title, edit.text() or str(self.project_root), pattern)
        if path:
            _set_line_edit_path(edit, path)

    def _append_log(self, message: str) -> None:
        if hasattr(self, "analysis_log"):
            self.analysis_log.appendPlainText(f"[{datetime.now():%H:%M:%S}] {message}")

    @staticmethod
    def _duration_text(value: object) -> str:
        try:
            seconds = int(round(float(value)))
        except (TypeError, ValueError, OverflowError):
            return ""
        if seconds < 0 or seconds > 365 * 24 * 3600:
            return ""
        hours, remainder = divmod(seconds, 3600)
        minutes, seconds = divmod(remainder, 60)
        if hours:
            return f"{hours}小时{minutes}分"
        if minutes:
            return f"{minutes}分{seconds}秒"
        return f"{seconds}秒"

    def _show_exception(self, title: str, exc: Exception) -> None:
        self._append_log(f"{title}：{exc}\n{traceback.format_exc()}")
        QMessageBox.critical(self, title, str(exc))
