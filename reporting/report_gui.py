from __future__ import annotations

import argparse
import json
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

from build_jlj_monthly_report import build_report as build_jlj_monthly_report
from build_guanbing_monthly_report import build_report as build_guanbing_monthly_report
from build_monthly_report import build_report as build_hongtang_monthly_report
from build_period_report import build_period_report
from build_shuixianhua_monthly_report import build_report as build_shuixianhua_monthly_report
from build_zhishan_monthly_report import build_report as build_zhishan_monthly_report
from bridge_profiles import BridgeProfile, load_profiles, profile_by_id
from missing_summary import missing_summary_paths
from analysis_manifest import manifest_precheck_warnings
from report_build_manifest import find_latest_report_build_manifest
from report_module_catalog import expected_result_dirs, expected_stats_files
from template_precheck import TemplateIssue, check_template, write_precheck_report


MONTHLY_REPORT = "\u6d2a\u5858\u6708\u62a5"
PERIOD_REPORT = "\u6d2a\u5858\u5468\u671f\u62a5\uff08\u542bWIM\uff09"
JLJ_MONTHLY_REPORT = "\u4e5d\u9f99\u6c5f\u6708\u62a5"
GUANBING_MONTHLY_REPORT = "管柄月报"
SHUIXIANHUA_MONTHLY_REPORT = "水仙花月报"
ZHISHAN_MONTHLY_REPORT = "芝山月报"
APP_VERSION = "v1.7.36"
MONTHLY_TEMPLATE_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u6708\u62a5\u6a21\u677f.docx"
PERIOD_TEMPLATE_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b2026\u5e74\u7b2c\u4e00\u5b63\u5b63\u62a5-\u65394.docx"
JLJ_TEMPLATE_NAME = "\u4e5d\u9f99\u6c5f\u5927\u6865\u5065\u5eb7\u76d1\u6d4b2026\u5e743\u6708\u4efd\u6708\u62a5_0508.docx"
GUANBING_TEMPLATE_NAME = "G104线管柄大桥监测月报模板-自动报告.docx"
SHUIXIANHUA_TEMPLATE_NAME = "水仙花大桥健康监测月报模板.docx"
ZHISHAN_TEMPLATE_NAME = "芝山大桥健康监测2026年3月份月报_0609_1652.docx"
PERIOD_TEMPLATE_AUTO_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f-\u81ea\u52a8\u62a5\u544a.docx"
PERIOD_TEMPLATE_LEGACY_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f0318.docx"
PERIOD_TEMPLATE_FALLBACK_NAME = "\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u5468\u671f\u62a5\u6a21\u677f.docx"
DEFAULT_RESULT_ROOT = Path("E:" + "\\" + "\u6d2a\u5858\u5927\u6865\u6570\u636e" + "\\" + "2026\u5e741-3\u6708")
DEFAULT_JLJ_RESULT_ROOT = Path("E:" + "\\" + "\u4e5d\u9f99\u6c5f\u6570\u636e" + "\\" + "2026\u5e743\u6708")
DEFAULT_GUANBING_RESULT_ROOT = Path("F:" + "\\" + "管柄大桥数据" + "\\" + "2026年3月")
DEFAULT_SHUIXIANHUA_RESULT_ROOT = Path("E:" + "\\" + "水仙花大桥数据" + "\\" + "2026年3月")
DEFAULT_ZHISHAN_RESULT_ROOT = Path("D:" + "\\" + "芝山大桥数据" + "\\" + "2026年3月")

PROFILE_REPORT_TYPES = {
    "hongtang_monthly": MONTHLY_REPORT,
    "hongtang_period_wim": PERIOD_REPORT,
    "jlj_monthly": JLJ_MONTHLY_REPORT,
    "guanbing_monthly": GUANBING_MONTHLY_REPORT,
    "shuixianhua_monthly": SHUIXIANHUA_MONTHLY_REPORT,
    "zhishan_monthly": ZHISHAN_MONTHLY_REPORT,
}


def report_type_for_profile(profile: BridgeProfile) -> str:
    return PROFILE_REPORT_TYPES.get(profile.report_gui_type, PERIOD_REPORT)


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


def profile_for_report_type(report_type: str) -> BridgeProfile | None:
    for profile in load_profiles(app_root()):
        if report_type_for_profile(profile) == report_type:
            return profile
    return None


def detect_default_config(report_type: str = PERIOD_REPORT) -> Path:
    profile = profile_for_report_type(report_type)
    if profile is not None:
        return profile.config_path(app_root())
    if report_type == JLJ_MONTHLY_REPORT:
        for config_dir in candidate_config_roots():
            jlj_cfg = config_dir / "jiulongjiang_config.json"
            if jlj_cfg.exists():
                return jlj_cfg.resolve()
        return (app_root() / "config" / "jiulongjiang_config.json").resolve()
    if report_type == GUANBING_MONTHLY_REPORT:
        for config_dir in candidate_config_roots():
            default_cfg = config_dir / "default_config.json"
            if default_cfg.exists():
                return default_cfg.resolve()
        return (app_root() / "config" / "default_config.json").resolve()
    if report_type == SHUIXIANHUA_MONTHLY_REPORT:
        for config_dir in candidate_config_roots():
            shx_cfg = config_dir / "shuixianhua_config.json"
            if shx_cfg.exists():
                return shx_cfg.resolve()
        return (app_root() / "config" / "shuixianhua_config.json").resolve()
    if report_type == ZHISHAN_MONTHLY_REPORT:
        for config_dir in candidate_config_roots():
            zhishan_cfg = config_dir / "zhishan_config.json"
            if zhishan_cfg.exists():
                return zhishan_cfg.resolve()
        return (app_root() / "config" / "zhishan_config.json").resolve()

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


def default_result_root(report_type: str) -> Path:
    profile = profile_for_report_type(report_type)
    if profile is not None and profile.default_data_root:
        return profile.data_root_path()
    if report_type == JLJ_MONTHLY_REPORT:
        return DEFAULT_JLJ_RESULT_ROOT
    if report_type == GUANBING_MONTHLY_REPORT:
        return DEFAULT_GUANBING_RESULT_ROOT
    if report_type == SHUIXIANHUA_MONTHLY_REPORT:
        return DEFAULT_SHUIXIANHUA_RESULT_ROOT
    if report_type == ZHISHAN_MONTHLY_REPORT:
        return DEFAULT_ZHISHAN_RESULT_ROOT
    return DEFAULT_RESULT_ROOT

def find_default_template(report_type: str) -> Path:
    profile = profile_for_report_type(report_type)
    if profile is not None and profile.report_template:
        candidate = profile.template_path(app_root())
        if candidate.exists():
            return candidate
    if report_type == JLJ_MONTHLY_REPORT:
        preferred = JLJ_TEMPLATE_NAME
        fallback_candidates = [JLJ_TEMPLATE_NAME]
    elif report_type == GUANBING_MONTHLY_REPORT:
        preferred = GUANBING_TEMPLATE_NAME
        fallback_candidates = [GUANBING_TEMPLATE_NAME]
    elif report_type == SHUIXIANHUA_MONTHLY_REPORT:
        preferred = SHUIXIANHUA_TEMPLATE_NAME
        fallback_candidates = [SHUIXIANHUA_TEMPLATE_NAME, JLJ_TEMPLATE_NAME]
    elif report_type == ZHISHAN_MONTHLY_REPORT:
        preferred = ZHISHAN_TEMPLATE_NAME
        fallback_candidates = [ZHISHAN_TEMPLATE_NAME, SHUIXIANHUA_TEMPLATE_NAME]
    elif report_type == PERIOD_REPORT:
        preferred = PERIOD_TEMPLATE_NAME
        fallback_candidates = [PERIOD_TEMPLATE_AUTO_NAME, PERIOD_TEMPLATE_LEGACY_NAME, PERIOD_TEMPLATE_FALLBACK_NAME, MONTHLY_TEMPLATE_NAME]
    else:
        preferred = MONTHLY_TEMPLATE_NAME
        fallback_candidates = [PERIOD_TEMPLATE_AUTO_NAME, PERIOD_TEMPLATE_FALLBACK_NAME]
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
        "桥梁项目：优先按管柄/洪塘/九龙江项目自动带出模板、配置、数据目录和报告类型；高级场景仍可手动覆盖各路径。\n"
        "\u6a21\u677f\u6587\u4ef6\uff1a\u6708\u62a5\u9ed8\u8ba4\u4f7f\u7528\u201c\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u6708\u62a5\u6a21\u677f.docx\u201d\uff0c"
        "\u5468\u671f\u62a5\u9ed8\u8ba4\u4f7f\u7528\u201c\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b2026\u5e74\u7b2c\u4e00\u5b63\u5b63\u62a5-\u65394.docx\u201d\uff0c"
        "\u4e5d\u9f99\u6c5f\u6708\u62a5\u9ed8\u8ba4\u4f7f\u7528\u201c\u4e5d\u9f99\u6c5f\u5927\u6865\u5065\u5eb7\u76d1\u6d4b2026\u5e743\u6708\u4efd\u6708\u62a5_\u4fee\u8ba25.docx\u201d\uff0c"
        "管柄月报默认使用“G104线管柄大桥监测月报模板-自动报告.docx”。\n"
        "\u914d\u7f6e\u6587\u4ef6\uff1a\u76f4\u63a5\u5f71\u54cd\u62a5\u544a\u751f\u6210\u7684\u4e3b\u8981\u662f plot_styles.* \u8f93\u51fa\u76ee\u5f55\u3001reporting.* \u63d2\u56fe\u987a\u5e8f/\u542f\u7528\u3001wim.* \u548c wim_db.*\u3002\n"
        "\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55\uff1a\u5b58\u653e\u56fe\u7247\u3001stats\u3001run_logs \u548c\u81ea\u52a8\u62a5\u544a\u3002\n"
        "\u5468\u671f\u62a5\u8bf4\u660e\uff1a1.4\u201c\u5065\u5eb7\u76d1\u6d4b\u7cfb\u7edf\u8fd0\u884c\u72b6\u51b5\u201d\u53ea\u7edf\u8ba1\u539f\u59cb\u6570\u636e\u7f3a\u5931/\u65e0\u6587\u4ef6/\u65e0\u8bb0\u5f55\u3002"
        "\u56e0\u6b64\u5468\u671f\u62a5\u6240\u9009\u7684\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55\uff0c\u5e94\u540c\u65f6\u5305\u542b\u539f\u59cb\u6570\u636e\u548c\u5904\u7406\u7ed3\u679c\u3002\n"
        "\u7a0b\u5e8f\u6839\u76ee\u5f55\uff08\u9ad8\u7ea7\uff09\uff1a\u4e3b\u8981\u7528\u4e8e\u517c\u5bb9\u65e7\u8def\u5f84\u548c\u56de\u9000\u67e5\u627e\uff0c\u901a\u5e38\u4fdd\u6301\u7a0b\u5e8f\u6240\u5728\u76ee\u5f55\u5373\u53ef\u3002"
    )


def report_type_description(report_type: str) -> str:
    if report_type == PERIOD_REPORT:
        return "\u6d2a\u5858\u5468\u671f\u62a5\uff1a\u4f7f\u7528\u6d2a\u5858\u5468\u671f/\u5b63\u62a5\u6a21\u677f\uff0c\u6309\u65e5\u671f\u8303\u56f4\u7ec4\u88c5\u975e WIM \u7ed3\u679c\uff0cWIM \u6309\u6708\u4ece WIM/results/hongtang \u63d2\u5165\uff0c\u5e76\u7edf\u8ba1 1.4 \u539f\u59cb\u6570\u636e\u7f3a\u5931\u3002"
    if report_type == JLJ_MONTHLY_REPORT:
        return "\u4e5d\u9f99\u6c5f\u6708\u62a5\uff1a\u4f7f\u7528\u4e5d\u9f99\u6c5f\u72ec\u7acb\u751f\u6210\u903b\u8f91\uff0c\u6309\u4e3b\u6865/\u5317\u6c5f\u6ee8\u531d\u9053/\u5357\u6c5f\u6ee8\u531d\u9053\u7ae0\u8282\u7ec4\u88c5\u7b2c 4 \u7ae0\u548c\u7ed3\u8bba\u9875\u3002"
    if report_type == GUANBING_MONTHLY_REPORT:
        return "管柄月报：使用管柄自动报告模板，按2026-02-26~2026-03-25这类月度周期从结果目录插入图片和统计文字；缺少挠度/倾角/加速度时程结果时保留模板原内容。"
    if report_type == SHUIXIANHUA_MONTHLY_REPORT:
        return "水仙花月报：使用水仙花独立模板，复用九龙江月报版式，按水仙花 stats、run_logs 和结果图片生成正文、摘要表、目录及 PDF。"
    if report_type == ZHISHAN_MONTHLY_REPORT:
        return "芝山月报：按芝山0609_1652模板生成，刷新梁端位移、结构振动、应变/动应变、索力加速度及索力换算表格和主要结果图。"
    return "\u6d2a\u5858\u6708\u62a5\uff1a\u4f7f\u7528\u65e7\u6d2a\u5858\u6708\u62a5\u6a21\u677f\u548c\u6708\u62a5\u751f\u6210\u6d41\u7a0b\uff0c\u9002\u7528\u5355\u6708\u5df2\u8ba1\u7b97\u597d\u7684\u7ed3\u679c\u76ee\u5f55\u3002"


class ReportWorker(QObject):
    log = Signal(str)
    finished = Signal(str, str, str)
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
            elif self.report_type == JLJ_MONTHLY_REPORT:
                report_path = build_jlj_monthly_report(
                    template=self.template,
                    config_path=self.config_path,
                    result_root=self.result_root,
                    image_root=self.result_root,
                    output_dir=self.output_dir,
                    wim_root=self.wim_root,
                    period_label=self.period_label,
                    monitoring_range=self.monitoring_range,
                    report_date=self.report_date,
                    patrol_docx=None,
                )
                manifest_path = find_latest_report_build_manifest(self.output_dir or (self.result_root / "自动报告"))
                missing = []
            elif self.report_type == GUANBING_MONTHLY_REPORT:
                report_path, manifest_path = build_guanbing_monthly_report(
                    template=self.template,
                    config_path=self.config_path,
                    result_root=self.result_root,
                    output_dir=self.output_dir,
                    period_label=self.period_label,
                    monitoring_range=self.monitoring_range,
                    report_date=self.report_date,
                    start_date=self.start_date,
                    end_date=self.end_date,
                )
                missing = []
            elif self.report_type == SHUIXIANHUA_MONTHLY_REPORT:
                report_path, pdf_path = build_shuixianhua_monthly_report(
                    template=self.template,
                    config_path=self.config_path,
                    result_root=self.result_root,
                    output_dir=self.output_dir,
                    period_label=self.period_label,
                    monitoring_range=self.monitoring_range,
                    report_date=self.report_date,
                )
                manifest_path = None
                missing = []
                if pdf_path is not None:
                    self.log.emit(f"PDF:      {pdf_path}")
            elif self.report_type == ZHISHAN_MONTHLY_REPORT:
                report_path, manifest_path = build_zhishan_monthly_report(
                    template=self.template,
                    config_path=self.config_path,
                    result_root=self.result_root,
                    output_dir=self.output_dir,
                    period_label=self.period_label,
                    monitoring_range=self.monitoring_range,
                    report_date=self.report_date,
                )
                missing = []
            else:
                manifest_path, report_path, missing = build_hongtang_monthly_report(
                    template=self.template,
                    config_path=self.config_path,
                    result_root=self.result_root,
                    analysis_root=self.analysis_root,
                    output_dir=self.output_dir,
                    period_label=self.period_label,
                    monitoring_range=self.monitoring_range,
                    report_date=self.report_date,
                )

            if manifest_path is not None:
                self.log.emit(f"Manifest: {manifest_path}")
            self.log.emit(f"Report:   {report_path}")
            if missing:
                self.log.emit("\u8b66\u544a/\u7f3a\u5931\u8d44\u6e90:")
                for item in missing:
                    self.log.emit(f"  - {item}")
            summary_files = [path for path in missing_summary_paths(report_path) if path.exists()]
            if summary_files:
                self.log.emit("\u7f3a\u5931\u5185\u5bb9\u6e05\u5355:")
                for path in summary_files:
                    self.log.emit(f"  - {path}")
            self.log.emit("\u5b8c\u6210")
            self.finished.emit(str(manifest_path or ""), str(report_path), "\n".join(str(path) for path in summary_files))
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
        self.profiles = load_profiles(app_root())
        self._updating_profile = False
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
        self.current_profile = profile_by_id(self.profiles, "hongtang")
        initial_report_type = report_type_for_profile(self.current_profile)
        initial_result_root = self.current_profile.data_root_path() if self.current_profile.default_data_root else default_result_root(initial_report_type)

        self.profile_combo = QComboBox()
        for profile in self.profiles:
            self.profile_combo.addItem(profile.bridge_name, profile.bridge_id)
        self.profile_combo.setCurrentIndex(max(0, self.profile_combo.findData(self.current_profile.bridge_id)))
        self.report_type_combo = QComboBox()
        self.report_type_combo.addItems([MONTHLY_REPORT, PERIOD_REPORT, JLJ_MONTHLY_REPORT, GUANBING_MONTHLY_REPORT, SHUIXIANHUA_MONTHLY_REPORT, ZHISHAN_MONTHLY_REPORT])
        self.report_type_combo.setCurrentText(initial_report_type)
        self.report_type_desc_label: QLabel | None = None
        self.profile_desc_label: QLabel | None = None
        self.template_edit = QLineEdit(str(self.current_profile.template_path(repo_root)))
        self.config_edit = QLineEdit(str(self.current_profile.config_path(repo_root)))
        self.result_root_edit = QLineEdit(str(initial_result_root))
        self.analysis_root_edit = QLineEdit(str(repo_root.resolve()))
        self.wim_root_edit = QLineEdit(str(self.current_profile.wim_root_for(initial_result_root)))
        self.output_dir_edit = QLineEdit(str(derive_output_dir(initial_result_root)))
        self.period_edit = QLineEdit(self.current_profile.default_period_label or "2026\u5e741-3\u6708")
        self.range_edit = QLineEdit(self.current_profile.default_monitoring_range or "2026年01月01日~2026年03月31日")
        self.start_edit = QLineEdit(self.current_profile.default_start_date or "2026-01-01")
        self.end_edit = QLineEdit(self.current_profile.default_end_date or "2026-03-31")
        self.date_edit = QLineEdit(datetime.now().strftime("%Y\u5e74%m\u6708%d\u65e5"))

        rows = [
            ("桥梁项目", self.profile_combo, None, self._profile_description(self.current_profile)),
            ("\u62a5\u544a\u7c7b\u578b", self.report_type_combo, None, report_type_description(initial_report_type)),
            ("\u6a21\u677f\u6587\u4ef6", self.template_edit, self._browse_template, "\u6d2a\u5858\u6708\u62a5\uff1a\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b\u6708\u62a5\u6a21\u677f.docx\uff1b\u6d2a\u5858\u5468\u671f\u62a5\uff1a\u6d2a\u5858\u5927\u6865\u5065\u5eb7\u76d1\u6d4b2026\u5e74\u7b2c\u4e00\u5b63\u5b63\u62a5-\u65394.docx\uff1b\u4e5d\u9f99\u6c5f\u6708\u62a5\uff1a\u4e5d\u9f99\u6c5f\u5927\u6865\u5065\u5eb7\u76d1\u6d4b2026\u5e743\u6708\u4efd\u6708\u62a5_\u4fee\u8ba25.docx\uff1b管柄月报：G104线管柄大桥监测月报模板-自动报告.docx；水仙花月报：水仙花大桥健康监测月报模板.docx。"),
            ("\u914d\u7f6e\u6587\u4ef6", self.config_edit, self._browse_config, "\u6d2a\u5858\u4f18\u5148\u8bfb\u53d6\u673a\u5668\u4e13\u7528\u914d\u7f6e hongtang_config_<COMPUTERNAME>.json\uff1b\u4e5d\u9f99\u6c5f\u9ed8\u8ba4\u4f7f\u7528 jiulongjiang_config.json；管柄默认使用 default_config.json。"),
            ("\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55", self.result_root_edit, self._browse_result_root, "\u8fd9\u91cc\u5e94\u5b58\u653e\u56fe\u7247\u3001stats\u3001run_logs \u548c\u81ea\u52a8\u62a5\u544a\u3002\u5bf9\u5468\u671f\u62a5\uff0c\u8fd9\u4e2a\u76ee\u5f55\u6700\u597d\u540c\u65f6\u5305\u542b raw \u539f\u59cb\u6570\u636e\uff0c\u5426\u5219 1.4 \u7ae0\u8282\u4f1a\u5c06\u7f3a\u5c11\u539f\u59cb\u6570\u636e\u89c6\u4e3a\u7f3a\u5931\u3002"),
            ("\u7a0b\u5e8f\u6839\u76ee\u5f55\uff08\u9ad8\u7ea7\uff09", self.analysis_root_edit, self._browse_analysis_root, "\u517c\u5bb9\u65e7\u8def\u5f84\u548c\u5c11\u91cf\u56de\u9000\u67e5\u627e\uff0c\u901a\u5e38\u4fdd\u6301\u7a0b\u5e8f\u6240\u5728\u76ee\u5f55\u5373\u53ef\u3002"),
            ("WIM\u7ed3\u679c\u76ee\u5f55", self.wim_root_edit, self._browse_wim_root, "\u5468\u671f\u62a5\u4f7f\u7528\uff0c\u9ed8\u8ba4\u662f <\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55>/WIM/results/hongtang\u3002WIM \u4ecd\u6309\u6708\u63d2\u5165\uff0c\u4e0d\u662f\u628a 1~3 \u4e2a\u6708\u76f4\u63a5\u5408\u6210\u4e00\u5f20\u8868\u3002"),
            ("\u8f93\u51fa\u76ee\u5f55", self.output_dir_edit, self._browse_output_dir, "\u62a5\u544a\u8f93\u51fa\u76ee\u5f55\uff0c\u9ed8\u8ba4\u662f <\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55>/\u81ea\u52a8\u62a5\u544a\u3002"),
            ("\u62a5\u544a\u671f", self.period_edit, None, "\u663e\u793a\u5728\u62a5\u544a\u4e2d\u7684\u62a5\u544a\u671f\u6587\u5b57\uff0c\u4f8b\u5982 2026\u5e741-3\u6708\u3002"),
            ("\u76d1\u6d4b\u65f6\u95f4", self.range_edit, None, "\u663e\u793a\u5728\u62a5\u544a\u4e2d\u7684\u76d1\u6d4b\u65f6\u95f4\u6587\u5b57\uff0c\u4f8b\u5982 2026\u5e7401\u670801\u65e5~2026\u5e7403\u670831\u65e5\u3002"),
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
            if edit is self.profile_combo:
                self.profile_desc_label = tip_label
            if edit is self.report_type_combo:
                self.report_type_desc_label = tip_label

        self.profile_combo.currentIndexChanged.connect(self._on_profile_changed)
        self.report_type_combo.currentTextChanged.connect(self._on_report_type_changed)

        action_row = QHBoxLayout()
        self.generate_btn = QPushButton("\u751f\u6210\u62a5\u544a")
        self.generate_btn.clicked.connect(self._on_generate)
        action_row.addWidget(self.generate_btn)

        self.check_btn = QPushButton("\u68c0\u67e5\u6a21\u677f/\u76ee\u5f55")
        self.check_btn.clicked.connect(self._on_check_inputs)
        action_row.addWidget(self.check_btn)

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
        self._last_result_root = initial_result_root

    def _profile_description(self, profile: BridgeProfile) -> str:
        return (
            f"{profile.bridge_name}：默认配置 {Path(profile.default_config).name}；"
            f"目录格式 {profile.data_layout or '/'}；选择后会自动带出模板、配置、数据目录和 WIM 目录。"
        )

    def _on_profile_changed(self, index: int) -> None:
        bridge_id = self.profile_combo.itemData(index)
        profile = profile_by_id(self.profiles, str(bridge_id))
        self.current_profile = profile
        self._updating_profile = True
        self.report_type_combo.setCurrentText(report_type_for_profile(profile))
        self._updating_profile = False
        self._apply_profile_defaults(profile)
        self._sync_report_type_state(self.report_type_combo.currentText())
        self._log(f"已切换桥梁项目: {profile.bridge_name}")

    def _apply_profile_defaults(self, profile: BridgeProfile) -> None:
        repo_root = app_root()
        report_type = report_type_for_profile(profile)
        self.template_edit.setText(str(profile.template_path(repo_root)))
        self.config_edit.setText(str(profile.config_path(repo_root)))
        if profile.default_data_root:
            result_root = profile.data_root_path()
            self.result_root_edit.setText(str(result_root))
            self.wim_root_edit.setText(str(profile.wim_root_for(result_root)))
            self.output_dir_edit.setText(str(derive_output_dir(result_root)))
            self._last_result_root = result_root
        if profile.default_period_label:
            self.period_edit.setText(profile.default_period_label)
        if profile.default_monitoring_range:
            self.range_edit.setText(profile.default_monitoring_range)
        if profile.default_start_date:
            self.start_edit.setText(profile.default_start_date)
        if profile.default_end_date:
            self.end_edit.setText(profile.default_end_date)
        if getattr(profile, "default_report_date", ""):
            self.date_edit.setText(profile.default_report_date)
        if self.profile_desc_label is not None:
            self.profile_desc_label.setText(self._profile_description(profile))
        if self.report_type_desc_label is not None:
            self.report_type_desc_label.setText(report_type_description(report_type))

    def _sync_report_type_state(self, text: str) -> None:
        period_mode = text == PERIOD_REPORT
        date_range_mode = text in (PERIOD_REPORT, GUANBING_MONTHLY_REPORT)
        self.wim_root_edit.setEnabled(period_mode)
        self.start_edit.setEnabled(date_range_mode)
        self.end_edit.setEnabled(date_range_mode)
        if self.report_type_desc_label is not None:
            self.report_type_desc_label.setText(report_type_description(text))

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
        names = {
            MONTHLY_TEMPLATE_NAME,
            PERIOD_TEMPLATE_NAME,
            JLJ_TEMPLATE_NAME,
            GUANBING_TEMPLATE_NAME,
            SHUIXIANHUA_TEMPLATE_NAME,
            ZHISHAN_TEMPLATE_NAME,
            PERIOD_TEMPLATE_AUTO_NAME,
            PERIOD_TEMPLATE_LEGACY_NAME,
            PERIOD_TEMPLATE_FALLBACK_NAME,
        }
        should_replace = (not current) or (Path(current).name in names) or (not Path(current).exists())
        if should_replace:
            self.template_edit.setText(str(find_default_template(self.report_type_combo.currentText())))

    def _maybe_update_config_for_type(self) -> None:
        current = self.config_edit.text().strip()
        names = {
            "hongtang_config.json",
            "jiulongjiang_config.json",
            "default_config.json",
            "shuixianhua_config.json",
            "zhishan_config.json",
        }
        computer_name = os.environ.get("COMPUTERNAME", "").strip()
        if computer_name:
            names.add(f"hongtang_config_{computer_name}.json")
        should_replace = (not current) or (Path(current).name in names) or (not Path(current).exists())
        if should_replace:
            self.config_edit.setText(str(detect_default_config(self.report_type_combo.currentText())))

    def _maybe_update_result_root_for_type(self) -> None:
        current = self.result_root_edit.text().strip()
        known_roots = {profile.data_root_path() for profile in self.profiles if profile.default_data_root}
        current_path = Path(current).expanduser() if current else None
        should_replace = (current_path is None) or (current_path in known_roots) or (not current_path.exists())
        if should_replace:
            new_root = default_result_root(self.report_type_combo.currentText())
            self.result_root_edit.setText(str(new_root))
            self._sync_result_dependent_paths(previous_root=current_path, force=True)

    def _profile_for_report_type(self, report_type: str) -> BridgeProfile:
        for profile in self.profiles:
            if report_type_for_profile(profile) == report_type:
                return profile
        return self.current_profile

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
        new_wim = self.current_profile.wim_root_for(result_root) if hasattr(self, "current_profile") else derive_wim_root(result_root)
        new_out = derive_output_dir(result_root)

        should_update_wim = force or old_wim is None or "outputs" in old_wim.parts
        should_update_out = force or old_out is None

        if previous_root is not None:
            previous_wim = self.current_profile.wim_root_for(previous_root) if hasattr(self, "current_profile") else derive_wim_root(previous_root)
            if old_wim == previous_wim:
                should_update_wim = True
            if old_out == derive_output_dir(previous_root):
                should_update_out = True
        if old_wim == new_wim:
            should_update_wim = True
        if old_out == derive_output_dir(result_root):
            should_update_out = True

        if should_update_wim:
            self.wim_root_edit.setText(str(new_wim))
        if should_update_out or not self.output_dir_edit.text().strip():
            self.output_dir_edit.setText(str(new_out))
        self._last_result_root = result_root

    def _on_report_type_changed(self, text: str) -> None:
        self._sync_report_type_state(text)
        if self._updating_profile:
            return
        self._maybe_update_template_for_type()
        self._maybe_update_config_for_type()
        self._maybe_update_result_root_for_type()
        if text == GUANBING_MONTHLY_REPORT:
            self.period_edit.setText("2026年03月")
            self.range_edit.setText("2026年02月26日~2026年03月25日")
            self.start_edit.setText("2026-02-26")
            self.end_edit.setText("2026-03-25")
        elif text == SHUIXIANHUA_MONTHLY_REPORT:
            self.period_edit.setText("2026年3月份")
            self.range_edit.setText("2026年03月23日~2026年03月31日")
            self.start_edit.setText("2026-03-23")
            self.end_edit.setText("2026-03-31")
            self.date_edit.setText("2026年04月05日")
        elif text == ZHISHAN_MONTHLY_REPORT:
            self.period_edit.setText("2026年3月")
            self.range_edit.setText("2026年03月01日~2026年03月31日")
            self.start_edit.setText("2026-03-01")
            self.end_edit.setText("2026-03-31")

    def _read_period_dates(self) -> tuple[date, date]:
        start_date = parse_iso_date(self.start_edit.text().strip())
        end_date = parse_iso_date(self.end_edit.text().strip())
        if end_date < start_date:
            raise ValueError("\u7ed3\u675f\u65e5\u671f\u4e0d\u80fd\u65e9\u4e8e\u5f00\u59cb\u65e5\u671f\u3002")
        return start_date, end_date

    def _collect_period_warnings(self, result_root: Path, wim_root: Path | None, start_date: date, end_date: date) -> list[str]:
        warnings: list[str] = []
        warnings.extend(manifest_precheck_warnings(result_root))

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
        profile = self._profile_for_report_type(PERIOD_REPORT)
        missing_stats = self._missing_profile_stats(result_root, profile)
        if missing_stats:
            warnings.append(f"\u7f3a\u5c11\u7edf\u8ba1\u8868\uff1a{', '.join(missing_stats)}\u3002\u5bf9\u5e94\u7ae0\u8282\u53ef\u80fd\u4fdd\u6301\u6a21\u677f\u539f\u72b6\u6216\u663e\u793a\u7f3a\u5931\u3002")
        missing_dirs = self._missing_profile_dirs(result_root, profile)
        if missing_dirs:
            warnings.append(f"\u7f3a\u5c11\u5173\u952e\u56fe\u7247\u76ee\u5f55\uff1a{', '.join(missing_dirs)}\u3002")
        return warnings

    def _missing_stats_files(self, result_root: Path, names: list[str]) -> list[str]:
        stats_dir = result_root / "stats"
        return [name for name in names if not (stats_dir / name).exists()]

    def _missing_result_dirs(self, result_root: Path, names: list[str]) -> list[str]:
        return [name for name in names if not (result_root / name).exists()]

    def _missing_profile_stats(self, result_root: Path, profile: BridgeProfile, *, extra: list[str] | None = None) -> list[str]:
        return self._missing_stats_files(result_root, expected_stats_files(profile.enabled_modules, extra=extra))

    def _missing_profile_dirs(self, result_root: Path, profile: BridgeProfile, *, extra: list[str] | None = None) -> list[str]:
        return self._missing_result_dirs(result_root, expected_result_dirs(profile.bridge_id, profile.enabled_modules, extra=extra))

    def _collect_jlj_warnings(self, result_root: Path) -> list[str]:
        warnings: list[str] = []
        warnings.extend(manifest_precheck_warnings(result_root))
        if not (result_root / "stats").exists():
            warnings.append("`stats/` \u4e0d\u5b58\u5728\uff0c\u4e5d\u9f99\u6c5f\u6708\u62a5\u7edd\u5927\u90e8\u5206\u7edf\u8ba1\u8868\u65e0\u6cd5\u586b\u5145\u3002")
        profile = self._profile_for_report_type(JLJ_MONTHLY_REPORT)
        missing_stats = self._missing_profile_stats(result_root, profile, extra=["bearing_displacement_stats.xlsx"])
        if missing_stats:
            warnings.append(f"\u7f3a\u5c11\u4e5d\u9f99\u6c5f\u6708\u62a5\u7edf\u8ba1\u8868\uff1a{', '.join(missing_stats)}\u3002")
        missing_dirs = self._missing_profile_dirs(result_root, profile)
        if missing_dirs:
            warnings.append(f"\u7f3a\u5c11\u4e5d\u9f99\u6c5f\u6708\u62a5\u5173\u952e\u56fe\u7247\u76ee\u5f55\uff1a{', '.join(missing_dirs)}\u3002")
        return warnings

    def _collect_guanbing_warnings(self, result_root: Path) -> list[str]:
        warnings: list[str] = []
        warnings.extend(manifest_precheck_warnings(result_root))
        if not (result_root / "stats").exists():
            warnings.append("`stats/` 不存在，管柄月报统计文字无法完整刷新。")
        profile = self._profile_for_report_type(GUANBING_MONTHLY_REPORT)
        missing_stats = self._missing_profile_stats(result_root, profile)
        if missing_stats:
            warnings.append(f"缺少管柄月报统计表：{', '.join(missing_stats)}。")
        missing_dirs = self._missing_profile_dirs(result_root, profile)
        if missing_dirs:
            warnings.append(f"缺少管柄月报关键图片目录：{', '.join(missing_dirs)}。")
        return warnings

    def _collect_shuixianhua_warnings(self, result_root: Path) -> list[str]:
        warnings: list[str] = []
        warnings.extend(manifest_precheck_warnings(result_root))
        if not (result_root / "stats").exists():
            warnings.append("`stats/` 不存在，水仙花月报统计表无法填充。")
        profile = self._profile_for_report_type(SHUIXIANHUA_MONTHLY_REPORT)
        missing_stats = self._missing_profile_stats(result_root, profile)
        if missing_stats:
            warnings.append(f"缺少水仙花月报统计表：{', '.join(missing_stats)}。")
        missing_dirs = self._missing_profile_dirs(result_root, profile)
        if missing_dirs:
            warnings.append(f"缺少水仙花月报关键图片目录：{', '.join(missing_dirs)}。")
        return warnings

    def _collect_zhishan_warnings(self, result_root: Path) -> list[str]:
        warnings: list[str] = []
        warnings.extend(manifest_precheck_warnings(result_root))
        if not (result_root / "stats").exists():
            warnings.append("`stats/` 不存在，芝山月报统计表无法填充。")
        profile = self._profile_for_report_type(ZHISHAN_MONTHLY_REPORT)
        missing_stats = self._missing_profile_stats(result_root, profile)
        if missing_stats:
            warnings.append(f"缺少芝山月报统计表：{', '.join(missing_stats)}。")
        missing_dirs = self._missing_profile_dirs(
            result_root,
            profile,
            extra=[
                "时程曲线_梁端纵向位移_组图",
                "时程曲线_加速度_组图",
                "时程曲线_加速度_RMS10min_组图",
                "频谱峰值曲线_结构加速度_组图",
                "时程曲线_动应变_高通滤波_组图",
                "时程曲线_动应变_低通滤波_组图",
                "动应变箱线图_高通滤波",
                "时程曲线_索力加速度",
                "索力时程图",
                "PSD_备查",
                "PSD_备查_索力加速度",
            ],
        )
        if missing_dirs:
            warnings.append(f"缺少芝山月报关键图片目录：{', '.join(missing_dirs)}。")
        return warnings

    def _template_check_kind(self, report_type: str) -> str | None:
        if report_type == PERIOD_REPORT:
            return "hongtang_period"
        if report_type == JLJ_MONTHLY_REPORT:
            return "jlj_monthly"
        if report_type == GUANBING_MONTHLY_REPORT:
            return "guanbing_monthly"
        if report_type == SHUIXIANHUA_MONTHLY_REPORT:
            return "shuixianhua_monthly"
        if report_type == ZHISHAN_MONTHLY_REPORT:
            return "zhishan_monthly"
        return None

    def _format_template_issues(self, issues: list[TemplateIssue]) -> str:
        return "\n".join(f"- [{issue.code}] {issue.message}" for issue in issues)

    def _precheck_output_dir(self) -> Path:
        output_text = self.output_dir_edit.text().strip()
        if output_text:
            return Path(output_text).expanduser() / "precheck"
        result_text = self.result_root_edit.text().strip()
        if result_text:
            return derive_output_dir(Path(result_text).expanduser()) / "precheck"
        return app_root() / "outputs" / "report_precheck"

    def _write_precheck_report(
        self,
        template: Path,
        report_type: str,
        issues: list[TemplateIssue],
        warnings: list[str] | None = None,
    ) -> tuple[Path, Path] | None:
        kind = self._template_check_kind(report_type) or "hongtang_monthly"
        context = {
            "bridge_profile": getattr(self.current_profile, "bridge_id", ""),
            "report_type": report_type,
            "config_path": self.config_edit.text().strip(),
            "result_root": self.result_root_edit.text().strip(),
            "wim_root": self.wim_root_edit.text().strip(),
            "output_dir": self.output_dir_edit.text().strip(),
            "period_label": self.period_edit.text().strip(),
            "monitoring_range": self.range_edit.text().strip(),
            "start_date": self.start_edit.text().strip(),
            "end_date": self.end_edit.text().strip(),
        }
        try:
            return write_precheck_report(
                kind=kind,
                template=template,
                issues=issues,
                warnings=warnings or [],
                output_dir=self._precheck_output_dir(),
                context=context,
            )
        except Exception as exc:  # noqa: BLE001
            self._log(f"预检报告写入失败: {exc}")
            return None

    def _validate_period_inputs(self, result_root: Path, wim_root: Path | None) -> bool:
        try:
            start_date, end_date = self._read_period_dates()
        except ValueError:
            QMessageBox.critical(self, "\u9519\u8bef", "\u5f00\u59cb/\u7ed3\u675f\u65e5\u671f\u683c\u5f0f\u5fc5\u987b\u662f YYYY-MM-DD\uff0c\u4e14\u7ed3\u675f\u65e5\u671f\u4e0d\u80fd\u65e9\u4e8e\u5f00\u59cb\u65e5\u671f\u3002")
            return False

        warnings = self._collect_period_warnings(result_root, wim_root, start_date, end_date)

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

    def _on_check_inputs(self) -> None:
        template = Path(self.template_edit.text()).expanduser()
        config_path = Path(self.config_edit.text()).expanduser()
        result_root = Path(self.result_root_edit.text()).expanduser()
        report_type = self.report_type_combo.currentText()
        wim_root = Path(self.wim_root_edit.text()).expanduser() if self.wim_root_edit.text().strip() else None

        errors: list[str] = []
        warnings: list[str] = []
        if not template.exists():
            errors.append(f"\u6a21\u677f\u4e0d\u5b58\u5728: {template}")
        if not config_path.exists():
            errors.append(f"\u914d\u7f6e\u4e0d\u5b58\u5728: {config_path}")
        if not result_root.exists():
            errors.append(f"\u6570\u636e/\u7ed3\u679c\u6839\u76ee\u5f55\u4e0d\u5b58\u5728: {result_root}")
        if errors:
            QMessageBox.critical(self, "\u68c0\u67e5\u5931\u8d25", "\n".join(f"- {item}" for item in errors))
            return

        template_issues: list[TemplateIssue] = []
        kind = self._template_check_kind(report_type)
        if kind is None:
            warnings.append("\u6708\u62a5\u6682\u672a\u914d\u7f6e\u6a21\u677f\u951a\u70b9\u9884\u68c0\uff0c\u672c\u6b21\u4ec5\u68c0\u67e5\u6587\u4ef6\u548c\u7ed3\u679c\u76ee\u5f55\u3002")
        else:
            try:
                template_issues = check_template(kind, template)
            except Exception as exc:  # noqa: BLE001
                template_issues = [TemplateIssue("precheck-error", str(exc))]

        if report_type == PERIOD_REPORT:
            try:
                start_date, end_date = self._read_period_dates()
                warnings.extend(self._collect_period_warnings(result_root, wim_root, start_date, end_date))
            except ValueError:
                errors.append("\u5f00\u59cb/\u7ed3\u675f\u65e5\u671f\u683c\u5f0f\u5fc5\u987b\u662f YYYY-MM-DD\uff0c\u4e14\u7ed3\u675f\u65e5\u671f\u4e0d\u80fd\u65e9\u4e8e\u5f00\u59cb\u65e5\u671f\u3002")
        elif report_type == JLJ_MONTHLY_REPORT:
            warnings.extend(self._collect_jlj_warnings(result_root))
        elif report_type == GUANBING_MONTHLY_REPORT:
            warnings.extend(self._collect_guanbing_warnings(result_root))
        elif report_type == SHUIXIANHUA_MONTHLY_REPORT:
            warnings.extend(self._collect_shuixianhua_warnings(result_root))
        elif report_type == ZHISHAN_MONTHLY_REPORT:
            warnings.extend(self._collect_zhishan_warnings(result_root))

        report_paths = self._write_precheck_report(template, report_type, template_issues, warnings)
        report_note = ""
        if report_paths is not None:
            txt_path, json_path = report_paths
            report_note = f"\n\n预检报告:\n{txt_path}\n{json_path}"

        if template_issues:
            QMessageBox.critical(
                self,
                "\u6a21\u677f\u9884\u68c0\u5931\u8d25",
                self._format_template_issues(template_issues) + report_note,
            )
            return
        if errors:
            QMessageBox.critical(self, "\u68c0\u67e5\u5931\u8d25", "\n".join(f"- {item}" for item in errors))
            return
        if warnings:
            QMessageBox.warning(self, "\u68c0\u67e5\u5b8c\u6210\uff08\u6709\u63d0\u793a\uff09", "\n".join(f"- {item}" for item in warnings) + report_note)
            return
        QMessageBox.information(self, "\u68c0\u67e5\u901a\u8fc7", "\u6a21\u677f\u3001\u914d\u7f6e\u548c\u7ed3\u679c\u76ee\u5f55\u68c0\u67e5\u901a\u8fc7\u3002" + report_note)

    def _log(self, text: str) -> None:
        self.log_edit.appendPlainText(text)

    def _set_busy(self, busy: bool) -> None:
        self.generate_btn.setEnabled(not busy)
        self.check_btn.setEnabled(not busy)
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
        kind = self._template_check_kind(report_type)
        template_warnings: list[str] = []
        template_issues: list[TemplateIssue] = []
        if kind is None:
            template_warnings.append("\u6708\u62a5\u6682\u672a\u914d\u7f6e\u6a21\u677f\u951a\u70b9\u9884\u68c0\uff0c\u672c\u6b21\u4ec5\u8bb0\u5f55\u6587\u4ef6\u68c0\u67e5\u7ed3\u679c\u3002")
        else:
            try:
                template_issues = check_template(kind, template)
            except Exception as exc:  # noqa: BLE001
                template_issues = [TemplateIssue("precheck-error", str(exc))]
        report_paths = self._write_precheck_report(template, report_type, template_issues, template_warnings)
        report_note = ""
        if report_paths is not None:
            txt_path, json_path = report_paths
            report_note = f"\n\n预检报告:\n{txt_path}\n{json_path}"
        if template_issues:
            QMessageBox.critical(
                self,
                "\u6a21\u677f\u9884\u68c0\u5931\u8d25",
                self._format_template_issues(template_issues) + report_note,
            )
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

    def _on_finished(self, manifest_path: str, report_path: str, summary_paths: str) -> None:
        self._last_output_dir = Path(report_path).parent
        self._set_busy(False)
        message = f"\u62a5\u544a\u5df2\u751f\u6210:\n{report_path}"
        if manifest_path:
            message += f"\n\nManifest:\n{manifest_path}"
        if summary_paths:
            message += f"\n\n\u7f3a\u5931\u5185\u5bb9\u6e05\u5355:\n{summary_paths}"
        QMessageBox.information(self, "\u5b8c\u6210", message)

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


def _self_test_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="BridgeReportBuilder hidden self-test entry.")
    parser.add_argument("--self-test-shuixianhua", action="store_true")
    parser.add_argument("--self-test-zhishan", action="store_true")
    parser.add_argument("--self-test-template", type=Path, default=None)
    parser.add_argument("--self-test-config", type=Path, default=None)
    parser.add_argument("--self-test-result-root", type=Path, default=None)
    parser.add_argument("--self-test-output-root", type=Path, default=app_root() / "tmp" / "report_exe_selftest")
    parser.add_argument("--self-test-period-label", default=None)
    parser.add_argument("--self-test-monitoring-range", default=None)
    parser.add_argument("--self-test-report-date", default=None)
    parser.add_argument("--self-test-no-word-update", action="store_true")
    return parser


def maybe_run_self_test(argv: list[str]) -> int | None:
    if "--self-test-shuixianhua" not in argv and "--self-test-zhishan" not in argv:
        return None
    parser = _self_test_parser()
    args = parser.parse_args(argv)
    if not args.self_test_shuixianhua and not args.self_test_zhishan:
        return None
    result_path = args.self_test_output_root / "selftest_result.json"
    if args.self_test_zhishan:
        try:
            profile = profile_for_report_type(ZHISHAN_MONTHLY_REPORT)
            template = (args.self_test_template or find_default_template(ZHISHAN_MONTHLY_REPORT)).expanduser().resolve()
            config_path = (args.self_test_config or detect_default_config(ZHISHAN_MONTHLY_REPORT)).expanduser().resolve()
            result_root = (args.self_test_result_root or default_result_root(ZHISHAN_MONTHLY_REPORT)).expanduser().resolve()
            output_dir = (args.self_test_output_root / "zhishan").expanduser().resolve()
            output_dir.mkdir(parents=True, exist_ok=True)
            period_label = args.self_test_period_label or (profile.default_period_label if profile else "") or "2026年3月"
            monitoring_range = (
                args.self_test_monitoring_range
                or (profile.default_monitoring_range if profile else "")
                or "2026年03月01日~2026年03月31日"
            )
            report_date = args.self_test_report_date or (profile.default_report_date if profile else "") or datetime.now().strftime("%Y年%m月%d日")
            issues = check_template("zhishan_monthly", template)
            if issues:
                joined = "; ".join(f"{issue.code}: {issue.message}" for issue in issues)
                raise RuntimeError(f"Template precheck failed: {joined}")
            report_path, manifest_path = build_zhishan_monthly_report(
                template=template,
                config_path=config_path,
                result_root=result_root,
                output_dir=output_dir,
                period_label=period_label,
                monitoring_range=monitoring_range,
                report_date=report_date,
                update_word=not args.self_test_no_word_update,
            )
            if not report_path.exists() or report_path.stat().st_size <= 0:
                raise RuntimeError(f"Self-test report missing or empty: {report_path}")
            result_path.parent.mkdir(parents=True, exist_ok=True)
            result_path.write_text(
                json.dumps(
                    {
                        "ok": True,
                        "version": APP_VERSION,
                        "template": str(template),
                        "config": str(config_path),
                        "result_root": str(result_root),
                        "report": str(report_path),
                        "manifest": str(manifest_path),
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )
            return 0
        except Exception as exc:  # noqa: BLE001
            result_path.parent.mkdir(parents=True, exist_ok=True)
            result_path.write_text(
                json.dumps(
                    {
                        "ok": False,
                        "version": APP_VERSION,
                        "error": str(exc),
                        "traceback": traceback.format_exc(),
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
                encoding="utf-8",
            )
            return 1
    try:
        profile = profile_for_report_type(SHUIXIANHUA_MONTHLY_REPORT)
        template = (args.self_test_template or find_default_template(SHUIXIANHUA_MONTHLY_REPORT)).expanduser().resolve()
        config_path = (args.self_test_config or detect_default_config(SHUIXIANHUA_MONTHLY_REPORT)).expanduser().resolve()
        result_root = (args.self_test_result_root or default_result_root(SHUIXIANHUA_MONTHLY_REPORT)).expanduser().resolve()
        output_dir = (args.self_test_output_root / "shuixianhua").expanduser().resolve()
        output_dir.mkdir(parents=True, exist_ok=True)

        period_label = args.self_test_period_label or (profile.default_period_label if profile else "") or "2026年3月份"
        monitoring_range = (
            args.self_test_monitoring_range
            or (profile.default_monitoring_range if profile else "")
            or "2026年3月23日~2026年3月31日"
        )
        report_date = args.self_test_report_date or (profile.default_report_date if profile else "") or "2026年4月5日"

        issues = check_template("shuixianhua_monthly", template)
        if issues:
            joined = "; ".join(f"{issue.code}: {issue.message}" for issue in issues)
            raise RuntimeError(f"Template precheck failed: {joined}")

        report_path, pdf_path = build_shuixianhua_monthly_report(
            template=template,
            config_path=config_path,
            result_root=result_root,
            output_dir=output_dir,
            period_label=period_label,
            monitoring_range=monitoring_range,
            report_date=report_date,
            update_word=not args.self_test_no_word_update,
        )
        if not report_path.exists() or report_path.stat().st_size <= 0:
            raise RuntimeError(f"Self-test report missing or empty: {report_path}")
        if not args.self_test_no_word_update and (pdf_path is None or not pdf_path.exists() or pdf_path.stat().st_size <= 0):
            raise RuntimeError("Self-test PDF was not generated.")

        result_path.parent.mkdir(parents=True, exist_ok=True)
        result_path.write_text(
            json.dumps(
                {
                    "ok": True,
                    "version": APP_VERSION,
                    "template": str(template),
                    "config": str(config_path),
                    "result_root": str(result_root),
                    "report": str(report_path),
                    "pdf": str(pdf_path) if pdf_path else None,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        return 0
    except Exception as exc:  # noqa: BLE001
        result_path.parent.mkdir(parents=True, exist_ok=True)
        result_path.write_text(
            json.dumps(
                {
                    "ok": False,
                    "version": APP_VERSION,
                    "error": str(exc),
                    "traceback": traceback.format_exc(),
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        return 1


def main() -> None:
    self_test_exit_code = maybe_run_self_test(sys.argv[1:])
    if self_test_exit_code is not None:
        sys.exit(self_test_exit_code)
    app = QApplication(sys.argv)
    win = ReportGui()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
