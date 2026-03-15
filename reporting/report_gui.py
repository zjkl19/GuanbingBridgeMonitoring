from __future__ import annotations

import os
import sys
import traceback
from datetime import datetime
from pathlib import Path

from PySide6.QtCore import QObject, QThread, Signal
from PySide6.QtWidgets import (
    QApplication,
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

    def run(self) -> None:
        try:
            self.log.emit(f"模板: {self.template}")
            self.log.emit(f"配置: {self.config_path}")
            self.log.emit(f"月结果目录: {self.result_root}")
            self.log.emit("开始生成报告...")
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
                self.log.emit("缺失图片:")
                for item in missing:
                    self.log.emit(f"  - {item}")
            self.log.emit("完成")
            self.finished.emit(str(manifest_path), str(report_path))
        except Exception as exc:  # noqa: BLE001
            self.log.emit("生成失败")
            self.log.emit(str(exc))
            self.log.emit(traceback.format_exc())
            self.failed.emit(str(exc))


class ReportGui(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Monthly Report Builder")
        self.resize(960, 680)
        self._last_output_dir: Path | None = None
        self._thread: QThread | None = None
        self._worker: ReportWorker | None = None
        self._build_ui()

    def _build_ui(self) -> None:
        central = QWidget(self)
        self.setCentralWidget(central)
        outer = QVBoxLayout(central)

        grid = QGridLayout()
        grid.setColumnStretch(1, 1)
        outer.addLayout(grid)

        self.template_edit = QLineEdit(str(self._find_default_template()))
        self.config_edit = QLineEdit(str(Path("config/hongtang_config.json").resolve()))
        self.result_root_edit = QLineEdit(r"E:\洪塘数据\2025年12月")
        self.analysis_root_edit = QLineEdit(str(Path(".").resolve()))
        self.output_dir_edit = QLineEdit(r"E:\洪塘数据\2025年12月\自动报告")
        self.period_edit = QLineEdit("2025年12月")
        self.range_edit = QLineEdit("2025.12.01～2025.12.31")
        self.date_edit = QLineEdit(datetime.now().strftime("%Y年%m月%d日"))

        rows = [
            ("模板文件", self.template_edit, self._browse_template),
            ("配置文件", self.config_edit, self._browse_config),
            ("月结果目录", self.result_root_edit, self._browse_result_root),
            ("分析根目录", self.analysis_root_edit, self._browse_analysis_root),
            ("输出目录", self.output_dir_edit, self._browse_output_dir),
            ("报告期", self.period_edit, None),
            ("监测时间", self.range_edit, None),
            ("报告日期", self.date_edit, None),
        ]

        for row_idx, (label, edit, callback) in enumerate(rows):
            grid.addWidget(QLabel(label), row_idx, 0)
            edit.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
            grid.addWidget(edit, row_idx, 1)
            if callback is not None:
                btn = QPushButton("浏览")
                btn.clicked.connect(callback)
                grid.addWidget(btn, row_idx, 2)

        action_row = QHBoxLayout()
        self.generate_btn = QPushButton("生成报告")
        self.generate_btn.clicked.connect(self._on_generate)
        action_row.addWidget(self.generate_btn)

        self.open_btn = QPushButton("打开输出目录")
        self.open_btn.clicked.connect(self._open_output_dir)
        action_row.addWidget(self.open_btn)

        action_row.addStretch(1)
        self.status_label = QLabel("就绪")
        action_row.addWidget(self.status_label)
        outer.addLayout(action_row)

        self.log_edit = QPlainTextEdit()
        self.log_edit.setReadOnly(True)
        outer.addWidget(self.log_edit, 1)

    def _find_default_template(self) -> Path:
        reports_dir = Path("reports")
        candidates = sorted(reports_dir.glob("*.docx"))
        return candidates[0].resolve() if candidates else reports_dir.resolve()

    def _browse_template(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "选择模板文件", str(Path.cwd()), "Word files (*.docx)")
        if path:
            self.template_edit.setText(path)

    def _browse_config(self) -> None:
        path, _ = QFileDialog.getOpenFileName(self, "选择配置文件", str(Path.cwd()), "JSON files (*.json)")
        if path:
            self.config_edit.setText(path)

    def _browse_result_root(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择月结果目录", self.result_root_edit.text())
        if path:
            self.result_root_edit.setText(path)

    def _browse_analysis_root(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择分析根目录", self.analysis_root_edit.text())
        if path:
            self.analysis_root_edit.setText(path)

    def _browse_output_dir(self) -> None:
        path = QFileDialog.getExistingDirectory(self, "选择输出目录", self.output_dir_edit.text())
        if path:
            self.output_dir_edit.setText(path)

    def _log(self, text: str) -> None:
        self.log_edit.appendPlainText(text)

    def _set_busy(self, busy: bool) -> None:
        self.generate_btn.setEnabled(not busy)
        self.status_label.setText("运行中..." if busy else "就绪")

    def _on_generate(self) -> None:
        template = Path(self.template_edit.text()).expanduser()
        config_path = Path(self.config_edit.text()).expanduser()
        result_root = Path(self.result_root_edit.text()).expanduser()
        analysis_root = Path(self.analysis_root_edit.text()).expanduser()
        output_dir = Path(self.output_dir_edit.text()).expanduser()

        if not template.exists():
            QMessageBox.critical(self, "错误", f"模板不存在:\n{template}")
            return
        if not config_path.exists():
            QMessageBox.critical(self, "错误", f"配置不存在:\n{config_path}")
            return
        if not result_root.exists():
            QMessageBox.critical(self, "错误", f"月结果目录不存在:\n{result_root}")
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
        QMessageBox.information(self, "完成", f"报告已生成:\n{report_path}\n\nManifest:\n{manifest_path}")

    def _on_failed(self, message: str) -> None:
        self._set_busy(False)
        QMessageBox.critical(self, "生成失败", message)

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
            QMessageBox.critical(self, "打开失败", str(exc))


def main() -> None:
    app = QApplication(sys.argv)
    win = ReportGui()
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
