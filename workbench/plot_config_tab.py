from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QGroupBox,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QLineEdit,
    QListWidget,
    QMessageBox,
    QPushButton,
    QSplitter,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from .config_editor import ConfigEditorError
from .plot_config import (
    PLOT_COMMON_SCHEMA,
    SPECTRUM_MODULES,
    PlotCommonConfigSession,
    PlotCommonRow,
    SpectrumConfigSession,
    SpectrumCoverage,
    SpectrumPeakOrderRow,
)


PLOT_FIELD_LABELS = {
    "save_fig": "保存可编辑图文件",
    "lightweight_fig": "可编辑图使用轻量数据",
    "fig_max_points": "普通图最大绘制点数",
    "append_timestamp": "输出文件名追加时间戳",
    "gap_mode": "数据缺口连接方式",
    "gap_break_factor": "断线判定间隔倍数",
    "dynamic_raw_sampling_mode": "高频原始图采样方式",
    "dynamic_raw_fig_max_points": "高频原始图最大绘制点数",
    "dynamic_raw_min_points_per_day": "高频原始图每日最低点数",
    "dynamic_raw_line_width": "高频原始曲线线宽",
    "dynamic_raw_render_mode": "高频原始图绘制方式",
    "dynamic_raw_band_bins": "密集带状图分箱数",
    "dynamic_raw_band_line_width": "密集带状图边线宽度",
    "dynamic_raw_trace_points": "密集带状图叠加轨迹点数",
}

PLOT_TYPE_LABELS = {
    "bool": "开关（是/否）",
    "int": "整数",
    "float": "数值",
    "enum:connect|break": "连续连接 / 按缺口断开",
    "enum:capped|full": "限量采样 / 完整数据",
    "enum:line|dense_band": "普通曲线 / 密集带状",
}

PLOT_VALUE_LABELS = {
    "gap_mode": {"connect": "连续连接", "break": "按数据缺口断开"},
    "dynamic_raw_sampling_mode": {"capped": "限量采样", "full": "完整数据"},
    "dynamic_raw_render_mode": {"line": "普通曲线", "dense_band": "密集带状"},
}

PLOT_DESCRIPTION_LABELS = {
    "save_fig": "同时保存后续可继续编辑的图文件",
    "lightweight_fig": "可编辑图文件仅保留展示所需数据，以减小文件体积",
    "fig_max_points": "普通图允许绘制的最大点数",
    "append_timestamp": "在输出文件名末尾增加生成时间",
    "gap_mode": "数据缺口处连续连接或按缺口断开",
    "gap_break_factor": "当相邻采样间隔超过该倍数时判定为缺口",
    "dynamic_raw_sampling_mode": "高频原始图使用限量采样或完整数据",
    "dynamic_raw_fig_max_points": "限量采样时，高频原始图允许绘制的总点数",
    "dynamic_raw_min_points_per_day": "限量采样时，每个自然日至少保留的点数",
    "dynamic_raw_line_width": "高频原始曲线的线宽",
    "dynamic_raw_render_mode": "高频原始图使用普通曲线或密集带状图",
    "dynamic_raw_band_bins": "密集带状图沿时间轴划分的区间数量",
    "dynamic_raw_band_line_width": "密集带状图边界线宽",
    "dynamic_raw_trace_points": "密集带状图叠加曲线的点数；0 表示不叠加",
}

SPECTRUM_MODULE_LABELS = {
    "accel_spectrum": "加速度频谱",
    "cable_accel_spectrum": "索力加速度频谱",
}
SPECTRUM_SCOPE_LABELS = {"default": "模块默认", "point": "测点专用"}
SPECTRUM_SCOPE_KEYS = {label: key for key, label in SPECTRUM_SCOPE_LABELS.items()}
SPECTRUM_SOURCE_LABELS = {
    "params": "模块默认配置",
    "params_legacy": "旧版模块默认配置",
    "per_point": "测点专用配置",
    "兼容配置": "旧版兼容配置",
    "new": "本次新建",
}


def _plot_value_label(field: str, value: object) -> str:
    if isinstance(value, bool):
        return "是" if value else "否"
    text = str(value)
    return PLOT_VALUE_LABELS.get(field, {}).get(text, text)


def _plot_value_key(field: str, value: str) -> str:
    labels = PLOT_VALUE_LABELS.get(field, {})
    reverse = {label: key for key, label in labels.items()}
    return reverse.get(value, value)


class PlotCommonEditorWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: PlotCommonConfigSession | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("绘图公共参数")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "管理普通绘图、高频原始时程的采样与绘制参数。取消“单独设置”后，"
            "该项会使用分析程序默认值。完整数据模式不会抽点，并强制使用普通曲线绘制；"
            "这些选项只改变图件表达和文件体积，不改变统计值。"
        )
        hint.setWordWrap(True)
        hint.setToolTip(
            "完整数据模式保留全部有效点；普通曲线模式按时间顺序连接数据"
        )
        outer.addWidget(hint)

        path_row = QHBoxLayout()
        self.path_label = QLabel("配置：尚未加载")
        self.path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        path_row.addWidget(self.path_label, 1)
        reload_button = QPushButton("重新加载")
        reload_button.clicked.connect(self._reload)
        path_row.addWidget(reload_button)
        validate_button = QPushButton("校验全部参数")
        validate_button.clicked.connect(self._validate_dialog)
        path_row.addWidget(validate_button)
        outer.addLayout(path_row)

        self.table = QTableWidget(0, 5)
        self.table.setHorizontalHeaderLabels(["单独设置", "参数名称", "可填写内容", "当前值", "作用"])
        self.table.horizontalHeaderItem(1).setToolTip("面向图件输出的可管理参数")
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.Stretch)
        header.setSectionResizeMode(4, QHeaderView.Stretch)
        outer.addWidget(self.table, 1)

        actions = QHBoxLayout()
        self.summary_label = QLabel("尚未加载。")
        actions.addWidget(self.summary_label, 1)
        copy_button = QPushButton("保存副本…")
        copy_button.clicked.connect(self._save_copy)
        actions.addWidget(copy_button)
        save_button = QPushButton("覆盖保存（自动备份）")
        save_button.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 6px 12px;"
        )
        save_button.clicked.connect(self._save_source)
        actions.addWidget(save_button)
        outer.addLayout(actions)

    def load_path(self, path: Path) -> None:
        self.session = PlotCommonConfigSession(path)
        self.path_label.setText(f"配置：{self.session.path}")
        self._populate(self.session.rows)
        explicit = sum(row.explicit for row in self.session.rows)
        self.summary_label.setText(
            f"已加载 {len(self.session.rows)} 个可管理参数，其中 {explicit} 个单独设置；"
            f"配置版本校验码={self.session.loaded_sha256[:16]}…"
        )

    def _reload(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法重新加载", "尚未选择配置文件。")
            return
        try:
            self.load_path(self.session.path)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "重新加载失败", str(exc))

    def _populate(self, rows: list[PlotCommonRow]) -> None:
        self.table.setRowCount(0)
        for row in rows:
            index = self.table.rowCount()
            self.table.insertRow(index)
            explicit = QTableWidgetItem()
            explicit.setFlags(explicit.flags() | Qt.ItemIsUserCheckable)
            explicit.setCheckState(Qt.Checked if row.explicit else Qt.Unchecked)
            self.table.setItem(index, 0, explicit)
            values = (
                PLOT_FIELD_LABELS.get(row.field, row.field),
                PLOT_TYPE_LABELS.get(row.value_type, row.value_type),
                _plot_value_label(row.field, row.value),
                PLOT_DESCRIPTION_LABELS.get(row.field, row.description),
            )
            for column, value in enumerate(values, 1):
                item = QTableWidgetItem(value)
                if column == 1:
                    item.setToolTip(PLOT_DESCRIPTION_LABELS.get(row.field, row.description))
                elif column == 3:
                    item.setToolTip(f"当前显示值：{_plot_value_label(row.field, row.value)}")
                if column in {1, 2, 4}:
                    item.setFlags(item.flags() & ~Qt.ItemIsEditable)
                self.table.setItem(index, column, item)

    def rows(self) -> list[PlotCommonRow]:
        rows: list[PlotCommonRow] = []
        for index, schema in enumerate(PLOT_COMMON_SCHEMA):
            rows.append(
                PlotCommonRow(
                    schema[0],
                    schema[1],
                    self.table.item(index, 0).checkState() == Qt.Checked,
                    _plot_value_key(schema[0], self.table.item(index, 3).text().strip()),
                    schema[3],
                ).validated()
            )
        if self.session is not None:
            self.session.build_payload(rows)
        return rows

    def _validate_dialog(self) -> None:
        try:
            rows = self.rows()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "绘图参数校验失败", str(exc))
            return
        explicit = sum(row.explicit for row in rows)
        QMessageBox.information(
            self, "绘图参数校验通过", f"{len(rows)} 个参数有效，其中 {explicit} 个单独设置。"
        )

    def _save_source(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        answer = QMessageBox.question(
            self,
            "确认覆盖绘图公共参数",
            f"将覆盖：\n{self.session.path}\n\n保存前自动备份，是否继续？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer == QMessageBox.Yes:
            self._save(None)

    def _save_copy(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        path, _ = QFileDialog.getSaveFileName(
            self,
            "保存绘图参数副本",
            str(self.session.path.with_name(f"{self.session.path.stem}_绘图参数副本.json")),
            "JSON files (*.json)",
        )
        if path:
            self._save(Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            result = self.session.save(self.rows(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存绘图参数失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无"
        self.summary_label.setText(
            f"保存完成：{result.path}；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.summary_label.text())


class SpectrumConfigEditorWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: SpectrumConfigSession | None = None
        self.coverages: dict[str, SpectrumCoverage] = {}
        self.order_drafts: dict[str, list[SpectrumPeakOrderRow]] = {}
        self.loaded_module = ""
        self._switching = False
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("频谱测点覆盖与找峰阶次")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "统一管理结构加速度与索力加速度频谱的测点清单，以及模块默认或测点专用的各阶找峰范围。"
            "未勾选“单独指定频谱测点清单”时，会沿用加速度、索力加速度或分组测点；"
            "只有实际编辑后，旧版频率配置才会转换为当前的各阶找峰配置。"
        )
        hint.setWordWrap(True)
        hint.setToolTip(
            "可分别设置结构加速度和索力加速度频谱的测点清单及各阶找峰范围"
        )
        outer.addWidget(hint)

        header = QHBoxLayout()
        header.addWidget(QLabel("频谱模块"))
        self.module_combo = QComboBox()
        for module, label in SPECTRUM_MODULE_LABELS.items():
            self.module_combo.addItem(label, module)
            self.module_combo.setItemData(
                self.module_combo.count() - 1,
                f"编辑{label}的测点清单和找峰范围",
                Qt.ToolTipRole,
            )
        self.module_combo.currentIndexChanged.connect(self._module_changed)
        header.addWidget(self.module_combo)
        self.path_label = QLabel("配置：尚未加载")
        self.path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        header.addWidget(self.path_label, 1)
        reload_button = QPushButton("重新加载")
        reload_button.clicked.connect(self._reload)
        header.addWidget(reload_button)
        validate_button = QPushButton("校验全部频谱配置")
        validate_button.clicked.connect(self._validate_dialog)
        header.addWidget(validate_button)
        outer.addLayout(header)

        splitter = QSplitter(Qt.Horizontal)
        coverage_box = QGroupBox("频谱测点覆盖")
        coverage_layout = QVBoxLayout(coverage_box)
        self.explicit_check = QCheckBox("单独指定频谱测点清单")
        self.explicit_check.setToolTip("勾选后只分析下方指定测点；不勾选时自动沿用项目测点清单")
        self.explicit_check.toggled.connect(self._coverage_edited)
        coverage_layout.addWidget(self.explicit_check)
        lists = QSplitter(Qt.Horizontal)
        selected_box = QGroupBox("参与频谱分析")
        selected_layout = QVBoxLayout(selected_box)
        self.selected_points = QListWidget()
        self.selected_points.setSelectionMode(QAbstractItemView.ExtendedSelection)
        selected_layout.addWidget(self.selected_points)
        remove_button = QPushButton("移除选中")
        remove_button.clicked.connect(self._remove_points)
        selected_layout.addWidget(remove_button)
        lists.addWidget(selected_box)
        available_box = QGroupBox("可用原始测点")
        available_layout = QVBoxLayout(available_box)
        self.filter_edit = QLineEdit()
        self.filter_edit.setPlaceholderText("按测点编号筛选…")
        self.filter_edit.setToolTip("输入部分测点编号可快速筛选")
        self.filter_edit.textChanged.connect(self._refresh_available)
        available_layout.addWidget(self.filter_edit)
        self.available_points = QListWidget()
        self.available_points.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.available_points.itemDoubleClicked.connect(lambda _item: self._add_points())
        available_layout.addWidget(self.available_points)
        add_button = QPushButton("← 加入指定清单")
        add_button.clicked.connect(self._add_points)
        available_layout.addWidget(add_button)
        lists.addWidget(available_box)
        coverage_layout.addWidget(lists)
        splitter.addWidget(coverage_box)

        orders_box = QGroupBox("默认与逐测点找峰阶次")
        orders_layout = QVBoxLayout(orders_box)
        self.order_table = QTableWidget(0, 10)
        self.order_table.setHorizontalHeaderLabels(
            [
                "启用",
                "适用范围",
                "测点编号",
                "阶次",
                "峰名称",
                "理论频率（Hz）",
                "搜索下限（Hz）",
                "搜索上限（Hz）",
                "理论频率标签",
                "配置来源",
            ]
        )
        order_header_tooltips = {
            1: "模块默认范围作用于全部测点；测点专用范围只作用于指定测点",
            2: "测点专用阶次必须填写测点编号",
            3: "同一测点的振型或频率阶次",
            5: "设计或理论参考频率",
            6: "找峰搜索区间的起点",
            7: "找峰搜索区间的终点",
            8: "报告和图件中显示的理论频率说明",
            9: "说明该阶次来自模块默认、测点专用、旧版兼容或本次新建配置",
        }
        for column, tooltip in order_header_tooltips.items():
            self.order_table.horizontalHeaderItem(column).setToolTip(tooltip)
        self.order_table.setAlternatingRowColors(True)
        self.order_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        header_view = self.order_table.horizontalHeader()
        header_view.setSectionResizeMode(QHeaderView.ResizeToContents)
        header_view.setSectionResizeMode(2, QHeaderView.Stretch)
        header_view.setSectionResizeMode(4, QHeaderView.Stretch)
        header_view.setSectionResizeMode(8, QHeaderView.Stretch)
        orders_layout.addWidget(self.order_table)
        order_actions = QHBoxLayout()
        add_default = QPushButton("新增默认阶次")
        add_default.clicked.connect(lambda: self._add_order("default"))
        order_actions.addWidget(add_default)
        add_point = QPushButton("为选中测点新增阶次")
        add_point.clicked.connect(lambda: self._add_order("point"))
        order_actions.addWidget(add_point)
        delete_order = QPushButton("删除选中阶次")
        delete_order.clicked.connect(self._delete_orders)
        order_actions.addWidget(delete_order)
        order_actions.addStretch(1)
        orders_layout.addLayout(order_actions)
        splitter.addWidget(orders_box)
        splitter.setSizes([720, 1100])
        outer.addWidget(splitter, 1)

        footer = QHBoxLayout()
        self.summary_label = QLabel("尚未加载。")
        footer.addWidget(self.summary_label, 1)
        copy_button = QPushButton("保存副本…")
        copy_button.clicked.connect(self._save_copy)
        footer.addWidget(copy_button)
        save_button = QPushButton("保存两个频谱模块（自动备份）")
        save_button.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 6px 12px;"
        )
        save_button.clicked.connect(self._save_source)
        footer.addWidget(save_button)
        outer.addLayout(footer)

    def load_path(self, path: Path) -> None:
        self.session = SpectrumConfigSession(path)
        self.coverages = {
            module: self.session.coverage(module) for module in SPECTRUM_MODULES
        }
        self.order_drafts = {
            module: self.session.orders(module) for module in SPECTRUM_MODULES
        }
        self.path_label.setText(f"配置：{self.session.path}")
        self._load_module(str(self.module_combo.currentData()))

    def _reload(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法重新加载", "尚未加载配置文件。")
            return
        try:
            self.load_path(self.session.path)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "重新加载失败", str(exc))

    def _module_changed(self) -> None:
        if self._switching:
            return
        try:
            self._persist_module()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "频谱配置校验失败", str(exc))
            self._switching = True
            previous = self.module_combo.findData(self.loaded_module)
            if previous >= 0:
                self.module_combo.setCurrentIndex(previous)
            self._switching = False
            return
        self._load_module(str(self.module_combo.currentData()))

    def _persist_module(self) -> None:
        module = self.loaded_module
        if not module:
            return
        points = tuple(
            self.selected_points.item(index).text()
            for index in range(self.selected_points.count())
        )
        self.coverages[module] = SpectrumCoverage(
            module, self.explicit_check.isChecked(), points
        )
        self.order_drafts[module] = self._table_orders(module)

    def _load_module(self, module: str) -> None:
        if not module or self.session is None:
            return
        self._switching = True
        self.loaded_module = module
        coverage = self.coverages[module]
        self.explicit_check.setChecked(coverage.explicit)
        self.selected_points.clear()
        self.selected_points.addItems(list(coverage.points))
        self._populate_orders(self.order_drafts[module])
        self._switching = False
        self._refresh_available()
        self._update_summary()

    def _refresh_available(self) -> None:
        self.available_points.clear()
        if self.session is None:
            return
        needle = self.filter_edit.text().strip().casefold()
        points = self.session.available_points(str(self.module_combo.currentData()))
        self.available_points.addItems(
            [point for point in points if not needle or needle in point.casefold()]
        )

    def _coverage_edited(self) -> None:
        if not self._switching:
            self._update_summary()

    def _add_points(self) -> None:
        existing = {
            self.selected_points.item(index).text()
            for index in range(self.selected_points.count())
        }
        for item in self.available_points.selectedItems():
            if item.text() not in existing:
                self.selected_points.addItem(item.text())
                existing.add(item.text())
        self.explicit_check.setChecked(True)
        self._update_summary()

    def _remove_points(self) -> None:
        for item in self.selected_points.selectedItems():
            self.selected_points.takeItem(self.selected_points.row(item))
        self.explicit_check.setChecked(True)
        self._update_summary()

    @staticmethod
    def _display(value: object | None) -> str:
        if value is None:
            return ""
        if isinstance(value, float):
            # JSON decimal arithmetic can produce tails such as
            # 1.6859999999999999. Keep the editable value precise without
            # exposing binary floating-point noise to operators.
            return f"{value:.12g}"
        return str(value)

    def _populate_orders(self, rows: list[SpectrumPeakOrderRow]) -> None:
        self.order_table.setRowCount(0)
        for row in rows:
            self._append_order(row)

    def _append_order(self, row: SpectrumPeakOrderRow) -> None:
        index = self.order_table.rowCount()
        self.order_table.insertRow(index)
        enabled = QTableWidgetItem()
        enabled.setFlags(enabled.flags() | Qt.ItemIsUserCheckable)
        enabled.setCheckState(Qt.Checked if row.enabled else Qt.Unchecked)
        self.order_table.setItem(index, 0, enabled)
        values = (
            SPECTRUM_SCOPE_LABELS.get(row.scope, row.scope),
            row.point_id,
            row.order,
            row.label,
            row.theoretical_hz,
            row.search_min_hz,
            row.search_max_hz,
            row.theor_label,
            SPECTRUM_SOURCE_LABELS.get(row.source, row.source),
        )
        for column, value in enumerate(values, 1):
            item = QTableWidgetItem(self._display(value))
            if column == 1:
                item.setToolTip("模块默认" if row.scope == "default" else "仅当前测点")
            elif column == 9:
                item.setData(Qt.UserRole, row.source)
                item.setToolTip(SPECTRUM_SOURCE_LABELS.get(row.source, row.source))
            if column == 9:
                item.setFlags(item.flags() & ~Qt.ItemIsEditable)
            self.order_table.setItem(index, column, item)

    @staticmethod
    def _optional_float(text: str) -> float | None:
        return None if not text.strip() else float(text)

    def _table_orders(self, module: str) -> list[SpectrumPeakOrderRow]:
        rows: list[SpectrumPeakOrderRow] = []
        for index in range(self.order_table.rowCount()):
            values = [
                self.order_table.item(index, column).text().strip()
                if self.order_table.item(index, column)
                else ""
                for column in range(1, 10)
            ]
            try:
                values[0] = SPECTRUM_SCOPE_KEYS.get(values[0], values[0])
                source_item = self.order_table.item(index, 9)
                source = str(source_item.data(Qt.UserRole) or values[8])
                rows.append(
                    SpectrumPeakOrderRow(
                        module,
                        values[0],
                        values[1],
                        self._optional_float(values[2]),
                        values[3],
                        self._optional_float(values[4]),
                        float(values[5]),
                        float(values[6]),
                        values[7],
                        self.order_table.item(index, 0).checkState() == Qt.Checked,
                        source,
                    ).validated()
                )
            except (ValueError, ConfigEditorError) as exc:
                raise ConfigEditorError(f"第 {index + 1} 行频谱阶次无效：{exc}") from exc
        return rows

    def _add_order(self, scope: str) -> None:
        point = ""
        if scope == "point":
            selected = self.selected_points.selectedItems()
            point = selected[0].text() if selected else ""
            if not point:
                QMessageBox.warning(self, "无法新增逐点阶次", "请先在左侧选择一个参与频谱分析的测点。")
                return
        try:
            existing = self._table_orders(self.loaded_module)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "无法新增频谱阶次", str(exc))
            return
        order_numbers = [row.order for row in existing if row.scope == scope and row.point_id == point and row.order]
        order = int(max(order_numbers or [0])) + 1
        self._append_order(
            SpectrumPeakOrderRow(
                self.loaded_module,
                scope,
                point,
                order,
                f"峰{order}",
                None,
                0.5,
                0.7,
                "",
                True,
                "new",
            )
        )
        self.order_table.selectRow(self.order_table.rowCount() - 1)
        self._update_summary()

    def _delete_orders(self) -> None:
        rows = sorted({item.row() for item in self.order_table.selectedIndexes()}, reverse=True)
        for row in rows:
            self.order_table.removeRow(row)
        self._update_summary()

    def _update_summary(self) -> None:
        module = str(self.module_combo.currentData() or "")
        mode = "单独指定" if self.explicit_check.isChecked() else "自动继承"
        self.summary_label.setText(
            f"{SPECTRUM_MODULE_LABELS.get(module, module)}：{mode}测点 "
            f"{self.selected_points.count()} 个；找峰阶次 {self.order_table.rowCount()} 行。"
        )

    def _drafts(self) -> tuple[dict[str, SpectrumCoverage], dict[str, list[SpectrumPeakOrderRow]]]:
        if self.session is None:
            raise ConfigEditorError("尚未加载配置")
        self._persist_module()
        self.session.build_payload_all(self.coverages, self.order_drafts)
        return self.coverages, self.order_drafts

    def _validate_dialog(self) -> None:
        try:
            coverages, orders = self._drafts()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "频谱配置校验失败", str(exc))
            return
        total_points = sum(len(item.points) for item in coverages.values())
        total_orders = sum(len(item) for item in orders.values())
        QMessageBox.information(
            self,
            "频谱配置校验通过",
            f"两个模块共展示 {total_points} 个覆盖测点、{total_orders} 行找峰阶次。",
        )

    def _save_source(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        answer = QMessageBox.question(
            self,
            "确认保存频谱配置",
            f"将覆盖：\n{self.session.path}\n\n发生编辑的旧版频率配置会转换为当前的各阶找峰配置，"
            "保存前会自动备份。是否继续？",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No,
        )
        if answer == QMessageBox.Yes:
            self._save(None)

    def _save_copy(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        path, _ = QFileDialog.getSaveFileName(
            self,
            "保存频谱配置副本",
            str(self.session.path.with_name(f"{self.session.path.stem}_spectrum_workbench.json")),
            "JSON files (*.json)",
        )
        if path:
            self._save(Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            coverages, orders = self._drafts()
            result = self.session.save_all(coverages, orders, target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存频谱配置失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无"
        self.summary_label.setText(
            f"保存完成：{result.path}；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.summary_label.text())
