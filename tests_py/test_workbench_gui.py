from __future__ import annotations

import os
import json
import unittest
from pathlib import Path
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

try:
    from PySide6.QtCore import QSettings, QThread
    from PySide6.QtWidgets import QApplication

    from workbench.main_window import WorkbenchWindow
    from workbench.models import JobContext
    from workbench.modules import options_for_modules
except ImportError:  # pragma: no cover - dependency gate
    QApplication = None
    WorkbenchWindow = None


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_window_builds_all_four_workflow_tabs(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        try:
            self.assertIn("v1.7.39-dev", window.windowTitle())
            self.assertEqual(window.tabs.count(), 4)
            self.assertGreaterEqual(len(window.module_checks), 20)
            self.assertIsNotNone(window.alarm_editor.session)
            self.assertIsNotNone(window.cleaning_editor.session)
            self.assertEqual(window.config_tabs.count(), 6)
            self.assertEqual(window.auto_threshold_editor.module_list.count(), 15)
            self.assertGreater(window.cleaning_editor.table.rowCount(), 0)
            self.assertIsNotNone(window.offset_editor.session)
            self.assertIsNotNone(window.group_plot_editor.session)
            self.assertGreater(window.group_plot_editor.module_combo.count(), 0)
            self.assertFalse(window.module_checks["temperature"].icon().isNull())
            self.assertFalse(window.module_checks["acceleration"].icon().isNull())
            self.assertEqual(window.update_controller.policy.repository, "zjkl19/GuanbingBridgeMonitoring")
            self.assertEqual(window.update_btn.text(), "检查更新")
            self.assertFalse(window.open_report_btn.isEnabled())
            self.assertEqual(window.analysis_progress.value(), 0)
        finally:
            window.poll_timer.stop()
            window.close()

    def test_window_restores_saved_job_context(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            data_root = Path(folder) / "data"
            data_root.mkdir()
            context = JobContext.create(
                project_root=root,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=data_root,
                start_date="2026-03-26",
                end_date="2026-04-26",
                config_path=root / "config" / "default_config.json",
                selected_modules=["temperature", "acceleration"],
                options=options_for_modules(["temperature", "acceleration"]),
                period_label="2026年4月",
                job_id="restore_unit",
            )
            path = context.write()
            status_path = Path(context.analysis.status_path)
            status_path.parent.mkdir(parents=True, exist_ok=True)
            status_path.write_text(json.dumps({
                "status": "running",
                "progress_fraction": 0.25,
                "current_module_label": "温度分析",
                "completed_modules": 1,
                "module_total": 4,
                "estimated_remaining_sec": 90,
            }, ensure_ascii=False), encoding="utf-8")
            window = WorkbenchWindow(root)
            try:
                window.load_context(path)
                self.assertEqual(window.current_context.job_id, "restore_unit")
                self.assertEqual(window.data_root_edit.text(), str(data_root.resolve()))
                self.assertTrue(window.module_checks["temperature"].isChecked())
                self.assertFalse(window.module_checks["wind"].isChecked())
                self.assertEqual(window.period_label_edit.text(), "2026年4月")
                self.assertEqual(window.analysis_progress.value(), 250)
                self.assertIn("温度分析", window.analysis_progress_label.text())
                self.assertIn("1分30秒", window.analysis_progress_label.text())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_finished_check_worker_does_not_clear_replacement_download_worker(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        stale_worker = QThread()
        replacement_worker = QThread()
        try:
            window.update_controller.worker = replacement_worker
            window.update_btn.setEnabled(False)
            window.update_btn.setText("正在下载更新…")
            window.update_controller._worker_finished(stale_worker)
            self.assertIs(window.update_controller.worker, replacement_worker)
            self.assertFalse(window.update_btn.isEnabled())
            self.assertEqual(window.update_btn.text(), "正在下载更新…")
        finally:
            window.update_controller.worker = None
            replacement_worker.deleteLater()
            window.poll_timer.stop()
            window.close()

    def test_no_release_result_is_recorded_for_startup_throttling(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            window = WorkbenchWindow(root)
            try:
                window.update_controller.settings = QSettings(
                    str(Path(folder) / "updates.ini"), QSettings.IniFormat
                )
                window.update_controller.manual = False
                window.update_controller._operation_failed("GitHub 尚未发布正式 Release")
                checked_at = float(
                    window.update_controller.settings.value("updates/last_check_epoch", 0.0)
                )
                self.assertGreater(checked_at, 0.0)
            finally:
                window.poll_timer.stop()
                window.close()


if __name__ == "__main__":
    unittest.main()
