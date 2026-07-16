from __future__ import annotations

import os
import json
import unittest
from unittest.mock import patch
from pathlib import Path
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

try:
    from PySide6.QtCore import QDate, QSettings, QThread
    from PySide6.QtWidgets import (
        QAbstractButton, QApplication, QCheckBox, QGroupBox, QLabel, QMainWindow, QMessageBox, QPushButton
    )

    from workbench.main_window import WorkbenchWindow
    from workbench.__main__ import smoke_payload
    from workbench.manifest import ManifestSummary
    from workbench.models import file_sha256
    from workbench.models import JobContext
    from workbench.modules import options_for_modules
    from workbench.operator_text import operator_friendly_text, operator_stage_label, operator_state_label
    from workbench.provenance import PlotProvenanceRow, PlotProvenanceSummary
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
            expected_version = (root / "VERSION").read_text(encoding="utf-8-sig").strip()
            self.assertIn(expected_version, window.windowTitle())
            self.assertEqual(window.tabs.count(), 4)
            self.assertGreaterEqual(len(window.module_checks), 20)
            self.assertIsNotNone(window.alarm_editor.session)
            self.assertIsNotNone(window.cleaning_editor.session)
            self.assertEqual(window.config_tabs.count(), 9)
            self.assertEqual(window.auto_threshold_editor.module_list.count(), 15)
            self.assertTrue(window.update_backup_btn.isEnabled())
            self.assertTrue(window.profile_matrix_btn.isEnabled())
            self.assertEqual(window.profile_matrix_btn.text(), "所有桥梁自检")
            self.assertGreater(window.cleaning_editor.table.rowCount(), 0)
            cleaning_modules = {
                window.cleaning_editor.table.item(row, 1).text()
                for row in range(window.cleaning_editor.table.rowCount())
            }
            self.assertIn("风向", cleaning_modules)
            self.assertNotIn("wind_direction", cleaning_modules)
            self.assertIsNotNone(window.offset_editor.session)
            self.assertIsNotNone(window.group_plot_editor.session)
            self.assertGreater(window.group_plot_editor.module_combo.count(), 0)
            self.assertIsNotNone(window.plot_common_editor.session)
            self.assertIsNotNone(window.spectrum_editor.session)
            self.assertIsNotNone(window.unzip_settings_editor.session)
            self.assertEqual(window.unzip_settings_editor.mode_combo.count(), 5)
            self.assertEqual(window.unzip_settings_editor.requested_value(), 1)
            self.assertEqual(window.plot_common_editor.table.rowCount(), 14)
            self.assertEqual(window.spectrum_editor.module_combo.count(), 2)
            self.assertEqual(window.provenance_table.columnCount(), 7)
            self.assertEqual(window.module_table.columnCount(), 5)
            self.assertNotIn(
                "内部标识",
                [
                    window.module_table.horizontalHeaderItem(column).text()
                    for column in range(window.module_table.columnCount())
                ],
            )
            self.assertEqual(window.report_qc_table.columnCount(), 5)
            self.assertEqual(window.open_report_btn.text(), "生成报告并执行质量检查")
            self.assertEqual(window.update_btn.text(), "立即检查更新")
            self.assertTrue(window.auto_update_check.isEnabled())
            self.assertGreaterEqual(window.font().pointSize(), 10)
            self.assertFalse(window.module_checks["temperature"].icon().isNull())
            self.assertFalse(window.module_checks["acceleration"].icon().isNull())
            cache_prebuild = window.module_checks["cache_prebuild"]
            unzip = window.module_checks["unzip"]
            self.assertIn("解压并发", unzip.toolTip())
            self.assertEqual(cache_prebuild.text(), "预生成分析缓存")
            self.assertFalse(cache_prebuild.icon().isNull())
            self.assertIn("已解压 CSV", cache_prebuild.toolTip())
            self.assertIn("默认保留 CSV", cache_prebuild.toolTip())
            self.assertIn("明确启用并确认", cache_prebuild.toolTip())
            self.assertIn("分析模块实际使用", cache_prebuild.toolTip())
            self.assertTrue(cache_prebuild.isEnabled())
            self.assertFalse(cache_prebuild.isChecked())
            for bridge_id in (
                "guanbing", "hongtang", "jiulongjiang", "shuixianhua",
                "chongyangxi", "zhishan",
            ):
                window.profile_combo.setCurrentIndex(window.profile_combo.findData(bridge_id))
                self.assertTrue(cache_prebuild.isEnabled(), bridge_id)
                self.assertFalse(cache_prebuild.isChecked(), bridge_id)
            self.assertFalse(window.windowIcon().isNull())
            self.assertFalse(window.organization_logo_label.isHidden())
            self.assertIsNotNone(window.organization_logo_label.pixmap())
            self.assertEqual(window.path_profile_combo.currentData(), "__auto__")
            self.assertIn("自动识别", window.data_source_mode_label.text())
            self.assertIn("MAT", window.data_source_mode_label.text())
            self.assertIn("开发机", window.path_profile_status_label.text())
            self.assertEqual(window.validate_btn.text(), "检查配置与路径（不运行）")
            self.assertEqual(window.open_context_btn.text(), "打开已保存任务方案")
            self.assertEqual(window.save_btn.text(), "保存任务方案（便于恢复）")
            self.assertEqual(window.history_btn.text(), "查看任务历史")
            self.assertIn("不会启动", window.save_btn.toolTip())
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

    def test_changing_task_inputs_discards_loaded_review_state(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            data_root = Path(folder) / "data"
            data_root.mkdir()
            context = JobContext.create(
                project_root=root,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=data_root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=root / "config" / "default_config.json",
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
                job_id="review_invalidation_unit",
            )
            old_manifest = data_root / "run_logs" / "analysis_manifest_old.json"
            old_manifest.parent.mkdir()
            old_manifest.write_text('{"status":"ok"}', encoding="utf-8")
            context.analysis.manifest_path = str(old_manifest.resolve())
            window = WorkbenchWindow(root)
            try:
                window.load_context(context.write())
                window.current_manifest = object()
                window.current_provenance = object()
                window.approval_check.setEnabled(True)
                window.approval_check.blockSignals(True)
                window.approval_check.setChecked(True)
                window.approval_check.blockSignals(False)
                window.current_context.report.plots_approved = True
                window.current_context.report.state = "ready"
                window.current_context.write(window.current_context_path)

                window.end_date_edit.setDate(QDate(2026, 6, 29))
                self.app.processEvents()

                self.assertIsNone(window.current_manifest)
                self.assertIsNone(window.current_provenance)
                self.assertFalse(window.approval_check.isChecked())
                self.assertFalse(window.approval_check.isEnabled())
                self.assertFalse(window.open_report_btn.isEnabled())
                self.assertFalse(window.current_context.report.plots_approved)

                with patch(
                    "workbench.main_window.read_analysis_status",
                    return_value={
                        "status": "completed",
                        "manifest_path": str(old_manifest.resolve()),
                    },
                ), patch(
                    "workbench.main_window.read_report_status",
                    return_value={
                        "state": "completed",
                        "qc": {"status": "passed"},
                    },
                ), patch.object(window, "_load_manifest") as load_manifest, patch.object(
                    window, "_show_report_qc"
                ) as show_report_qc:
                    window._poll_status()

                load_manifest.assert_not_called()
                show_report_qc.assert_not_called()
                self.assertIsNone(window.current_manifest)
                self.assertIsNone(window.current_provenance)
                self.assertFalse(window.approval_check.isEnabled())

                window.end_date_edit.setDate(QDate(2026, 6, 30))
                window.current_manifest = object()
                window.current_provenance = object()
                window.approval_check.setEnabled(True)
                self.assertFalse(window._report_gate_ready())
                restored = JobContext.read(window.current_context_path)
                self.assertFalse(restored.report.plots_approved)
            finally:
                window.poll_timer.stop()
                window.close()

    def test_data_source_summary_reads_effective_layered_config(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            config_root = Path(folder)
            base = config_root / "base.json"
            base.write_text(
                '{"data_adapter":{"time_series":{"source_mode":"prefer_mat"}}}',
                encoding="utf-8",
            )
            config = config_root / "project.json"
            config.write_text('{"extends":"base.json"}', encoding="utf-8")

            window = WorkbenchWindow(root)
            try:
                window.config_edit.setText(str(config))
                window._refresh_data_source_summary()
                self.assertIn("优先读取 MAT", window.data_source_mode_label.text())

                base.write_text(
                    '{"data_adapter":{"time_series":{"source_mode":"mat_only"}}}',
                    encoding="utf-8",
                )
                window._refresh_data_source_summary()
                self.assertIn("高级验证模式", window.data_source_mode_label.text())
                self.assertIn("不会回退读取 CSV", window.data_source_mode_label.text())
            finally:
                window.poll_timer.stop()
                window.close()

    def test_layered_config_dependency_change_blocks_report_without_ui_edit(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            task_root = Path(folder)
            data_root = task_root / "data"
            data_root.mkdir()
            layer = task_root / "base.json"
            layer.write_text('{"plot_common":{"gap_mode":"connect"}}', encoding="utf-8")
            config = task_root / "project.json"
            config.write_text(
                '{"extends":"base.json","bridge":{"id":"guanbing"}}', encoding="utf-8"
            )
            context = JobContext.create(
                project_root=root,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=data_root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=config,
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
                job_id="layered_gate_unit",
            )
            context.analysis.state = "completed"
            context.analysis.manifest_path = str(task_root / "analysis_manifest.json")
            context.report.plots_approved = True
            window = WorkbenchWindow(root)
            try:
                window.load_context(context.write())
                window.current_manifest = ManifestSummary(
                    path=Path(context.analysis.manifest_path),
                    status="ok",
                    artifact_count=1,
                    modules=(),
                )
                window.current_manifest_missing_selected = ()
                window.current_provenance = PlotProvenanceSummary(rows=(
                    PlotProvenanceRow(
                        module_key="temperature",
                        path=task_root / "temperature.plot.json",
                        status="closed",
                        series_count=1,
                        source_count=1,
                        plotted_count=1,
                        incomplete_days=(),
                    ),
                ))
                window.approval_check.blockSignals(True)
                window.approval_check.setEnabled(True)
                window.approval_check.setChecked(True)
                window.approval_check.blockSignals(False)
                self.assertTrue(window._context_matches_current_inputs(context))
                self.assertTrue(window._report_gate_ready())

                layer.write_text('{"plot_common":{"gap_mode":"break"}}', encoding="utf-8")

                self.assertFalse(window._context_matches_current_inputs(context))
                self.assertFalse(window._report_gate_ready())
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

    def test_dynamic_report_status_translates_internal_terms(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            data_root = Path(folder) / "data"
            data_root.mkdir()
            context = JobContext.create(
                project_root=root,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=data_root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=root / "config" / "default_config.json",
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
                period_label="2026年6月",
                job_id="operator_terms_unit",
            )
            context_path = context.write()
            window = WorkbenchWindow(root)
            try:
                window.current_context = context
                window.current_context_path = context_path
                status = {
                    "state": "running",
                    "stage": "qc",
                    "progress_fraction": 0.9,
                    "message": "Manifest QC checks source provenance and legacy fallback",
                }
                with patch("workbench.main_window.read_report_status", return_value=status):
                    window._poll_report_status()
                visible = (window.report_progress_label.text() + "\n" + window.report_log.toPlainText()).casefold()
                for jargon in ("manifest", "provenance", "legacy", " qc", "running"):
                    self.assertNotIn(jargon, visible)
                self.assertIn("正在处理", visible)
                self.assertIn("质量检查", visible)
                self.assertIn("数据来源记录", visible)
            finally:
                window.poll_timer.stop()
                window.close()

    def test_operator_term_mapping_is_centralized(self) -> None:
        self.assertEqual("正在处理", operator_state_label("running"))
        self.assertEqual("正在停止", operator_state_label("stopping"))
        self.assertEqual("质量检查", operator_stage_label("qc"))
        self.assertEqual("正在安全停止", operator_stage_label("stop_requested"))
        self.assertEqual("重新读取状态", operator_stage_label("status_retry"))
        message = operator_friendly_text("release manifest provenance legacy QC gate")
        for jargon in ("manifest", "provenance", "legacy", "qc", "gate"):
            self.assertNotIn(jargon, message.casefold())

    def test_all_catalog_profiles_load_without_mutating_assets(self) -> None:
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
            self.assertEqual(len(rows), len(window.profiles))
            expected_report_capable = sum(
                bool(profile.report_template and profile.report_gui_type)
                for profile in window.profiles
            )
            self.assertEqual(sum(row["report_capable"] for row in rows), expected_report_capable)
            self.assertEqual(
                sum(not row["report_capable"] for row in rows),
                len(window.profiles) - expected_report_capable,
            )
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

    def test_latest_result_selection_ignores_newer_partial_repair_manifest(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            data_root = Path(folder) / "data"
            logs = data_root / "run_logs"
            logs.mkdir(parents=True)
            complete = logs / "analysis_manifest_complete.json"
            repair = logs / "analysis_manifest_repair.json"
            previous = logs / "analysis_manifest_previous.json"

            def write_manifest(path: Path, modules: list[str]) -> None:
                config_path = root / "config" / "default_config.json"
                path.write_text(json.dumps({
                    "status": "ok",
                    "bridge_profile": {"bridge_id": "guanbing"},
                    "run_request": {
                        "data_root": str(data_root),
                        "start_date": "2026-05-26",
                        "end_date": "2026-05-28",
                        "config_path": str(config_path.resolve()),
                        "config_sha256": file_sha256(config_path),
                    },
                    "module_results": [
                        {"key": key, "label": key, "status": "ok"}
                        for key in modules
                    ],
                }), encoding="utf-8")

            selected = ["temperature", "acceleration"]
            write_manifest(complete, selected)
            write_manifest(repair, ["acceleration"])
            write_manifest(previous, selected)
            previous_payload = json.loads(previous.read_text(encoding="utf-8"))
            previous_payload["generation"] = "previous"
            previous.write_text(json.dumps(previous_payload), encoding="utf-8")
            complete_payload = json.loads(complete.read_text(encoding="utf-8"))
            complete_payload["generation"] = "current"
            complete.write_text(json.dumps(complete_payload), encoding="utf-8")
            os.utime(previous, (0.5, 0.5))
            os.utime(complete, (1, 1))
            os.utime(repair, (2, 2))
            context = JobContext.create(
                project_root=root,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=data_root,
                start_date="2026-05-26",
                end_date="2026-05-28",
                config_path=root / "config" / "default_config.json",
                selected_modules=selected,
                options=options_for_modules(selected),
                job_id="manifest_selection_unit",
            )
            context.analysis.state = "completed"
            context.analysis.manifest_path = str(previous.resolve())
            context.analysis.manifest_sha256 = file_sha256(previous)
            context.report.plots_approved = True
            context.report.state = "ready"
            window = WorkbenchWindow(root)
            try:
                window.load_context(context.write())
                with patch(
                    "workbench.main_window.QMessageBox.question",
                    return_value=QMessageBox.Yes,
                ), patch("workbench.main_window.QMessageBox.warning") as warning:
                    window._load_latest_manifest()
                warning.assert_not_called()
                self.assertEqual(
                    window.current_context.analysis.manifest_path,
                    str(complete.resolve()),
                )
                self.assertEqual(
                    window.current_context.analysis.manifest_sha256,
                    file_sha256(complete),
                )
                self.assertFalse(window.current_context.report.plots_approved)
                saved = JobContext.read(window.current_context_path)
                self.assertEqual(saved.analysis.manifest_path, str(complete.resolve()))
                self.assertEqual(saved.analysis.manifest_sha256, file_sha256(complete))
                self.assertFalse(saved.report.plots_approved)
            finally:
                window.poll_timer.stop()
                window.close()

    def test_shuixianhua_custom_root_and_may_dates_refresh_auto_report_fields(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        try:
            window.profile_combo.setCurrentIndex(window.profile_combo.findData("shuixianhua"))
            data_root = r"E:\水仙花大桥数据\2026年5月"
            window.data_root_edit.setText(data_root)
            window.start_date_edit.setDate(QDate(2026, 5, 1))
            window.end_date_edit.setDate(QDate(2026, 5, 31))

            self.assertEqual(
                Path(window.output_dir_edit.text()), Path(data_root) / "自动报告"
            )
            self.assertEqual(window.period_label_edit.text(), "2026年5月份")
            self.assertEqual(
                window.monitoring_range_edit.text(), "2026年05月01日~2026年05月31日"
            )
        finally:
            window.poll_timer.stop()
            window.close()

    def test_report_autofill_preserves_manual_overrides_but_profile_change_resets_them(self) -> None:
        root = Path(__file__).resolve().parents[1]
        window = WorkbenchWindow(root)
        try:
            window.profile_combo.setCurrentIndex(window.profile_combo.findData("shuixianhua"))
            manual_output = root / "manual-report-output"
            window.output_dir_edit.setText(str(manual_output))
            window.period_label_edit.setText("业主专项期")
            window.monitoring_range_edit.setText("人工填写的监测时间")

            window.data_root_edit.setText(r"E:\水仙花大桥数据\2026年6月")
            window.start_date_edit.setDate(QDate(2026, 6, 1))
            window.end_date_edit.setDate(QDate(2026, 6, 30))
            self.assertEqual(Path(window.output_dir_edit.text()), manual_output)
            self.assertEqual(window.period_label_edit.text(), "业主专项期")
            self.assertEqual(window.monitoring_range_edit.text(), "人工填写的监测时间")

            window.profile_combo.setCurrentIndex(window.profile_combo.findData("zhishan"))
            self.assertNotEqual(window.period_label_edit.text(), "业主专项期")
            self.assertNotEqual(window.monitoring_range_edit.text(), "人工填写的监测时间")
            self.assertNotEqual(Path(window.output_dir_edit.text()), manual_output)
        finally:
            window.poll_timer.stop()
            window.close()

    def test_loaded_context_establishes_auto_report_field_baseline(self) -> None:
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory() as folder:
            task_root = Path(folder)
            may_root = task_root / "水仙花" / "2026年5月"
            june_root = task_root / "水仙花" / "2026年6月"
            context = JobContext.create(
                project_root=root,
                bridge_id="shuixianhua",
                bridge_name="水仙花大桥",
                data_root=may_root,
                start_date="2026-05-01",
                end_date="2026-05-31",
                config_path=root / "config" / "shuixianhua_config.json",
                selected_modules=["temperature"],
                options=options_for_modules(["temperature"]),
                report_type="shuixianhua_monthly",
                output_dir=may_root / "自动报告",
                period_label="2026年5月份",
                monitoring_range="2026年05月01日~2026年05月31日",
            )
            context_path = context.write(task_root / "job_context.json")
            window = WorkbenchWindow(root)
            try:
                window.load_context(context_path)
                window.data_root_edit.setText(str(june_root))
                window.start_date_edit.setDate(QDate(2026, 6, 1))
                window.end_date_edit.setDate(QDate(2026, 6, 30))
                self.assertEqual(
                    Path(window.output_dir_edit.text()), june_root / "自动报告"
                )
                self.assertEqual(window.period_label_edit.text(), "2026年6月份")
                self.assertEqual(
                    window.monitoring_range_edit.text(),
                    "2026年06月01日~2026年06月30日",
                )
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
            visible = "\n".join(
                window.task_history_page.table.item(row, column).text()
                for row in range(window.task_history_page.table.rowCount())
                for column in (3, 4)
                if window.task_history_page.table.item(row, column) is not None
            ).casefold()
            for jargon in ("running", "completed", "blocked", "qc=", "sha256"):
                self.assertNotIn(jargon, visible)
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
            config_path = root / "config" / "default_config.json"
            manifest.write_text(json.dumps({
                "status": "ok",
                "bridge_profile": {"bridge_id": "guanbing"},
                "run_request": {
                    "data_root": str(data_root),
                    "start_date": "2026-04-01",
                    "end_date": "2026-04-30",
                    "config_path": str(config_path.resolve()),
                    "config_sha256": file_sha256(config_path),
                },
                "module_results": [{
                    "key": "acceleration", "label": "加速度", "status": "ok",
                    "artifacts": [{"kind": "plot_provenance", "path": str(provenance)}],
                }],
            }, ensure_ascii=False), encoding="utf-8")
            context = JobContext.create(
                project_root=root, bridge_id="guanbing", bridge_name="管柄大桥",
                data_root=data_root, start_date="2026-04-01", end_date="2026-04-30",
                config_path=config_path,
                selected_modules=["acceleration"], options=options_for_modules(["acceleration"]),
            )
            context.analysis.state = "completed"
            context.analysis.manifest_path = str(manifest)
            context.report.plots_approved = True
            context.report.state = "ready"
            window = WorkbenchWindow(root)
            try:
                window.current_context = context
                window.current_context_path = context.write()
                window._load_manifest(manifest)
                self.assertEqual(window.provenance_table.rowCount(), 1)
                self.assertIn("通过：1", window.provenance_summary_label.text())
                self.assertTrue(window.approval_check.isEnabled())
                self.assertFalse(window.current_context.report.plots_approved)
                saved = JobContext.read(window.current_context_path)
                self.assertEqual(saved.analysis.manifest_sha256, file_sha256(manifest))
                self.assertFalse(saved.report.plots_approved)
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
