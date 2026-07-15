from __future__ import annotations

from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QDate, QDateTime, QTime, Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QComboBox,
    QDateTimeEdit,
    QDialog,
    QDialogButtonBox,
    QFileDialog,
    QFormLayout,
    QGridLayout,
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

from .config_editor import (
    ConfigEditorError,
    GroupPlotConfigEditorSession,
    GroupPlotRow,
    OffsetConfigEditorSession,
    OffsetCorrectionRow,
)


MODULE_LABELS = {
    "temperature": "温度",
    "humidity": "湿度",
    "strain": "应变箱线/统计组",
    "strain_timeseries": "应变时程组",
    "dynamic_strain": "动应变（高通）",
    "dynamic_strain_lowpass": "动应变（低通）",
    "deflection": "挠度",
    "bearing_displacement": "支座/伸缩缝位移",
    "tilt": "倾角",
    "acceleration": "加速度",
    "cable_accel": "索力加速度",
    "crack": "裂缝宽度",
}
MODULE_KEYS_BY_LABEL = {label: key for key, label in MODULE_LABELS.items()}

OFFSET_MODE_LABELS = {
    "scalar": "固定数值（简写）",
    "fixed": "固定数值",
    "constant": "固定常数",
    "first_day_mean": "首日均值",
    "earliest_day_mean": "最早有效日均值",
    "daily_mean": "逐日均值",
    "day_mean": "逐日均值",
    "daily_median": "逐日中位数",
    "day_median": "逐日中位数",
    "hourly_mean": "逐小时均值",
    "hour_mean": "逐小时均值",
    "hourly_median": "逐小时中位数",
    "hour_median": "逐小时中位数",
}
OFFSET_MODE_KEYS = {label: key for key, label in OFFSET_MODE_LABELS.items()}

OFFSET_NOTE_LABELS = {
    "Raw CF cable acceleration is in mm/s^2; apply daily median baseline removal first, then per-point March 2026 filtering.":
        "CF 吊索加速度原始单位为 mm/s²；先按日中位数消除基线，再执行 2026 年 3 月测点专用滤波。",
    "Keep the validated April fixed baseline; use hourly median baseline removal for May-June because the CF-5 raw baseline drifts within rolling exports.":
        "保留已验证的 4 月固定基线；CF-5 滚动导出存在基线漂移，5—6 月按小时中位数消除基线。",
}

CONFIG_SCOPE_LABELS = {
    "defaults": "模块默认",
    "per_point": "测点专用",
}
CONFIG_SCOPE_KEYS = {label: key for key, label in CONFIG_SCOPE_LABELS.items()}


def _config_scope_label(value: str) -> str:
    return CONFIG_SCOPE_LABELS.get(value, value)


def _config_scope_key(value: str) -> str:
    return CONFIG_SCOPE_KEYS.get(value, value)


def _stored_or_edited(item: QTableWidgetItem | None, labels: dict[str, str]) -> str:
    if item is None:
        return ""
    text = item.text().strip()
    stored = item.data(Qt.UserRole)
    if stored is not None and text == labels.get(str(stored), str(stored)):
        return str(stored)
    reverse = {label: key for key, label in labels.items()}
    return reverse.get(text, text)


class OffsetEffectiveRangeDialog(QDialog):
    """Calendar-backed editor for the period in which a correction is applied."""

    def __init__(
        self,
        start_text: str = "",
        end_text: str = "",
        parent: QWidget | None = None,
    ) -> None:
        super().__init__(parent)
        self.setWindowTitle("设置零点修正生效时间")
        self.setMinimumWidth(460)
        layout = QVBoxLayout(self)
        note = QLabel(
            "该时间段是“修正结果应用到哪些数据”的生效范围。"
            "首日、逐日或逐小时基线仍按所选修正方式计算，并不是另设一段参考样本。"
        )
        note.setWordWrap(True)
        layout.addWidget(note)
        form = QFormLayout()
        self.start_edit = self._date_time_edit(start_text, end=False)
        self.end_edit = self._date_time_edit(end_text, end=True)
        form.addRow("生效开始时间", self.start_edit)
        form.addRow("生效结束时间", self.end_edit)
        layout.addLayout(form)
        buttons = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        buttons.accepted.connect(self._accept_if_valid)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    @staticmethod
    def _parse(text: str, *, end: bool) -> QDateTime:
        text = str(text or "").strip()
        for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
            try:
                parsed = datetime.strptime(text, fmt)
                if fmt == "%Y-%m-%d" and end:
                    parsed = parsed.replace(hour=23, minute=59, second=59)
                return QDateTime(
                    QDate(parsed.year, parsed.month, parsed.day),
                    QTime(parsed.hour, parsed.minute, parsed.second),
                )
            except ValueError:
                continue
        now = QDateTime.currentDateTime()
        if end:
            return QDateTime(now.date(), now.time()).addSecs(3600)
        return now

    @classmethod
    def _date_time_edit(cls, text: str, *, end: bool) -> QDateTimeEdit:
        editor = QDateTimeEdit(cls._parse(text, end=end))
        editor.setCalendarPopup(True)
        editor.setDisplayFormat("yyyy-MM-dd HH:mm:ss")
        return editor

    def _accept_if_valid(self) -> None:
        if self.end_edit.dateTime() < self.start_edit.dateTime():
            QMessageBox.warning(self, "时间范围无效", "生效结束时间不能早于开始时间。")
            return
        self.accept()

    def values(self) -> tuple[str, str]:
        return (
            self.start_edit.dateTime().toString("yyyy-MM-dd HH:mm:ss"),
            self.end_edit.dateTime().toString("yyyy-MM-dd HH:mm:ss"),
        )


class OffsetCorrectionEditorWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: OffsetConfigEditorSession | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("零点修正配置")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "编辑模块默认或测点专用的零点修正；修正值会加到原始测值上。"
            "支持固定数值、首日/逐日/逐小时均值或中位数，以及互不重叠的分段修正。"
            "“生效开始/结束时间”限定修正应用范围，可精确到秒；它不是另一个基线参考样本范围。"
            "只替换零点修正字段，不修改清洗阈值、缩放、绘图或报警配置。"
        )
        hint.setWordWrap(True)
        hint.setToolTip(
            "模块默认规则作用于该类型全部测点；测点专用规则只作用于指定测点。修正值与原始测值相加。"
        )
        outer.addWidget(hint)

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
                "模式",
                "修正值",
                "生效开始时间",
                "生效结束时间",
                "是否分段",
                "序号",
                "备注",
            ]
        )
        header_tooltips = {
            0: "选择修正规则作用于全部同类测点，或仅作用于指定测点",
            1: "需要进行零点修正的数据类型",
            2: "测点专用规则必须填写测点编号",
            3: "选择固定值、均值或中位数等基线修正方式",
            4: "固定数值模式必须填写；统计基线模式留空",
            5: "零点修正开始生效的时刻；留空表示不限制开始时间",
            6: "零点修正停止生效的时刻；留空表示不限制结束时间",
            7: "分段规则必须填写完整且互不重叠的生效时间范围",
        }
        for column, tooltip in header_tooltips.items():
            self.table.horizontalHeaderItem(column).setToolTip(tooltip)
        self.table.setAlternatingRowColors(True)
        self.table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.table.setSelectionMode(QAbstractItemView.ExtendedSelection)
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.Stretch)
        header.setSectionResizeMode(2, QHeaderView.Stretch)
        header.setSectionResizeMode(9, QHeaderView.Stretch)
        outer.addWidget(self.table, 1)

        actions = QHBoxLayout()
        add_scalar = QPushButton("新增测点数值修正")
        add_scalar.clicked.connect(self._add_scalar)
        actions.addWidget(add_scalar)
        add_rule = QPushButton("新增结构化修正")
        add_rule.clicked.connect(self._add_rule)
        actions.addWidget(add_rule)
        add_segment = QPushButton("新增分段")
        add_segment.clicked.connect(self._add_segment)
        actions.addWidget(add_segment)
        self.edit_effective_range_button = QPushButton("设置选中行生效时间…")
        self.edit_effective_range_button.clicked.connect(self._edit_selected_time_range)
        actions.addWidget(self.edit_effective_range_button)
        self.clear_effective_range_button = QPushButton("清除选中行时间限制")
        self.clear_effective_range_button.clicked.connect(self._clear_selected_time_range)
        actions.addWidget(self.clear_effective_range_button)
        delete_button = QPushButton("删除选中行")
        delete_button.clicked.connect(self._delete)
        actions.addWidget(delete_button)
        actions.addStretch(1)
        self.count_label = QLabel("0 条零点修正规则")
        actions.addWidget(self.count_label)
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

        self.message_label = QLabel("尚未加载配置。")
        self.message_label.setWordWrap(True)
        self.message_label.setStyleSheet("color: #6b7280;")
        outer.addWidget(self.message_label)

    def load_path(self, path: Path) -> None:
        self.session = OffsetConfigEditorSession(path)
        self.path_label.setText(f"配置：{self.session.path}")
        self._populate(self.session.rows)
        structured = sum(row.mode != "scalar" for row in self.session.rows)
        self.message_label.setText(
            f"已加载；配置版本校验码={self.session.loaded_sha256[:16]}…；"
            f"结构化/分段行 {structured} 条。"
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
    def _text(value: object | None) -> str:
        if value is None:
            return ""
        if isinstance(value, bool):
            return "是" if value else "否"
        return str(value)

    def _populate(self, rows: list[OffsetCorrectionRow]) -> None:
        self.table.setRowCount(0)
        for row in rows:
            self._append(row)
        self.count_label.setText(f"{len(rows)} 条零点修正规则")

    def _append(self, row: OffsetCorrectionRow) -> None:
        index = self.table.rowCount()
        self.table.insertRow(index)
        values = (
            _config_scope_label(row.scope),
            MODULE_LABELS.get(row.module_key, row.module_key),
            row.point_key,
            OFFSET_MODE_LABELS.get(row.mode, row.mode),
            row.value,
            row.start_date,
            row.end_date,
            row.segmented,
            row.segment_index,
            OFFSET_NOTE_LABELS.get(row.note, row.note),
        )
        for column, value in enumerate(values):
            item = QTableWidgetItem(self._text(value))
            if column == 0:
                item.setData(Qt.UserRole, row.scope)
            elif column == 1:
                item.setData(Qt.UserRole, row.module_key)
            elif column == 3:
                item.setData(Qt.UserRole, row.mode)
            elif column == 9:
                item.setData(Qt.UserRole, row.note)
            self.table.setItem(index, column, item)
        self.count_label.setText(f"{self.table.rowCount()} 条零点修正规则")

    def _selected_context(self) -> tuple[str, str]:
        row = self.table.currentRow()
        module = "strain"
        point = "POINT_ID"
        if row >= 0:
            module = _stored_or_edited(self.table.item(row, 1), MODULE_LABELS) or module
            point = self.table.item(row, 2).text().strip() or point
        return module, point

    def _add_scalar(self) -> None:
        module, point = self._selected_context()
        self._append(OffsetCorrectionRow("per_point", module, point, "scalar", 0))

    def _add_rule(self) -> None:
        module, point = self._selected_context()
        self._append(OffsetCorrectionRow("per_point", module, point, "fixed", 0))

    def _add_segment(self) -> None:
        module, point = self._selected_context()
        indexes = [
            row.segment_index
            for row in self.rows(validate_groups=False)
            if row.scope == "per_point" and row.module_key == module and row.point_key == point
        ]
        new_index = self.table.rowCount()
        self._append(
            OffsetCorrectionRow(
                "per_point",
                module,
                point,
                "fixed",
                0,
                "",
                "",
                True,
                max(indexes or [0]) + 1,
            )
        )
        self.table.selectRow(new_index)
        if not self._edit_selected_time_range():
            self.table.removeRow(new_index)
            self.count_label.setText(f"{self.table.rowCount()} 条零点修正规则")

    def _selected_rows(self) -> list[int]:
        selected = sorted({item.row() for item in self.table.selectedIndexes()})
        if not selected and self.table.currentRow() >= 0:
            selected = [self.table.currentRow()]
        return selected

    def _edit_selected_time_range(self) -> bool:
        selected = self._selected_rows()
        if not selected:
            QMessageBox.warning(self, "未选择规则", "请先选择一行或多行零点修正规则。")
            return False
        first = selected[0]
        start = self.table.item(first, 5).text().strip() if self.table.item(first, 5) else ""
        end = self.table.item(first, 6).text().strip() if self.table.item(first, 6) else ""
        dialog = OffsetEffectiveRangeDialog(start, end, self)
        if dialog.exec() != QDialog.Accepted:
            return False
        start, end = dialog.values()
        for row in selected:
            self.table.item(row, 5).setText(start)
            self.table.item(row, 6).setText(end)
        return True

    def _clear_selected_time_range(self) -> None:
        selected = self._selected_rows()
        if not selected:
            QMessageBox.warning(self, "未选择规则", "请先选择一行或多行零点修正规则。")
            return
        segmented = [
            row
            for row in selected
            if self._bool(self.table.item(row, 7).text() if self.table.item(row, 7) else "")
        ]
        if segmented:
            QMessageBox.warning(
                self,
                "分段规则不能清空时间",
                "分段零点修正必须保留完整生效时间。请改用“设置选中行生效时间”。",
            )
            return
        for row in selected:
            self.table.item(row, 5).setText("")
            self.table.item(row, 6).setText("")

    def _delete(self) -> None:
        selected = sorted({item.row() for item in self.table.selectedIndexes()}, reverse=True)
        for row in selected:
            self.table.removeRow(row)
        self.count_label.setText(f"{self.table.rowCount()} 条零点修正规则")

    @staticmethod
    def _optional_float(text: str) -> float | None:
        return None if not text.strip() else float(text)

    @staticmethod
    def _bool(text: str) -> bool:
        return text.strip().lower() in {"true", "1", "yes", "是"}

    def rows(self, *, validate_groups: bool = True) -> list[OffsetCorrectionRow]:
        rows: list[OffsetCorrectionRow] = []
        for index in range(self.table.rowCount()):
            values = [
                self.table.item(index, column).text().strip()
                if self.table.item(index, column)
                else ""
                for column in range(10)
            ]
            try:
                values[0] = _stored_or_edited(self.table.item(index, 0), CONFIG_SCOPE_LABELS)
                values[1] = _stored_or_edited(self.table.item(index, 1), MODULE_LABELS)
                values[3] = _stored_or_edited(self.table.item(index, 3), OFFSET_MODE_LABELS)
                note_item = self.table.item(index, 9)
                original_note = str(note_item.data(Qt.UserRole) or "") if note_item else ""
                if original_note and values[9] == OFFSET_NOTE_LABELS.get(original_note, original_note):
                    values[9] = original_note
                row = OffsetCorrectionRow(
                    values[0],
                    values[1],
                    values[2],
                    values[3],
                    self._optional_float(values[4]),
                    values[5],
                    values[6],
                    self._bool(values[7]),
                    int(values[8] or 0),
                    values[9],
                ).validated()
            except (ValueError, ConfigEditorError) as exc:
                raise ConfigEditorError(f"第 {index + 1} 行无效：{exc}") from exc
            rows.append(row)
        if validate_groups and self.session is not None:
            self.session.build_payload(rows)
        return rows

    def _validate_dialog(self) -> None:
        try:
            rows = self.rows()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "零点修正校验失败", str(exc))
            return
        modes = sorted({row.mode for row in rows})
        QMessageBox.information(
            self,
            "零点修正校验通过",
            f"{len(rows)} 行均有效；修正方式："
            f"{', '.join(OFFSET_MODE_LABELS.get(mode, mode) for mode in modes)}。",
        )

    def _save_source(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        answer = QMessageBox.question(
            self,
            "确认覆盖配置",
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
            "保存零点修正配置副本",
            str(self.session.path.with_name(f"{self.session.path.stem}_offset_workbench.json")),
            "JSON files (*.json)",
        )
        if path:
            self._save(Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            result = self.session.save(self.rows(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存零点修正失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无"
        self.message_label.setText(
            f"保存完成：{result.path}；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.message_label.setStyleSheet("color: #167c35; font-weight: 600;")
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.message_label.text())


class GroupPlotConfigEditorWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: GroupPlotConfigEditorSession | None = None
        self.drafts: dict[str, list[GroupPlotRow]] = {}
        self.group_points: list[list[str]] = []
        self.current_group = -1
        self.loaded_module = ""
        self._switching = False
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("组图配置")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "按分析类型编辑图件分组和报告显示名称。应变统计组与应变时程组分开显示；"
            "历史二维数组在未改变结构时会原样保留。每个分组需要唯一的分组编号，"
            "编号只允许英文字母、数字和下划线。"
        )
        hint.setWordWrap(True)
        hint.setToolTip(
            "分组编号用于唯一识别图组；报告显示名称用于图题和报告正文"
        )
        outer.addWidget(hint)

        header = QHBoxLayout()
        header.addWidget(QLabel("组图模块"))
        self.module_combo = QComboBox()
        self.module_combo.currentIndexChanged.connect(self._module_changed)
        header.addWidget(self.module_combo, 1)
        self.path_label = QLabel("配置：尚未加载")
        self.path_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        header.addWidget(self.path_label, 3)
        reload_button = QPushButton("重新加载")
        reload_button.clicked.connect(self._reload)
        header.addWidget(reload_button)
        validate_button = QPushButton("校验全部草稿")
        validate_button.clicked.connect(self._validate_dialog)
        header.addWidget(validate_button)
        outer.addLayout(header)

        splitter = QSplitter(Qt.Horizontal)
        group_box = QGroupBox("分组")
        group_layout = QVBoxLayout(group_box)
        self.group_table = QTableWidget(0, 3)
        self.group_table.setHorizontalHeaderLabels(["分组编号", "报告显示名称", "测点数量"])
        self.group_table.horizontalHeaderItem(0).setToolTip(
            "分组的唯一编号，仅支持英文字母、数字和下划线"
        )
        self.group_table.setSelectionBehavior(QAbstractItemView.SelectRows)
        self.group_table.setSelectionMode(QAbstractItemView.SingleSelection)
        self.group_table.horizontalHeader().setSectionResizeMode(0, QHeaderView.Stretch)
        self.group_table.horizontalHeader().setSectionResizeMode(1, QHeaderView.Stretch)
        self.group_table.horizontalHeader().setSectionResizeMode(2, QHeaderView.ResizeToContents)
        self.group_table.itemSelectionChanged.connect(self._group_changed)
        group_layout.addWidget(self.group_table)
        group_actions = QHBoxLayout()
        add_group = QPushButton("新增组")
        add_group.clicked.connect(self._add_group)
        group_actions.addWidget(add_group)
        delete_group = QPushButton("删除组")
        delete_group.clicked.connect(self._delete_group)
        group_actions.addWidget(delete_group)
        group_layout.addLayout(group_actions)
        splitter.addWidget(group_box)

        points_box = QGroupBox("当前组测点（顺序即图例顺序）")
        points_layout = QVBoxLayout(points_box)
        self.point_list = QListWidget()
        self.point_list.setSelectionMode(QAbstractItemView.ExtendedSelection)
        points_layout.addWidget(self.point_list)
        point_actions = QGridLayout()
        remove = QPushButton("移除")
        remove.clicked.connect(self._remove_points)
        point_actions.addWidget(remove, 0, 0)
        up = QPushButton("上移")
        up.clicked.connect(lambda: self._move_point(-1))
        point_actions.addWidget(up, 0, 1)
        down = QPushButton("下移")
        down.clicked.connect(lambda: self._move_point(1))
        point_actions.addWidget(down, 0, 2)
        points_layout.addLayout(point_actions)
        splitter.addWidget(points_box)

        available_box = QGroupBox("可选测点")
        available_layout = QVBoxLayout(available_box)
        self.filter_edit = QLineEdit()
        self.filter_edit.setPlaceholderText("按测点编号筛选…")
        self.filter_edit.setToolTip("输入部分测点编号可快速筛选")
        self.filter_edit.textChanged.connect(self._refresh_available)
        available_layout.addWidget(self.filter_edit)
        self.available_list = QListWidget()
        self.available_list.setSelectionMode(QAbstractItemView.ExtendedSelection)
        self.available_list.itemDoubleClicked.connect(lambda _item: self._add_points())
        available_layout.addWidget(self.available_list)
        add_points = QPushButton("加入当前组 →")
        add_points.clicked.connect(self._add_points)
        available_layout.addWidget(add_points)
        splitter.addWidget(available_box)
        splitter.setSizes([560, 480, 480])
        outer.addWidget(splitter, 1)

        actions = QHBoxLayout()
        self.summary_label = QLabel("尚未加载组图配置。")
        actions.addWidget(self.summary_label, 1)
        copy_button = QPushButton("保存副本…")
        copy_button.clicked.connect(self._save_copy)
        actions.addWidget(copy_button)
        save_button = QPushButton("保存全部模块（自动备份）")
        save_button.setStyleSheet(
            "font-weight: 700; background: #005eac; color: white; padding: 6px 12px;"
        )
        save_button.clicked.connect(self._save_source)
        actions.addWidget(save_button)
        outer.addLayout(actions)

    def load_path(self, path: Path) -> None:
        self.session = GroupPlotConfigEditorSession(path)
        self.drafts = {
            module: list(self.session.rows_for(module)) for module in self.session.modules
        }
        self.path_label.setText(f"配置：{self.session.path}")
        self._switching = True
        self.module_combo.clear()
        for module in self.session.modules:
            self.module_combo.addItem(MODULE_LABELS.get(module, module), module)
            self.module_combo.setItemData(
                self.module_combo.count() - 1,
                f"编辑{MODULE_LABELS.get(module, module)}的图件分组",
                Qt.ToolTipRole,
            )
        self._switching = False
        if self.module_combo.count():
            self.module_combo.setCurrentIndex(0)
            self._load_module(str(self.module_combo.currentData()))
        self.summary_label.setText(
            f"已加载 {len(self.session.modules)} 个可编辑模块；配置版本校验码="
            f"{self.session.loaded_sha256[:16]}…"
        )

    def _reload(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法重新加载", "尚未选择配置文件。")
            return
        try:
            self.load_path(self.session.path)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "重新加载失败", str(exc))

    def _current_module(self) -> str:
        return str(self.module_combo.currentData() or "")

    def _module_changed(self) -> None:
        if self._switching:
            return
        self._persist_module()
        self._load_module(self._current_module())

    def _persist_current_points(self) -> None:
        if 0 <= self.current_group < len(self.group_points):
            self.group_points[self.current_group] = [
                self.point_list.item(index).text()
                for index in range(self.point_list.count())
            ]

    def _persist_module(self) -> None:
        module = self.loaded_module
        if not module:
            return
        self._persist_current_points()
        rows: list[GroupPlotRow] = []
        for index in range(self.group_table.rowCount()):
            key = self.group_table.item(index, 0).text().strip()
            label = self.group_table.item(index, 1).text().strip()
            points = tuple(self.group_points[index]) if index < len(self.group_points) else ()
            rows.append(GroupPlotRow(module, key, label, points))
        self.drafts[module] = rows
        if module in {"strain", "strain_timeseries"}:
            labels = {row.group_key: row.label for row in rows}
            other = "strain_timeseries" if module == "strain" else "strain"
            if other in self.drafts:
                self.drafts[other] = [
                    GroupPlotRow(
                        row.module_key,
                        row.group_key,
                        labels.get(row.group_key, row.label),
                        row.points,
                    )
                    for row in self.drafts[other]
                ]

    def _load_module(self, module: str) -> None:
        self._switching = True
        rows = self.drafts.get(module, [])
        self.group_table.setRowCount(0)
        self.group_points = []
        for row in rows:
            index = self.group_table.rowCount()
            self.group_table.insertRow(index)
            self.group_table.setItem(index, 0, QTableWidgetItem(row.group_key))
            self.group_table.setItem(index, 1, QTableWidgetItem(row.label))
            count = QTableWidgetItem(str(len(row.points)))
            count.setFlags(count.flags() & ~Qt.ItemIsEditable)
            self.group_table.setItem(index, 2, count)
            self.group_points.append(list(row.points))
        self.current_group = -1
        self.loaded_module = module
        self.point_list.clear()
        self._switching = False
        if rows:
            self.group_table.selectRow(0)
        self._refresh_available()
        self._update_summary()

    def _group_changed(self) -> None:
        if self._switching:
            return
        self._persist_current_points()
        selected = self.group_table.currentRow()
        self.current_group = selected
        self.point_list.clear()
        if 0 <= selected < len(self.group_points):
            self.point_list.addItems(self.group_points[selected])
        self._update_counts()

    def _add_group(self) -> None:
        existing = {
            self.group_table.item(index, 0).text()
            for index in range(self.group_table.rowCount())
        }
        number = self.group_table.rowCount() + 1
        while f"Group_{number}" in existing:
            number += 1
        index = self.group_table.rowCount()
        self.group_table.insertRow(index)
        self.group_table.setItem(index, 0, QTableWidgetItem(f"Group_{number}"))
        self.group_table.setItem(index, 1, QTableWidgetItem(""))
        count = QTableWidgetItem("0")
        count.setFlags(count.flags() & ~Qt.ItemIsEditable)
        self.group_table.setItem(index, 2, count)
        self.group_points.append([])
        self.group_table.selectRow(index)
        self._update_summary()

    def _delete_group(self) -> None:
        row = self.group_table.currentRow()
        if row < 0:
            return
        self.group_table.removeRow(row)
        if row < len(self.group_points):
            self.group_points.pop(row)
        self.current_group = -1
        self.point_list.clear()
        if self.group_table.rowCount():
            self.group_table.selectRow(min(row, self.group_table.rowCount() - 1))
        self._update_summary()

    def _refresh_available(self) -> None:
        self.available_list.clear()
        if self.session is None:
            return
        needle = self.filter_edit.text().strip().casefold()
        points = self.session.available_points(self._current_module())
        self.available_list.addItems(
            [point for point in points if not needle or needle in point.casefold()]
        )

    def _add_points(self) -> None:
        if self.current_group < 0:
            QMessageBox.warning(self, "无法加入测点", "请先选择或新增一个分组。")
            return
        existing = {
            self.point_list.item(index).text() for index in range(self.point_list.count())
        }
        for item in self.available_list.selectedItems():
            if item.text() not in existing:
                self.point_list.addItem(item.text())
                existing.add(item.text())
        self._persist_current_points()
        self._update_counts()

    def _remove_points(self) -> None:
        for item in self.point_list.selectedItems():
            self.point_list.takeItem(self.point_list.row(item))
        self._persist_current_points()
        self._update_counts()

    def _move_point(self, delta: int) -> None:
        row = self.point_list.currentRow()
        target = row + delta
        if row < 0 or target < 0 or target >= self.point_list.count():
            return
        item = self.point_list.takeItem(row)
        self.point_list.insertItem(target, item)
        self.point_list.setCurrentRow(target)
        self._persist_current_points()

    def _update_counts(self) -> None:
        self._persist_current_points()
        for index, points in enumerate(self.group_points):
            item = self.group_table.item(index, 2)
            if item:
                item.setText(str(len(points)))
        self._update_summary()

    def _update_summary(self) -> None:
        module = self._current_module()
        count = self.group_table.rowCount()
        points = sum(len(item) for item in self.group_points)
        self.summary_label.setText(
            f"当前分析类型 {MODULE_LABELS.get(module, module) or '—'}："
            f"{count} 组、{points} 个组内测点。"
        )

    def _draft_payload(self) -> dict[str, list[GroupPlotRow]]:
        self._persist_module()
        if self.session is None:
            raise ConfigEditorError("尚未加载配置")
        self.session.build_payload_all(self.drafts)
        return self.drafts

    def _validate_dialog(self) -> None:
        try:
            drafts = self._draft_payload()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "组图配置校验失败", str(exc))
            return
        groups = sum(len(rows) for rows in drafts.values())
        QMessageBox.information(
            self, "组图配置校验通过", f"{len(drafts)} 个模块、{groups} 个分组均有效。"
        )

    def _save_source(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        answer = QMessageBox.question(
            self,
            "确认保存全部组图模块",
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
            "保存组图配置副本",
            str(self.session.path.with_name(f"{self.session.path.stem}_groups_workbench.json")),
            "JSON files (*.json)",
        )
        if path:
            self._save(Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            result = self.session.save_all(self._draft_payload(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存组图配置失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无"
        self.summary_label.setText(
            f"保存完成：{result.path}；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.summary_label.text())
