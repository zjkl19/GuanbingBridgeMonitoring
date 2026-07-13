from __future__ import annotations

import os
import json
import unittest
from pathlib import Path
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

try:
    from PySide6.QtCore import QSettings, QThread
    from PySide6.QtWidgets import (
        QAbstractButton, QApplication, QCheckBox, QGroupBox, QLabel, QMainWindow, QPushButton
    )

    from workbench.main_window import WorkbenchWindow
    from workbench.__main__ import smoke_payload
    from workbench.models import file_sha256
    from workbench.models import JobContext
    from workbench.modules import options_for_modules
    from workbench.update_ui import UpdateController
    from scripts.validate_workbench_installed_profiles import validate_profile_payload
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
            self.assertEqual(window.config_tabs.count(), 8)
            self.assertEqual(window.auto_threshold_editor.module_list.count(), 15)
            self.assertTrue(window.update_backup_btn.isEnabled())
            self.assertTrue(window.profile_matrix_btn.isEnabled())
            self.assertGreater(window.cleaning_editor.table.rowCount(), 0)
            self.assertIsNotNone(window.offset_editor.session)
            self.assertIsNotNone(window.group_plot_editor.session)
            self.assertGreater(window.group_plot_editor.module_combo.count(), 0)
            self.assertIsNotNone(window.plot_common_editor.session)
            self.assertIsNotNone(window.spectrum_editor.session)
            self.assertEqual(window.plot_common_editor.table.rowCount(), 14)
            self.assertEqual(window.spectrum_editor.module_combo.count(), 2)
            self.assertEqual(window.provenance_table.columnCount(), 7)
            self.assertEqual(window.report_qc_table.columnCount(), 5)
            self.assertEqual(window.open_report_btn.text(), "生成报告并执行质量检查")
            self.assertEqual(window.update_btn.text(), "立即检查更新")
            self.assertTrue(window.auto_update_check.isEnabled())
            self.assertGreaterEqual(window.font().pointSize(), 10)
            self.assertFalse(window.module_checks["temperature"].icon().isNull())
            self.assertFalse(window.module_checks["acceleration"].icon().isNull())
            self.assertEqual(window.update_controller.policy.repository, "zjkl19/GuanbingBridgeMonitoring")
            self.assertEqual(window.update_btn.text(), "立即检查更新")
            self.assertFalse(window.open_report_btn.isEnabled())
            self.assertFalse(window.open_report_qc_btn.isEnabled())
            self.assertEqual(window.analysis_progress.value(), 0)
            self.assertTrue(window.history_btn.isEnabled())
            self.assertEqual(window.analysis_stack.count(), 2)
            self.assertEqual(window.task_history_page.table.columnCount(), 8)
        finally:
            window.poll_timer.stop()
            window.close()

    def test_primary_workflow_uses_operator_friendly_terms(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        try:
            visible_text = [widget.text() for widget in window.findChildren(QLabel)]
            visible_text += [widget.text() for widget in window.findChildren(QAbstractButton)]
            visible_text += [widget.title() for widget in window.findChildren(QGroupBox)]
            visible_text += [
                window.provenance_table.horizontalHeaderItem(column).text()
                for column in range(window.provenance_table.columnCount())
            ]
            joined = "\n".join(visible_text).casefold()
            for jargon in ("manifest", "provenance", "门禁", " qc"):
                self.assertNotIn(jargon, joined)
            self.assertIn("正式图件数据完整性检查", joined)
            self.assertIn("正式报告生成条件", joined)
        finally:
            window.poll_timer.stop()
            window.close()

    def test_all_six_profiles_load_without_mutating_assets(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        assets = {root / "config" / "bridge_profiles.json"}
        for profile in window.profiles:
            assets.add(profile.config_path(root))
            if profile.report_template:
                assets.add(profile.template_path(root))
        before = {path: file_sha256(path) for path in assets}
        try:
            rows = []
            for index, profile in enumerate(window.profiles):
                window.profile_combo.setCurrentIndex(index)
                self.app.processEvents()
                rows.append(validate_profile_payload(profile, smoke_payload(window), root))
            self.assertEqual(len(rows), 6)
            self.assertEqual(sum(row["report_capable"] for row in rows), 5)
            self.assertEqual(sum(not row["report_capable"] for row in rows), 1)
            self.assertEqual(before, {path: file_sha256(path) for path in assets})
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
                self.assertIn(path.resolve(), window.known_context_paths)
            finally:
                window.poll_timer.stop()
                window.close()

    def test_task_history_demo_is_embedded_without_changing_top_level_tabs(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        try:
            window.show_task_history(demo=True)
            self.assertEqual(window.tabs.count(), 4)
            self.assertEqual(window.analysis_stack.currentIndex(), 1)
            self.assertEqual(window.task_history_page.table.rowCount(), 4)
            window.task_history_page.back_requested.emit()
            self.assertEqual(window.analysis_stack.currentIndex(), 0)
        finally:
            window.poll_timer.stop()
            window.close()

    def test_report_qc_table_exposes_render_contact_sheet(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            contact = Path(folder) / "contact.png"
            contact.write_bytes(b"png")
            window = WorkbenchWindow(root)
            try:
                window._show_report_qc({
                    "report_path": str(Path(folder) / "report.docx"),
                    "pdf_path": str(Path(folder) / "report.pdf"),
                    "qc": {
                        "docx": {"zip_integrity": True, "document_xml": True, "size_bytes": 10, "media_count": 2},
                        "pdf": {"exists": True, "page_count": 3, "size_bytes": 20},
                        "manifest": {"status": "ok", "missing_count": 0, "warning_count": 0},
                        "visual": {
                            "status": "passed", "page_count": 3,
                            "blank_pages": [], "edge_touch_pages": [],
                            "contact_sheet": str(contact), "output_dir": folder,
                        },
                    },
                })
                self.assertEqual(window.report_qc_table.rowCount(), 4)
                self.assertTrue(window.open_report_qc_btn.isEnabled())
                self.assertIn("3 页", window.report_qc_table.item(3, 2).text())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_review_page_requires_closed_source_provenance(self) -> None:
        root = Path(__file__).resolve().parents[1]
        fixture = root / "tests" / "fixtures" / "workbench_provenance_contract.json"
        with tempfile.TemporaryDirectory() as folder:
            data_root = Path(folder) / "data"
            data_root.mkdir()
            provenance = data_root / "A1.plot.json"
            provenance.write_bytes(fixture.read_bytes())
            manifest = data_root / "analysis_manifest.json"
            manifest.write_text(json.dumps({
                "status": "ok",
                "bridge_profile": {"bridge_id": "guanbing"},
                "run_request": {
                    "data_root": str(data_root),
                    "start_date": "2026-04-01",
                    "end_date": "2026-04-30",
                },
                "module_results": [{
                    "key": "acceleration", "label": "加速度", "status": "ok",
                    "artifacts": [{"kind": "plot_provenance", "path": str(provenance)}],
                }],
            }, ensure_ascii=False), encoding="utf-8")
            context = JobContext.create(
                project_root=root, bridge_id="guanbing", bridge_name="管柄大桥",
                data_root=data_root, start_date="2026-04-01", end_date="2026-04-30",
                config_path=root / "config" / "default_config.json",
                selected_modules=["acceleration"], options=options_for_modules(["acceleration"]),
            )
            context.analysis.state = "completed"
            context.analysis.manifest_path = str(manifest)
            window = WorkbenchWindow(root)
            try:
                window.current_context = context
                window.current_context_path = context.write()
                window._load_manifest(manifest)
                self.assertEqual(window.provenance_table.rowCount(), 1)
                self.assertIn("通过：1", window.provenance_summary_label.text())
                self.assertTrue(window.approval_check.isEnabled())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_auto_update_defaults_on_and_user_choice_persists(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            settings = QSettings(str(Path(folder) / "updates.ini"), QSettings.IniFormat)
            window = QMainWindow()
            checkbox = QCheckBox()
            controller = UpdateController(
                window, QPushButton(), root, auto_check_box=checkbox, settings=settings
            )
            self.assertTrue(controller.policy.auto_check)
            self.assertTrue(checkbox.isChecked())
            checkbox.setChecked(False)
            self.assertFalse(controller.auto_check_enabled())
            self.assertEqual(settings.value("updates/auto_check_enabled", type=bool), False)

            second_checkbox = QCheckBox()
            second = UpdateController(
                window, QPushButton(), root, auto_check_box=second_checkbox, settings=settings
            )
            self.assertFalse(second.auto_check_enabled())
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
