from __future__ import annotations

import json
import math
import os
import re
import traceback
import copy
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QDate, QRect, QSettings, QSize, QTimer, Qt, QUrl
from PySide6.QtGui import QCursor, QDesktopServices, QFont, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QDateEdit,
    QFileDialog,
    QFrame,
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
    QScrollArea,
    QStackedWidget,
    QTabWidget,
    QVBoxLayout,
    QWidget,
)

from .analysis import (
    AnalysisLauncher,
    ExecutorResolver,
    bind_analysis_manifest,
    persist_analysis_state,
    read_analysis_status,
)
from .branding import application_icon, organization_logo_path
from .advanced_config_tab import (
    GroupPlotConfigEditorWidget,
    OffsetCorrectionEditorWidget,
)
from .auto_threshold_tab import AutoThresholdProposalWidget
from .config_tab import (
    AlarmBoundsEditorWidget,
    CleaningThresholdEditorWidget,
    PostFilterThresholdEditorWidget,
)
from .config_layers import config_dependency_sha256, load_layered_config
from .copyable_table import CopyableTableWidget
from .cache_cleanup_settings import (
    CACHE_SOURCE_CLEANUP_CONFIRMATION,
    CACHE_SOURCE_CLEANUP_KEY,
    CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS,
    CacheSourceCleanupSettings,
    cleanup_validation_errors,
)
from .cache_cleanup_preflight import cleanup_root_preflight_errors
from .manifest import ManifestSummary, find_latest_manifest, load_manifest_summary, manifest_context_issues
from .module_icons import module_icon
from .models import JobContext, file_sha256
from .modules import MODULE_SPECS, options_for_modules
from .module_progress import normalize_module_progress
from .module_progress_widget import ModuleProgressPanel, module_stage_label
from .operator_text import operator_friendly_text, operator_stage_label, operator_state_label
from .profiles import PathProfileResolver, WorkbenchProfile, load_profiles, profile_by_id
from .plot_config_tab import PlotCommonEditorWidget, SpectrumConfigEditorWidget
from .preprocess_config_tab import UnzipSettingsEditorWidget
from .profile_audit import ProfileAuditError, load_installed_profile_matrix
from .provenance import PlotProvenanceSummary, inspect_manifest_plot_provenance
from .report_task import (
    launch_report_job,
    persist_report_state,
    read_report_status,
    terminate_report_job,
)
from .report_disclosures import (
    DISCLOSABLE_MODULE_STATUSES,
    DISCLOSURE_POLICY_VERSION,
    DisclosureItem,
    analysis_disclosure_items,
    confirmation_record,
    disclosure_supported_for_report,
    invalidate_disclosure_approval,
    validate_confirmations,
)
from .report_gate import inspect_report_gate, require_report_gate
from .result_location import analysis_result_location
from .task_history_tab import TaskHistoryWidget
from .threshold_curve_task_dialog import ThresholdCurveTaskDialog
from .update_ui import UpdateController
from .ui_styles import apply_danger_action_style
from .version import APP_DISPLAY_NAME, app_version, project_root as default_project_root
from .window_geometry import fit_window_geometry


SUCCESS_STATES = {"ok", "success", "completed"}


def _set_line_edit_path(edit: QLineEdit, value: Path | str) -> None:
    edit.setText(str(value))
    edit.setCursorPosition(0)


def _provenance_detail_text(item) -> str:
    details: list[str] = []
    reason = str(getattr(item, "reason_zh", "") or "").strip()
    suggestion = str(getattr(item, "suggestion_zh", "") or "").strip()
    if reason:
        details.append(reason)
    if suggestion:
        details.append(f"修复建议：{suggestion}")
    if not details:
        fallback = str(getattr(item, "message", "") or "").strip()
        if fallback:
            details.append(fallback)
    return "\n".join(details)


def _whole_seconds_text(value: object) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    try:
        seconds = max(0.0, float(text))
    except (TypeError, ValueError, OverflowError):
        return text
    if not math.isfinite(seconds):
        return text
    return f"{round(seconds)} 秒"


class WorkbenchWindow(QMainWindow):
    def __init__(
        self,
        project_root: Path | None = None,
        window_settings: QSettings | None = None,
    ) -> None:
        super().__init__()
        self._window_settings = (
            window_settings
            if window_settings is not None
            else QSettings("Guanbing", "BridgeMonitoringWorkbench")
        )
        self._persist_window_geometry = bool(
            window_settings is not None
            or os.environ.get("QT_QPA_PLATFORM", "").casefold() != "offscreen"
        )
        self.project_root = (project_root or default_project_root()).resolve()
        self.profiles = load_profiles(self.project_root)
        self.path_resolver = PathProfileResolver(self.project_root)
        self.active_path_profile = self.path_resolver.active()
        self.custom_data_roots: dict[str, str] = {}
        self.current_context: JobContext | None = None
        self._analysis_context_superseded = False
        self._report_context_superseded = False
        self.current_context_path: Path | None = None
        self.current_manifest: ManifestSummary | None = None
        self.current_provenance: PlotProvenanceSummary | None = None
        self.current_disclosure_items: tuple[DisclosureItem, ...] = ()
        self.current_manifest_missing_selected: tuple[str, ...] = ()
        self.known_context_paths: set[Path] = set()
        self.module_checks: dict[str, QCheckBox] = {}
        self._report_auto_values: dict[str, str] = {}
        self._suspend_report_autofill = False
        self._report_gate_audit_cache = None
        self._report_gate_audit_signature: tuple[object, ...] | None = None
        self.setFont(QFont("Microsoft YaHei UI", 10))
        self.setWindowTitle(f"{APP_DISPLAY_NAME} {app_version(self.project_root)}")
        self.setWindowIcon(application_icon(self.project_root))
        self._build_ui()
        self._restore_window_geometry()
        self._apply_profile(self.profiles[0])
        self.update_controller = UpdateController(
            self,
            self.update_btn,
            self.project_root,
            self.update_backup_btn,
            self.auto_update_check,
        )
        self.update_controller.schedule_auto_check()
        self.poll_timer = QTimer(self)
        self.poll_timer.setInterval(2000)
        self.poll_timer.timeout.connect(self._poll_status)
        self.poll_timer.start()

    def _available_screen_geometries(self) -> tuple[QRect, ...]:
        return tuple(QRect(screen.availableGeometry()) for screen in QApplication.screens())

    def _restore_window_geometry(self) -> None:
        screens = self._available_screen_geometries()
        restored_rect: QRect | None = None
        if self._persist_window_geometry:
            raw_geometry = self._window_settings.value("window/geometry")
            if raw_geometry is not None:
                try:
                    if self.restoreGeometry(raw_geometry):
                        restored_rect = QRect(self.normalGeometry())
                except (TypeError, ValueError):
                    restored_rect = None
            if restored_rect is None:
                raw_rect = self._window_settings.value("window/normal_geometry")
                if isinstance(raw_rect, QRect):
                    restored_rect = QRect(raw_rect)
        target = fit_window_geometry(
            screens,
            saved=restored_rect,
            anchor=QCursor.pos(),
        )
        self.setGeometry(target)

    def closeEvent(self, event) -> None:  # noqa: N802 - Qt API
        if self._persist_window_geometry:
            self._window_settings.setValue("window/geometry", self.saveGeometry())
            self._window_settings.setValue(
                "window/normal_geometry", self.normalGeometry()
            )
            self._window_settings.sync()
        super().closeEvent(event)

    def _build_ui(self) -> None:
        tabs = QTabWidget(self)
        tabs.addTab(
            self._scrollable_page(self._build_analysis_tab(), "analysisScrollArea"),
            "项目与数据分析",
        )
        config_tabs = QTabWidget()
        self.alarm_editor = AlarmBoundsEditorWidget()
        self.alarm_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "预警值", path, sha256, backup
            )
        )
        self.cleaning_editor = CleaningThresholdEditorWidget(
            preview_context_provider=self._threshold_task_context,
            project_root=self.project_root,
        )
        self.cleaning_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "数据清洗", path, sha256, backup
            )
        )
        self.post_filter_editor = PostFilterThresholdEditorWidget(
            project_root=self.project_root
        )
        self.post_filter_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "滤波后二次清洗", path, sha256, backup
            )
        )
        self.auto_threshold_editor = AutoThresholdProposalWidget(
            self.project_root, self._threshold_task_context
        )
        self.cleaning_editor.threshold_curve_requested.connect(
            self._generate_current_threshold_curve
        )
        self.auto_threshold_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "自动清洗建议", path, sha256, backup
            )
        )
        self.offset_editor = OffsetCorrectionEditorWidget()
        self.offset_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "零点修正", path, sha256, backup
            )
        )
        self.group_plot_editor = GroupPlotConfigEditorWidget()
        self.group_plot_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "组图", path, sha256, backup
            )
        )
        self.plot_common_editor = PlotCommonEditorWidget()
        self.plot_common_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "绘图公共参数", path, sha256, backup
            )
        )
        self.spectrum_editor = SpectrumConfigEditorWidget()
        self.spectrum_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "频谱覆盖与找峰", path, sha256, backup
            )
        )
        self.unzip_settings_editor = UnzipSettingsEditorWidget()
        self.unzip_settings_editor.config_saved.connect(
            lambda path, sha256, backup: self._on_config_saved(
                "ZIP 解压并发", path, sha256, backup
            )
        )
        config_tabs.addTab(
            self._scrollable_page(self.alarm_editor, "alarmConfigScrollArea"),
            "预警值",
        )
        config_tabs.addTab(
            self._scrollable_page(self.cleaning_editor, "cleaningConfigScrollArea"),
            "数据清洗阈值",
        )
        config_tabs.addTab(
            self._scrollable_page(
                self.post_filter_editor, "postFilterConfigScrollArea"
            ),
            "滤波后二次清洗",
        )
        self.auto_threshold_scroll = self._scrollable_page(
            self.auto_threshold_editor, "autoThresholdConfigScrollArea"
        )
        config_tabs.addTab(
            self.auto_threshold_scroll,
            "自动清洗建议（Beta）",
        )
        config_tabs.addTab(
            self._scrollable_page(self.offset_editor, "offsetConfigScrollArea"),
            "零点修正",
        )
        config_tabs.addTab(
            self._scrollable_page(self.group_plot_editor, "groupPlotConfigScrollArea"),
            "组图配置",
        )
        config_tabs.addTab(
            self._scrollable_page(
                self.plot_common_editor, "plotCommonConfigScrollArea"
            ),
            "绘图公共参数",
        )
        config_tabs.addTab(
            self._scrollable_page(self.spectrum_editor, "spectrumConfigScrollArea"),
            "频谱覆盖与找峰",
        )
        config_tabs.addTab(
            self._scrollable_page(self.unzip_settings_editor, "unzipConfigScrollArea"),
            "解压并发",
        )
        self.config_tabs = config_tabs
        tabs.addTab(config_tabs, "配置与预警值")
        tabs.addTab(
            self._scrollable_page(self._build_review_tab(), "reviewScrollArea"),
            "结果与图件审核",
        )
        tabs.addTab(
            self._scrollable_page(self._build_report_tab(), "reportScrollArea"),
            "报告生成",
        )
        self.setCentralWidget(tabs)
        self.tabs = tabs

    @staticmethod
    def _scrollable_page(page: QWidget, object_name: str) -> QScrollArea:
        """Keep dense task pages usable when the window height is reduced."""

        area = QScrollArea()
        area.setObjectName(object_name)
        area.setFrameShape(QFrame.NoFrame)
        area.setWidgetResizable(True)
        area.setHorizontalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        area.setVerticalScrollBarPolicy(Qt.ScrollBarAsNeeded)
        area.setWidget(page)
        return area

    def _build_analysis_tab(self) -> QWidget:
        page = QWidget()
        outer = QVBoxLayout(page)
        title = QLabel(APP_DISPLAY_NAME)
        title.setStyleSheet("font-size: 22px; font-weight: 700; color: #005eac;")
        title_row = QHBoxLayout()
        self.brand_icon_label = QLabel()
        brand_icon = application_icon(self.project_root)
        self.brand_icon_label.setPixmap(brand_icon.pixmap(38, 38))
        self.brand_icon_label.setToolTip(APP_DISPLAY_NAME)
        title_row.addWidget(self.brand_icon_label)
        title_row.addWidget(title)
        title_row.addStretch(1)
        self.organization_logo_label = QLabel()
        logo_path = organization_logo_path(self.project_root)
        if logo_path is not None:
            logo = QPixmap(str(logo_path))
            self.organization_logo_label.setPixmap(
                logo.scaled(160, 42, Qt.KeepAspectRatio, Qt.SmoothTransformation)
            )
            self.organization_logo_label.setToolTip("单位标识")
        else:
            self.organization_logo_label.hide()
            self.organization_logo_label.setToolTip(
                "已预留单位标识位置；加入 workbench/assets/organization_logo.svg 或 .png 后自动显示"
            )
        title_row.addWidget(self.organization_logo_label)
        self.auto_update_check = QCheckBox("自动检查更新")
        self.auto_update_check.setToolTip("默认开启；关闭后仍可随时手动检查更新")
        title_row.addWidget(self.auto_update_check)
        self.update_btn = QPushButton("立即检查更新")
        self.update_btn.setToolTip("从 GitHub Release 检查工作平台正式更新")
        title_row.addWidget(self.update_btn)
        self.update_backup_btn = QPushButton("更新备份")
        self.update_backup_btn.setToolTip("查看更新备份；经确认后保留最新两个并清理更旧备份")
        title_row.addWidget(self.update_backup_btn)
        self.profile_matrix_btn = QPushButton("所有桥梁自检")
        self.profile_matrix_btn.setToolTip("查看冻结版所有桥梁的配置、模板、模块和报告能力矩阵")
        self.profile_matrix_btn.clicked.connect(self._show_profile_matrix)
        title_row.addWidget(self.profile_matrix_btn)
        outer.addLayout(title_row)

        form_group = QGroupBox("任务设置")
        form = QFormLayout(form_group)
        self.profile_combo = QComboBox()
        for profile in self.profiles:
            self.profile_combo.addItem(profile.bridge_name, profile.bridge_id)
        self.profile_combo.currentIndexChanged.connect(self._on_profile_changed)
        form.addRow("桥梁项目", self.profile_combo)

        self.path_profile_combo = QComboBox()
        self.path_profile_combo.addItem("自动识别（推荐）", PathProfileResolver.AUTO_ID)
        selectable_profiles = {
            path_profile.profile_id: path_profile for path_profile in self.path_resolver.profiles
        }
        for path_profile in selectable_profiles.values():
            self.path_profile_combo.addItem(path_profile.display_name, path_profile.profile_id)
        self.path_profile_combo.addItem("自定义路径", PathProfileResolver.CUSTOM_ID)
        self.path_profile_combo.setToolTip(
            "默认按 GUANBING_PATH_PROFILE、电脑名、已有目录的顺序自动选择；也可手动指定配置组或自定义路径"
        )
        self.path_profile_combo.currentIndexChanged.connect(self._on_path_profile_changed)
        form.addRow("存储位置方案", self.path_profile_combo)
        self.path_profile_status_label = QLabel()
        self.path_profile_status_label.setWordWrap(True)
        self.path_profile_status_label.setStyleSheet("color: #174a75;")
        form.addRow("自动匹配结果", self.path_profile_status_label)

        self.data_root_edit = QLineEdit()
        self.data_root_edit.textEdited.connect(self._on_data_root_edited)
        self.data_root_edit.textChanged.connect(self._refresh_report_defaults)
        self.data_root_edit.textChanged.connect(self._on_task_inputs_changed)
        self.data_root_edit.textChanged.connect(self._refresh_analysis_result_location)
        form.addRow("数据根目录", self._path_row(self.data_root_edit, self._browse_data_root, directory=True))
        self.config_edit = QLineEdit()
        self.config_edit.textChanged.connect(self._refresh_data_source_summary)
        self.config_edit.textChanged.connect(self._on_task_inputs_changed)
        self.config_edit.setToolTip("桥梁业务配置保持单一；机器配置组只切换数据路径，不复制业务参数")
        form.addRow("配置文件", self._path_row(self.config_edit, self._browse_config))

        self.data_source_mode_label = QLabel()
        self.data_source_mode_label.setWordWrap(True)
        self.data_source_mode_label.setStyleSheet("color: #174a75;")
        self.data_source_mode_label.setToolTip(
            "保持推荐的自动识别即可：有 CSV 时读取 CSV；没有 CSV 时读取有效的 MAT 缓存。"
        )
        form.addRow("数据读取方式", self.data_source_mode_label)

        date_row = QWidget()
        date_layout = QHBoxLayout(date_row)
        date_layout.setContentsMargins(0, 0, 0, 0)
        self.start_date_edit = QDateEdit(calendarPopup=True)
        self.start_date_edit.setDisplayFormat("yyyy-MM-dd")
        self.end_date_edit = QDateEdit(calendarPopup=True)
        self.end_date_edit.setDisplayFormat("yyyy-MM-dd")
        self.start_date_edit.dateChanged.connect(self._refresh_report_defaults)
        self.end_date_edit.dateChanged.connect(self._refresh_report_defaults)
        self.start_date_edit.dateChanged.connect(self._on_task_inputs_changed)
        self.end_date_edit.dateChanged.connect(self._on_task_inputs_changed)
        date_layout.addWidget(QLabel("开始"))
        date_layout.addWidget(self.start_date_edit)
        date_layout.addSpacing(16)
        date_layout.addWidget(QLabel("结束"))
        date_layout.addWidget(self.end_date_edit)
        date_layout.addStretch(1)
        form.addRow("监测日期", date_row)
        outer.addWidget(form_group)

        result_group = QGroupBox("本次计算结果在哪里")
        result_layout = QVBoxLayout(result_group)
        result_path_row = QHBoxLayout()
        self.analysis_result_path_label = QLabel("尚未选择结果目录")
        self.analysis_result_path_label.setObjectName("analysisResultPathLabel")
        self.analysis_result_path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        self.analysis_result_path_label.setWordWrap(True)
        self.analysis_result_path_label.setStyleSheet("font-weight: 700; color: #174a75;")
        result_path_row.addWidget(self.analysis_result_path_label, 1)
        self.copy_analysis_result_path_button = QPushButton("复制路径")
        self.copy_analysis_result_path_button.setObjectName(
            "copyAnalysisResultPathButton"
        )
        self.copy_analysis_result_path_button.setToolTip(
            "把统计表、图件和运行记录所在的结果根目录复制到剪贴板"
        )
        self.copy_analysis_result_path_button.clicked.connect(
            self._copy_analysis_result_path
        )
        result_path_row.addWidget(self.copy_analysis_result_path_button)
        self.open_analysis_result_button = QPushButton("打开结果目录")
        self.open_analysis_result_button.setObjectName("openAnalysisResultDirectoryButton")
        self.open_analysis_result_button.clicked.connect(self._open_analysis_result_dir)
        result_path_row.addWidget(self.open_analysis_result_button)
        self.open_analysis_stats_button = QPushButton("打开统计表")
        self.open_analysis_stats_button.clicked.connect(
            lambda: self._open_analysis_result_child("stats")
        )
        result_path_row.addWidget(self.open_analysis_stats_button)
        self.open_analysis_logs_button = QPushButton("打开运行记录")
        self.open_analysis_logs_button.clicked.connect(
            lambda: self._open_analysis_result_child("run_logs")
        )
        result_path_row.addWidget(self.open_analysis_logs_button)
        result_layout.addLayout(result_path_row)
        self.analysis_result_help_label = QLabel(
            "选择数据目录后，这里会显示统计表、分析图件和运行记录的实际保存位置。"
        )
        self.analysis_result_help_label.setObjectName("analysisResultLocationHelp")
        self.analysis_result_help_label.setWordWrap(True)
        self.analysis_result_help_label.setStyleSheet("color: #5f6368;")
        result_layout.addWidget(self.analysis_result_help_label)
        outer.addWidget(result_group)

        module_group = QGroupBox("处理与分析模块")
        module_layout = QGridLayout(module_group)
        for index, spec in enumerate(MODULE_SPECS):
            checkbox = QCheckBox(spec.label)
            checkbox.setProperty("module_key", spec.key)
            tooltip = spec.description or spec.label
            checkbox.setToolTip(tooltip)
            checkbox.setIcon(module_icon(self.project_root, spec.icon_asset))
            checkbox.setIconSize(QSize(22, 22))
            checkbox.stateChanged.connect(self._on_task_inputs_changed)
            self.module_checks[spec.key] = checkbox
            module_layout.addWidget(checkbox, index // 4, index % 4)
        outer.addWidget(module_group)

        cleanup_group = QGroupBox("缓存完成后的磁盘空间处理（高风险）")
        cleanup_layout = QVBoxLayout(cleanup_group)
        self.cache_cleanup_check = QCheckBox(
            "缓存逐日验证通过后，删除本次缓存对应的已解压 CSV"
        )
        self.cache_cleanup_check.setToolTip(
            "默认关闭。只删除配置实际使用、缓存可独立读取且能由原 ZIP 恢复的 CSV；"
            "原 ZIP、WIM、Excel、未配置 CSV 和缓存文件不会删除。"
        )
        self.cache_cleanup_check.toggled.connect(self._on_cache_cleanup_toggled)
        cleanup_layout.addWidget(self.cache_cleanup_check)
        cleanup_explanation = QLabel(
            "请把它作为独立预处理任务运行：同时选择解压与缓存时，系统逐日执行"
            "解压→缓存→完整性与恢复来源核验→删除；只选择缓存时，仅处理已有且具备"
            "有效解压清单和原 ZIP 的目录。校验失败不会进入删除；删除阶段若意外中断，"
            "会保留恢复回执供确认后续跑。完成后再新建分析任务，普通用户保持“自动识别”"
            "即可，正式隔离验收可选“仅读 MAT”。此设置不会写入桥梁公共配置。"
        )
        cleanup_explanation.setWordWrap(True)
        cleanup_explanation.setStyleSheet("color: #8a3b12;")
        cleanup_layout.addWidget(cleanup_explanation)
        confirmation_row = QHBoxLayout()
        confirmation_row.addWidget(QLabel("确认口令"))
        self.cache_cleanup_confirmation_edit = QLineEdit()
        self.cache_cleanup_confirmation_edit.setPlaceholderText(
            CACHE_SOURCE_CLEANUP_CONFIRMATION
        )
        self.cache_cleanup_confirmation_edit.setToolTip(
            "必须完整输入所示英文口令；仅勾选复选框不会执行删除。"
        )
        self.cache_cleanup_confirmation_edit.textChanged.connect(
            self._on_task_inputs_changed
        )
        confirmation_row.addWidget(self.cache_cleanup_confirmation_edit, 1)
        cleanup_layout.addLayout(confirmation_row)
        outer.addWidget(cleanup_group)
        self.module_checks["cache_prebuild"].toggled.connect(
            self._sync_cache_cleanup_controls
        )
        self._sync_cache_cleanup_controls()

        action_row = QHBoxLayout()
        self.validate_btn = QPushButton("检查配置与路径（不运行）")
        self.validate_btn.setToolTip(
            "只检查数据目录、配置文件、日期和所选模块是否可用，不启动 MATLAB，也不修改数据"
        )
        self.validate_btn.clicked.connect(self._validate_inputs_dialog)
        action_row.addWidget(self.validate_btn)
        self.open_context_btn = QPushButton("打开已保存任务方案")
        self.open_context_btn.setToolTip(
            "读取以前保存的桥梁、目录、日期和模块选择；打开后不会自动重新运行分析"
        )
        self.open_context_btn.clicked.connect(self._open_context_dialog)
        action_row.addWidget(self.open_context_btn)
        self.history_btn = QPushButton("查看任务历史")
        self.history_btn.setToolTip(
            "查看当前数据目录里已经保存或运行过的任务，便于恢复进度；仅查看，不会自动重算"
        )
        self.history_btn.clicked.connect(lambda: self.show_task_history())
        action_row.addWidget(self.history_btn)
        self.save_btn = QPushButton("保存任务方案（便于恢复）")
        self.save_btn.setToolTip(
            "保存当前桥梁、数据路径、配置、日期和模块选择，供中断后恢复或复核；不会启动分析"
        )
        self.save_btn.clicked.connect(self._save_context)
        action_row.addWidget(self.save_btn)
        self.start_btn = QPushButton("启动本机分析")
        self.start_btn.setStyleSheet("font-weight: 700; background: #005eac; color: white; padding: 6px 16px;")
        self.start_btn.clicked.connect(self._start_analysis)
        action_row.addWidget(self.start_btn)
        self.stop_btn = QPushButton("请求停止")
        apply_danger_action_style(self.stop_btn)
        self.stop_btn.setEnabled(False)
        self.stop_btn.clicked.connect(self._request_stop)
        action_row.addWidget(self.stop_btn)
        action_row.addStretch(1)
        outer.addLayout(action_row)
        task_help = QLabel(
            "建议顺序：先“检查配置与路径（不运行）”→ 再“保存任务方案（便于恢复）”→ 最后启动分析。"
            "“打开已保存任务方案”和“查看任务历史”都只恢复或查看记录，不会自行重算数据。"
        )
        task_help.setWordWrap(True)
        task_help.setStyleSheet("color: #5f6368; padding: 2px 0;")
        outer.addWidget(task_help)

        self.analysis_status_label = QLabel("状态：尚未建立任务")
        self.analysis_status_label.setStyleSheet("font-weight: 600;")
        outer.addWidget(self.analysis_status_label)
        progress_row = QHBoxLayout()
        self.analysis_progress = QProgressBar()
        self.analysis_progress.setRange(0, 1000)
        self.analysis_progress.setValue(0)
        self.analysis_progress.setFormat("模块进度 %p%（非耗时比例）")
        progress_row.addWidget(self.analysis_progress, 1)
        self.analysis_progress_label = QLabel("等待任务")
        self.analysis_progress_label.setMinimumWidth(220)
        progress_row.addWidget(self.analysis_progress_label)
        outer.addLayout(progress_row)
        self.module_progress_panel = ModuleProgressPanel(self)
        outer.addWidget(self.module_progress_panel)
        self.analysis_log = QPlainTextEdit()
        self.analysis_log.setReadOnly(True)
        self.analysis_log.setPlaceholderText("工作平台操作、启动信息和状态变化会显示在这里。")
        outer.addWidget(self.analysis_log, 1)
        self.analysis_form_page = page
        self.task_history_page = TaskHistoryWidget(tuple(profile.bridge_id for profile in self.profiles))
        self.task_history_page.back_requested.connect(lambda: self.analysis_stack.setCurrentIndex(0))
        self.task_history_page.restore_requested.connect(self._restore_history_context)
        self.analysis_stack = QStackedWidget()
        self.analysis_stack.addWidget(page)
        self.analysis_stack.addWidget(self.task_history_page)
        return self.analysis_stack

    def _build_review_tab(self) -> QWidget:
        page = QWidget()
        outer = QVBoxLayout(page)
        header = QHBoxLayout()
        self.manifest_label = QLabel("分析结果清单：未加载")
        self.manifest_label.setWordWrap(True)
        self.manifest_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        outer.addWidget(self.manifest_label)
        header.addStretch(1)
        refresh = QPushButton("刷新当前任务")
        refresh.clicked.connect(self._poll_status)
        header.addWidget(refresh)
        load_latest = QPushButton("选择数据目录中的最新分析结果")
        load_latest.clicked.connect(self._load_latest_manifest)
        header.addWidget(load_latest)
        self.review_open_result_button = QPushButton("打开结果目录")
        self.review_open_result_button.clicked.connect(self._open_analysis_result_dir)
        header.addWidget(self.review_open_result_button)
        outer.addLayout(header)

        self.manifest_summary_label = QLabel("等待分析完成。")
        outer.addWidget(self.manifest_summary_label)
        module_filter_row = QHBoxLayout()
        self.module_failed_filter = QCheckBox("只看未通过项目")
        self.module_gap_filter = QCheckBox("只看有缺口项目")
        module_filter_row.addWidget(self.module_failed_filter)
        module_filter_row.addWidget(self.module_gap_filter)
        module_filter_row.addStretch(1)
        outer.addLayout(module_filter_row)
        self.module_table = CopyableTableWidget(0, 5)
        self.module_table.setHorizontalHeaderLabels(["分析项目", "状态", "耗时", "统计文件", "消息"])
        self.module_failed_filter.stateChanged.connect(self._apply_module_table_filters)
        self.module_gap_filter.stateChanged.connect(self._apply_module_table_filters)
        self.module_table.horizontalHeader().setStretchLastSection(False)
        header_view = self.module_table.horizontalHeader()
        header_view.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        header_view.setSectionResizeMode(1, QHeaderView.ResizeToContents)
        header_view.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        header_view.setSectionResizeMode(3, QHeaderView.Interactive)
        header_view.setSectionResizeMode(4, QHeaderView.Stretch)
        self.module_table.setColumnWidth(3, 300)
        outer.addWidget(self.module_table, 1)

        provenance_group = QGroupBox("正式图件数据完整性检查")
        provenance_layout = QVBoxLayout(provenance_group)
        self.provenance_summary_label = QLabel("等待加载分析结果清单。")
        provenance_layout.addWidget(self.provenance_summary_label)
        provenance_filter_row = QHBoxLayout()
        self.provenance_failed_filter = QCheckBox("只看未通过")
        self.provenance_gap_filter = QCheckBox("只看有数据缺口")
        provenance_filter_row.addWidget(self.provenance_failed_filter)
        provenance_filter_row.addWidget(self.provenance_gap_filter)
        provenance_filter_row.addStretch(1)
        provenance_layout.addLayout(provenance_filter_row)
        self.provenance_table = CopyableTableWidget(0, 8)
        self.provenance_table.setHorizontalHeaderLabels(
            ["模块", "检查结果", "序列", "源点数", "绘制点数", "不完整日期", "失败原因", "核验文件"]
        )
        self.provenance_failed_filter.stateChanged.connect(
            self._apply_provenance_table_filters
        )
        self.provenance_gap_filter.stateChanged.connect(
            self._apply_provenance_table_filters
        )
        provenance_header = self.provenance_table.horizontalHeader()
        for column in range(6):
            provenance_header.setSectionResizeMode(column, QHeaderView.ResizeToContents)
        provenance_header.setSectionResizeMode(6, QHeaderView.Stretch)
        provenance_header.setSectionResizeMode(7, QHeaderView.Interactive)
        self.provenance_table.setColumnWidth(7, 320)
        self.provenance_table.setMinimumHeight(130)
        provenance_layout.addWidget(self.provenance_table)
        outer.addWidget(provenance_group)

        approval_group = QGroupBox("正式报告生成条件")
        approval_layout = QVBoxLayout(approval_group)
        approval_layout.addWidget(QLabel("请先检查关键图件、统计工作簿和图件数据完整性。审核只对当前任务及其分析结果清单生效。"))
        self.approval_check = QCheckBox("我已审核当前任务图件，允许进入正式报告阶段")
        self.approval_check.stateChanged.connect(self._on_approval_changed)
        approval_layout.addWidget(self.approval_check)
        self.disclosure_summary_label = QLabel("当前分析结果没有需要逐项确认的黄色缺项。")
        self.disclosure_summary_label.setWordWrap(True)
        approval_layout.addWidget(self.disclosure_summary_label)
        disclosure_actions = QHBoxLayout()
        self.disclosure_select_all_btn = QPushButton("全选报告条件")
        self.disclosure_select_all_btn.setObjectName("selectAllReportDisclosuresButton")
        self.disclosure_select_all_btn.setToolTip(
            "勾选图件审核确认和当前分析清单中的全部黄色可披露缺项；"
            "不能绕过任何红色硬阻塞"
        )
        self.disclosure_select_all_btn.setEnabled(False)
        self.disclosure_select_all_btn.clicked.connect(
            lambda: self._set_all_report_conditions(Qt.Checked)
        )
        disclosure_actions.addWidget(self.disclosure_select_all_btn)
        self.disclosure_clear_all_btn = QPushButton("取消全选")
        self.disclosure_clear_all_btn.setObjectName("clearAllReportDisclosuresButton")
        self.disclosure_clear_all_btn.setEnabled(False)
        self.disclosure_clear_all_btn.clicked.connect(
            lambda: self._set_all_report_conditions(Qt.Unchecked)
        )
        disclosure_actions.addWidget(self.disclosure_clear_all_btn)
        disclosure_actions.addStretch(1)
        approval_layout.addLayout(disclosure_actions)
        self.disclosure_table = CopyableTableWidget(0, 6)
        self.disclosure_table.setHorizontalHeaderLabels(
            ["逐项确认", "原因类型", "模块/项目", "确认原因", "报告处置", "核验文件"]
        )
        disclosure_header = self.disclosure_table.horizontalHeader()
        disclosure_header.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        disclosure_header.setSectionResizeMode(1, QHeaderView.ResizeToContents)
        disclosure_header.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        disclosure_header.setSectionResizeMode(3, QHeaderView.Stretch)
        disclosure_header.setSectionResizeMode(4, QHeaderView.Stretch)
        disclosure_header.setSectionResizeMode(5, QHeaderView.Interactive)
        self.disclosure_table.setColumnWidth(5, 280)
        self.disclosure_table.setMinimumHeight(120)
        self.disclosure_table.itemChanged.connect(self._on_disclosure_item_changed)
        approval_layout.addWidget(self.disclosure_table)
        outer.addWidget(approval_group)
        return page

    def _build_report_tab(self) -> QWidget:
        page = QWidget()
        outer = QVBoxLayout(page)
        form = QFormLayout()
        self.template_edit = QLineEdit()
        self.template_edit.textChanged.connect(self._on_report_gate_input_changed)
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

        self.report_gate_label = QLabel("尚不能生成报告：请先完成分析结果检查和图件审核。")
        self.report_gate_label.setWordWrap(True)
        outer.addWidget(self.report_gate_label)
        buttons = QGridLayout()
        self.open_report_btn = QPushButton("生成报告并执行质量检查")
        self.open_report_btn.setEnabled(False)
        self.open_report_btn.clicked.connect(self._start_report_job)
        buttons.addWidget(self.open_report_btn, 0, 0)
        self.stop_report_btn = QPushButton("停止报告任务")
        apply_danger_action_style(self.stop_report_btn)
        self.stop_report_btn.setEnabled(False)
        self.stop_report_btn.clicked.connect(self._stop_report_job)
        buttons.addWidget(self.stop_report_btn, 0, 1)
        open_output = QPushButton("打开输出目录")
        open_output.clicked.connect(self._open_output_dir)
        buttons.addWidget(open_output, 1, 0)
        self.open_report_qc_btn = QPushButton("打开逐页版面检查")
        self.open_report_qc_btn.setEnabled(False)
        self.open_report_qc_btn.clicked.connect(self._open_report_qc_dir)
        buttons.addWidget(self.open_report_qc_btn, 1, 1)
        buttons.setColumnStretch(2, 1)
        outer.addLayout(buttons)
        progress_row = QHBoxLayout()
        self.report_progress = QProgressBar()
        self.report_progress.setRange(0, 1000)
        progress_row.addWidget(self.report_progress, 1)
        self.report_progress_label = QLabel("等待报告任务")
        self.report_progress_label.setMinimumWidth(220)
        progress_row.addWidget(self.report_progress_label)
        outer.addLayout(progress_row)
        self.report_output_label = QLabel("DOCX/PDF：尚未生成")
        self.report_output_label.setWordWrap(True)
        self.report_output_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        outer.addWidget(self.report_output_label)
        qc_filter_row = QHBoxLayout()
        self.report_qc_failed_filter = QCheckBox("只看未通过")
        self.report_qc_gap_filter = QCheckBox("只看有缺口")
        qc_filter_row.addWidget(self.report_qc_failed_filter)
        qc_filter_row.addWidget(self.report_qc_gap_filter)
        qc_filter_row.addStretch(1)
        outer.addLayout(qc_filter_row)
        self.report_qc_table = CopyableTableWidget(0, 6)
        self.report_qc_table.setHorizontalHeaderLabels(
            ["对象", "状态", "大小/页数", "图片/缺失/警告", "失败原因", "核验文件"]
        )
        self.report_qc_failed_filter.stateChanged.connect(
            self._apply_report_qc_table_filters
        )
        self.report_qc_gap_filter.stateChanged.connect(
            self._apply_report_qc_table_filters
        )
        qc_header = self.report_qc_table.horizontalHeader()
        for column in range(4):
            qc_header.setSectionResizeMode(column, QHeaderView.ResizeToContents)
        qc_header.setSectionResizeMode(4, QHeaderView.Stretch)
        qc_header.setSectionResizeMode(5, QHeaderView.Interactive)
        self.report_qc_table.setColumnWidth(5, 320)
        outer.addWidget(self.report_qc_table)
        self.report_log = QPlainTextEdit()
        self.report_log.setReadOnly(True)
        self.report_log.setPlaceholderText("报告生成阶段、错误和最终质量检查会显示在这里。")
        outer.addWidget(self.report_log, 1)
        return page

    def _apply_module_table_filters(self) -> None:
        self.module_table.set_filters(
            failed_only=self.module_failed_filter.isChecked(),
            gap_only=self.module_gap_filter.isChecked(),
        )

    def _apply_provenance_table_filters(self) -> None:
        self.provenance_table.set_filters(
            failed_only=self.provenance_failed_filter.isChecked(),
            gap_only=self.provenance_gap_filter.isChecked(),
        )

    def _apply_report_qc_table_filters(self) -> None:
        self.report_qc_table.set_filters(
            failed_only=self.report_qc_failed_filter.isChecked(),
            gap_only=self.report_qc_gap_filter.isChecked(),
        )

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

    def _on_path_profile_changed(self, _index: int) -> None:
        if not hasattr(self, "current_profile"):
            return
        selection = str(self.path_profile_combo.currentData() or PathProfileResolver.AUTO_ID)
        if selection == PathProfileResolver.CUSTOM_ID:
            value = self.custom_data_roots.get(
                self.current_profile.bridge_id, self.data_root_edit.text().strip()
            )
            if value:
                _set_line_edit_path(self.data_root_edit, value)
            self.active_path_profile = None
            self.path_profile_status_label.setText(
                "当前配置组：自定义路径（只影响本任务；任务方案会保存该路径）"
            )
            return
        selected = self.path_resolver.select(selection)
        self.active_path_profile = selected
        root = self.path_resolver.resolve_data_root(
            self.current_profile.bridge_id,
            self.current_profile.default_data_root,
            selected,
        )
        _set_line_edit_path(self.data_root_edit, root)
        self.path_profile_status_label.setText(self.path_resolver.describe(selected))
        self._update_default_output_dir(root)

    def _on_data_root_edited(self, value: str) -> None:
        if not hasattr(self, "current_profile"):
            return
        self.custom_data_roots[self.current_profile.bridge_id] = value.strip()
        custom_index = self.path_profile_combo.findData(PathProfileResolver.CUSTOM_ID)
        if custom_index >= 0 and self.path_profile_combo.currentIndex() != custom_index:
            self.path_profile_combo.setCurrentIndex(custom_index)

    def _update_default_output_dir(self, data_root: str) -> None:
        self._refresh_report_defaults(data_root=data_root)

    @staticmethod
    def _period_label_for_dates(profile: WorkbenchProfile, start: QDate, end: QDate) -> str:
        if profile.report_type == "period":
            if start.year() == end.year():
                if start.month() == end.month():
                    return f"{end.year()}年{end.month()}月"
                return f"{start.year()}年{start.month()}-{end.month()}月"
            return f"{start.year()}年{start.month()}月-{end.year()}年{end.month()}月"

        default = profile.default_period_label
        suffix = "月份" if "月份" in default else "月"
        zero_padded = re.search(r"年0\d月", default) is not None
        month = f"{end.month():02d}" if zero_padded else str(end.month())
        return f"{end.year()}年{month}{suffix}"

    @staticmethod
    def _monitoring_range_for_dates(profile: WorkbenchProfile, start: QDate, end: QDate) -> str:
        default = profile.default_monitoring_range
        zero_padded = re.search(r"年0\d月|月0\d日", default) is not None
        separator = "～" if "～" in default else ("至" if "至" in default else "~")

        def format_date(value: QDate) -> str:
            if zero_padded:
                return f"{value.year():04d}年{value.month():02d}月{value.day():02d}日"
            return f"{value.year()}年{value.month()}月{value.day()}日"

        return f"{format_date(start)}{separator}{format_date(end)}"

    def _derived_report_values(
        self,
        *,
        profile: WorkbenchProfile | None = None,
        data_root: str | None = None,
    ) -> dict[str, str]:
        active_profile = profile or self.current_profile
        root = self.data_root_edit.text().strip() if data_root is None else str(data_root).strip()
        output = Path(root) / "自动报告" if root else self.project_root / "output" / "doc"
        return {
            "output_dir": str(output),
            "period_label": self._period_label_for_dates(
                active_profile, self.start_date_edit.date(), self.end_date_edit.date()
            ),
            "monitoring_range": self._monitoring_range_for_dates(
                active_profile, self.start_date_edit.date(), self.end_date_edit.date()
            ),
        }

    def _refresh_report_defaults(
        self,
        *_args: object,
        profile: WorkbenchProfile | None = None,
        data_root: str | None = None,
        force: bool = False,
    ) -> None:
        if self._suspend_report_autofill or not hasattr(self, "output_dir_edit"):
            return
        values = self._derived_report_values(profile=profile, data_root=data_root)
        edits = {
            "output_dir": self.output_dir_edit,
            "period_label": self.period_label_edit,
            "monitoring_range": self.monitoring_range_edit,
        }
        for key, edit in edits.items():
            current = edit.text().strip()
            previous_auto = self._report_auto_values.get(key, "")
            still_auto = current == previous_auto
            if key == "output_dir" and current and previous_auto:
                still_auto = os.path.normcase(os.path.normpath(current)) == os.path.normcase(
                    os.path.normpath(previous_auto)
                )
            if force or not current or still_auto:
                if key == "output_dir":
                    _set_line_edit_path(edit, values[key])
                else:
                    edit.setText(values[key])
            self._report_auto_values[key] = values[key]

    def _establish_report_defaults_baseline(self, profile: WorkbenchProfile) -> None:
        values = self._derived_report_values(profile=profile)
        edits = {
            "output_dir": self.output_dir_edit,
            "period_label": self.period_label_edit,
            "monitoring_range": self.monitoring_range_edit,
        }
        for key, edit in edits.items():
            if not edit.text().strip():
                if key == "output_dir":
                    _set_line_edit_path(edit, values[key])
                else:
                    edit.setText(values[key])
        self._report_auto_values = values

    def _refresh_data_source_summary(self, *_args: object) -> None:
        if not hasattr(self, "data_source_mode_label"):
            return
        path = Path(self.config_edit.text().strip()).expanduser()
        mode = "auto"
        if path.is_file():
            try:
                payload, _dependencies = load_layered_config(path)
                adapter = payload.get("data_adapter") if isinstance(payload, dict) else None
                series = adapter.get("time_series") if isinstance(adapter, dict) else None
                configured = series.get("source_mode") if isinstance(series, dict) else None
                mode = str(configured or "auto").strip().lower()
            except (OSError, ValueError, json.JSONDecodeError):
                self.data_source_mode_label.setText("配置文件暂时无法读取；请先执行“检查配置与路径”。")
                self.data_source_mode_label.setStyleSheet("color: #a33;")
                return
        descriptions = {
            "auto": "自动识别（推荐）：有 CSV 时读取 CSV；没有 CSV 时读取有效的 MAT 缓存。",
            "prefer_mat": "优先读取 MAT 缓存；缓存不可用时再读取 CSV。",
            "mat_only": "仅读取 MAT 缓存（高级验证模式，不会回退读取 CSV）。",
            "csv_cache": "仅从 CSV 构建或复用缓存（高级兼容模式）。",
        }
        self.data_source_mode_label.setText(descriptions.get(mode, f"配置的数据读取方式：{mode}"))
        self.data_source_mode_label.setStyleSheet("color: #174a75;")

    def _threshold_task_context(self) -> dict[str, str]:
        return {
            "bridge_id": str(self.profile_combo.currentData() or ""),
            "data_root": self.data_root_edit.text().strip(),
            "config_path": self.config_edit.text().strip(),
            "start_date": self.start_date_edit.date().toString("yyyy-MM-dd"),
            "end_date": self.end_date_edit.date().toString("yyyy-MM-dd"),
        }

    def _show_auto_threshold_for_module(self, module_key: str) -> None:
        self.tabs.setCurrentWidget(self.config_tabs)
        self.config_tabs.setCurrentWidget(self.auto_threshold_scroll)
        if not self.auto_threshold_editor.select_only_module(module_key):
            self._append_log(
                f"自动清洗建议暂不支持当前分析类型：{module_key}；请改选受支持模块。"
            )

    def _generate_current_threshold_curve(
        self, module_key: str, point_id: str
    ) -> None:
        dialog = ThresholdCurveTaskDialog(
            self.project_root,
            self._threshold_task_context(),
            module_key,
            point_id,
            self,
        )
        dialog.exec()
        dialog.deleteLater()

    def _analysis_result_location(self):
        current_root = self.data_root_edit.text().strip()
        # Once a task exists, keep every result action bound to that task even
        # if the operator edits the controls for the *next* task.  Falling back
        # to the edited data root here makes a healthy/finished task appear to
        # have written somewhere it never used.
        return analysis_result_location(
            data_root=current_root,
            context=self.current_context,
        )

    def _refresh_analysis_result_location(self, *_args: object) -> None:
        if not hasattr(self, "analysis_result_path_label"):
            return
        location = self._analysis_result_location()
        if location is None:
            self.analysis_result_path_label.setText("尚未选择结果目录")
            self.analysis_result_help_label.setText(
                "先选择数据根目录；建立任务后这里会持续显示实际结果位置。"
            )
            self.open_analysis_result_button.setEnabled(False)
            self.copy_analysis_result_path_button.setEnabled(False)
            self.open_analysis_stats_button.setEnabled(False)
            self.open_analysis_logs_button.setEnabled(False)
            if hasattr(self, "review_open_result_button"):
                self.review_open_result_button.setEnabled(False)
            return
        prefix = "本任务实际结果根目录" if location.task_dir is not None else "计划结果根目录"
        self.analysis_result_path_label.setText(f"{prefix}：{location.root}")
        explanation = location.explanation
        context = self.current_context
        if context is not None and not self._context_matches_current_inputs(context):
            planned = self.data_root_edit.text().strip()
            if planned:
                planned_root = Path(planned).expanduser().resolve(strict=False)
                explanation += (
                    f" 你已修改任务输入；下一次新任务计划使用：{planned_root}。"
                    "上方路径及打开/复制按钮仍指向当前正在监控或已保存任务的真实结果。"
                )
        self.analysis_result_help_label.setText(explanation)
        available = location.root.is_dir()
        self.copy_analysis_result_path_button.setEnabled(True)
        self.open_analysis_result_button.setEnabled(available)
        self.open_analysis_stats_button.setEnabled(location.stats_dir.is_dir())
        self.open_analysis_logs_button.setEnabled(location.run_logs_dir.is_dir())
        self.open_analysis_result_button.setToolTip(
            "打开统计表、图件和 run_logs 所在的结果根目录"
            if available
            else "结果根目录尚不存在；请先检查数据目录或保存任务方案"
        )
        if hasattr(self, "review_open_result_button"):
            self.review_open_result_button.setEnabled(available)

    def _open_analysis_result_dir(self) -> None:
        location = self._analysis_result_location()
        if location is None or not location.root.is_dir():
            QMessageBox.warning(
                self,
                "结果目录尚不可用",
                "当前任务的结果根目录不存在。请先检查数据目录并保存或打开任务方案。",
            )
            return
        if os.name == "nt":
            os.startfile(location.root)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(location.root)))

    def _copy_analysis_result_path(self) -> None:
        location = self._analysis_result_location()
        if location is None:
            QMessageBox.information(
                self,
                "尚无结果路径",
                "请先选择数据根目录，或打开一个已保存的任务方案。",
            )
            return
        QApplication.clipboard().setText(str(location.root))
        self._append_log(f"已复制计算结果目录：{location.root}")

    def _open_analysis_result_child(self, name: str) -> None:
        location = self._analysis_result_location()
        child = None
        if location is not None:
            child = location.stats_dir if name == "stats" else location.run_logs_dir
        if child is None or not child.is_dir():
            label = "统计表" if name == "stats" else "运行记录"
            QMessageBox.information(
                self,
                f"{label}目录尚未生成",
                f"当前结果根目录下还没有{label}目录。任务运行并产生产物后再打开即可。",
            )
            return
        if os.name == "nt":
            os.startfile(child)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(child)))

    def _apply_profile(self, profile: WorkbenchProfile) -> None:
        previous_suspend = self._suspend_report_autofill
        self._suspend_report_autofill = True
        self.current_profile = profile
        try:
            selection = str(self.path_profile_combo.currentData() or PathProfileResolver.AUTO_ID)
            if selection == PathProfileResolver.CUSTOM_ID:
                data_root = self.custom_data_roots.get(profile.bridge_id, profile.default_data_root)
                self.active_path_profile = None
                self.path_profile_status_label.setText(
                    "当前配置组：自定义路径（只影响本任务；任务方案会保存该路径）"
                )
            else:
                self.active_path_profile = self.path_resolver.select(selection)
                data_root = self.path_resolver.resolve_data_root(
                    profile.bridge_id, profile.default_data_root, self.active_path_profile
                )
                self.path_profile_status_label.setText(
                    self.path_resolver.describe(self.active_path_profile)
                )
            _set_line_edit_path(self.data_root_edit, data_root)
            _set_line_edit_path(self.config_edit, profile.config_path(self.project_root))
            try:
                self.alarm_editor.load_path(profile.config_path(self.project_root))
                self.cleaning_editor.load_path(profile.config_path(self.project_root))
                self.post_filter_editor.load_path(profile.config_path(self.project_root))
                self.offset_editor.load_path(profile.config_path(self.project_root))
                self.group_plot_editor.load_path(profile.config_path(self.project_root))
                self.plot_common_editor.load_path(profile.config_path(self.project_root))
                self.spectrum_editor.load_path(profile.config_path(self.project_root))
                self.unzip_settings_editor.load_path(profile.config_path(self.project_root))
            except Exception as exc:  # noqa: BLE001
                self.alarm_editor.message_label.setText(f"配置加载失败：{exc}")
                self.alarm_editor.message_label.setStyleSheet("color: #a33;")
                self.cleaning_editor.message_label.setText(f"配置加载失败：{exc}")
                self.cleaning_editor.message_label.setStyleSheet("color: #a33;")
                self.post_filter_editor.message_label.setText(f"配置加载失败：{exc}")
                self.post_filter_editor.message_label.setStyleSheet("color: #a33;")
                self.offset_editor.message_label.setText(f"配置加载失败：{exc}")
                self.offset_editor.message_label.setStyleSheet("color: #a33;")
                self.group_plot_editor.summary_label.setText(f"配置加载失败：{exc}")
                self.group_plot_editor.summary_label.setStyleSheet("color: #a33;")
                self.plot_common_editor.summary_label.setText(f"配置加载失败：{exc}")
                self.plot_common_editor.summary_label.setStyleSheet("color: #a33;")
                self.spectrum_editor.summary_label.setText(f"配置加载失败：{exc}")
                self.spectrum_editor.summary_label.setStyleSheet("color: #a33;")
                self.unzip_settings_editor.message_label.setText(f"配置加载失败：{exc}")
                self.unzip_settings_editor.message_label.setStyleSheet("color: #a33;")
            _set_line_edit_path(self.template_edit, profile.template_path(self.project_root) if profile.report_template else "")
            self._set_date(self.start_date_edit, profile.default_start_date)
            self._set_date(self.end_date_edit, profile.default_end_date)
            self.report_date_edit.setText(profile.default_report_date or datetime.now().strftime("%Y年%m月%d日"))
            enabled = set(profile.enabled_modules)
            optional = set(profile.optional_modules)
            for key, checkbox in self.module_checks.items():
                supported = key != "cache_prebuild" or key in enabled or key in optional
                checkbox.setEnabled(supported)
                checkbox.setChecked(supported and key in enabled)
            self._reset_cache_cleanup_controls()
        finally:
            self._suspend_report_autofill = previous_suspend
        if not previous_suspend:
            self._refresh_report_defaults(profile=profile, data_root=data_root, force=True)
        self._refresh_analysis_result_location()
        self._append_log(f"已切换项目：{profile.bridge_name}")

    @staticmethod
    def _set_date(widget: QDateEdit, value: str) -> None:
        parsed = QDate.fromString(value, "yyyy-MM-dd")
        widget.setDate(parsed if parsed.isValid() else QDate.currentDate())

    def _selected_modules(self) -> list[str]:
        return [key for key, checkbox in self.module_checks.items() if checkbox.isChecked()]

    def _reset_cache_cleanup_controls(self) -> None:
        self.cache_cleanup_check.blockSignals(True)
        self.cache_cleanup_check.setChecked(False)
        self.cache_cleanup_check.blockSignals(False)
        self.cache_cleanup_confirmation_edit.clear()
        self._sync_cache_cleanup_controls()

    def _sync_cache_cleanup_controls(self, *_: object) -> None:
        cache_selected = self.module_checks["cache_prebuild"].isChecked()
        # This is also called while the analysis tab is being built, before
        # the first bridge profile has been applied.  Treat that short
        # construction phase as layout-neutral; _apply_profile() calls us
        # again immediately with the real data layout.
        profile = getattr(self, "current_profile", None)
        layout_supported = (
            profile is None
            or profile.data_layout in CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS
        )
        if (not cache_selected or not layout_supported) and self.cache_cleanup_check.isChecked():
            self.cache_cleanup_check.blockSignals(True)
            self.cache_cleanup_check.setChecked(False)
            self.cache_cleanup_check.blockSignals(False)
            self.cache_cleanup_confirmation_edit.clear()
        self.cache_cleanup_check.setEnabled(cache_selected and layout_supported)
        if not layout_supported:
            self.cache_cleanup_check.setToolTip(
                "默认关闭。当前数据目录格式没有可验证的逐日 ZIP 恢复协议；CSV 将保留。"
            )
        else:
            self.cache_cleanup_check.setToolTip(
                "默认关闭。只删除配置实际使用、缓存可独立读取且能由原 ZIP 恢复的 CSV；"
                "原 ZIP、WIM、Excel、未配置 CSV 和缓存文件不会删除。运行前还会按实际"
                "数据根逐日核对 ZIP 条目路径、大小和 CRC；任何一项失败，当天零删除。"
            )
        self.cache_cleanup_confirmation_edit.setEnabled(
            cache_selected and self.cache_cleanup_check.isChecked()
        )

    def _on_cache_cleanup_toggled(self, checked: bool) -> None:
        if not checked:
            self.cache_cleanup_confirmation_edit.clear()
        self._sync_cache_cleanup_controls()
        self._on_task_inputs_changed()

    def _cache_cleanup_settings(self) -> CacheSourceCleanupSettings:
        return CacheSourceCleanupSettings(
            enabled=self.cache_cleanup_check.isChecked(),
            confirmation=self.cache_cleanup_confirmation_edit.text(),
        )

    def _task_options(self, selected: list[str]) -> dict[str, object]:
        options: dict[str, object] = dict(options_for_modules(selected))
        settings = self._cache_cleanup_settings()
        if settings.enabled:
            options[CACHE_SOURCE_CLEANUP_KEY] = settings.to_task_option(selected)
        return options

    def _on_task_inputs_changed(self, *_: object) -> None:
        context = self.current_context
        if context is None or self._context_matches_current_inputs(context):
            return
        if (
            self.current_manifest is not None
            or self.current_provenance is not None
            or self.approval_check.isChecked()
            or self.approval_check.isEnabled()
        ):
            self._reset_review_state()

    def _context_matches_current_inputs(self, context: JobContext) -> bool:
        try:
            same_root = os.path.normcase(str(Path(context.data_root).resolve())) == os.path.normcase(
                str(Path(self.data_root_edit.text().strip()).expanduser().resolve())
            )
            current_config = Path(self.config_edit.text().strip()).expanduser().resolve()
            same_config = os.path.normcase(str(Path(context.config_path).resolve())) == os.path.normcase(
                str(current_config)
            )
            same_config_hash = (
                current_config.is_file()
                and config_dependency_sha256(current_config) == context.config_sha256.upper()
            )
        except (OSError, ValueError, json.JSONDecodeError):
            return False
        cleanup = CacheSourceCleanupSettings.from_task_options(context.options)
        return (
            context.bridge_id == self.current_profile.bridge_id
            and same_root
            and same_config
            and same_config_hash
            and context.start_date == self.start_date_edit.date().toString("yyyy-MM-dd")
            and context.end_date == self.end_date_edit.date().toString("yyyy-MM-dd")
            and tuple(context.selected_modules) == tuple(self._selected_modules())
            and cleanup.policy_compatible
            and cleanup.enabled == self.cache_cleanup_check.isChecked()
            and cleanup.confirmation == self.cache_cleanup_confirmation_edit.text()
        )

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
        errors.extend(
            cleanup_validation_errors(
                self._selected_modules(),
                enabled=self.cache_cleanup_check.isChecked(),
                confirmation=self.cache_cleanup_confirmation_edit.text(),
                data_layout=self.current_profile.data_layout,
            )
        )
        if (
            self.cache_cleanup_check.isChecked()
            and data_root.is_dir()
            and config.is_file()
            and self.end_date_edit.date() >= self.start_date_edit.date()
        ):
            errors.extend(
                cleanup_root_preflight_errors(
                    data_root,
                    config,
                    self.start_date_edit.date().toString("yyyy-MM-dd"),
                    self.end_date_edit.date().toString("yyyy-MM-dd"),
                    self.current_profile.data_layout,
                )
            )
        return errors

    def _validate_inputs_dialog(self) -> None:
        errors = self._validate_inputs()
        if errors:
            QMessageBox.critical(self, "任务检查失败", "\n".join(f"- {item}" for item in errors))
        else:
            QMessageBox.information(self, "任务检查通过", "数据目录、配置、日期和模块检查通过。")

    def _show_profile_matrix(self) -> None:
        try:
            matrix = load_installed_profile_matrix(self.project_root)
        except ProfileAuditError as exc:
            QMessageBox.information(self, "所有桥梁自检", str(exc))
            return
        lines = []
        for row in matrix.profiles:
            capability = row.get("report_gui_type") or "仅分析"
            lines.append(
                f"{row.get('bridge_name')} ({row.get('bridge_id')})："
                f"模块 {row.get('enabled_module_count')}；{capability}；"
                f"配置 {str(row.get('config_sha256') or '')[:16]}…"
            )
        box = QMessageBox(self)
        box.setWindowTitle("冻结版所有桥梁自检已通过")
        box.setIcon(QMessageBox.Information)
        box.setText(
            f"所有桥梁 {matrix.profile_count}/{matrix.profile_count}；报告型 {matrix.report_capable_count}；"
            f"仅分析 {matrix.analysis_only_count}；资产 {matrix.asset_count} 个未修改。"
        )
        box.setInformativeText(f"矩阵文件：{matrix.path}")
        box.setDetailedText("\n".join(lines))
        box.exec()

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
            options=self._task_options(selected),
            report_type=profile.report_gui_type,
            template_path=Path(self.template_edit.text().strip()) if self.template_edit.text().strip() else None,
            output_dir=Path(self.output_dir_edit.text().strip()),
            period_label=self.period_label_edit.text().strip(),
            monitoring_range=self.monitoring_range_edit.text().strip(),
            report_date=self.report_date_edit.text().strip(),
        )
        self.current_context = context
        self._analysis_context_superseded = False
        self._report_context_superseded = False
        self._refresh_analysis_result_location()
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
            self.known_context_paths.add(self.current_context_path)
            self._append_log(f"任务方案已保存：{self.current_context_path}")
            self.analysis_status_label.setText(f"状态：draft；任务 {context.job_id}")
            self._refresh_analysis_result_location()
        except Exception as exc:  # noqa: BLE001
            self._show_exception("保存任务失败", exc)

    def _open_context_dialog(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "打开已保存任务方案",
            str(self.project_root / "run_logs"),
            "任务方案 (job_context.json);;JSON files (*.json)",
        )
        if path:
            try:
                self.load_context(Path(path))
            except Exception as exc:  # noqa: BLE001
                self._show_exception("打开任务失败", exc)

    def load_context(self, path: Path) -> None:
        context = JobContext.read(path.expanduser().resolve())
        profile = profile_by_id(self.profiles, context.bridge_id)
        previous_suspend = self._suspend_report_autofill
        self._suspend_report_autofill = True
        try:
            index = self.profile_combo.findData(profile.bridge_id)
            if index >= 0:
                self.profile_combo.setCurrentIndex(index)
            restored_root = str(Path(context.data_root))
            auto_profile = self.path_resolver.select(PathProfileResolver.AUTO_ID)
            automatic_root = self.path_resolver.resolve_data_root(
                profile.bridge_id, profile.default_data_root, auto_profile
            )
            if os.path.normcase(os.path.normpath(restored_root)) != os.path.normcase(
                os.path.normpath(automatic_root)
            ):
                self.custom_data_roots[profile.bridge_id] = restored_root
                custom_index = self.path_profile_combo.findData(PathProfileResolver.CUSTOM_ID)
                if custom_index >= 0:
                    self.path_profile_combo.setCurrentIndex(custom_index)
            _set_line_edit_path(self.data_root_edit, restored_root)
            _set_line_edit_path(self.config_edit, context.config_path)
            self._set_date(self.start_date_edit, context.start_date)
            self._set_date(self.end_date_edit, context.end_date)
            selected = set(context.selected_modules)
            for key, checkbox in self.module_checks.items():
                checkbox.setChecked(key in selected)
            cleanup = CacheSourceCleanupSettings.from_task_options(context.options)
            self.cache_cleanup_check.setChecked(cleanup.enabled)
            self.cache_cleanup_confirmation_edit.setText(cleanup.confirmation)
            self._sync_cache_cleanup_controls()
            _set_line_edit_path(self.template_edit, context.report.template_path)
            _set_line_edit_path(self.output_dir_edit, context.report.output_dir)
            self.period_label_edit.setText(context.period_label)
            self.monitoring_range_edit.setText(context.monitoring_range)
            self.report_date_edit.setText(context.report_date)
        finally:
            self._suspend_report_autofill = previous_suspend
        self._establish_report_defaults_baseline(profile)
        self.current_context = context
        self._analysis_context_superseded = False
        self._report_context_superseded = False
        self.current_context_path = path.resolve()
        self.known_context_paths.add(self.current_context_path)
        self._reset_review_state(clear_context_approval=False)
        if context.analysis.manifest_path and Path(context.analysis.manifest_path).is_file():
            self._load_manifest(Path(context.analysis.manifest_path))
            if context.report.plots_approved and self.approval_check.isEnabled():
                self.approval_check.blockSignals(True)
                self.approval_check.setChecked(True)
                self.approval_check.blockSignals(False)
        self._append_log(f"已恢复任务：{context.job_id}；任务方案={path}")
        self._refresh_analysis_result_location()
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
            self.known_context_paths.add(self.current_context_path)
            self.start_btn.setEnabled(False)
            self.stop_btn.setEnabled(True)
            self.analysis_status_label.setText(f"状态：launched；PID {result.pid}")
            self._append_log(f"已启动分析：{executor.kind}，PID={result.pid}")
            self._append_log(f"请求文件：{context.analysis.request_path}")
            self._refresh_analysis_result_location()
        except Exception as exc:  # noqa: BLE001
            self._show_exception("启动分析失败", exc)

    def show_task_history(self, *, demo: bool = False) -> None:
        """Show the bounded local task index for the current data root."""
        if demo:
            self.task_history_page.load_demo()
        else:
            roots: list[Path] = []
            data_root = self.data_root_edit.text().strip()
            if data_root:
                roots.append(Path(data_root))
            extras = set(self.known_context_paths)
            if self.current_context_path is not None:
                extras.add(self.current_context_path)
            self.task_history_page.load_sources(tuple(roots), tuple(extras))
        self.analysis_stack.setCurrentIndex(1)

    def _restore_history_context(self, path: str) -> None:
        try:
            self.load_context(Path(path))
            self.analysis_stack.setCurrentIndex(0)
        except Exception as exc:  # noqa: BLE001
            self._show_exception("重新打开历史任务失败", exc)

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
        context_matches_inputs = self._context_matches_current_inputs(context)
        self._refresh_analysis_result_location()
        status = read_analysis_status(context)
        state = str(status.get("status") or "unknown").lower()
        superseded = bool(status.get("context_superseded"))
        self._analysis_context_superseded = superseded
        cleanup_pending = bool(status.get("process_cleanup_pending"))
        changed = False
        if not superseded and not cleanup_pending:
            changed = context.analysis.state != state
            context.analysis.state = state
        manifest_path = str(status.get("manifest_path") or "")
        if (
            not superseded
            and manifest_path
            and context.analysis.manifest_path != manifest_path
        ):
            context.analysis.manifest_path = manifest_path
            changed = True
        self.analysis_status_label.setText(f"状态：{state}；任务 {context.job_id}")
        progress_snapshot = normalize_module_progress(
            status,
            selected_modules=context.selected_modules,
        )
        progress_value = max(
            0,
            min(1000, round(float(progress_snapshot.progress_fraction) * 1000)),
        )
        self.analysis_progress.setValue(progress_value)
        self.module_progress_panel.set_snapshot(progress_snapshot)
        current_step = progress_snapshot.current_step
        progress_bits: list[str] = []
        if current_step is not None:
            if current_step.current_point_id:
                progress_bits.append(f"当前测点：{current_step.current_point_id}")
            if current_step.current_date:
                progress_bits.append(f"当前日期：{current_step.current_date}")
            if current_step.total_dates is not None and current_step.total_dates > 0:
                progress_bits.append(
                    "本模块日期："
                    f"{current_step.processed_dates or 0}/{current_step.total_dates}"
                )
            if current_step.stage:
                progress_bits.append(f"阶段：{module_stage_label(current_step.stage)}")
        self.analysis_progress_label.setText(
            "；".join(progress_bits) if progress_bits else progress_snapshot.summary_text
        )
        if state == "completed":
            location = self._analysis_result_location()
            if location is not None:
                self.analysis_progress_label.setText(
                    f"计算完成；结果保存在：{location.root}"
                )
        terminal = state in {
            "completed",
            "disclosure_required",
            "failed",
            "stopped",
            "launch_failed",
        }
        if superseded:
            self.start_btn.setEnabled(False)
            self.stop_btn.setEnabled(False)
            self.analysis_progress_label.setText(
                "此窗口显示的是旧轮次；请重新打开最新任务后再操作。"
            )
        elif cleanup_pending:
            self.start_btn.setEnabled(False)
            self.stop_btn.setEnabled(False)
            self.analysis_progress_label.setText(
                "结果已生成，后台进程正在退出清理，请稍候。"
            )
        else:
            self.start_btn.setEnabled(
                terminal or state in {"draft", "unknown", "status_read_failed"}
            )
            self.stop_btn.setEnabled(
                not terminal
                and state not in {"draft", "prepared", "stopping", "unknown"}
            )
        if changed and not superseded and not cleanup_pending:
            persist_analysis_state(context)
            self._append_log(f"分析状态更新：{state}")
            if state == "completed":
                location = self._analysis_result_location()
                if location is not None:
                    self._append_log(
                        f"计算完成。统计表、图件和运行记录保存在：{location.root}"
                    )
        # Keep monitoring an already-started task after the operator edits the
        # bridge/date/config controls, but never repopulate the review page
        # from that now-stale task.  The operator must explicitly reopen the
        # matching task (or restore the inputs) before its manifest/QC is
        # shown again.
        if context_matches_inputs and context.analysis.manifest_path:
            path = Path(context.analysis.manifest_path)
            if path.is_file() and (self.current_manifest is None or self.current_manifest.path != path.resolve()):
                self._load_manifest(path)
        self._poll_report_status(show_details=context_matches_inputs)
        self._update_report_gate()

    def _poll_report_status(self, *, show_details: bool | None = None) -> None:
        context = self.current_context
        if context is None or not hasattr(self, "report_progress"):
            return
        if show_details is None:
            show_details = self._context_matches_current_inputs(context)
        status = read_report_status(context)
        state = str(status.get("state") or context.report.state or "blocked").lower()
        superseded = bool(status.get("context_superseded"))
        self._report_context_superseded = superseded
        cleanup_pending = bool(status.get("process_cleanup_pending"))
        stage = str(status.get("stage") or state)
        message = str(status.get("message") or "")
        display_state = operator_state_label(state)
        display_stage = operator_stage_label(stage)
        display_message = operator_friendly_text(message)
        try:
            value = max(0, min(1000, round(float(status.get("progress_fraction", 0)) * 1000)))
        except (TypeError, ValueError, OverflowError):
            value = self.report_progress.value()
        self.report_progress.setValue(value)
        self.report_progress_label.setText(
            f"{display_state} / {display_stage}"
            + (f"；{display_message}" if display_message else "")
        )
        terminal = state in {"completed", "failed", "stopped", "launch_failed"}
        safe_stop_identity = bool(
            context.report.launch_id
            and context.report.process_creation_time_100ns
            and context.report.process_executable
        )
        self.stop_report_btn.setEnabled(
            not superseded
            and not cleanup_pending
            and not terminal
            and state in {"launched", "running"}
            and safe_stop_identity
        )
        if state in {"launched", "running"} and not safe_stop_identity:
            self.stop_report_btn.setToolTip(
                "这是旧版任务，缺少安全进程身份记录；为避免误停其他程序，不能从工作平台强制停止。"
            )
        else:
            self.stop_report_btn.setToolTip("安全停止当前报告后台任务")
        if superseded:
            self.stop_report_btn.setToolTip(
                "此窗口显示的是旧轮次；请重新打开最新任务后再操作。"
            )
        elif cleanup_pending:
            self.stop_report_btn.setToolTip(
                "报告结果已生成，后台进程正在退出清理，请稍候。"
            )
        if not superseded and not cleanup_pending and context.report.state != state:
            context.report.state = state
            persist_report_state(context)
            self.report_log.appendPlainText(
                f"[{datetime.now():%H:%M:%S}] 报告状态："
                f"{display_state} / {display_stage}；{display_message}"
            )
        if state == "completed" and status.get("qc"):
            output_docx = str(status.get("report_path") or "")
            output_pdf = str(status.get("pdf_path") or "")
            report_manifest = str(status.get("manifest_path") or "")
            qc_state = str(status.get("qc", {}).get("status") or "")
            visual = status.get("qc", {}).get("visual", {}) if isinstance(status.get("qc"), dict) else {}
            visual_qc_dir = str(visual.get("output_dir") or "") if isinstance(visual, dict) else ""
            visual_contact_sheet = str(visual.get("contact_sheet") or "") if isinstance(visual, dict) else ""
            if not cleanup_pending and (
                context.report.output_docx != output_docx
                or context.report.output_pdf != output_pdf
                or context.report.manifest_path != report_manifest
                or context.report.qc_state != qc_state
                or context.report.visual_qc_dir != visual_qc_dir
                or context.report.visual_contact_sheet != visual_contact_sheet
                or context.report.pid is not None
            ):
                context.report.output_docx = output_docx
                context.report.output_pdf = output_pdf
                context.report.manifest_path = report_manifest
                context.report.qc_state = qc_state
                context.report.visual_qc_dir = visual_qc_dir
                context.report.visual_contact_sheet = visual_contact_sheet
                context.report.pid = None
                persist_report_state(context)
            if show_details:
                self._show_report_qc(status)
        elif state == "disclosure_required" and not cleanup_pending:
            self._invalidate_report_gate_cache()
            candidates = status.get("disclosure_candidates")
            analysis_sha = str(status.get("analysis_manifest_sha256") or "").upper()
            if analysis_sha and analysis_sha != context.analysis.manifest_sha256.upper():
                context.report.report_build_disclosure_candidates = []
                context.report.disclosure_confirmations = [
                    raw
                    for raw in context.report.disclosure_confirmations
                    if isinstance(raw, dict)
                    and str(raw.get("source_kind") or "") != "report_build"
                ]
                context.report.qc_state = "failed"
                self.report_log.appendPlainText(
                    f"[{datetime.now():%H:%M:%S}] 报告预检查绑定的分析清单已变化，黄色缺项确认已失效。"
                )
            elif isinstance(candidates, list):
                normalized = [dict(raw) for raw in candidates if isinstance(raw, dict)]
                new_candidates = normalized != context.report.report_build_disclosure_candidates
                if new_candidates:
                    context.report.report_build_disclosure_candidates = normalized
                    actual_ids = {
                        str(raw.get("stable_id") or "") for raw in normalized
                    }
                    context.report.disclosure_confirmations = [
                        raw
                        for raw in context.report.disclosure_confirmations
                        if isinstance(raw, dict)
                        and (
                            str(raw.get("source_kind") or "") != "report_build"
                            or str(raw.get("stable_id") or "") in actual_ids
                        )
                    ]
                context.report.qc_state = "disclosure_required"
                context.report.manifest_path = str(status.get("manifest_path") or "")
                context.report.output_docx = str(status.get("report_path") or "")
                if new_candidates:
                    self.report_log.appendPlainText(
                        f"[{datetime.now():%H:%M:%S}] 报告预检查发现{len(normalized)}项黄色缺项；"
                        "请在“分析结果与图件审核”页逐项确认后重新生成。"
                    )
            context.report.pid = None
            persist_report_state(context)
            self._refresh_disclosure_table()
            self._update_report_gate()
        elif state == "failed" and not cleanup_pending:
            context.report.pid = None
            context.report.qc_state = "failed"
            persist_report_state(context)
            error = str(status.get("error") or message)
            display_error = operator_friendly_text(error)
            if display_error and display_error not in self.report_log.toPlainText():
                self.report_log.appendPlainText(f"[{datetime.now():%H:%M:%S}] 失败：{display_error}")

    def _show_report_qc(self, result: dict[str, object]) -> None:
        qc = result.get("qc") if isinstance(result.get("qc"), dict) else {}
        docx = qc.get("docx") if isinstance(qc.get("docx"), dict) else {}
        pdf = qc.get("pdf") if isinstance(qc.get("pdf"), dict) else {}
        manifest = qc.get("manifest") if isinstance(qc.get("manifest"), dict) else {}
        visual = qc.get("visual") if isinstance(qc.get("visual"), dict) else {}
        preview_pdf_path = str(visual.get("preview_pdf_path") or "")
        pdf_authoritative = bool(pdf.get("authoritative"))
        pdf_passed = bool(
            pdf_authoritative and pdf.get("exists") and pdf.get("page_count")
        )
        rows = (
            (
                "DOCX",
                "通过" if docx.get("zip_integrity") and docx.get("document_xml") else "失败",
                f"{docx.get('size_bytes', 0)} bytes",
                f"媒体 {docx.get('media_count', 0)}",
                "" if docx.get("zip_integrity") and docx.get("document_xml") else "DOCX 结构或正文检查未通过",
                str(docx.get("path") or ""),
            ),
            (
                "PDF",
                "通过" if pdf_passed else ("仅版面预览" if preview_pdf_path else "未生成权威 PDF"),
                f"{pdf.get('size_bytes', 0)} bytes / {pdf.get('page_count', 0)} 页",
                "Microsoft Word 权威导出" if pdf_passed else "LibreOffice 结果不作为交付 PDF",
                "" if pdf_passed else "尚未取得 Microsoft Word 权威导出的有效 PDF",
                str(pdf.get("path") or preview_pdf_path),
            ),
            (
                "报告内容清单",
                operator_state_label(manifest.get("status") or "missing"),
                "",
                f"缺失 {manifest.get('missing_count', 0)} / 警告 {manifest.get('warning_count', 0)} / "
                f"披露 {manifest.get('disclosure_count', 0)}",
                operator_friendly_text(manifest.get("message") or ""),
                str(manifest.get("path") or ""),
            ),
            (
                "逐页渲染",
                operator_state_label(visual.get("status") or "unavailable"),
                f"{visual.get('page_count', 0)} 页",
                f"空白页 {len(visual.get('blank_pages') or [])} / 边界告警 {len(visual.get('edge_touch_pages') or [])}",
                operator_friendly_text(visual.get("message") or ""),
                str(visual.get("contact_sheet") or ""),
            ),
        )
        self.report_qc_table.setRowCount(len(rows))
        for row_index, row in enumerate(rows):
            for column, value in enumerate(row):
                self.report_qc_table.set_copyable_item(
                    row_index,
                    column,
                    value,
                    path=value if column == 5 and str(value).strip() else None,
                )
            status_text = str(row[1])
            gap = bool(
                (row_index == 2 and (manifest.get("missing_count") or manifest.get("warning_count")))
                or (row_index == 3 and (visual.get("blank_pages") or visual.get("edge_touch_pages")))
            )
            self.report_qc_table.set_row_flags(
                row_index,
                failed=status_text not in {"通过", "通过（含缺项披露）"},
                gap=gap,
            )
        self._apply_report_qc_table_filters()
        report_path = str(result.get("report_path") or "")
        pdf_path = str(result.get("pdf_path") or "")
        pdf_text = pdf_path or "未生成权威 Word PDF"
        if not pdf_path and preview_pdf_path:
            pdf_text += f"（LibreOffice 仅版面预览：{preview_pdf_path}）"
        self.report_output_label.setText(f"DOCX：{report_path or '未生成'}\nPDF：{pdf_text}")
        contact_sheet = str(visual.get("contact_sheet") or "")
        self.open_report_qc_btn.setEnabled(bool(contact_sheet and Path(contact_sheet).is_file()))

    def _load_latest_manifest(self) -> None:
        data_root = Path(self.data_root_edit.text().strip()).expanduser()
        errors = self._validate_inputs()
        if errors:
            QMessageBox.critical(self, "无法建立任务", "\n".join(f"- {item}" for item in errors))
            return
        if self.current_context is None or not self._context_matches_current_inputs(
            self.current_context
        ):
            self.current_context = self._build_context()
        path = find_latest_manifest(
            data_root,
            bridge_id=self.current_context.bridge_id,
            start_date=self.current_context.start_date,
            end_date=self.current_context.end_date,
            config_path=Path(self.current_context.config_path),
            config_sha256=self.current_context.config_sha256,
            selected_modules=self.current_context.selected_modules,
            successful_only=True,
            disclosure_capable=True,
        )
        if path is None:
            QMessageBox.warning(
                self,
                "未找到",
                "未找到与当前桥梁、日期和所选分析模块完整匹配的成功结果清单。\n\n"
                f"请检查：{data_root / 'run_logs'}",
            )
            return
        answer = QMessageBox.question(
            self,
            "使用匹配的最新完整结果",
            "已按当前桥梁、监测日期和所选分析模块筛选成功的完整结果清单。\n\n"
            f"{path}",
        )
        if answer != QMessageBox.Yes:
            return
        if self._load_manifest(path, allow_rebind=True):
            self.current_context_path = self.current_context.context_path

    def _load_manifest(self, path: Path, *, allow_rebind: bool = False) -> bool:
        self._invalidate_report_gate_cache()
        try:
            summary = load_manifest_summary(path)
        except Exception as exc:  # noqa: BLE001
            self._show_exception("读取分析结果清单失败", exc)
            return False
        if self.current_context is not None:
            issues = manifest_context_issues(
                summary,
                bridge_id=self.current_context.bridge_id,
                data_root=Path(self.current_context.data_root),
                start_date=self.current_context.start_date,
                end_date=self.current_context.end_date,
                config_path=Path(self.current_context.config_path),
                config_sha256=self.current_context.config_sha256,
            )
            if issues:
                self._reset_review_state()
                self._append_log("分析结果与当前任务不一致：" + "; ".join(issues))
                return False
            actual_hash = file_sha256(path)
            pinned_hash = self.current_context.analysis.manifest_sha256
            if pinned_hash and pinned_hash != actual_hash and not allow_rebind:
                self._reset_review_state()
                self._append_log(
                    f"分析结果清单已发生变化，需重新审核：expected={pinned_hash}, actual={actual_hash}"
                )
                return False
            stored_path = str(self.current_context.analysis.manifest_path or "")
            binding_changed = (
                not pinned_hash
                or pinned_hash != actual_hash
                or not stored_path
                or Path(stored_path).expanduser().resolve() != path.resolve()
            )
            invalidate_approval = bool(binding_changed)
            if binding_changed:
                state = (
                    "completed"
                    if summary.status.lower() in SUCCESS_STATES
                    else summary.status.lower()
                )
                if not bind_analysis_manifest(
                    self.current_context,
                    path,
                    actual_hash,
                    analysis_state=state,
                    invalidate_report_approval=invalidate_approval,
                ):
                    self._reset_review_state(clear_context_approval=False)
                    self._append_log(
                        "任务方案已被其他窗口更新，未采用新的分析结果；请重新打开任务后再试。"
                    )
                    return False
                if invalidate_approval:
                    self._append_log(
                        "已绑定新的分析结果指纹；原有图件审核已失效，请重新审核。"
                    )
        self.current_manifest = summary
        selected = self.current_context.selected_modules if self.current_context is not None else []
        self.current_manifest_missing_selected = summary.missing_selected_modules(selected)
        self.manifest_label.setText(f"分析结果清单：{summary.path}")
        failed = len(summary.failed_modules)
        self.manifest_summary_label.setText(
            f"运行状态：{operator_state_label(summary.status)}；分析项目：{len(summary.modules)}；失败/异常：{failed}；"
            f"所选模块未记录：{len(self.current_manifest_missing_selected)}；产物：{summary.artifact_count}"
        )
        self.module_table.setRowCount(len(summary.modules))
        for row, item in enumerate(summary.modules):
            values = (
                item.label,
                operator_state_label(item.status),
                _whole_seconds_text(item.elapsed_sec),
                item.stats_path,
                operator_friendly_text(item.message),
            )
            for column, value in enumerate(values):
                self.module_table.set_copyable_item(
                    row,
                    column,
                    value,
                    path=value if column == 3 and str(value).strip() else None,
                    user_data=item.key if column == 0 else None,
                )
            message_text = str(item.message or "")
            self.module_table.set_row_flags(
                row,
                failed=str(item.status).lower() not in SUCCESS_STATES | {"skipped"},
                gap=any(
                    marker in message_text
                    for marker in ("缺口", "不完整", "缺失", "无有效数据", "断采")
                ),
            )
        self._apply_module_table_filters()
        self.module_table.resizeColumnsToContents()
        self.module_table.setColumnWidth(3, 300)
        try:
            self.current_provenance = inspect_manifest_plot_provenance(path)
            provenance = self.current_provenance
            self.provenance_table.setRowCount(len(provenance.rows))
            module_labels = {spec.key: spec.label for spec in MODULE_SPECS}
            for row_index, item in enumerate(provenance.rows):
                values = (
                    module_labels.get(item.module_key, item.module_key),
                    {
                        "closed": "通过",
                        "closed_incomplete_source": "通过（有已说明的数据缺口）",
                        "failed": "未通过",
                    }.get(item.status, item.status),
                    item.series_count,
                    item.source_count,
                    item.plotted_count,
                    ", ".join(item.incomplete_days),
                    _provenance_detail_text(item),
                    item.path,
                )
                for column, value in enumerate(values):
                    self.provenance_table.set_copyable_item(
                        row_index,
                        column,
                        value,
                        path=value if column == 7 and str(value).strip() else None,
                        user_data=item.module_key if column == 0 else None,
                    )
                self.provenance_table.set_row_flags(
                    row_index,
                    failed=item.status == "failed",
                    gap=bool(item.incomplete_days) or item.status == "closed_incomplete_source",
                )
            self._apply_provenance_table_filters()
            self.provenance_summary_label.setText(
                f"正式图件核验记录：{len(provenance.rows)}；"
                f"通过：{provenance.closed_count}；未通过：{provenance.failed_count}；"
                f"已披露不完整源日期：{provenance.incomplete_source_count}"
            )
            self.provenance_summary_label.setStyleSheet(
                "color: #a33; font-weight: 600;" if provenance.failed_count else "color: #167c35; font-weight: 600;"
            )
        except Exception as exc:  # noqa: BLE001
            self.current_provenance = None
            self.provenance_table.setRowCount(0)
            self.provenance_summary_label.setText(f"图件数据完整性检查失败：{exc}")
            self.provenance_summary_label.setStyleSheet("color: #a33; font-weight: 600;")
        disclosable_module_keys = {
            item.key
            for item in summary.modules
            if str(item.status or "").strip().casefold()
            in DISCLOSABLE_MODULE_STATUSES
            and str(item.message or "").strip()
        }
        hard_failed = tuple(
            item
            for item in summary.failed_modules
            if item.key not in disclosable_module_keys
        )
        modules_requiring_provenance = {
            key for key in selected if key not in disclosable_module_keys
        }
        provenance_ready = bool(
            self.current_provenance is not None
            and self.current_provenance.failed_count == 0
            and (self.current_provenance.rows or not modules_requiring_provenance)
        )
        self._refresh_disclosure_table()
        self.approval_check.setEnabled(
            summary.status.lower() in SUCCESS_STATES
            and not hard_failed
            and not self.current_manifest_missing_selected
            and bool(selected)
            and provenance_ready
        )
        self._refresh_report_condition_buttons()
        if hard_failed or self.current_manifest_missing_selected or (
            self.current_provenance is not None and self.current_provenance.failed_count
        ):
            self.approval_check.setChecked(False)
        self._update_report_gate()
        return True

    def _refresh_disclosure_table(self) -> None:
        context = self.current_context
        if self.current_manifest is None or self.current_provenance is None:
            self.current_disclosure_items = ()
        else:
            discovered = analysis_disclosure_items(
                self.current_manifest,
                self.current_provenance,
            )
            report_type = self.current_context.report.report_type if self.current_context else ""
            analysis_items = tuple(
                item
                for item in discovered
                if disclosure_supported_for_report(report_type, item)
            )
            report_items: list[DisclosureItem] = []
            if self.current_context is not None:
                for raw in self.current_context.report.report_build_disclosure_candidates:
                    if not isinstance(raw, dict):
                        continue
                    try:
                        report_items.append(
                            DisclosureItem(**{
                                name: str(raw.get(name) or "")
                                for name in DisclosureItem.__dataclass_fields__
                            })
                        )
                    except TypeError:
                        continue
            self.current_disclosure_items = (*analysis_items, *report_items)
        self.disclosure_table.blockSignals(True)
        try:
            self.disclosure_table.setRowCount(len(self.current_disclosure_items))
            confirmed_ids: set[str] = set()
            if context is not None:
                missing, stale = validate_confirmations(
                    self.current_disclosure_items,
                    context.report.disclosure_confirmations,
                    analysis_manifest_sha256=context.analysis.manifest_sha256,
                    policy_version=context.report.disclosure_policy_version,
                )
                if (
                    not stale
                    and context.report.disclosure_manifest_sha256.upper()
                    == context.analysis.manifest_sha256.upper()
                ):
                    confirmed_ids = {
                        item.stable_id
                        for item in self.current_disclosure_items
                        if item.stable_id not in missing
                    }
            reason_labels = {
                "incomplete_source_coverage": "设备断采/来源不完整",
                "no_valid_data": "本期无有效数据",
                "not_applicable": "模块明确不适用",
                "report_type_omission_allowed": "报告类型允许省略",
            }
            for row, disclosure in enumerate(self.current_disclosure_items):
                check_item = self.disclosure_table.set_copyable_item(
                    row,
                    0,
                    "已确认" if disclosure.stable_id in confirmed_ids else "待确认",
                    user_data=disclosure.stable_id,
                )
                check_item.setFlags(
                    check_item.flags()
                    | Qt.ItemIsUserCheckable
                    | Qt.ItemIsEnabled
                    | Qt.ItemIsSelectable
                )
                check_item.setCheckState(
                    Qt.Checked if disclosure.stable_id in confirmed_ids else Qt.Unchecked
                )
                values = (
                    reason_labels.get(disclosure.reason_code, disclosure.reason_code),
                    disclosure.label,
                    disclosure.reason_zh,
                    disclosure.action_zh,
                    disclosure.source_path,
                )
                for column, value in enumerate(values, start=1):
                    self.disclosure_table.set_copyable_item(
                        row,
                        column,
                        value,
                        path=value if column == 5 and str(value).strip() else None,
                    )
                self.disclosure_table.set_row_flags(row, gap=True)
        finally:
            self.disclosure_table.blockSignals(False)
        total = len(self.current_disclosure_items)
        self._refresh_report_condition_buttons()
        confirmed = sum(
            self.disclosure_table.item(row, 0) is not None
            and self.disclosure_table.item(row, 0).checkState() == Qt.Checked
            for row in range(total)
        )
        if total:
            self.disclosure_summary_label.setText(
                f"黄色可披露缺项：{total}项；已逐项确认：{confirmed}项。"
                "确认仅绑定当前分析清单 SHA，清单变化后自动失效。"
            )
            self.disclosure_summary_label.setStyleSheet(
                "color: #946200; font-weight: 600;"
            )
        else:
            self.disclosure_summary_label.setText(
                "当前分析结果没有需要逐项确认的黄色缺项。"
            )
            self.disclosure_summary_label.setStyleSheet("color: #167c35;")

    def _refresh_report_condition_buttons(self) -> None:
        if not hasattr(self, "disclosure_select_all_btn"):
            return
        available = bool(
            (hasattr(self, "approval_check") and self.approval_check.isEnabled())
            or self.current_disclosure_items
        )
        self.disclosure_select_all_btn.setEnabled(available)
        self.disclosure_clear_all_btn.setEnabled(available)

    def _set_all_report_conditions(self, state: Qt.CheckState) -> None:
        """Apply one explicit bulk choice without bypassing hard blockers."""

        if self.current_context is None:
            return
        checked = state == Qt.Checked
        if self.approval_check.isEnabled():
            blocked = self.approval_check.blockSignals(True)
            self.approval_check.setChecked(checked)
            self.approval_check.blockSignals(blocked)
            self.current_context.report.plots_approved = checked
        first_item = None
        self.disclosure_table.blockSignals(True)
        try:
            for row in range(self.disclosure_table.rowCount()):
                item = self.disclosure_table.item(row, 0)
                if item is None:
                    continue
                item.setCheckState(state)
                if first_item is None:
                    first_item = item
        finally:
            self.disclosure_table.blockSignals(False)
        if first_item is not None:
            self._on_disclosure_item_changed(first_item)
            return
        if not persist_report_state(self.current_context):
            self._append_log(
                "任务方案已被其他窗口更新，本次报告条件全选未保存；请重新打开任务。"
            )
        self._invalidate_report_gate_cache()
        self._update_report_gate()

    def _on_disclosure_item_changed(self, item) -> None:
        if item.column() != 0 or self.current_context is None:
            return
        context = self.current_context
        by_id = {entry.stable_id: entry for entry in self.current_disclosure_items}
        confirmations: list[dict[str, object]] = []
        self.disclosure_table.blockSignals(True)
        try:
            for row in range(self.disclosure_table.rowCount()):
                check_item = self.disclosure_table.item(row, 0)
                if check_item is None:
                    continue
                checked = check_item.checkState() == Qt.Checked
                check_item.setText("已确认" if checked else "待确认")
                stable_id = str(check_item.data(Qt.UserRole) or "")
                disclosure = by_id.get(stable_id)
                if checked and disclosure is not None:
                    confirmations.append(
                        confirmation_record(
                            disclosure,
                            analysis_manifest_sha256=context.analysis.manifest_sha256,
                        )
                    )
        finally:
            self.disclosure_table.blockSignals(False)
        context.report.disclosure_manifest_sha256 = context.analysis.manifest_sha256
        context.report.disclosure_policy_version = DISCLOSURE_POLICY_VERSION
        context.report.disclosure_confirmations = confirmations
        if not persist_report_state(context):
            self._append_log(
                "任务方案已被其他窗口更新，本次黄色缺项确认未保存；请重新打开任务。"
            )
        self._refresh_disclosure_table()
        self._update_report_gate()

    def _reset_review_state(self, *, clear_context_approval: bool = True) -> None:
        self._invalidate_report_gate_cache()
        if clear_context_approval and self.current_context is not None:
            context = self.current_context
            changed = context.report.plots_approved
            context.report.plots_approved = False
            if context.report.disclosure_confirmations:
                changed = True
            invalidate_disclosure_approval(context.report)
            if context.report.state.lower() not in {"launched", "running"}:
                changed = changed or context.report.state.lower() != "blocked"
                context.report.state = "blocked"
            persisted_path = self.current_context_path or context.context_path
            if changed and persisted_path.is_file():
                if not persist_report_state(context):
                    self._append_log(
                        "任务方案已被其他窗口更新，未覆盖其图件审核状态；请重新打开任务。"
                    )
        self.current_manifest = None
        self.current_provenance = None
        self.current_disclosure_items = ()
        self.current_manifest_missing_selected = ()
        self.approval_check.blockSignals(True)
        self.approval_check.setChecked(False)
        self.approval_check.setEnabled(False)
        self.approval_check.blockSignals(False)
        self.module_table.setRowCount(0)
        self.manifest_label.setText("分析结果清单：未加载")
        self.manifest_summary_label.setText("等待分析完成。")
        self.provenance_table.setRowCount(0)
        self.provenance_summary_label.setText("等待加载分析结果清单。")
        self.provenance_summary_label.setStyleSheet("")
        self.disclosure_table.blockSignals(True)
        self.disclosure_table.setRowCount(0)
        self.disclosure_table.blockSignals(False)
        self.disclosure_select_all_btn.setEnabled(False)
        self.disclosure_clear_all_btn.setEnabled(False)
        self.disclosure_summary_label.setText("当前分析结果没有需要逐项确认的黄色缺项。")
        self._update_report_gate()

    def _on_approval_changed(self) -> None:
        if self.current_context is None:
            self.approval_check.setChecked(False)
            return
        self.current_context.report.plots_approved = self.approval_check.isChecked()
        self.current_context.report.state = "ready" if self.current_context.report_ready else "blocked"
        if not persist_report_state(self.current_context):
            self.approval_check.blockSignals(True)
            self.approval_check.setChecked(
                bool(self.current_context.report.plots_approved)
            )
            self.approval_check.blockSignals(False)
            self._append_log(
                "任务方案已被其他窗口更新，本次审核状态未保存；请重新打开任务。"
            )
        self._update_report_gate()

    def _update_report_gate(self, *, force_audit: bool = False) -> None:
        audit = self._current_report_gate_audit(force=force_audit)
        ready = bool(audit is not None and audit.passed)
        running = bool(
            self.current_context
            and (
                self.current_context.report.pid is not None
                or self.current_context.report.state.lower()
                in {"launching", "launched", "running", "stopping"}
            )
        )
        self.open_report_btn.setEnabled(ready and not running)
        if ready:
            disclosure_count = len(audit.disclosure_items) if audit is not None else 0
            self.report_gate_label.setText(
                "报告任务运行中。"
                if running
                else (
                    f"已满足报告生成条件：{disclosure_count}项黄色缺项已逐项确认，"
                    "将生成缺项披露版正式报告。"
                    if disclosure_count
                    else "已满足报告生成条件：分析结果和图件数据均已检查。"
                )
            )
            self.report_gate_label.setStyleSheet(
                "color: #946200; font-weight: 600;"
                if disclosure_count
                else "color: #167c35; font-weight: 600;"
            )
        else:
            details = ""
            if audit is not None and audit.issues:
                details = "\n" + "；".join(audit.issues[:3])
            self.report_gate_label.setText(
                "尚不能生成报告：请先完成分析结果检查、图件审核和黄色缺项逐项确认。"
                + details
            )
            self.report_gate_label.setStyleSheet("color: #a33; font-weight: 600;")

    @staticmethod
    def _report_gate_file_signature(raw_path: str) -> tuple[object, ...]:
        text = str(raw_path or "").strip()
        if not text:
            return ("", 0, 0)
        path = Path(text).expanduser().resolve(strict=False)
        try:
            stat = path.stat()
        except OSError:
            return (str(path), -1, -1)
        return (str(path), stat.st_size, stat.st_mtime_ns)

    def _report_gate_cache_key(self) -> tuple[object, ...]:
        context = self.current_context
        if context is None:
            return ()
        confirmations = tuple(
            sorted(
                (
                    str(raw.get("stable_id") or ""),
                    str(raw.get("analysis_manifest_sha256") or ""),
                    str(raw.get("policy_version") or ""),
                )
                for raw in context.report.disclosure_confirmations
                if isinstance(raw, dict)
            )
        )
        template_path = (
            self.template_edit.text().strip()
            if hasattr(self, "template_edit")
            else context.report.template_path
        )
        try:
            live_config_sha = config_dependency_sha256(
                Path(context.config_path).expanduser()
            )
        except Exception:  # noqa: BLE001 - cache keys must never break UI polling
            live_config_sha = "<配置依赖无法读取>"
        provenance_signatures = tuple(
            self._report_gate_file_signature(str(row.path))
            for row in getattr(self.current_provenance, "rows", ())
        )
        report_build_candidates = tuple(
            json.dumps(raw, ensure_ascii=False, sort_keys=True, default=str)
            for raw in context.report.report_build_disclosure_candidates
            if isinstance(raw, dict)
        )
        return (
            id(context),
            context.analysis.state,
            context.analysis.manifest_sha256,
            context.config_sha256,
            bool(context.report.plots_approved),
            context.report.disclosure_manifest_sha256,
            context.report.disclosure_policy_version,
            context.report.state,
            context.report.qc_state,
            confirmations,
            report_build_candidates,
            tuple(context.selected_modules),
            context.report.report_type,
            live_config_sha,
            self._report_gate_file_signature(context.config_path),
            self._report_gate_file_signature(template_path),
            self._report_gate_file_signature(context.analysis.manifest_path),
            provenance_signatures,
        )

    def _invalidate_report_gate_cache(self) -> None:
        self._report_gate_audit_cache = None
        self._report_gate_audit_signature = None

    def _on_report_gate_input_changed(self, *_args: object) -> None:
        self._invalidate_report_gate_cache()
        if hasattr(self, "open_report_btn"):
            self._update_report_gate()

    def _current_report_gate_audit(self, *, force: bool = False):
        if not (
            self.current_context
            and not self._analysis_context_superseded
            and not self._report_context_superseded
            and self.current_context.report.pid is None
            and self.approval_check.isChecked()
            and self._context_matches_current_inputs(self.current_context)
            and self.current_manifest is not None
            and self.current_provenance is not None
        ):
            self._invalidate_report_gate_cache()
            return None
        signature = self._report_gate_cache_key()
        if (
            not force
            and self._report_gate_audit_cache is not None
            and self._report_gate_audit_signature == signature
        ):
            return self._report_gate_audit_cache
        candidate = copy.deepcopy(self.current_context)
        if hasattr(self, "template_edit"):
            candidate.report.template_path = self.template_edit.text().strip()
            template = Path(candidate.report.template_path).expanduser()
            candidate.report.template_sha256 = (
                file_sha256(template) if template.is_file() else ""
            )
        audit = inspect_report_gate(candidate)
        self._report_gate_audit_cache = audit
        self._report_gate_audit_signature = signature
        return audit

    def _report_gate_ready(self) -> bool:
        audit = self._current_report_gate_audit(force=True)
        return bool(audit is not None and audit.passed)

    def _start_report_job(self) -> None:
        context = self.current_context
        if context is None or not self._report_gate_ready():
            QMessageBox.warning(self, "尚不能生成报告", "请先完成分析、加载有效的分析结果清单并审核图件。")
            return
        try:
            config_path = Path(context.config_path)
            if not config_path.is_file():
                raise FileNotFoundError(f"任务配置不存在：{config_path}")
            if config_dependency_sha256(config_path) != context.config_sha256.upper():
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
                raise FileNotFoundError(f"分析结果清单不存在：{manifest_path}")
            actual_manifest_hash = file_sha256(manifest_path)
            if context.analysis.manifest_sha256 != actual_manifest_hash:
                raise RuntimeError("分析结果清单在图件审核后发生变化，必须重新审核")
            require_report_gate(context)
            self.current_context_path = context.context_path
            launch = launch_report_job(
                context,
                self.current_context_path,
                runtime_root=self.project_root,
            )
            self.report_progress.setValue(0)
            self.report_progress_label.setText(f"launched；PID {launch.pid}")
            self.report_qc_table.setRowCount(0)
            self.open_report_qc_btn.setEnabled(False)
            self.report_output_label.setText("DOCX/PDF：正在生成")
            self.stop_report_btn.setEnabled(True)
            self.open_report_btn.setEnabled(False)
            self.report_log.appendPlainText(
                f"[{datetime.now():%H:%M:%S}] 已启动嵌入式报告任务，PID={launch.pid}\n"
                f"状态：{launch.status_path}\n结果：{launch.result_path}"
            )
            self._append_log(f"已启动报告任务，PID={launch.pid}；任务方案={self.current_context_path}")
        except Exception as exc:  # noqa: BLE001
            self._show_exception("启动报告任务失败", exc)

    def _stop_report_job(self) -> None:
        if self.current_context is None:
            return
        try:
            outcome = terminate_report_job(self.current_context)
            self.stop_report_btn.setEnabled(False)
            if outcome == "stopped":
                self.report_progress_label.setText("已停止；报告后台主任务已退出")
                message = "已停止报告后台主任务"
            elif outcome.endswith("_cleanup_pending"):
                state = outcome.removesuffix("_cleanup_pending")
                self.report_progress_label.setText(
                    f"{operator_state_label(state)}；结果已发布，后台正在退出清理"
                )
                message = "报告结果已先完成，正在等待后台退出清理"
            else:
                self.report_progress_label.setText(operator_state_label(outcome))
                message = f"报告任务已是{operator_state_label(outcome)}状态"
            self.report_log.appendPlainText(
                f"[{datetime.now():%H:%M:%S}] {message}"
            )
        except Exception as exc:  # noqa: BLE001
            self._show_exception("停止报告任务失败", exc)

    def _open_output_dir(self) -> None:
        path = Path(self.output_dir_edit.text().strip()).expanduser()
        path.mkdir(parents=True, exist_ok=True)
        if os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(path.resolve())))

    def _open_report_qc_dir(self) -> None:
        context = self.current_context
        if context is None or not context.report.visual_qc_dir:
            return
        path = Path(context.report.visual_qc_dir).expanduser()
        if not path.is_dir():
            QMessageBox.warning(self, "逐页版面检查结果不存在", str(path))
            return
        if os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(path.resolve())))

    def _browse_data_root(self) -> None:
        value = QFileDialog.getExistingDirectory(
            self,
            "选择数据根目录",
            self.data_root_edit.text() or str(self.project_root),
        )
        if not value:
            return
        _set_line_edit_path(self.data_root_edit, value)
        if hasattr(self, "current_profile"):
            self.custom_data_roots[self.current_profile.bridge_id] = value
            custom_index = self.path_profile_combo.findData(PathProfileResolver.CUSTOM_ID)
            if custom_index >= 0:
                self.path_profile_combo.setCurrentIndex(custom_index)

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
                self.cleaning_editor.load_path(path)
                self.post_filter_editor.load_path(path)
                self.offset_editor.load_path(path)
                self.group_plot_editor.load_path(path)
                self.plot_common_editor.load_path(path)
                self.spectrum_editor.load_path(path)
                self.unzip_settings_editor.load_path(path)
            except Exception as exc:  # noqa: BLE001
                self._show_exception("加载高级配置失败", exc)

    def _on_config_saved(self, editor_label: str, path: str, sha256: str, backup: str) -> None:
        saved_path = Path(path).resolve()
        selected_path = Path(self.config_edit.text().strip()).expanduser().resolve()
        if saved_path == selected_path:
            self.current_context = None
            self.current_context_path = None
            self._reset_review_state()
            self.analysis_status_label.setText("状态：配置已修改，请重新保存任务方案")
            self._append_log(
                f"{editor_label}配置已保存；SHA256={sha256[:16]}…；备份={backup}。"
                "旧任务方案已失效。"
            )
            for editor in (
                self.alarm_editor,
                self.cleaning_editor,
                self.post_filter_editor,
                self.offset_editor,
                self.group_plot_editor,
                self.plot_common_editor,
                self.spectrum_editor,
                self.unzip_settings_editor,
            ):
                try:
                    editor.load_path(saved_path)
                except Exception as exc:  # noqa: BLE001
                    self._append_log(f"配置编辑器重新加载失败：{exc}")

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
