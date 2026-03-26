from __future__ import annotations

import os
import re
import sys
import traceback
from datetime import date, datetime
from pathlib import Path

from PySide6.QtCore import QObject, QThread, Signal, Qt
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QFileDialog,
    QGridLayout,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QPlainTextEdit,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from build_monthly_report import build_report
from build_period_report import build_period_report


MONTHLY_REPORT = "\u6708\u62a5"
PERIOD_REPORT = "\u5468\u671f\u62a5\uff08\u542bWIM\uff09"
APP_VERSION = "v1.5.5"
MONTHLY_TEMPLATE_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u6708\u62a5\u6a21\u677f.docx"
PERIOD_TEMPLATE_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f-\u81ea\u52a8\u62a5\u544a.docx"
PERIOD_TEMPLATE_LEGACY_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f0318.docx"
PERIOD_TEMPLATE_FALLBACK_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f.docx"
DEFAULT_RESULT_ROOT = Path("E:" + "\\" + "\u6d2a\u5858\u5927\u6865\u6570\u636e" + "\\" + "2026\u5e741-3\u6708")


def app_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def candidate_config_roots() -> list[Path]:
    roots = [app_root() / "config", Path.cwd() / "config"]
    unique: list[Path] = []
    for root in roots:
        if root not in unique:
            unique.append(root)
    return unique


def candidate_report_roots() -> list[Path]:
    roots = [app_root() / "reports", Path.cwd() / "reports"]
    unique: list[Path] = []
    for root in roots:
        if root not in unique:
            unique.append(root)
    return unique


def detect_default_config() -> Path:
    computer_name = os.environ.get("COMPUTERNAME", "").strip()
    for config_dir in candidate_config_roots():
        if computer_name:
            machine_cfg = config_dir / f"hongtang_config_{computer_name}.json"
            if machine_cfg.exists():
                return machine_cfg.resolve()
        default_cfg = config_dir / "hongtang_config.json"
        if default_cfg.exists():
            return default_cfg.resolve()
    return (app_root() / "config" / "hongtang_config.json").resolve()


def find_default_template(report_type: str) -> Path:
    preferred = PERIOD_TEMPLATE_NAME if report_type == PERIOD_REPORT else MONTHLY_TEMPLATE_NAME
    if report_type == PERIOD_REPORT:
        fallback_candidates = [PERIOD_TEMPLATE_LEGACY_NAME, PERIOD_TEMPLATE_FALLBACK_NAME, MONTHLY_TEMPLATE_NAME]
    else:
        fallback_candidates = [PERIOD_TEMPLATE_NAME, PERIOD_TEMPLATE_FALLBACK_NAME]
    for reports_dir in candidate_report_roots():
        preferred_path = reports_dir / preferred
        if preferred_path.exists():
            return preferred_path.resolve()
        for fallback in fallback_candidates:
            fallback_path = reports_dir / fallback
            if fallback_path.exists():
                return fallback_path.resolve()
        candidates = sorted(reports_dir.glob("*.docx"))
        if candidates:
            return candidates[0].resolve()
    return (app_root() / "reports" / preferred).resolve()


def derive_wim_root(result_root: Path) -> Path:
    return result_root / "WIM" / "results" / "hongtang"


def derive_output_dir(result_root: Path) -> Path:
    return result_root / "\u81ea\u52a8\u62a5\u544a"


def parse_iso_date(text: str) -> date:
    return datetime.strptime(text, "%Y-%m-%d").date()


def iter_months(start_date: date, end_date: date) -> list[str]:
    months: list[str] = []
    year = start_date.year
    month = start_date.month
    while (year, month) <= (end_date.year, end_date.month):
        months.append(f"{year:04d}{month:02d}")
        if month == 12:
            year += 1
            month = 1
        else:
            month += 1
    return months


def has_dated_raw_dirs(result_root: Path) -> bool:
    pattern = re.compile(r"^\d{4}-\d{2}-\d{2}$")
    for child in result_root.iterdir():
        if child.is_dir() and pattern.match(child.name):
            return True
    return False


def top_help_text() -> str:
    return (
        "\u6a21\u677f\u6587\u4ef6\uff1a\u6708\u62a5\u9ed8\u8ba4\u4f7f\u7528\u201c\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u6708\u62a5\u6a21\u677f.docx\u201d\uff0c"
        "\u5468\u671f\u62a5\u9ed8\u8ba4\u4f7f\u7528\u201c\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f-\u81ea\u52a8\u62a5\u544a.docx\u201d\u3002\n"
        "\u914d\u7f6e\u6587\u4ef6\uff1a\u76f4\u63a5\u5f71\u54cd\u62a5\u544a\u751f\u6210\u7684\u4e3b\u8981\u662f plot_styles.* \u8f93\u51fa\u76ee\u5f55\u3001reporting.* \u63d2\u56fe\u987a\u5e8f/\u542f\u7528\u3001wim.* \u548c wim_db.*\u3002\n"
        "\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55\uff1a\u5b58\u653e\u56fe\u7247\u3001stats\u3001run_logs \u548c\u81ea\u52a8\u62a5\u544a\u3002\n"
        "\u5468\u671f\u62a5\u8bf4\u660e\uff1a1.4\u201c\u5065\u5eb7\u76d1\u6d4b\u7cfb\u7edf\u8fd0\u884c\u72b6\u51b5\u201d\u53ea\u7edf\u8ba1\u539f\u59cb\u6570\u636e\u7f3a\u5931/\u65e0\u6587\u4ef6/\u65e0\u8bb0\u5f55\u3002"
        "\u56e0\u6b64\u5468\u671f\u62a5\u6240\u9009\u7684\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55\uff0c\u5e94\u540c\u65f6\u5305\u542b\u539f\u59cb\u6570\u636e\u548c\u5904\u7406\u7ed3\u679c\u3002\n"
        "\u7a0b\u5e8f\u6839\u76ee\u5f55\uff08\u9ad8\u7ea7\uff09\uff1a\u4e3b\u8981\u7528\u4e8e\u517c\u5bb9\u65e7\u8def\u5f84\u548c\u56de\u9000\u67e5\u627e\uff0c\u901a\u5e38\u4fdd\u6301\u7a0b\u5e8f\u6240\u5728\u76ee\u5f55\u5373\u53ef\u3002"
    )


class ReportWorker(QObject):
    log = Signal(str)
    finished = Signal(str, str)
    failed = Signal(str)

    def __init__(
        self,
        template: Path,
        config_path: Path,
        result_root: Path,
        analysis_root: Path,
        output_dir: Path,
        period_label: str,
        monitoring_range: str,
        report_date: str,
        report_type: str,
        wim_root: Path | None,
        start_date: str,
        end_date: str,
    ) -> None:
        super().__init__()
        self.template = template
        self.config_path = config_path
        self.result_root = result_root
        self.analysis_root = analysis_root
        self.output_dir = output_dir
        self.period_label = period_label
        self.monitoring_range = monitoring_range
        self.report_date = report_date
        self.report_type = report_type
        self.wim_root = wim_root
        self.start_date = start_date
        self.end_date = end_date

    def run(self) -> None:
        try:
            self.log.emit(f"\u6a21\u677f: {self.template}")
            self.log.emit(f"\u914d\u7f6e: {self.config_path}")
            self.log.emit(f"\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55: {self.result_root}")
            self.log.emit(f"\u62a5\u544a\u7c7b\u578b: {self.report_type}")
            if self.report_type == PERIOD_REPORT and self.wim_root is not None:
                self.log.emit(f"WIM\u7ed3\u679c\u76ee\u5f55: {self.wim_root}")
            self.log.emit("\u5f00\u59cb\u751f\u6210\u62a5\u544a...")

            if self.report_type == PERIOD_REPORT:
                manifest_path, report_path, missing = build_period_report(
                    template=self.template,
                    config_path=self.config_path,
                    result_root=self.result_root,
                    analysis_root=self.analysis_root,
                    wim_root=self.wim_root,
                    output_dir=self.output_dir,
                    period_label=self.period_label,
                    monitoring_range=self.monitoring_range,
                    report_date=self.report_date,
                    start_date=self.start_date,
                    end_date=self.end_date,
                )
            else:
                manifest_path, report_path, missing = build_report(
                    template=self.template,
                    config_path=self.config_path,
                    result_root=self.result_root,
                    analysis_root=self.analysis_root,
                    output_dir=self.output_dir,
                    period_label=self.period_label,
                    monitoring_range=self.monitoring_range,
                    report_date=self.report_date,
                )

            self.log.emit(f"Manifest: {manifest_path}")
            self.log.emit(f"Report:   {report_path}")
            if missing:
                self.log.emit("\u8b66\u544a/\u7f3a\u5931\u8d44\u6e90:")
                for item in missing:
                    self.log.emit(f"  - {item}")
            self.log.emit("\u5b8c\u6210")
            self.finished.emit(str(manifest_path), str(report_path))
        except Exception as exc:  # noqa: BLE001
            self.log.emit("\u751f\u6210\u5931\u8d25")
            self.log.emit(str(exc))
            self.log.emit(traceback.format_exc())
            self.failed.emit(str(exc))


class ReportGui(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle(f"\u6865\u6881\u62a5\u544a\u751f\u6210\u5668 {APP_VERSION}")
        self.resize(1040, 820)
        self._last_output_dir: Path | None = None
        self._last_result_root: Path | None = None
        self._thread: QThread | None = None
        self._worker: ReportWorker | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        central = QWidget(self)
        self.setCentralWidget(central)
        outer = QVBoxLayout(central)

        help_label = QLabel(top_help_text())
        help_label.setWordWrap(True)
        help_label.setTextInteractionFlags(Qt.TextSelectableByMouse)
        help_label.setStyleSheet("QLabel { background: #f5f7fa; border: 1px solid #d0d7de; padding: 8px; }")
        outer.addWidget(help_label)

        top_actions = QHBoxLayout()
        doc_btn = QPushButton("\u6253\u5f00\u81ea\u52a8\u62a5\u544a\u8bf4\u660e")
        doc_btn.clicked.connect(self._open_logic_doc)
        top_actions.addWidget(doc_btn)
        top_actions.addStretch(1)
        outer.addLayout(top_actions)

        grid = QGridLayout()
        grid.setColumnStretch(1, 1)
        outer.addLayout(grid)

        repo_root = app_root()
        default_result_root = DEFAULT_RESULT_ROOT

        self.report_type_combo = QComboBox()
        self.report_type_combo.addItems([MONTHLY_REPORT, PERIOD_REPORT])
        self.template_edit = QLineEdit(str(find_default_template(MONTHLY_REPORT)))
        self.config_edit = QLineEdit(str(detect_default_config()))
        self.result_root_edit = QLineEdit(str(default_result_root))
        self.analysis_root_edit = QLineEdit(str(repo_root.resolve()))
        self.wim_root_edit = QLineEdit(str(derive_wim_root(default_result_root)))
        self.output_dir_edit = QLineEdit(str(derive_output_dir(default_result_root)))
        self.period_edit = QLineEdit("2026\u5e741-3\u6708")
        self.range_edit = QLineEdit("2026.01.01~2026.03.16")
        self.start_edit = QLineEdit("2026-01-01")
        self.end_edit = QLineEdit("2026-03-16")
        self.date_edit = QLineEdit(datetime.now().strftime("%Y\u5e74%m\u6708%d\u65e5"))

        rows = [
            ("\u62a5\u544a\u7c7b\u578b", self.report_type_combo, None, "\u6708\u62a5\u6216\u5468\u671f\u62a5\uff08\u542bWIM\uff09\u3002\u5207\u6362\u540e\u4f1a\u81ea\u52a8\u5207\u6362\u9ed8\u8ba4\u6a21\u677f\u3002"),
            ("\u6a21\u677f\u6587\u4ef6", self.template_edit, self._browse_template, "\u6708\u62a5\u9ed8\u8ba4\uff1a\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u6708\u62a5\u6a21\u677f.docx\uff1b\u5468\u671f\u62a5\u9ed8\u8ba4\uff1a\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f-\u81ea\u52a8\u62a5\u544a.docx\u3002"),
            ("\u914d\u7f6e\u6587\u4ef6", self.config_edit, self._browse_config, "\u4f18\u5148\u8bfb\u53d6\u673a\u5668\u4e13\u7528\u914d\u7f6e hongtang_config_<COMPUTERNAME>.json\u3002"),
            ("\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55", self.result_root_edit, self._browse_result_root, "\u8fd9\u91cc\u5e94\u5b58\u653e\u56fe\u7247\u3001stats\u3001run_logs \u548c\u81ea\u52a8\u62a5\u544a\u3002\u5bf9\u5468\u671f\u62a5\uff0c\u8fd9\u4e2a\u76ee\u5f55\u6700\u597d\u540c\u65f6\u5305\u542b raw \u539f\u59cb\u6570\u636e\uff0c\u5426\u5219 1.4 \u7ae0\u8282\u4f1a\u5c06\u7f3a\u5c11\u539f\u59cb\u6570\u636e\u89c6\u4e3a\u7f3a\u5931\u3002"),
            ("\u7a0b\u5e8f\u6839\u76ee\u5f55\uff08\u9ad8\u7ea7\uff09", self.analysis_root_edit, self._browse_analysis_root, "\u517c\u5bb9\u65e7\u8def\u5f84\u548c\u5c11\u91cf\u56de\u9000\u67e5\u627e\uff0c\u901a\u5e38\u4fdd\u6301\u7a0b\u5e8f\u6240\u5728\u76ee\u5f55\u5373\u53ef\u3002"),
            ("WIM\u7ed3\u679c\u76ee\u5f55", self.wim_root_edit, self._browse_wim_root, "\u5468\u671f\u62a5\u4f7f\u7528\uff0c\u9ed8\u8ba4\u662f <\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55>/WIM/results/hongtang\u3002WIM \u4ecd\u6309\u6708\u63d2\u5165\uff0c\u4e0d\u662f\u628a 1~3 \u4e2a\u6708\u76f4\u63a5\u5408\u6210\u4e00\u5f20\u8868\u3002"),
            ("\u8f93\u51fa\u76ee\u5f55", self.output_dir_edit, self._browse_output_dir, "\u62a5\u544a\u8f93\u51fa\u76ee\u5f55\uff0c\u9ed8\u8ba4\u662f <\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55>/\u81ea\u52a8\u62a5\u544a\u3002"),
            ("\u62a5\u544a\u671f", self.period_edit, None, "\u663e\u793a\u5728\u62a5\u544a\u4e2d\u7684\u62a5\u544a\u671f\u6587\u5b57\uff0c\u4f8b\u5982 2026\u5e741-3\u6708\u3002"),
            ("\u76d1\u6d4b\u65f6\u95f4", self.range_edit, None, "\u663e\u793a\u5728\u62a5\u544a\u4e2d\u7684\u76d1\u6d4b\u65f6\u95f4\u6587\u5b57\uff0c\u4f8b\u5982 2026.01.01~2026.03.16\u3002"),
            ("\u5f00\u59cb\u65e5\u671f", self.start_edit, None, "\u5468\u671f\u62a5\u4f7f\u7528\uff0c\u7528\u4e8e\u63a8\u5bfc WIM \u5904\u7406\u6708\u4efd\u8303\u56f4\u3002"),
            ("\u7ed3\u675f\u65e5\u671f", self.end_edit, None, "\u5468\u671f\u62a5\u4f7f\u7528\uff0c\u7528\u4e8e\u63a8\u5bfc WIM \u5904\u7406\u6708\u4efd\u8303\u56f4\u3002"),
            ("\u62a5\u544a\u65e5\u671f", self.date_edit, None, "\u663e\u793a\u5728\u5c01\u9762\u548c\u6b63\u6587\u4e2d\u7684\u62a5\u544a\u65e5\u671f\u3002"),
        ]

        for row_idx, (label, edit, callback, tip) in enumerate(rows):
            base_row = row_idx * 2
            lab = QLabel(label)
            grid.addWidget(lab, base_row, 0)
            edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
            grid.addWidget(edit, base_row, 1)
            if callback is not None:
                btn = QPushButton("\u6d4f\u89c8")
                btn.clicked.connect(callback)
                grid.addWidget(btn, base_row, 2)
            tip_label = QLabel(tip)
            tip_label.setWordWrap(True)
            tip_label.setStyleSheet("QLabel { color: #6b7280; font-size: 12px; }")
            grid.addWidget(tip_label, base_row + 1, 1, 1, 2)

        self.report_type_combo.currentTextChanged.connect(self._on_report_type_changed)

        action_row = QHBoxLayout()
        self.generate_btn = QPushButton("\u751f\u6210\u62a5\u544a")
        self.generate_btn.clicked.connect(self._on_generate)
        action_row.addWidget(self.generate_btn)

        self.open_btn = QPushButton("\u6253\u5f00\u8f93\u51fa\u76ee\u5f55")
        self.open_btn.clicked.connect(self._open_output_dir)
        action_row.addWidget(self.open_btn)

        sync_btn = QPushButton("\u6309\u7ed3\u679c\u76ee\u5f55\u540c\u6b65\u8def\u5f84")
        sync_btn.clicked.connect(lambda: self._sync_result_dependent_paths(force=True))
        action_row.addWidget(sync_btn)

        action_row.addStretch(1)
        self.status_label = QLabel("\u5c31\u7eea")
        action_row.addWidget(self.status_label)
        outer.addLayout(action_row)

        self.log_edit = QPlainTextEdit()
        self.log_edit.setReadOnly(True)
        outer.addWidget(self.log_edit, 1)

        self._on_report_type_changed(self.report_type_combo.currentText())
        self._last_result_root = default_result_root

    def _open_logic_doc(self) -> None:
        candidates = [app_root() / "REPORTING_LOGIC.md", app_root() / "reporting" / "REPORTING_LOGIC.md"]
        doc_path = next((p for p in candidates if p.exists()), None)
        if doc_path is None:
            QMessageBox.warning(self, "\u672a\u627e\u5230\u8bf4\u660e", "\u672a\u627e\u5230 REPORTING_LOGIC.md\u3002")
            return
        try:
            os.startfile(str(doc_path))
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "\u6253\u5f00\u5931\u8d25", str(exc))

    def _maybe_update_template_for_type(self) -> None:
        current = self.template_edit.text().strip()
        names = {MONTHLY_TEMPLATE_NAME, PERIOD_TEMPLATE_NAME, PERIOD_TEMPLATE_LEGACY_NAME, PERIOD_TEMPLATE_FALLBACK_NAME}
        should_replace = (not current) or (Path(current).name in names) or (not Path(current).exists())
        if should_replace:
            self.template_edit.setText(str(find_default_template(self.report_type_combo.currentText())))

    def _browse_template(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "\u9009\u62e9\u6a21\u677f\u6587\u4ef6", str(app_root()), "Word files (*.docx)")
        if path:
            self.template_edit.setText(path)

    def _browse_config(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "\u9009\u62e9\u914d\u7f6e\u6587\u4ef6", str(app_root()), "JSON files (*.json)")
        if path:
            self.config_edit.setText(path)

    def _browse_result_root(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "\u9009\u62e9\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55", self.result_root_edit.text())
        if path:
            previous_root = Path(self.result_root_edit.text()).expanduser() if self.result_root_edit.text().strip() else None
            self.result_root_edit.setText(path)
            self._sync_result_dependent_paths(previous_root=previous_root, force=False)

    def _browse_analysis_root(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "\u9009\u62e9\u7a0b\u5e8f\u6839\u76ee\u5f55", self.analysis_root_edit.text())
        if path:
            self.analysis_root_edit.setText(path)

    def _browse_wim_root(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "\u9009\u62e9WIM\u7ed3\u679c\u76ee\u5f55", self.wim_root_edit.text())
        if path:
            self.wim_root_edit.setText(path)

    def _browse_output_dir(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "\u9009\u62e9\u8f93\u51fa\u76ee\u5f55", self.output_dir_edit.text())
        if path:
            self.output_dir_edit.setText(path)

    def _sync_result_dependent_paths(self, previous_root: Path | None = None, force: bool = False) -> None:
        result_root = Path(self.result_root_edit.text()).expanduser()
        if not str(result_root).strip():
            return

        old_wim = Path(self.wim_root_edit.text()).expanduser() if self.wim_root_edit.text().strip() else None
        old_out = Path(self.output_dir_edit.text()).expanduser() if self.output_dir_edit.text().strip() else None
        previous_root = previous_root or self._last_result_root
        new_wim = derive_wim_root(result_root)
        new_out = derive_output_dir(result_root)

        should_update_wim = force or old_wim is None or "outputs" in old_wim.parts
        should_update_out = force or old_out is None

        if previous_root is not None:
            if old_wim == derive_wim_root(previous_root):
                should_update_wim = True
            if old_out == derive_output_dir(previous_root):
                should_update_out = True
        if old_wim == derive_wim_root(result_root):
            should_update_wim = True
        if old_out == derive_output_dir(result_root):
            should_update_out = True

        if should_update_wim:
            self.wim_root_edit.setText(str(new_wim))
        if should_update_out or not self.output_dir_edit.text().strip():
            self.output_dir_edit.setText(str(new_out))
        self._last_result_root = result_root

    def _on_report_type_changed(self, text: str) -> None:
        period_mode = text == PERIOD_REPORT
        self.wim_root_edit.setEnabled(period_mode)
        self.start_edit.setEnabled(period_mode)
        self.end_edit.setEnabled(period_mode)
        self._maybe_update_template_for_type()

    def _validate_period_inputs(self, result_root: Path, wim_root: Path | None) -> bool:
        try:
            start_date = parse_iso_date(self.start_edit.text().strip())
            end_date = parse_iso_date(self.end_edit.text().strip())
        except ValueError:
            QMessageBox.critical(self, "\u9519\u8bef", "\u5f00\u59cb/\u7ed3\u675f\u65e5\u671f\u683c\u5f0f\u5fc5\u987b\u662f YYYY-MM-DD\u3002")
            return False

        if end_date < start_date:
            QMessageBox.critical(self, "\u9519\u8bef", "\u7ed3\u675f\u65e5\u671f\u4e0d\u80fd\u65e9\u4e8e\u5f00\u59cb\u65e5\u671f\u3002")
            return False

        warnings: list[str] = []

        lowfreq_file = result_root / "lowfreq" / "data.xlsx"
        if not lowfreq_file.exists():
            warnings.append("`lowfreq/data.xlsx` \u4e0d\u5b58\u5728\uff0c`1.4 \u5065\u5eb7\u76d1\u6d4b\u7cfb\u7edf\u8fd0\u884c\u72b6\u51b5` \u4f1a\u628a\u4f4e\u9891\u539f\u59cb\u6570\u636e\u89c6\u4e3a\u7f3a\u5931\u3002")

        if not has_dated_raw_dirs(result_root):
            warnings.append("\u672a\u5728\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55\u4e0b\u627e\u5230 `YYYY-MM-DD` \u5f62\u5f0f\u7684\u539f\u59cb\u9ad8\u9891\u6570\u636e\u76ee\u5f55\uff0c`1.4` \u4f1a\u5c06\u9ad8\u9891\u539f\u59cb\u6570\u636e\u89c6\u4e3a\u7f3a\u5931\u3002")

        stats_dir = result_root / "stats"
        if not stats_dir.exists():
            warnings.append("`stats/` \u4e0d\u5b58\u5728\uff0c\u975e WIM \u7ae0\u8282\u53ef\u80fd\u7f3a\u5c11\u7edf\u8ba1\u8868\u6216\u65e0\u6cd5\u751f\u6210\u3002")

        if wim_root is None or not wim_root.exists():
            warnings.append("WIM \u7ed3\u679c\u76ee\u5f55\u4e0d\u5b58\u5728\uff0cWIM \u7ae0\u8282\u65e0\u6cd5\u6309\u6708\u63d2\u5165\u3002")
        else:
            missing_months = [m for m in iter_months(start_date, end_date) if not (wim_root / m).exists()]
            if missing_months:
                warnings.append(f"WIM \u7ed3\u679c\u76ee\u5f55\u7f3a\u5c11\u6708\u4efd\uff1a{', '.join(missing_months)}\u3002")

        if not warnings:
            return True

        detail = "\n".join(f"- {item}" for item in warnings)
        ret = QMessageBox.warning(
            self,
            "\u5468\u671f\u62a5\u8f93\u5165\u6821\u9a8c",
            "\u53d1\u73b0\u4ee5\u4e0b\u95ee\u9898\uff1a\n\n"
            f"{detail}\n\n"
            "\u53ef\u4ee5\u7ee7\u7eed\u751f\u6210\uff0c\u4f46\u62a5\u544a\u5185\u5bb9\u53ef\u80fd\u4e0d\u5b8c\u6574\u6216 1.4 \u7ae0\u8282\u4f1a\u4ea7\u751f\u8f83\u591a\u7f3a\u5931\u63d0\u793a\u3002\n\n"
            "\u662f\u5426\u7ee7\u7eed\uff1f",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
            QMessageBox.StandardButton.No,
        )
        return ret == QMessageBox.StandardButton.Yes

    def _log(self, text: str) -> None:
        self.log_edit.appendPlainText(text)

    def _set_busy(self, busy: bool) -> None:
        self.generate_btn.setEnabled(not busy)
        self.status_label.setText("\u8fd0\u884c\u4e2d..." if busy else "\u5c31\u7eea")

    def _on_generate(self) -> None:
        template = Path(self.template_edit.text()).expanduser()
        config_path = Path(self.config_edit.text()).expanduser()
        result_root = Path(self.result_root_edit.text()).expanduser()
        analysis_root = Path(self.analysis_root_edit.text()).expanduser()
        output_dir = Path(self.output_dir_edit.text()).expanduser()
        report_type = self.report_type_combo.currentText()
        wim_root = Path(self.wim_root_edit.text()).expanduser() if self.wim_root_edit.text().strip() else None

        if not template.exists():
            QMessageBox.critical(self, "\u9519\u8bef", f"\u6a21\u677f\u4e0d\u5b58\u5728:\n{template}")
            return
        if not config_path.exists():
            QMessageBox.critical(self, "\u9519\u8bef", f"\u914d\u7f6e\u4e0d\u5b58\u5728:\n{config_path}")
            return
        if not result_root.exists():
            QMessageBox.critical(self, "\u9519\u8bef", f"\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55\u4e0d\u5b58\u5728:\n{result_root}")
            return
        if report_type == PERIOD_REPORT and wim_root is not None and not wim_root.exists():
            QMessageBox.critical(self, "\u9519\u8bef", f"WIM\u7ed3\u679c\u76ee\u5f55\u4e0d\u5b58\u5728:\n{wim_root}")
            return
        if report_type == PERIOD_REPORT and not self._validate_period_inputs(result_root, wim_root):
            return

        self._set_busy(True)
        self.log_edit.clear()
        self._thread = QThread(self)
        self._worker = ReportWorker(
            template=template,
            config_path=config_path,
            result_root=result_root,
            analysis_root=analysis_root,
            output_dir=output_dir,
            period_label=self.period_edit.text().strip(),
            monitoring_range=self.range_edit.text().strip(),
            report_date=self.date_edit.text().strip(),
            report_type=report_type,
            wim_root=wim_root,
            start_date=self.start_edit.text().strip(),
            end_date=self.end_edit.text().strip(),
        )
        self._worker.moveToThread(self._thread)
        self._thread.started.connect(self._worker.run)
        self._worker.log.connect(self._log)
        self._worker.finished.connect(self._on_finished)
        self._worker.failed.connect(self._on_failed)
        self._worker.finished.connect(self._thread.quit)
        self._worker.failed.connect(self._thread.quit)
        self._thread.finished.connect(self._cleanup_thread)
        self._thread.start()

    def _on_finished(self, manifest_path: str, report_path: str) -> None:
        self._last_output_dir = Path(report_path).parent
        self._set_busy(False)
        QMessageBox.information(self, "\u5b8c\u6210", f"\u62a5\u544a\u5df2\u751f\u6210:\n{report_path}\n\nManifest:\n{manifest_path}")

    def _on_failed(self, message: str) -> None:
        self._set_busy(False)
        QMessageBox.critical(self, "\u751f\u6210\u5931\u8d25", message)

    def _cleanup_thread(self) -> None:
        if self._worker is not None:
            self._worker.deleteLater()
            self._worker = None
        if self._thread is not None:
            self._thread.deleteLater()
            self._thread = None

    def _open_output_dir(self) -> None:
        out_dir = self._last_output_dir or Path(self.output_dir_edit.text()).expanduser()
        out_dir.mkdir(parents=True, exist_ok=True)
        try:
            os.startfile(str(out_dir))
        except Exception as exc:  # noqa: BLE001
            QMessageBox.critical(self, "\u6253\u5f00\u5931\u8d25", str(exc))


def main() -> None:
    app = QApplication(sys.argv)
    win = ReportGui()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
