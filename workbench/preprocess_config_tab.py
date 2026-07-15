from __future__ import annotations

import copy
from pathlib import Path

from PySide6.QtCore import Qt, Signal
from PySide6.QtWidgets import (
    QComboBox,
    QFileDialog,
    QFormLayout,
    QHBoxLayout,
    QLabel,
    QMessageBox,
    QPushButton,
    QSpinBox,
    QVBoxLayout,
    QWidget,
)

from .config_editor import ConfigEditorSession
from .unzip_settings import (
    AUTO_MAX_WORKERS,
    AUTO_TOKEN,
    MAX_CUSTOM_WORKERS,
    PRESET_WORKERS,
    UnzipWorkerSetting,
    apply_unzip_worker_setting,
    normalize_unzip_worker_setting,
    unzip_worker_setting_from_config,
    unzip_worker_summary,
)


CUSTOM_TOKEN = "__custom__"


class UnzipSettingsEditorWidget(QWidget):
    """Focused editor for ``preprocessing.unzip.max_workers`` only."""

    config_saved = Signal(str, str, str)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.session: ConfigEditorSession | None = None
        self._setting = normalize_unzip_worker_setting()
        self._build_ui()

    def _build_ui(self) -> None:
        outer = QVBoxLayout(self)
        title = QLabel("ZIP 解压并发设置")
        title.setStyleSheet("font-size: 20px; font-weight: 700; color: #005eac;")
        outer.addWidget(title)
        hint = QLabel(
            "仅配置安全解压步骤同时处理多少个 ZIP，不改变数据清洗、时间覆盖、缺口连接、"
            "预警阈值或零点修正。缺失配置继续按串行 1 运行；自动模式最多使用 "
            f"{AUTO_MAX_WORKERS} 个 MATLAB 工作进程。并行环境不可用或多个 ZIP 共享输出目录时，"
            "程序会安全回退并在解压摘要中记录请求值、实际值和原因。"
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
        outer.addLayout(path_row)

        form = QFormLayout()
        self.mode_combo = QComboBox()
        self.mode_combo.addItem(
            f"自动（推荐，最多 {AUTO_MAX_WORKERS} 个工作进程）", AUTO_TOKEN
        )
        self.mode_combo.addItem("串行（1，兼容安全默认）", 1)
        self.mode_combo.addItem("并行（2）", 2)
        self.mode_combo.addItem("并行（4）", 4)
        self.mode_combo.addItem("自定义…", CUSTOM_TOKEN)
        self.mode_combo.currentIndexChanged.connect(self._refresh_state)
        form.addRow("解压并发", self.mode_combo)

        self.custom_workers = QSpinBox()
        self.custom_workers.setRange(1, MAX_CUSTOM_WORKERS)
        self.custom_workers.setValue(2)
        self.custom_workers.setSuffix(" 个工作进程")
        self.custom_workers.valueChanged.connect(self._refresh_state)
        form.addRow("自定义数量", self.custom_workers)
        outer.addLayout(form)

        self.summary_label = QLabel()
        self.summary_label.setWordWrap(True)
        self.summary_label.setStyleSheet(
            "background: #eef6ff; border: 1px solid #b8d8f4; "
            "border-radius: 4px; padding: 8px; color: #174a75;"
        )
        outer.addWidget(self.summary_label)

        warning = QLabel(
            "建议：普通工作站使用“自动”或 2；内存较小、同时运行其它 MATLAB 任务时使用 1。"
            "选择 4 或更高值前，应先用本机合成 ZIP 基准验证资源占用。"
        )
        warning.setWordWrap(True)
        warning.setStyleSheet("color: #7a4b00;")
        outer.addWidget(warning)

        actions = QHBoxLayout()
        validate_button = QPushButton("校验当前设置")
        validate_button.clicked.connect(self._validate_dialog)
        actions.addWidget(validate_button)
        actions.addStretch(1)
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
        outer.addStretch(1)
        self._set_setting(self._setting)

    def load_path(self, path: Path) -> None:
        session = ConfigEditorSession(path)
        setting = unzip_worker_setting_from_config(session.payload)
        self.session = session
        self._set_setting(setting)
        self.path_label.setText(f"配置：{session.path}")
        self.message_label.setText(
            f"已加载；配置版本校验码={session.loaded_sha256[:16]}…。"
            f"当前值：{setting.requested_workers!s}。"
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

    def _set_setting(self, setting: UnzipWorkerSetting) -> None:
        self._setting = setting
        if setting.is_auto:
            index = self.mode_combo.findData(AUTO_TOKEN)
        elif setting.requested_workers in PRESET_WORKERS:
            index = self.mode_combo.findData(setting.requested_workers)
        else:
            index = self.mode_combo.findData(CUSTOM_TOKEN)
            self.custom_workers.setValue(int(setting.worker_limit))
        self.mode_combo.setCurrentIndex(max(0, index))
        self._refresh_state()

    def requested_value(self) -> int | str:
        selected = self.mode_combo.currentData()
        if selected == CUSTOM_TOKEN:
            return int(self.custom_workers.value())
        return selected

    def current_setting(self) -> UnzipWorkerSetting:
        return normalize_unzip_worker_setting(self.requested_value())

    def build_payload(self) -> dict:
        if self.session is None:
            raise RuntimeError("尚未加载配置文件")
        # A missing max_workers key has always meant the serial default.  Merely
        # opening the page and saving must not materialize that implicit value,
        # otherwise an operator no-op rewrites every bridge configuration.  An
        # actual selection change still writes the explicit requested value.
        if self.current_setting() == self._setting:
            return copy.deepcopy(self.session.payload)
        return apply_unzip_worker_setting(self.session.payload, self.requested_value())

    def _refresh_state(self, *_args: object) -> None:
        custom = self.mode_combo.currentData() == CUSTOM_TOKEN
        self.custom_workers.setVisible(custom)
        self.custom_workers.setEnabled(custom)
        try:
            setting = self.current_setting()
            self.summary_label.setText(unzip_worker_summary(setting))
        except Exception as exc:  # noqa: BLE001
            self.summary_label.setText(f"设置无效：{exc}")

    def _validate_dialog(self) -> None:
        try:
            setting = self.current_setting()
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "解压并发设置无效", str(exc))
            return
        QMessageBox.information(self, "设置校验通过", unzip_worker_summary(setting))

    def _save_source(self) -> None:
        if self.session is None:
            QMessageBox.warning(self, "无法保存", "尚未加载配置文件。")
            return
        answer = QMessageBox.question(
            self,
            "确认覆盖配置",
            f"仅更新 preprocessing.unzip.max_workers：\n{self.session.path}\n\n"
            "保存前会自动备份原文件。是否继续？",
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
            str(
                self.session.path.with_name(
                    f"{self.session.path.stem}_unzip_workers{self.session.path.suffix}"
                )
            ),
            "JSON files (*.json)",
        )
        if path:
            self._save(target=Path(path))

    def _save(self, target: Path | None) -> None:
        assert self.session is not None
        try:
            result = self.session.save_payload(self.build_payload(), target=target)
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "保存解压并发设置失败", str(exc))
            return
        backup = str(result.backup_path) if result.backup_path else "无（内容未变化或为新文件）"
        self.message_label.setText(
            f"保存完成：{result.path}；配置版本校验码={result.sha256[:16]}…；备份={backup}"
        )
        self.message_label.setStyleSheet("color: #167c35; font-weight: 600;")
        if target is None:
            self.load_path(result.path)
        self.config_saved.emit(str(result.path), result.sha256, backup)
        QMessageBox.information(self, "保存完成", self.message_label.text())
