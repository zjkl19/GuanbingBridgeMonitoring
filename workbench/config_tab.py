from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QAbstractItemView,
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QLabel,
    QMessageBox,
    QPushButton,
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
)


class AlarmBoundsEditorWidget(QWidget):
    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: ConfigEditorSession | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("测点预警值配置")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "本页编辑 defaults/per_point 下的 alarm_bounds；level 使用 level1、level2、level3…，"
            "上下限必须是有限数值且上限大于下限。覆盖保存前会校验文件哈希并自动备份，"
            "其它配置字段保持不变。数据清洗 thresholds 与图上参考线不在本页修改。"
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
        validate_button = QPushButton("校验表格")
        validate_button.clicked.connect(self._validate_dialog)
        path_row.addWidget(validate_button)
        outer.addLayout(path_row)

        self.table = QTableWidget(0, 6)
        self.table.setHorizontalHeaderLabels(
            ["范围", "模块键", "测点配置键", "等级", "下限", "上限"]
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
        outer.addWidget(self.table, 1)

        actions = QHBoxLayout()
        add_default = QPushButton("新增默认阈值")
        add_default.clicked.connect(lambda: self.add_row("defaults"))
        actions.addWidget(add_default)
        add_point = QPushButton("新增测点阈值")
        add_point.clicked.connect(lambda: self.add_row("per_point"))
        actions.addWidget(add_point)
        delete_button = QPushButton("删除选中行")
        delete_button.clicked.connect(self.delete_selected_rows)
        actions.addWidget(delete_button)
        actions.addStretch(1)
        self.count_label = QLabel("0 条显式预警配置")
        actions.addWidget(self.count_label)
        save_copy = QPushButton("保存副本…")
        save_copy.clicked.connect(self._save_copy)
        actions.addWidget(save_copy)
        save_source = QPushButton("覆盖保存（自动备份）")
        save_source.setStyleSheet("font-weight: 700; background: #005eac; color: white; padding: 6px 12px;")
        save_source.clicked.connect(self._save_source)
        actions.addWidget(save_source)
        outer.addLayout(actions)

        self.message_label = QLabel("尚未加载配置。")
        self.message_label.setWordWrap(True)
        self.message_label.setStyleSheet("color: #6b7280;")
        outer.addWidget(self.message_label)

    def load_path(self, path: Path) -> None:
        session = ConfigEditorSession(path)
        self.session = session
        self.path_label.setText(f"配置：{session.path}")
        self._populate(session.rows)
        self.message_label.setText(
            f"已加载；SHA256={session.loaded_sha256[:16]}…。表中只列出显式 alarm_bounds。"
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

    def _populate(self, rows: list[AlarmBoundRow]) -> None:
        self.table.setRowCount(0)
        for row in rows:
            self._append_row(row)
        self.count_label.setText(f"{len(rows)} 条显式预警配置")

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
        self.count_label.setText(f"{self.table.rowCount()} 条显式预警配置")

    def delete_selected_rows(self) -> None:
        selected = sorted({index.row() for index in self.table.selectedIndexes()}, reverse=True)
        for row in selected:
            self.table.removeRow(row)
        self.count_label.setText(f"{self.table.rowCount()} 条显式预警配置")

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

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: CleaningConfigEditorSession | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("数据清洗阈值配置")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "编辑 defaults/per_point 下的 thresholds、zero_to_nan 和 outlier。min/max 可单边填写；"
            "时间窗必须成对填写。历史 1000/-1000 全抑制哨兵可读取和保留，但不建议新增。"
            "保存仅替换上述清洗字段，预警值、零点修正和其它配置保持不变。"
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
        add_default = QPushButton("新增默认清洗规则")
        add_default.clicked.connect(lambda: self.add_row("defaults"))
        actions.addWidget(add_default)
        add_point = QPushButton("新增测点清洗规则")
        add_point.clicked.connect(lambda: self.add_row("per_point"))
        actions.addWidget(add_point)
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
        session = CleaningConfigEditorSession(path)
        self.session = session
        self.path_label.setText(f"配置：{session.path}")
        self._populate(session.rows)
        self.message_label.setText(
            f"已加载；SHA256={session.loaded_sha256[:16]}…。仅列出显式清洗字段。"
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
        self.count_label.setText(f"{len(rows)} 条清洗配置行")

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
        self.count_label.setText(f"{self.table.rowCount()} 条清洗配置行")

    def delete_selected_rows(self) -> None:
        selected = sorted({index.row() for index in self.table.selectedIndexes()}, reverse=True)
        for row in selected:
            self.table.removeRow(row)
        self.count_label.setText(f"{self.table.rowCount()} 条清洗配置行")

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
            QMessageBox.critical(self, "清洗配置校验失败", str(exc))
            return
        suppressions = sum(
            row.minimum == 1000 and row.maximum == -1000 for row in rows
        )
        suffix = f"；其中 {suppressions} 条历史全抑制哨兵" if suppressions else ""
        QMessageBox.information(self, "清洗配置校验通过", f"{len(rows)} 条配置行均有效{suffix}。")

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
            str(self.session.path.with_name(f"{self.session.path.stem}_cleaning_workbench.json")),
            "JSON files (*.json)",
        )
        if path:
            self._save(target=Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            result = self.session.save(self.rows(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存清洗配置失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无（内容未变化或为新文件）"
        self.message_label.setText(
            f"保存完成：{result.path}；SHA256={result.sha256[:16]}…；备份={backup}"
        )
        self.message_label.setStyleSheet("color: #167c35; font-weight: 600;")
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.message_label.text())
