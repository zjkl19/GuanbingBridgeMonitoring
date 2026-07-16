from __future__ import annotations

import copy
from datetime import datetime
from pathlib import Path
from typing import Callable, Mapping

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QDialog,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QInputDialog,
    QMessageBox,
    QPushButton,
    QTabWidget,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .config_editor import (
    AlarmBoundRow,
    CleaningConfigEditorSession,
    CleaningThresholdRow,
    ConfigEditorError,
    ConfigEditorSession,
    EffectiveWarningRow,
    ExcludeRangeRow,
    PostFilterConfigEditorSession,
    apply_alarm_bounds,
    extract_alarm_bounds,
    extract_effective_warning_rows,
    update_effective_warning_value,
    warning_edit_value,
)
from .manual_threshold import (
    LOWER_SIDE,
    UPPER_SIDE,
    apply_one_sided_to_selected_row,
    accepted_point_ids,
    merge_two_sided_rule,
)
from .box_threshold_dialog import BoxThresholdDialog
from .manual_threshold_dialog import ThresholdBandDialog
from .threshold_preview import find_matching_threshold_preview, preview_query


WARNING_SOURCE_LABELS = {
    "alarm_bounds": "测点上下限",
    "force_alarm_bounds": "索力上下限",
    "alarm_levels": "分级预警值",
    "warn_lines": "时程图参考线",
    "rms_warn_lines": "RMS图参考线",
    "group_warn_lines": "组图参考线",
}

WARNING_STATUS_LABELS = {
    "configured": "有效",
    "unset": "未设置",
    "invalid": "格式错误",
}

WARNING_SCOPE_LABELS = {
    "defaults": "模块默认",
    "per_point": "测点覆盖",
    "global": "全局参数",
    "plot_styles": "绘图参数",
}

WARNING_MODULE_LABELS = {
    "acceleration": "主梁/主塔加速度",
    "cable_accel": "吊索加速度/索力",
    "deflection": "挠度",
    "bearing_displacement": "支座/伸缩缝位移",
    "crack": "裂缝",
    "gnss": "GNSS位移",
    "strain": "应变",
    "dynamic_strain": "动应变（高通）",
    "dynamic_strain_lowpass": "动应变（低通）",
    "tilt": "倾角",
    "wind": "风速",
    "wind_speed": "风速",
    "wind_direction": "风向",
    "earthquake": "地震动",
    "eq": "地震动",
    "temperature": "温度",
    "humidity": "湿度",
    "rainfall": "雨量",
}

CONFIG_SCOPE_LABELS = {
    "defaults": "模块默认",
    "per_point": "测点专用",
}
CONFIG_SCOPE_KEYS = {label: key for key, label in CONFIG_SCOPE_LABELS.items()}

_LEVEL_LABELS = {
    "level1": "一级",
    "level2": "二级",
    "level3": "三级",
    "level4": "四级",
    "level5": "五级",
}
_LEVEL_KEYS = {label: key for key, label in _LEVEL_LABELS.items()}
_MODULE_KEYS_BY_LABEL: dict[str, str] = {}
for _module_key, _module_label_text in WARNING_MODULE_LABELS.items():
    _MODULE_KEYS_BY_LABEL.setdefault(_module_label_text, _module_key)


def _config_scope_label(value: str) -> str:
    return CONFIG_SCOPE_LABELS.get(value, value)


def _config_scope_key(value: str) -> str:
    return CONFIG_SCOPE_KEYS.get(value, value)


def _module_label(value: str) -> str:
    return WARNING_MODULE_LABELS.get(value, value)


def _level_label(value: str) -> str:
    if value in _LEVEL_LABELS:
        return _LEVEL_LABELS[value]
    if value.startswith("line") and value[4:].isdigit():
        return f"参考线{value[4:]}"
    return value


def _stored_or_edited_value(
    item: QTableWidgetItem | None,
    *,
    labeler: Callable[[str], str],
    reverse: dict[str, str] | None = None,
) -> str:
    if item is None:
        return ""
    text = item.text().strip()
    stored = item.data(Qt.UserRole)
    if stored is not None and text == labeler(str(stored)):
        return str(stored)
    return (reverse or {}).get(text, text)


def _warning_location_label(row: EffectiveWarningRow) -> str:
    module = _module_label(row.module_key)
    target = row.target_key or WARNING_SCOPE_LABELS.get(row.scope, "默认")
    detail = _level_label(row.level) if row.level else WARNING_SOURCE_LABELS.get(
        row.source_kind, "预警配置"
    )
    return f"{module} / {target} / {detail}"


class AlarmBoundsEditorWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: ConfigEditorSession | None = None
        self.working_payload: dict = {}
        self.effective_rows: list[EffectiveWarningRow] = []
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("有效预警值总览与上下限配置")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "“有效值总览”完整列出当前配置中的测点上下限、索力上下限、风/地震分级值及各类图上参考线，"
            "并保留各自来源和用途，绝不把不同含义的配置自动互转。“双边上下限”页只修改"
            "模块默认或测点专属的成对上下限；覆盖保存前校验文件版本并自动备份。"
        )
        hint.setWordWrap(True)
        outer.addWidget(hint)

        path_row = QHBoxLayout()
        self.path_label = QLabel("配置：尚未加载")
        self.path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        path_row.addWidget(self.path_label, 1)
        reload_button = QPushButton("重新加载")
        reload_button.clicked.connect(self._reload)
        path_row.addWidget(reload_button)
        validate_button = QPushButton("复核全部来源")
        validate_button.clicked.connect(self._validate_all_dialog)
        path_row.addWidget(validate_button)
        outer.addLayout(path_row)

        self.inner_tabs = QTabWidget()
        overview_page = QWidget()
        overview_layout = QVBoxLayout(overview_page)
        self.overview_summary_label = QLabel("尚未加载有效预警值。")
        self.overview_summary_label.setWordWrap(True)
        self.overview_summary_label.setStyleSheet(
            "background: #eef6ff; border: 1px solid #b8d8f4; border-radius: 4px; padding: 7px;"
        )
        overview_layout.addWidget(self.overview_summary_label)

        filters = QHBoxLayout()
        filters.addWidget(QLabel("来源"))
        self.source_filter = QComboBox()
        self.source_filter.addItem("全部来源", "")
        self.source_filter.currentIndexChanged.connect(self._apply_effective_filters)
        filters.addWidget(self.source_filter)
        filters.addWidget(QLabel("状态"))
        self.status_filter = QComboBox()
        self.status_filter.addItem("全部状态", "")
        for key in ("configured", "unset", "invalid"):
            self.status_filter.addItem(WARNING_STATUS_LABELS[key], key)
        self.status_filter.currentIndexChanged.connect(self._apply_effective_filters)
        filters.addWidget(self.status_filter)
        filters.addWidget(QLabel("搜索"))
        self.warning_search = QLineEdit()
        self.warning_search.setPlaceholderText("分析类型、测点、等级、数值或来源")
        self.warning_search.setClearButtonEnabled(True)
        self.warning_search.textChanged.connect(self._apply_effective_filters)
        filters.addWidget(self.warning_search, 1)
        self.effective_count_label = QLabel("0 条")
        filters.addWidget(self.effective_count_label)
        overview_layout.addLayout(filters)

        self.effective_table = QTableWidget(0, 10)
        self.effective_table.setHorizontalHeaderLabels(
            ["来源", "范围", "分析类型", "测点/分组", "等级/标签", "配置值", "单位", "用途", "状态", "来源说明"]
        )
        self.effective_table.horizontalHeaderItem(9).setToolTip(
            "按分析类型、测点和等级说明该预警值来自哪里"
        )
        self.effective_table.setAlternatingRowColors(True)
        self.effective_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.effective_table.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.effective_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        self.effective_table.itemDoubleClicked.connect(
            lambda _item: self._edit_selected_effective_value()
        )
        effective_header = self.effective_table.horizontalHeader()
        effective_header.setSectionResizeMode(QHeaderView.ResizeToContents)
        effective_header.setSectionResizeMode(3, QHeaderView.Stretch)
        effective_header.setSectionResizeMode(7, QHeaderView.Stretch)
        effective_header.setSectionResizeMode(9, QHeaderView.Stretch)
        overview_layout.addWidget(self.effective_table, 1)
        overview_actions = QHBoxLayout()
        self.edit_effective_button = QPushButton("编辑选中预警值…")
        self.edit_effective_button.setToolTip(
            "按原有来源修改选中值：上下限仍是上下限，分级值仍是分级值，图上参考线仍是参考线"
        )
        self.edit_effective_button.clicked.connect(self._edit_selected_effective_value)
        overview_actions.addWidget(self.edit_effective_button)
        revert_effective = QPushButton("撤销未保存修改")
        revert_effective.clicked.connect(self._discard_warning_edits)
        overview_actions.addWidget(revert_effective)
        overview_actions.addStretch(1)
        save_overview_copy = QPushButton("保存副本…")
        save_overview_copy.clicked.connect(self._save_copy)
        overview_actions.addWidget(save_overview_copy)
        save_overview = QPushButton("保存全部预警修改（自动备份）")
        save_overview.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 6px 12px;"
        )
        save_overview.clicked.connect(self._save_source)
        overview_actions.addWidget(save_overview)
        overview_layout.addLayout(overview_actions)
        overview_hint = QLabel(
            "说明：图上参考线只影响图件表达；分级预警值是单边等级；测点/索力上下限才是成对的下限和上限。"
            "“未设置”表示字段存在但为空，“格式错误”必须修复后才能作为有效预警依据。"
            "双击任一有效行或点击“编辑选中预警值”可在原来源中修改，不会把不同含义的值互相转换。"
        )
        overview_hint.setWordWrap(True)
        overview_hint.setStyleSheet("color: #5f6368;")
        overview_layout.addWidget(overview_hint)
        self.inner_tabs.addTab(overview_page, "有效值总览")

        explicit_page = QWidget()
        explicit_layout = QVBoxLayout(explicit_page)
        explicit_hint = QLabel(
            "本页只编辑成对的下限/上限规则；未配置时不代表项目没有预警值。"
            "规则可作用于整个分析类型或单个测点，等级使用一级、二级、三级等；"
            "上下限必须为有限数值且上限大于下限。"
        )
        explicit_hint.setWordWrap(True)
        explicit_layout.addWidget(explicit_hint)
        self.empty_bounds_label = QLabel()
        self.empty_bounds_label.setAlignment(Qt.AlignCenter)
        self.empty_bounds_label.setWordWrap(True)
        self.empty_bounds_label.setMinimumHeight(150)
        self.empty_bounds_label.setStyleSheet(
            "background: #eef6ff; border: 1px solid #b8d8f4; border-radius: 6px; "
            "color: #174a75; font-size: 15px; padding: 24px;"
        )
        explicit_layout.addWidget(self.empty_bounds_label, 1)
        self.table = QTableWidget(0, 6)
        self.table.setHorizontalHeaderLabels(
            ["适用范围", "分析类型", "测点编号", "等级", "下限", "上限"]
        )
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.ExtendedSelection)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.Stretch)
        header.setSectionResizeMode(3, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(5, QHeaderView.ResizeToContents)
        explicit_layout.addWidget(self.table, 1)

        actions = QHBoxLayout()
        validate_explicit = QPushButton("校验上下限表格")
        validate_explicit.clicked.connect(self._validate_dialog)
        actions.addWidget(validate_explicit)
        add_default = QPushButton("新增模块默认上下限")
        add_default.clicked.connect(lambda: self.add_row("defaults"))
        actions.addWidget(add_default)
        add_point = QPushButton("新增测点上下限")
        add_point.clicked.connect(lambda: self.add_row("per_point"))
        actions.addWidget(add_point)
        delete_button = QPushButton("删除选中行")
        delete_button.clicked.connect(self.delete_selected_rows)
        actions.addWidget(delete_button)
        actions.addStretch(1)
        self.count_label = QLabel("尚未配置双边上下限")
        actions.addWidget(self.count_label)
        save_copy = QPushButton("保存副本…")
        save_copy.clicked.connect(self._save_copy)
        actions.addWidget(save_copy)
        save_source = QPushButton("覆盖保存（自动备份）")
        save_source.setStyleSheet("font-weight: 700; background: #005eac; color: white; padding: 6px 12px;")
        save_source.clicked.connect(self._save_source)
        actions.addWidget(save_source)
        explicit_layout.addLayout(actions)
        self.inner_tabs.addTab(explicit_page, "双边上下限（未配置）")
        outer.addWidget(self.inner_tabs, 1)

        self.message_label = QLabel("尚未加载配置。")
        self.message_label.setWordWrap(True)
        self.message_label.setStyleSheet("color: #6b7280;")
        outer.addWidget(self.message_label)

    def load_path(self, path: Path) -> None:
        session = ConfigEditorSession(path)
        self.session = session
        self.working_payload = copy.deepcopy(session.payload)
        self.path_label.setText(f"配置：{session.path}")
        self._populate(session.rows)
        self._populate_effective(session.effective_warning_rows)
        self._refresh_explicit_state()
        configured = sum(row.status == "configured" for row in self.effective_rows)
        unset = sum(row.status == "unset" for row in self.effective_rows)
        invalid = sum(row.status == "invalid" for row in self.effective_rows)
        self.message_label.setText(
            f"已加载；配置版本校验码={session.loaded_sha256[:16]}…。"
            f"有效值 {configured} 条，未设置 {unset} 条，格式错误 {invalid} 条；"
            f"双边上下限 {len(session.rows)} 条。"
        )
        self.message_label.setStyleSheet("color: #b42318; font-weight: 600;" if invalid else "color: #167c35;")

    def _reload(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法重新加载", "尚未选择配置文件。")
            return
        try:
            self.load_path(self.session.path)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "重新加载失败", str(exc))

    def _populate(self, rows: list[AlarmBoundRow]) -> None:
        self.table.setRowCount(0)
        for row in rows:
            self._append_row(row)
        self._refresh_explicit_state()

    def _refresh_explicit_state(self) -> None:
        count = self.table.rowCount()
        has_rows = count > 0
        self.table.setVisible(has_rows)
        self.empty_bounds_label.setVisible(not has_rows)
        if has_rows:
            self.count_label.setText(f"{count} 条双边上下限")
            self.inner_tabs.setTabText(1, f"双边上下限（{count} 条）")
            return
        configured = sum(row.status == "configured" for row in self.effective_rows)
        self.count_label.setText("尚未配置双边上下限")
        self.inner_tabs.setTabText(1, "双边上下限（未配置）")
        self.empty_bounds_label.setText(
            "<b>本项目未配置双边上下限规则，这不是加载失败。</b><br><br>"
            f"当前配置仍有 {configured} 条有效的分级预警值或图上参考线，可在“有效值总览”查看。"
            "这些值与双边上下限含义不同，程序不会自动转换。<br><br>"
            "如项目标准确实要求新增双边上下限，请使用下方“新增模块默认上下限”或“新增测点上下限”，"
            "并在覆盖保存前核对正式预警标准。"
        )

    def _populate_effective(self, rows: list[EffectiveWarningRow]) -> None:
        self.effective_rows = list(rows)
        selected_source = self.source_filter.currentData()
        self.source_filter.blockSignals(True)
        self.source_filter.clear()
        self.source_filter.addItem("全部来源", "")
        for source_kind in sorted(
            {row.source_kind for row in rows}, key=lambda key: WARNING_SOURCE_LABELS.get(key, key)
        ):
            self.source_filter.addItem(WARNING_SOURCE_LABELS.get(source_kind, source_kind), source_kind)
        index = self.source_filter.findData(selected_source)
        self.source_filter.setCurrentIndex(max(0, index))
        self.source_filter.blockSignals(False)

        configured = sum(row.status == "configured" for row in rows)
        unset = sum(row.status == "unset" for row in rows)
        invalid = sum(row.status == "invalid" for row in rows)
        explicit = sum(row.source_kind == "alarm_bounds" for row in rows)
        summary = (
            f"检测到 {configured} 条有效预警/参考值；{unset} 条字段已存在但未设置；"
            f"{invalid} 条格式错误。双边上下限为 {explicit} 条。"
        )
        if explicit == 0 and configured:
            summary += " 当前桥梁未配置双边上下限；其它预警值和参考线已在下表按来源展示。"
        elif not rows:
            summary = "当前配置未检测到任何受支持的预警来源；请核对配置或补充明确的预警配置。"
        self.overview_summary_label.setText(summary)
        self.overview_summary_label.setStyleSheet(
            (
                "background: #fff2f0; border: 1px solid #ffccc7; color: #b42318;"
                if invalid
                else "background: #eef6ff; border: 1px solid #b8d8f4; color: #174a75;"
            )
            + " border-radius: 4px; padding: 7px;"
        )
        self._apply_effective_filters()

    def _selected_effective_row(self) -> EffectiveWarningRow:
        selected = self.effective_table.currentRow()
        if selected < 0:
            raise ConfigEditorError("请先在有效值总览中选择一行")
        path_item = self.effective_table.item(selected, 9)
        config_path = str(path_item.data(Qt.UserRole) or "") if path_item else ""
        matches = [row for row in self.effective_rows if row.config_path == config_path]
        if len(matches) != 1:
            raise ConfigEditorError("无法唯一定位选中的配置值，请重新加载后再试")
        if matches[0].status == "invalid":
            raise ConfigEditorError("该行当前格式错误，请先在配置文件中修复结构后再编辑")
        if matches[0].status == "unset":
            raise ConfigEditorError(
                "该来源目前是空集合，尚无可定位的等级或图线。为避免猜测语义，本页只直接编辑已有值；"
                "双边上下限可在相邻页新增，其它来源请先按项目制度明确等级或标签。"
            )
        return matches[0]

    def _edit_selected_effective_value(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法编辑", "尚未加载配置文件。")
            return
        try:
            row = self._selected_effective_row()
            current = warning_edit_value(self.working_payload, row)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.warning(self, "无法编辑", str(exc))
            return
        if row.source_kind in {"alarm_bounds", "force_alarm_bounds"}:
            prompt = "填写“下限, 上限”；留空表示该等级未设置。"
        elif row.source_kind == "alarm_levels":
            prompt = "填写单个分级预警值；各等级必须保持从小到大。"
        else:
            prompt = "填写单个图上参考值；原有标签、单位、颜色和线型保持不变。"
        value, accepted = QInputDialog.getText(
            self,
            f"编辑{WARNING_SOURCE_LABELS.get(row.source_kind, row.source_kind)}",
            f"{_module_label(row.module_key)} / {row.target_key or '默认'} / "
            f"{_level_label(row.level) or '当前值'}\n{prompt}\n"
            f"来源：{_warning_location_label(row)}",
            text=current,
        )
        if not accepted:
            return
        try:
            self.working_payload = update_effective_warning_value(
                self.working_payload, row, value
            )
            self._populate(extract_alarm_bounds(self.working_payload))
            self._populate_effective(extract_effective_warning_rows(self.working_payload))
            self.message_label.setText(
                "预警值已在工作区修改，尚未写入配置文件；请复核后点击“保存全部预警修改”。"
            )
            self.message_label.setStyleSheet("color: #a65a00; font-weight: 600;")
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "预警值修改失败", str(exc))

    def _discard_warning_edits(self) -> None:
        if self.session is None:
            return
        self.working_payload = copy.deepcopy(self.session.payload)
        self._populate(extract_alarm_bounds(self.working_payload))
        self._populate_effective(extract_effective_warning_rows(self.working_payload))
        self.message_label.setText("已撤销未保存的预警修改。")
        self.message_label.setStyleSheet("color: #167c35;")

    def _apply_effective_filters(self, *_args: object) -> None:
        source = str(self.source_filter.currentData() or "")
        status = str(self.status_filter.currentData() or "")
        query = self.warning_search.text().strip().casefold()
        visible = []
        for row in self.effective_rows:
            if source and row.source_kind != source:
                continue
            if status and row.status != status:
                continue
            haystack = " ".join(
                (
                    row.source_kind,
                    WARNING_SOURCE_LABELS.get(row.source_kind, ""),
                    row.scope,
                    row.module_key,
                    row.target_key,
                    row.level,
                    row.value_text,
                    row.unit,
                    row.purpose,
                    row.config_path,
                    WARNING_STATUS_LABELS.get(row.status, row.status),
                )
            ).casefold()
            if query and query not in haystack:
                continue
            visible.append(row)

        self.effective_table.setRowCount(0)
        for row in visible:
            index = self.effective_table.rowCount()
            self.effective_table.insertRow(index)
            values = (
                WARNING_SOURCE_LABELS.get(row.source_kind, row.source_kind),
                WARNING_SCOPE_LABELS.get(row.scope, row.scope),
                _module_label(row.module_key),
                row.target_key or "全局/默认",
                _level_label(row.level),
                row.value_text,
                row.unit,
                row.purpose,
                WARNING_STATUS_LABELS.get(row.status, row.status),
                _warning_location_label(row),
            )
            for column, value in enumerate(values):
                item = QTableWidgetItem(str(value))
                item.setToolTip(_warning_location_label(row))
                if column == 9:
                    item.setData(Qt.UserRole, row.config_path)
                if row.status == "invalid":
                    item.setForeground(Qt.red)
                elif row.status == "unset":
                    item.setForeground(Qt.darkYellow)
                self.effective_table.setItem(index, column, item)
        configured = sum(row.status == "configured" for row in self.effective_rows)
        self.effective_count_label.setText(
            f"显示 {len(visible)} / {len(self.effective_rows)}；有效 {configured}"
        )

    def _append_row(self, row: AlarmBoundRow) -> None:
        index = self.table.rowCount()
        self.table.insertRow(index)
        values = (
            _config_scope_label(row.scope),
            _module_label(row.module_key),
            row.point_key,
            _level_label(row.level),
            row.lower,
            row.upper,
        )
        for column, value in enumerate(values):
            item = QTableWidgetItem(str(value))
            if column == 0:
                item.setData(Qt.UserRole, row.scope)
            elif column == 1:
                item.setData(Qt.UserRole, row.module_key)
            elif column == 3:
                item.setData(Qt.UserRole, row.level)
            self.table.setItem(index, column, item)

    def add_row(self, scope: str) -> None:
        module_key = "acceleration"
        selected = self.table.currentRow()
        if selected >= 0 and self.table.item(selected, 1):
            module_key = _stored_or_edited_value(
                self.table.item(selected, 1),
                labeler=_module_label,
                reverse=_MODULE_KEYS_BY_LABEL,
            ) or module_key
        point_key = "POINT_ID" if scope == "per_point" else ""
        self._append_row(AlarmBoundRow(scope, module_key, point_key, "level1", 0.0, 1.0))
        row = self.table.rowCount() - 1
        self.table.selectRow(row)
        self.table.scrollToItem(self.table.item(row, 0))
        self._refresh_explicit_state()

    def delete_selected_rows(self) -> None:
        selected = sorted({index.row() for index in self.table.selectedIndexes()}, reverse=True)
        for row in selected:
            self.table.removeRow(row)
        self._refresh_explicit_state()

    def rows(self) -> list[AlarmBoundRow]:
        rows: list[AlarmBoundRow] = []
        for index in range(self.table.rowCount()):
            values = [self.table.item(index, column).text().strip() if self.table.item(index, column) else ""
                      for column in range(6)]
            try:
                values[0] = _stored_or_edited_value(
                    self.table.item(index, 0),
                    labeler=_config_scope_label,
                    reverse=CONFIG_SCOPE_KEYS,
                )
                values[1] = _stored_or_edited_value(
                    self.table.item(index, 1),
                    labeler=_module_label,
                    reverse=_MODULE_KEYS_BY_LABEL,
                )
                values[3] = _stored_or_edited_value(
                    self.table.item(index, 3),
                    labeler=_level_label,
                    reverse=_LEVEL_KEYS,
                )
                row = AlarmBoundRow(
                    values[0], values[1], values[2], values[3], float(values[4]), float(values[5])
                ).validated()
            except (ValueError, ConfigEditorError) as exc:
                raise ConfigEditorError(f"第 {index + 1} 行无效：{exc}") from exc
            rows.append(row)
        if self.session is not None:
            self.session.build_payload(rows)
        return rows

    def _validate_dialog(self) -> None:
        try:
            rows = self.rows()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "阈值校验失败", str(exc))
            return
        QMessageBox.information(self, "阈值校验通过", f"{len(rows)} 条显式预警配置均有效。")

    def _validate_all_dialog(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法复核", "尚未加载配置文件。")
            return
        invalid = [row for row in self.effective_rows if row.status == "invalid"]
        unset = [row for row in self.effective_rows if row.status == "unset"]
        configured = [row for row in self.effective_rows if row.status == "configured"]
        if invalid:
            details = "\n".join(_warning_location_label(row) for row in invalid[:12])
            QMessageBox.critical(
                self,
                "预警来源复核失败",
                f"发现 {len(invalid)} 条格式错误：\n{details}",
            )
            return
        QMessageBox.information(
            self,
            "预警来源复核通过",
            f"{len(configured)} 条有效预警/参考值格式正确；{len(unset)} 条字段明确未设置。\n"
            "不同来源保持原有语义，未发生自动转换。",
        )

    def _save_source(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        answer = QMessageBox.question(
            self,
            "确认覆盖配置",
            f"将覆盖：\n{self.session.path}\n\n保存前会自动备份原文件。是否继续？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer != QMessageBox.Yes:
            return
        self._save(target=None)

    def _save_copy(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        path, _ = QFileDialog.getSaveFileName(
            self,
            "保存配置副本",
            str(self.session.path.with_name(f"{self.session.path.stem}_workbench{self.session.path.suffix}")),
            "JSON files (*.json)",
        )
        if path:
            self._save(target=Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            updated = apply_alarm_bounds(self.working_payload, self.rows())
            result = self.session.save_payload(updated, target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存配置失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无（目标内容未变化或为新文件）"
        self.message_label.setText(
            f"保存完成：{result.path}；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.message_label.setStyleSheet("color: #167c35; font-weight: 600;")
        if target is None:
            self.working_payload = copy.deepcopy(self.session.payload)
            self._populate(extract_alarm_bounds(self.working_payload))
            self._populate_effective(extract_effective_warning_rows(self.working_payload))
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.message_label.text())


class CleaningThresholdEditorWidget(QWidget):
    config_saved = Signal(str, str, str)
    session_class = CleaningConfigEditorSession
    row_label = "清洗配置行"
    copy_suffix = "cleaning_workbench"
    editor_label = "清洗配置"
    managed_field_text = "显式清洗字段"
    add_default_text = "新增默认数值清洗规则"
    add_point_text = "新增测点数值清洗规则"
    supports_exclude_ranges = True
    supports_curve_threshold_tools = True
    threshold_band_dialog_class = ThresholdBandDialog
    box_threshold_dialog_class = BoxThresholdDialog

    def __init__(
        self,
        parent: QWidget | None = None,
        *,
        preview_context_provider: Callable[[], Mapping[str, object]] | None = None,
    ) -> None:
        super().__init__(parent)
        self.session: CleaningConfigEditorSession | None = None
        self.preview_context_provider = preview_context_provider
        self._manual_threshold_undo: (
            tuple[
                list[CleaningThresholdRow],
                int,
                list[CleaningThresholdRow],
            ]
            | None
        ) = None
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        self.title_label = QLabel("数据清洗阈值配置")
        self.title_label.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(self.title_label)
        self.hint_label = QLabel(
            "编辑模块默认或测点专用的数值清洗规则，包括上下限、零值转为空值和滑动窗口异常值剔除。"
            "下限或上限可单边填写；"
            "时间窗必须成对填写。需要将某个测点在一段时间内全部排除时，请使用“整段排除规则”页，"
            "明确填写起止时间和原因。保存不修改预警值、零点修正和其它配置。"
        )
        self.hint_label.setWordWrap(True)
        self.hint_label.setToolTip(
            "模块默认规则作用于该类全部测点；测点专用规则只作用于指定测点"
        )
        outer.addWidget(self.hint_label)

        path_row = QHBoxLayout()
        self.path_label = QLabel("配置：尚未加载")
        self.path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        path_row.addWidget(self.path_label, 1)
        reload_button = QPushButton("重新加载")
        reload_button.clicked.connect(self._reload)
        path_row.addWidget(reload_button)
        validate_button = QPushButton("校验表格")
        validate_button.clicked.connect(self._validate_dialog)
        path_row.addWidget(validate_button)
        outer.addLayout(path_row)

        self.table = QTableWidget(0, 10)
        self.table.setHorizontalHeaderLabels(
            [
                "适用范围",
                "分析类型",
                "测点编号",
                "下限",
                "上限",
                "开始时间",
                "结束时间",
                "零值转为空值",
                "异常检测窗口（秒）",
                "异常判定系数",
            ]
        )
        header_tooltips = {
            0: "选择规则作用于该分析类型全部测点，或仅作用于指定测点",
            1: "需要清洗的数据类型",
            2: "测点专用规则必须填写测点编号",
            3: "低于该值的数据将被清洗；留空表示不设置下限",
            4: "高于该值的数据将被清洗；留空表示不设置上限",
            7: "启用后，数值零将按无效值处理",
            8: "滑动异常检测使用的时间窗口，单位为秒",
            9: "数值越小，异常检测越敏感",
        }
        for column, tooltip in header_tooltips.items():
            self.table.horizontalHeaderItem(column).setToolTip(tooltip)
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.table.itemChanged.connect(self._invalidate_manual_threshold_undo)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.Stretch)
        self.cleaning_tabs = QTabWidget()
        self.cleaning_tabs.addTab(self.table, "数值清洗规则")
        if self.supports_exclude_ranges:
            exclude_page = QWidget()
            exclude_layout = QVBoxLayout(exclude_page)
            exclude_hint = QLabel(
                "整段排除规则用于明确标记某测点在指定起止时间内整体无效；原因会随配置保留，"
                "便于复核。它不是数值上下限，也不会与预警值互相转换。"
            )
            exclude_hint.setWordWrap(True)
            exclude_layout.addWidget(exclude_hint)
            self.exclude_table = QTableWidget(0, 6)
            self.exclude_table.setHorizontalHeaderLabels(
                ["范围", "分析类型", "测点编号", "开始时间", "结束时间", "排除原因"]
            )
            self.exclude_table.setAlternatingRowColors(True)
            self.exclude_table.setSelectionBehavior(QAbstractItemView.SelectRows)
            self.exclude_table.setSelectionMode(QAbstractItemView.ExtendedSelection)
            exclude_header = self.exclude_table.horizontalHeader()
            for column in range(5):
                exclude_header.setSectionResizeMode(column, QHeaderView.ResizeToContents)
            exclude_header.setSectionResizeMode(5, QHeaderView.Stretch)
            exclude_layout.addWidget(self.exclude_table, 1)
            exclude_actions = QHBoxLayout()
            add_exclude = QPushButton("新增测点整段排除规则")
            add_exclude.clicked.connect(self.add_exclude_row)
            exclude_actions.addWidget(add_exclude)
            delete_exclude = QPushButton("删除选中排除规则")
            delete_exclude.clicked.connect(self.delete_selected_exclude_rows)
            exclude_actions.addWidget(delete_exclude)
            exclude_actions.addStretch(1)
            self.exclude_count_label = QLabel("0 条整段排除规则")
            exclude_actions.addWidget(self.exclude_count_label)
            exclude_layout.addLayout(exclude_actions)
            self.cleaning_tabs.addTab(exclude_page, "整段排除规则（0 条）")
        outer.addWidget(self.cleaning_tabs, 1)

        if self.supports_curve_threshold_tools:
            self.manual_threshold_group = QGroupBox("从曲线设置清洗阈值（测点专用）")
            self.manual_threshold_group.setObjectName("manualThresholdGroup")
            single_side_layout = QVBoxLayout(self.manual_threshold_group)
            self.manual_threshold_entry_label = QLabel(
                "<b>先在上表选择一条“测点专用”规则。</b> “拖线设置上下限”沿用旧 MATLAB GUI："
                "在同一曲线上同时调整下限、上限和共同时间窗。框选是两个独立动作："
                "<b>下侧框选取框中实际样本的最高值作为下限</b>（删除更低值）；"
                "<b>上侧框选取框中实际样本的最低值作为上限</b>（删除更高值）。"
                "框选边界值本身保留；确认前只显示候选值和预计删除数，不修改表格、不写配置。"
            )
            self.manual_threshold_entry_label.setObjectName("manualThresholdEntryHelp")
            self.manual_threshold_entry_label.setWordWrap(True)
            self.manual_threshold_entry_label.setStyleSheet(
                "background: #edf6ff; border: 1px solid #9cc7e8; "
                "border-radius: 4px; padding: 7px; color: #17324d;"
            )
            single_side_layout.addWidget(self.manual_threshold_entry_label)

            band_actions = QHBoxLayout()
            primary_button_style = (
                "font-weight: 700; background: #005eac; color: white; padding: 7px 12px;"
            )
            self.threshold_band_button = QPushButton(
                "拖线设置上下限（旧 MATLAB 方式：双线 + 共同时间窗）…"
            )
            self.threshold_band_button.setObjectName("openThresholdBandCurveButton")
            self.threshold_band_button.setToolTip(
                "打开同一测点曲线，同时拖动下限线和上限线；两条线共享一个可调整时间窗"
            )
            self.threshold_band_button.setAccessibleName("拖线设置上下限")
            self.threshold_band_button.setMinimumHeight(36)
            self.threshold_band_button.setStyleSheet(primary_button_style)
            self.threshold_band_button.clicked.connect(self.open_threshold_band)
            band_actions.addWidget(self.threshold_band_button, 1)
            self.undo_manual_threshold_button = QPushButton("撤销上次尚未保存的曲线设置")
            self.undo_manual_threshold_button.setEnabled(False)
            self.undo_manual_threshold_button.clicked.connect(self.undo_manual_threshold)
            band_actions.addWidget(self.undo_manual_threshold_button)
            single_side_layout.addLayout(band_actions)

            box_actions = QHBoxLayout()
            self.lower_box_threshold_button = QPushButton(
                "框选设为下限（下侧框选取最高值；删除更低值）…"
            )
            self.lower_box_threshold_button.setObjectName("openLowerBoxThresholdButton")
            self.lower_box_threshold_button.setToolTip(
                "拉框选中低值侧实际样本；取框中最高值作为下限，严格删除低于该值的数据"
            )
            self.lower_box_threshold_button.setAccessibleName(
                "框选设为下限，下侧框选取最高值"
            )
            self.lower_box_threshold_button.setMinimumHeight(36)
            self.lower_box_threshold_button.clicked.connect(
                lambda: self.open_box_threshold(LOWER_SIDE)
            )
            box_actions.addWidget(self.lower_box_threshold_button, 1)
            self.upper_box_threshold_button = QPushButton(
                "框选设为上限（上侧框选取最低值；删除更高值）…"
            )
            self.upper_box_threshold_button.setObjectName("openUpperBoxThresholdButton")
            self.upper_box_threshold_button.setToolTip(
                "拉框选中高值侧实际样本；取框中最低值作为上限，严格删除高于该值的数据"
            )
            self.upper_box_threshold_button.setAccessibleName(
                "框选设为上限，上侧框选取最低值"
            )
            self.upper_box_threshold_button.setMinimumHeight(36)
            self.upper_box_threshold_button.clicked.connect(
                lambda: self.open_box_threshold(UPPER_SIDE)
            )
            box_actions.addWidget(self.upper_box_threshold_button, 1)
            single_side_layout.addLayout(box_actions)

            # Backward-compatible attribute names are retained for older smoke
            # consumers; the two buttons now intentionally mean box selection.
            self.lower_threshold_button = self.lower_box_threshold_button
            self.upper_threshold_button = self.upper_box_threshold_button
            self.undo_single_side_button = self.undo_manual_threshold_button
            outer.addWidget(self.manual_threshold_group)

        actions = QHBoxLayout()
        self.add_default_button = QPushButton(self.add_default_text)
        self.add_default_button.clicked.connect(lambda: self.add_row("defaults"))
        actions.addWidget(self.add_default_button)
        self.add_point_button = QPushButton(self.add_point_text)
        self.add_point_button.clicked.connect(lambda: self.add_row("per_point"))
        actions.addWidget(self.add_point_button)
        delete_button = QPushButton("删除选中数值规则")
        delete_button.clicked.connect(self.delete_selected_rows)
        actions.addWidget(delete_button)
        actions.addStretch(1)
        self.count_label = QLabel("0 条清洗配置行")
        actions.addWidget(self.count_label)
        save_copy = QPushButton("保存副本…")
        save_copy.clicked.connect(self._save_copy)
        actions.addWidget(save_copy)
        save_source = QPushButton("覆盖保存（自动备份）")
        save_source.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 6px 12px;"
        )
        save_source.clicked.connect(self._save_source)
        actions.addWidget(save_source)
        outer.addLayout(actions)

        self.message_label = QLabel("尚未加载配置。")
        self.message_label.setWordWrap(True)
        self.message_label.setStyleSheet("color: #6b7280;")
        outer.addWidget(self.message_label)

    def load_path(self, path: Path) -> None:
        session = self.session_class(path)
        self.session = session
        self._manual_threshold_undo = None
        if self.supports_curve_threshold_tools:
            self.undo_manual_threshold_button.setEnabled(False)
        self.path_label.setText(f"配置：{session.path}")
        self._populate(session.rows)
        if self.supports_exclude_ranges:
            self._populate_exclude_rows(session.exclude_rows)
        if self.supports_exclude_ranges:
            detail = (
                f"数值清洗 {len(session.rows)} 条；整段排除 {len(session.exclude_rows)} 条。"
                "未显示的其它配置保持不变。"
            )
        else:
            detail = f"仅列出{self.managed_field_text}；未显示的其它配置保持不变。"
        manual_threshold_hint = (
            " 选择测点专用规则后，可使用双线拖动，或使用下侧/上侧框选两个独立入口。"
            if self.supports_curve_threshold_tools
            else ""
        )
        self.message_label.setText(
            f"已加载；配置版本校验码={session.loaded_sha256[:16]}…。{detail}"
            f"{manual_threshold_hint}"
        )
        self.message_label.setStyleSheet("color: #167c35;")

    def _reload(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法重新加载", "尚未选择配置文件。")
            return
        try:
            self.load_path(self.session.path)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "重新加载失败", str(exc))

    @staticmethod
    def _display(value: object | None) -> str:
        if value is None:
            return ""
        if isinstance(value, bool):
            return "是" if value else "否"
        return str(value)

    def _populate(self, rows: list[CleaningThresholdRow]) -> None:
        blocked = self.table.blockSignals(True)
        try:
            self.table.setRowCount(0)
            for row in rows:
                self._append_row(row)
        finally:
            self.table.blockSignals(blocked)
        self.count_label.setText(f"{len(rows)} 条{self.row_label}")

    def _invalidate_manual_threshold_undo(self, *_args: object) -> None:
        if self._manual_threshold_undo is None:
            return
        self._manual_threshold_undo = None
        if self.supports_curve_threshold_tools:
            self.undo_manual_threshold_button.setEnabled(False)

    def _append_row(self, row: CleaningThresholdRow) -> None:
        index = self.table.rowCount()
        self.table.insertRow(index)
        values = (
            _config_scope_label(row.scope),
            _module_label(row.module_key),
            row.point_key,
            row.minimum,
            row.maximum,
            row.t_range_start,
            row.t_range_end,
            row.zero_to_nan,
            row.outlier_window_sec,
            row.outlier_threshold_factor,
        )
        for column, value in enumerate(values):
            item = QTableWidgetItem(self._display(value))
            if column == 0:
                item.setData(Qt.UserRole, row.scope)
            elif column == 1:
                item.setData(Qt.UserRole, row.module_key)
            self.table.setItem(index, column, item)

    def add_row(self, scope: str) -> None:
        self._invalidate_manual_threshold_undo()
        module_key = "acceleration"
        selected = self.table.currentRow()
        if selected >= 0 and self.table.item(selected, 1):
            module_key = _stored_or_edited_value(
                self.table.item(selected, 1),
                labeler=_module_label,
                reverse=_MODULE_KEYS_BY_LABEL,
            ) or module_key
        point_key = "POINT_ID" if scope == "per_point" else ""
        self._append_row(CleaningThresholdRow(scope, module_key, point_key, -1, 1))
        row = self.table.rowCount() - 1
        self.table.selectRow(row)
        self.table.scrollToItem(self.table.item(row, 0))
        self.count_label.setText(f"{self.table.rowCount()} 条{self.row_label}")

    def delete_selected_rows(self) -> None:
        self._invalidate_manual_threshold_undo()
        selected = sorted({index.row() for index in self.table.selectedIndexes()}, reverse=True)
        for row in selected:
            self.table.removeRow(row)
        self.count_label.setText(f"{self.table.rowCount()} 条{self.row_label}")

    def _preview_context(self) -> dict[str, str]:
        if self.preview_context_provider is None:
            return {}
        try:
            raw = self.preview_context_provider()
        except Exception as exc:  # noqa: BLE001
            raise ConfigEditorError(f"无法读取当前任务信息：{exc}") from exc
        if not isinstance(raw, Mapping):
            raise ConfigEditorError("当前任务信息格式无效")
        context = {
            key: str(raw.get(key) or "").strip()
            for key in ("bridge_id", "data_root", "config_path", "start_date", "end_date")
        }
        required = ("bridge_id", "data_root", "start_date", "end_date")
        missing = [key for key in required if not context[key]]
        if missing:
            raise ConfigEditorError(
                "当前任务信息不完整，不能安全加载曲线预览："
                + "、".join(missing)
            )
        try:
            start = datetime.strptime(context["start_date"], "%Y-%m-%d").date()
            end = datetime.strptime(context["end_date"], "%Y-%m-%d").date()
        except ValueError as exc:
            raise ConfigEditorError("当前任务的起止日期无效") from exc
        if end < start:
            raise ConfigEditorError("当前任务的结束日期早于开始日期")
        return context

    def _automatic_preview_resolver(
        self,
        target: CleaningThresholdRow,
        aliases: tuple[str, ...],
        context: Mapping[str, str],
    ) -> Callable[[], Path]:
        def resolve() -> Path:
            match = find_matching_threshold_preview(
                preview_query(
                    bridge_id=context.get("bridge_id", ""),
                    data_root=context.get("data_root", ""),
                    start_date=context.get("start_date", ""),
                    end_date=context.get("end_date", ""),
                    config_sha256=(self.session.loaded_sha256 if self.session else ""),
                    module_key=target.module_key,
                    point_ids=aliases,
                )
            )
            if match.path is None:
                raise ConfigEditorError(match.message)
            return match.path

        return resolve

    def _manual_threshold_target(
        self,
    ) -> tuple[int, list[CleaningThresholdRow], CleaningThresholdRow, tuple[str, ...]]:
        selected_index = self.table.currentRow()
        selected_rows = {index.row() for index in self.table.selectedIndexes()}
        if len(selected_rows) != 1:
            raise ConfigEditorError("曲线设置阈值一次只作用于一条规则；请只选择一行")
        current_rows = self.rows()
        if selected_index < 0 or selected_index >= len(current_rows):
            raise ConfigEditorError("请先在数值清洗规则表中选择一条测点专用规则")
        target = current_rows[selected_index]
        if target.scope != "per_point":
            raise ConfigEditorError(
                "曲线设置阈值只适用于测点专用规则；请先选择或新增测点规则"
            )
        if target.point_key in {"", "POINT_ID"}:
            raise ConfigEditorError("请先把测点编号填写为配置中真实存在的测点")
        payload = self.session.payload if self.session is not None else {}
        return selected_index, current_rows, target, accepted_point_ids(
            payload, target.point_key
        )

    def _apply_manual_threshold_rows(
        self,
        *,
        before: list[CleaningThresholdRow],
        previous_index: int,
        updated: list[CleaningThresholdRow],
        result_index: int,
        message: str,
    ) -> None:
        self._populate(updated)
        self.table.selectRow(result_index)
        self.table.scrollToItem(self.table.item(result_index, 0))
        self._manual_threshold_undo = (before, previous_index, list(updated))
        self.undo_manual_threshold_button.setEnabled(True)
        self.message_label.setText(message)
        self.message_label.setStyleSheet("color: #9a6700; font-weight: 600;")

    def open_threshold_band(self) -> None:
        dialog = None
        try:
            selected_index, current_rows, target, aliases = self._manual_threshold_target()
            context = self._preview_context()
            dialog = self.threshold_band_dialog_class(
                target,
                accepted_preview_point_ids=aliases,
                expected_config_sha256=(self.session.loaded_sha256 if self.session else ""),
                expected_bridge_id=context.get("bridge_id", ""),
                expected_data_root=context.get("data_root", ""),
                expected_start_date=context.get("start_date", ""),
                expected_end_date=context.get("end_date", ""),
                automatic_preview_resolver=self._automatic_preview_resolver(
                    target, aliases, context
                ),
                parent=self,
            )
            if dialog.exec() != QDialog.Accepted:
                return
            draft = dialog.draft()
            estimate_summary = dialog.estimate_summary()
            updated_rows, result_index, _replaced = merge_two_sided_rule(
                current_rows,
                selected_index=selected_index,
                draft=draft,
            )
        except (ValueError, ConfigEditorError) as exc:
            QMessageBox.warning(self, "无法拖线设置上下限", str(exc))
            return
        finally:
            if dialog is not None and hasattr(dialog, "deleteLater"):
                dialog.deleteLater()
        self._apply_manual_threshold_rows(
            before=current_rows,
            previous_index=selected_index,
            updated=updated_rows,
            result_index=result_index,
            message=(
                f"尚未保存：已按旧 MATLAB 双线方式修改 {draft.module_key}/{draft.point_key}，"
                f"下限={draft.lower:.15g}，上限={draft.upper:.15g}，"
                f"共同时间窗={draft.time_window_text}。{estimate_summary}"
            ),
        )

    def open_box_threshold(self, side: str) -> None:
        dialog = None
        try:
            selected_index, current_rows, target, aliases = self._manual_threshold_target()
            context = self._preview_context()
            dialog = self.box_threshold_dialog_class(
                target,
                side=side,
                accepted_preview_point_ids=aliases,
                expected_config_sha256=(self.session.loaded_sha256 if self.session else ""),
                expected_bridge_id=context.get("bridge_id", ""),
                expected_data_root=context.get("data_root", ""),
                expected_start_date=context.get("start_date", ""),
                expected_end_date=context.get("end_date", ""),
                automatic_preview_resolver=self._automatic_preview_resolver(
                    target, aliases, context
                ),
                parent=self,
            )
            if dialog.exec() != QDialog.Accepted:
                return
            proposal = dialog.proposal()
            draft = proposal.draft
            estimate_summary = dialog.estimate_summary()
            updated_rows, result_index, _replaced = apply_one_sided_to_selected_row(
                current_rows,
                selected_index=selected_index,
                draft=draft,
            )
        except (ValueError, ConfigEditorError) as exc:
            QMessageBox.warning(self, "无法框选设置阈值", str(exc))
            return
        finally:
            if dialog is not None and hasattr(dialog, "deleteLater"):
                dialog.deleteLater()
        rule = "下侧框选取最高值" if side == LOWER_SIDE else "上侧框选取最低值"
        self._apply_manual_threshold_rows(
            before=current_rows,
            previous_index=selected_index,
            updated=updated_rows,
            result_index=result_index,
            message=(
                f"尚未保存：{rule}，已把 {draft.module_key}/{draft.point_key} 的"
                f"{draft.direction_text}更新为 {draft.value:.15g}；"
                f"框中有限预览点 {proposal.selected_sample_count} 个。"
                f"等于阈值的点保留。{estimate_summary}"
            ),
        )

    def undo_manual_threshold(self) -> None:
        if self._manual_threshold_undo is None:
            return
        rows, selected_index, expected_current = self._manual_threshold_undo
        try:
            current = self.rows()
        except (ValueError, ConfigEditorError):
            current = []
        if current != expected_current:
            self._manual_threshold_undo = None
            self.undo_manual_threshold_button.setEnabled(False)
            self.message_label.setText(
                "表格在曲线设置后又发生了其它修改，为避免覆盖这些修改，已取消本次撤销。"
            )
            self.message_label.setStyleSheet("color: #9a6700; font-weight: 600;")
            return
        self._populate(rows)
        if 0 <= selected_index < self.table.rowCount():
            self.table.selectRow(selected_index)
        self._manual_threshold_undo = None
        self.undo_manual_threshold_button.setEnabled(False)
        self.message_label.setText("已撤销上次尚未保存的曲线阈值设置。")
        self.message_label.setStyleSheet("color: #167c35;")

    def _populate_exclude_rows(self, rows: list[ExcludeRangeRow]) -> None:
        self.exclude_table.setRowCount(0)
        for row in rows:
            index = self.exclude_table.rowCount()
            self.exclude_table.insertRow(index)
            for column, value in enumerate(
                (
                    _config_scope_label(row.scope),
                    _module_label(row.module_key),
                    row.point_key,
                    row.start_time,
                    row.end_time,
                    row.reason,
                )
            ):
                item = QTableWidgetItem(str(value))
                if column == 0:
                    item.setData(Qt.UserRole, row.scope)
                elif column == 1:
                    item.setData(Qt.UserRole, row.module_key)
                self.exclude_table.setItem(index, column, item)
        self.exclude_count_label.setText(f"{len(rows)} 条整段排除规则")
        self.cleaning_tabs.setTabText(1, f"整段排除规则（{len(rows)} 条）")

    def add_exclude_row(self) -> None:
        now = datetime.now().replace(minute=0, second=0, microsecond=0)
        row = ExcludeRangeRow(
            "per_point",
            "acceleration",
            "POINT_ID",
            now.strftime("%Y-%m-%d %H:%M:%S"),
            now.strftime("%Y-%m-%d %H:%M:%S"),
            "请填写排除原因",
        )
        index = self.exclude_table.rowCount()
        self.exclude_table.insertRow(index)
        for column, value in enumerate(
            (
                _config_scope_label(row.scope),
                _module_label(row.module_key),
                row.point_key,
                row.start_time,
                row.end_time,
                row.reason,
            )
        ):
            item = QTableWidgetItem(str(value))
            if column == 0:
                item.setData(Qt.UserRole, row.scope)
            elif column == 1:
                item.setData(Qt.UserRole, row.module_key)
            self.exclude_table.setItem(index, column, item)
        self.exclude_table.selectRow(index)
        self.exclude_count_label.setText(f"{self.exclude_table.rowCount()} 条整段排除规则")
        self.cleaning_tabs.setTabText(1, f"整段排除规则（{self.exclude_table.rowCount()} 条）")

    def delete_selected_exclude_rows(self) -> None:
        selected = sorted(
            {index.row() for index in self.exclude_table.selectedIndexes()}, reverse=True
        )
        for row in selected:
            self.exclude_table.removeRow(row)
        count = self.exclude_table.rowCount()
        self.exclude_count_label.setText(f"{count} 条整段排除规则")
        self.cleaning_tabs.setTabText(1, f"整段排除规则（{count} 条）")

    def exclude_rows(self) -> list[ExcludeRangeRow]:
        if not self.supports_exclude_ranges:
            return []
        rows: list[ExcludeRangeRow] = []
        for index in range(self.exclude_table.rowCount()):
            values = [
                self.exclude_table.item(index, column).text().strip()
                if self.exclude_table.item(index, column)
                else ""
                for column in range(6)
            ]
            try:
                values[0] = _stored_or_edited_value(
                    self.exclude_table.item(index, 0),
                    labeler=_config_scope_label,
                    reverse=CONFIG_SCOPE_KEYS,
                )
                values[1] = _stored_or_edited_value(
                    self.exclude_table.item(index, 1),
                    labeler=_module_label,
                    reverse=_MODULE_KEYS_BY_LABEL,
                )
                rows.append(ExcludeRangeRow(*values).validated())
            except ConfigEditorError as exc:
                raise ConfigEditorError(f"整段排除规则第 {index + 1} 行无效：{exc}") from exc
        return rows

    @staticmethod
    def _optional_float(text: str) -> float | None:
        return None if not text.strip() else float(text)

    @staticmethod
    def _optional_bool(text: str) -> bool | None:
        value = text.strip().lower()
        if not value:
            return None
        if value in {"true", "1", "yes", "是"}:
            return True
        if value in {"false", "0", "no", "否"}:
            return False
        raise ConfigEditorError(f"“零值转为空值”只能填写是、否或留空：{text!r}")

    def rows(self) -> list[CleaningThresholdRow]:
        rows: list[CleaningThresholdRow] = []
        for index in range(self.table.rowCount()):
            values = [
                self.table.item(index, column).text().strip()
                if self.table.item(index, column)
                else ""
                for column in range(10)
            ]
            try:
                values[0] = _stored_or_edited_value(
                    self.table.item(index, 0),
                    labeler=_config_scope_label,
                    reverse=CONFIG_SCOPE_KEYS,
                )
                values[1] = _stored_or_edited_value(
                    self.table.item(index, 1),
                    labeler=_module_label,
                    reverse=_MODULE_KEYS_BY_LABEL,
                )
                row = CleaningThresholdRow(
                    values[0],
                    values[1],
                    values[2],
                    self._optional_float(values[3]),
                    self._optional_float(values[4]),
                    values[5],
                    values[6],
                    self._optional_bool(values[7]),
                    self._optional_float(values[8]),
                    self._optional_float(values[9]),
                ).validated()
            except (ValueError, ConfigEditorError) as exc:
                raise ConfigEditorError(f"第 {index + 1} 行无效：{exc}") from exc
            rows.append(row)
        if self.session is not None:
            self.session.build_payload(rows)
        return rows

    def _validate_dialog(self) -> None:
        try:
            rows = self.rows()
            exclude_rows = self.exclude_rows()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, f"{self.editor_label}校验失败", str(exc))
            return
        QMessageBox.information(
            self,
            f"{self.editor_label}校验通过",
            f"{len(rows)} 条数值清洗规则、{len(exclude_rows)} 条整段排除规则均有效。",
        )

    def _save_source(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        answer = QMessageBox.question(
            self,
            "确认覆盖配置",
            f"将覆盖：\n{self.session.path}\n\n保存前会自动备份原文件。是否继续？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer == QMessageBox.Yes:
            self._save(target=None)

    def _save_copy(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        path, _ = QFileDialog.getSaveFileName(
            self,
            "保存配置副本",
            str(self.session.path.with_name(f"{self.session.path.stem}_{self.copy_suffix}.json")),
            "JSON files (*.json)",
        )
        if path:
            self._save(target=Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            if self.supports_exclude_ranges:
                updated = self.session.build_payload_all(self.rows(), self.exclude_rows())
                result = self.session.save_payload(updated, target=target)
            else:
                result = self.session.save(self.rows(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, f"保存{self.editor_label}失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无（内容未变化或为新文件）"
        self.message_label.setText(
            f"保存完成：{result.path}；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.message_label.setStyleSheet("color: #167c35; font-weight: 600;")
        self._invalidate_manual_threshold_undo()
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.message_label.text())


class PostFilterThresholdEditorWidget(CleaningThresholdEditorWidget):
    session_class = PostFilterConfigEditorSession
    row_label = "滤波后二次清洗行"
    copy_suffix = "post_filter_workbench"
    editor_label = "滤波后二次清洗配置"
    managed_field_text = "已明确配置的滤波后二次清洗规则"
    add_default_text = "新增默认滤波后规则"
    add_point_text = "新增测点滤波后规则"
    supports_exclude_ranges = False
    # Automatic-cleaning previews are pre-filter data.  Do not expose curve
    # tools here until a filter-chain-pinned post-filter preview exists.
    supports_curve_threshold_tools = False

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.title_label.setText("滤波后二次清洗配置")
        self.hint_label.setText(
            "编辑模块默认或测点专用的滤波后二次清洗规则；这些规则仅在滤波完成后按顺序执行。"
            "支持单边上下限和成对时间窗；不修改原始清洗、零点修正或报警边界。"
        )
        self.hint_label.setToolTip(
            "这些规则在滤波完成后执行；模块默认与测点专用规则的作用范围不同"
        )
        for column in (7, 8, 9):
            self.table.setColumnHidden(column, True)
