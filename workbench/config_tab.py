from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
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
    PostFilterConfigEditorSession,
)


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
    "earthquake": "地震动",
    "eq": "地震动",
    "temperature": "温度",
    "humidity": "湿度",
    "rainfall": "雨量",
}


class AlarmBoundsEditorWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: ConfigEditorSession | None = None
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
        self.warning_search.setPlaceholderText("模块、测点、等级、值或配置路径")
        self.warning_search.setClearButtonEnabled(True)
        self.warning_search.textChanged.connect(self._apply_effective_filters)
        filters.addWidget(self.warning_search, 1)
        self.effective_count_label = QLabel("0 条")
        filters.addWidget(self.effective_count_label)
        overview_layout.addLayout(filters)

        self.effective_table = QTableWidget(0, 10)
        self.effective_table.setHorizontalHeaderLabels(
            ["来源", "范围", "模块", "测点/分组", "等级/标签", "配置值", "单位", "用途", "状态", "配置路径"]
        )
        self.effective_table.setAlternatingRowColors(True)
        self.effective_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.effective_table.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.effective_table.setEditTriggers(QAbstractItemView.NoEditTriggers)
        effective_header = self.effective_table.horizontalHeader()
        effective_header.setSectionResizeMode(QHeaderView.ResizeToContents)
        effective_header.setSectionResizeMode(3, QHeaderView.Stretch)
        effective_header.setSectionResizeMode(7, QHeaderView.Stretch)
        effective_header.setSectionResizeMode(9, QHeaderView.Stretch)
        overview_layout.addWidget(self.effective_table, 1)
        overview_hint = QLabel(
            "说明：图上参考线只影响图件表达；分级预警值是单边等级；测点/索力上下限才是成对的下限和上限。"
            "“未设置”表示字段存在但为空，“格式错误”必须修复后才能作为有效预警依据。"
        )
        overview_hint.setWordWrap(True)
        overview_hint.setStyleSheet("color: #5f6368;")
        overview_layout.addWidget(overview_hint)
        self.inner_tabs.addTab(overview_page, "有效值总览")

        explicit_page = QWidget()
        explicit_layout = QVBoxLayout(explicit_page)
        explicit_hint = QLabel(
            "本页只编辑成对的下限/上限规则；未配置时不代表项目没有预警值。"
            "规则可作用于整个分析类型或单个测点，等级使用 level1、level2、level3…；"
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
        self.path_label.setText(f"配置：{session.path}")
        self._populate(session.rows)
        self._populate_effective(session.effective_warning_rows)
        self._refresh_explicit_state()
        configured = sum(row.status == "configured" for row in self.effective_rows)
        unset = sum(row.status == "unset" for row in self.effective_rows)
        invalid = sum(row.status == "invalid" for row in self.effective_rows)
        self.message_label.setText(
            f"已加载；SHA256={session.loaded_sha256[:16]}…。"
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
                (
                    f"{WARNING_MODULE_LABELS[row.module_key]} ({row.module_key})"
                    if row.module_key in WARNING_MODULE_LABELS
                    else row.module_key
                ),
                row.target_key or "全局/默认",
                row.level,
                row.value_text,
                row.unit,
                row.purpose,
                WARNING_STATUS_LABELS.get(row.status, row.status),
                row.config_path,
            )
            for column, value in enumerate(values):
                item = QTableWidgetItem(str(value))
                item.setToolTip(row.config_path)
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
        values = (row.scope, row.module_key, row.point_key, row.level, row.lower, row.upper)
        for column, value in enumerate(values):
            self.table.setItem(index, column, QTableWidgetItem(str(value)))

    def add_row(self, scope: str) -> None:
        module_key = "acceleration"
        selected = self.table.currentRow()
        if selected >= 0 and self.table.item(selected, 1):
            module_key = self.table.item(selected, 1).text().strip() or module_key
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
            details = "\n".join(row.config_path for row in invalid[:12])
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
            result = self.session.save(self.rows(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存配置失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无（目标内容未变化或为新文件）"
        self.message_label.setText(
            f"保存完成：{result.path}；SHA256={result.sha256[:16]}…；备份={backup}"
        )
        self.message_label.setStyleSheet("color: #167c35; font-weight: 600;")
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.message_label.text())


class CleaningThresholdEditorWidget(QWidget):
    config_saved = Signal(str, str, str)
    session_class = CleaningConfigEditorSession
    row_label = "清洗配置行"
    copy_suffix = "cleaning_workbench"
    editor_label = "清洗配置"
    managed_field_text = "显式清洗字段"
    add_default_text = "新增默认清洗规则"
    add_point_text = "新增测点清洗规则"

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: CleaningConfigEditorSession | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        self.title_label = QLabel("数据清洗阈值配置")
        self.title_label.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(self.title_label)
        self.hint_label = QLabel(
            "编辑 defaults/per_point 下的 thresholds、zero_to_nan 和 outlier。min/max 可单边填写；"
            "时间窗必须成对填写。历史 1000/-1000 全抑制哨兵可读取和保留，但不建议新增。"
            "保存仅替换上述清洗字段，预警值、零点修正和其它配置保持不变。"
        )
        self.hint_label.setWordWrap(True)
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
                "范围",
                "模块键",
                "测点配置键",
                "min",
                "max",
                "开始时间",
                "结束时间",
                "zero_to_nan",
                "异常窗(s)",
                "异常系数",
            ]
        )
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.ExtendedSelection)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.Stretch)
        outer.addWidget(self.table, 1)

        actions = QHBoxLayout()
        self.add_default_button = QPushButton(self.add_default_text)
        self.add_default_button.clicked.connect(lambda: self.add_row("defaults"))
        actions.addWidget(self.add_default_button)
        self.add_point_button = QPushButton(self.add_point_text)
        self.add_point_button.clicked.connect(lambda: self.add_row("per_point"))
        actions.addWidget(self.add_point_button)
        delete_button = QPushButton("删除选中行")
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
        self.path_label.setText(f"配置：{session.path}")
        self._populate(session.rows)
        self.message_label.setText(
            f"已加载；SHA256={session.loaded_sha256[:16]}…。仅列出{self.managed_field_text}。"
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
            return "true" if value else "false"
        return str(value)

    def _populate(self, rows: list[CleaningThresholdRow]) -> None:
        self.table.setRowCount(0)
        for row in rows:
            self._append_row(row)
        self.count_label.setText(f"{len(rows)} 条{self.row_label}")

    def _append_row(self, row: CleaningThresholdRow) -> None:
        index = self.table.rowCount()
        self.table.insertRow(index)
        values = (
            row.scope,
            row.module_key,
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
            self.table.setItem(index, column, QTableWidgetItem(self._display(value)))

    def add_row(self, scope: str) -> None:
        module_key = "acceleration"
        selected = self.table.currentRow()
        if selected >= 0 and self.table.item(selected, 1):
            module_key = self.table.item(selected, 1).text().strip() or module_key
        point_key = "POINT_ID" if scope == "per_point" else ""
        self._append_row(CleaningThresholdRow(scope, module_key, point_key, -1, 1))
        row = self.table.rowCount() - 1
        self.table.selectRow(row)
        self.table.scrollToItem(self.table.item(row, 0))
        self.count_label.setText(f"{self.table.rowCount()} 条{self.row_label}")

    def delete_selected_rows(self) -> None:
        selected = sorted({index.row() for index in self.table.selectedIndexes()}, reverse=True)
        for row in selected:
            self.table.removeRow(row)
        self.count_label.setText(f"{self.table.rowCount()} 条{self.row_label}")

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
        raise ConfigEditorError(f"zero_to_nan 无法识别：{text!r}")

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
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, f"{self.editor_label}校验失败", str(exc))
            return
        suppressions = sum(
            row.minimum == 1000 and row.maximum == -1000 for row in rows
        )
        suffix = f"；其中 {suppressions} 条历史全抑制哨兵" if suppressions else ""
        QMessageBox.information(self, f"{self.editor_label}校验通过", f"{len(rows)} 条配置行均有效{suffix}。")

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
            result = self.session.save(self.rows(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, f"保存{self.editor_label}失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无（内容未变化或为新文件）"
        self.message_label.setText(
            f"保存完成：{result.path}；SHA256={result.sha256[:16]}…；备份={backup}"
        )
        self.message_label.setStyleSheet("color: #167c35; font-weight: 600;")
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.message_label.text())


class PostFilterThresholdEditorWidget(CleaningThresholdEditorWidget):
    session_class = PostFilterConfigEditorSession
    row_label = "滤波后二次清洗行"
    copy_suffix = "post_filter_workbench"
    editor_label = "滤波后二次清洗配置"
    managed_field_text = "显式 post_filter_thresholds"
    add_default_text = "新增默认滤波后规则"
    add_point_text = "新增测点滤波后规则"

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.title_label.setText("滤波后二次清洗配置")
        self.hint_label.setText(
            "编辑 defaults/per_point 下的 post_filter_thresholds，仅在滤波完成后按顺序执行。"
            "支持单边上下限和成对时间窗；不修改原始清洗、零点修正或报警边界。"
        )
        for column in (7, 8, 9):
            self.table.setColumnHidden(column, True)
