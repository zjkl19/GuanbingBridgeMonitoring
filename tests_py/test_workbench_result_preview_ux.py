from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication

from workbench.box_threshold_dialog import BoxThresholdDialog
from workbench.config_editor import CleaningThresholdRow
from workbench.main_window import WorkbenchWindow
from workbench.manual_threshold import LOWER_SIDE
from workbench.manual_threshold_dialog import ThresholdBandDialog
from workbench.models import JobContext
from workbench.result_location import analysis_result_location
from workbench.threshold_preview import (
    find_matching_threshold_preview,
    preview_query,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]


def _write_preview(
    path: Path,
    *,
    root: Path,
    bridge_id: str = "unit_bridge",
    point_id: str = "PT-1",
    config_sha256: str = "a" * 64,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "artifact_type": "auto_threshold_preview",
                "request_type": "auto_threshold_proposal",
                "request_id": path.parent.name,
                "bridge_id": bridge_id,
                "data_root": str(root.resolve()),
                "config_sha256": config_sha256,
                "start_date": "2026-01-01",
                "end_date": "2026-01-31",
                "preview_series": [
                    {
                        "module_key": "acceleration",
                        "point_id": point_id,
                        "sensor_type": "acceleration",
                        "times": [
                            "2026-01-01T00:00:00",
                            "2026-01-01T00:00:01",
                            "2026-01-01T00:00:02",
                        ],
                        "values": [-2.0, 0.0, 3.0],
                        "sample_count": 3,
                    }
                ],
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )


class ResultAndPreviewUxTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_result_location_is_data_root_and_distinguishes_report_output(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            context = JobContext.create(
                project_root=PROJECT_ROOT,
                bridge_id="unit_bridge",
                bridge_name="测试桥",
                data_root=root,
                start_date="2026-01-01",
                end_date="2026-01-31",
                config_path=config,
                selected_modules=["acceleration"],
                options={},
                job_id="unit_job",
            )
            context.write()
            location = analysis_result_location(context=context)
            self.assertIsNotNone(location)
            assert location is not None
            self.assertEqual(location.root, root.resolve())
            self.assertEqual(location.stats_dir, root.resolve() / "stats")
            self.assertEqual(location.run_logs_dir, root.resolve() / "run_logs")
            self.assertIn("报告 DOCX/PDF 是另一套输出", location.explanation)

    def test_analysis_page_shows_actual_result_root_and_plain_help(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "stats").mkdir()
            (root / "run_logs").mkdir()
            window = WorkbenchWindow(PROJECT_ROOT)
            try:
                window.data_root_edit.setText(str(root))
                self.app.processEvents()
                self.assertIn(str(root.resolve()), window.analysis_result_path_label.text())
                self.assertIn("统计表", window.analysis_result_help_label.text())
                self.assertIn("报告生成", window.analysis_result_help_label.text())
                self.assertTrue(window.open_analysis_result_button.isEnabled())
                self.assertTrue(window.copy_analysis_result_path_button.isEnabled())
                self.assertTrue(window.open_analysis_stats_button.isEnabled())
                self.assertTrue(window.open_analysis_logs_button.isEnabled())
                self.assertTrue(window.review_open_result_button.isEnabled())
                window._copy_analysis_result_path()
                self.assertEqual(QApplication.clipboard().text(), str(root.resolve()))
            finally:
                window.poll_timer.stop()
                window.close()

    def test_completed_result_path_survives_repeated_status_polls(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            context = JobContext.create(
                project_root=PROJECT_ROOT,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=PROJECT_ROOT / "config" / "default_config.json",
                selected_modules=["temperature"],
                options={},
                job_id="completed_result_path",
            )
            context_path = context.write()
            status_path = Path(context.analysis.status_path)
            status_path.write_text(
                json.dumps({"status": "completed", "progress_fraction": 1.0}),
                encoding="utf-8",
            )
            window = WorkbenchWindow(PROJECT_ROOT)
            try:
                window.load_context(context_path)
                window._poll_status()
                window._poll_status()
                self.assertEqual(
                    window.analysis_progress_label.text(),
                    f"计算完成；结果保存在：{root.resolve()}",
                )
            finally:
                window.poll_timer.stop()
                window.close()

    def test_current_task_result_path_survives_next_task_input_edits(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            actual = root / "actual"
            planned = root / "planned"
            (actual / "stats").mkdir(parents=True)
            (actual / "run_logs").mkdir()
            planned.mkdir()
            context = JobContext.create(
                project_root=PROJECT_ROOT,
                bridge_id="guanbing",
                bridge_name="管柄大桥",
                data_root=actual,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_path=PROJECT_ROOT / "config" / "default_config.json",
                selected_modules=["temperature"],
                options={},
                job_id="actual_result_path_after_edit",
            )
            context_path = context.write()
            Path(context.analysis.status_path).write_text(
                json.dumps({"status": "completed", "progress_fraction": 1.0}),
                encoding="utf-8",
            )
            window = WorkbenchWindow(PROJECT_ROOT)
            try:
                window.load_context(context_path)
                window.data_root_edit.setText(str(planned))
                self.app.processEvents()
                window._poll_status()
                self.assertIn(str(actual.resolve()), window.analysis_result_path_label.text())
                self.assertNotIn(str(planned.resolve()), window.analysis_result_path_label.text())
                self.assertIn(str(planned.resolve()), window.analysis_result_help_label.text())
                self.assertEqual(
                    window.analysis_progress_label.text(),
                    f"计算完成；结果保存在：{actual.resolve()}",
                )
                window._copy_analysis_result_path()
                self.assertEqual(QApplication.clipboard().text(), str(actual.resolve()))
            finally:
                window.poll_timer.stop()
                window.close()

    def test_preview_locator_uses_only_exact_task_and_point_binding(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            wrong = root / "run_logs" / "workbench" / "new_wrong" / "auto_threshold_preview.json"
            right = root / "run_logs" / "workbench" / "old_right" / "auto_threshold_preview.json"
            _write_preview(wrong, root=root, bridge_id="other_bridge")
            _write_preview(right, root=root)
            wrong.touch()
            query = preview_query(
                bridge_id="unit_bridge",
                data_root=root,
                start_date="2026-01-01",
                end_date="2026-01-31",
                config_sha256="a" * 64,
                module_key="acceleration",
                point_ids=("PT-1",),
            )
            match = find_matching_threshold_preview(query)
            self.assertEqual(match.path, right.resolve())
            self.assertGreaterEqual(match.checked_count, 2)

            missing = find_matching_threshold_preview(
                preview_query(
                    bridge_id="unit_bridge",
                    data_root=root,
                    start_date="2026-01-01",
                    end_date="2026-01-31",
                    config_sha256="a" * 64,
                    module_key="acceleration",
                    point_ids=("MISSING",),
                )
            )
            self.assertIsNone(missing.path)
            self.assertIn("自动清洗建议", missing.message)

    def test_curve_dialogs_auto_load_and_offer_explicit_external_reference(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            preview = root / "run_logs" / "workbench" / "preview" / "auto_threshold_preview.json"
            _write_preview(preview, root=root)
            common = {
                "accepted_preview_point_ids": ("PT-1",),
                "expected_config_sha256": "a" * 64,
                "expected_bridge_id": "unit_bridge",
                "expected_data_root": str(root),
                "expected_start_date": "2026-01-01",
                "expected_end_date": "2026-01-31",
                "automatic_preview_resolver": lambda: preview,
            }
            target = CleaningThresholdRow(
                "per_point", "acceleration", "PT-1", -1.0, 1.0
            )
            band = ThresholdBandDialog(target, **common)
            box = BoxThresholdDialog(target, side=LOWER_SIDE, **common)
            try:
                band.show()
                box.show()
                self.app.processEvents()
                self.assertIsNotNone(band.preview_series)
                self.assertIsNotNone(box.preview_series)
                self.assertIn("已核对", band.preview_path_label.text())
                self.assertIn("已核对", box.preview_path_label.text())
                self.assertTrue(band.import_preview_button.isVisible())
                self.assertTrue(box.import_preview_button.isVisible())
                self.assertIn("自动加载", band.auto_load_preview_button.text())
                self.assertIn("自动加载", box.auto_load_preview_button.text())
                self.assertNotIn("JSON", band.auto_load_preview_button.toolTip())
                self.assertNotIn("JSON", box.auto_load_preview_button.toolTip())
                self.assertIn("其他任务/项目", band.import_preview_button.text())
                self.assertIn("其他任务/项目", box.import_preview_button.text())
            finally:
                band.close()
                box.close()

    def test_external_reference_rebinds_values_without_claiming_task_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            preview = root / "external_curve.json"
            _write_preview(preview, root=root, bridge_id="other_bridge")
            target = CleaningThresholdRow(
                "per_point",
                "cable_accel",
                "CURRENT-POINT",
                -3.0,
                3.0,
                "2026-06-01 00:00:00",
                "2026-06-30 23:59:59",
            )
            common = {
                "accepted_preview_point_ids": ("CURRENT-POINT",),
                "expected_config_sha256": "b" * 64,
                "expected_bridge_id": "current_bridge",
                "expected_data_root": str(root / "current"),
                "expected_start_date": "2026-06-01",
                "expected_end_date": "2026-06-30",
                "automatic_preview_resolver": None,
            }
            band = ThresholdBandDialog(target, **common)
            box = BoxThresholdDialog(target, side=LOWER_SIDE, **common)
            try:
                band.load_reference_preview_path(preview)
                box.load_reference_preview_path(preview)
                self.assertTrue(band.external_reference_mode)
                self.assertTrue(box.external_reference_mode)
                self.assertFalse(band.preview_identity_verified)
                self.assertFalse(box.preview_identity_verified)
                self.assertEqual(band.preview_series.module_key, "cable_accel")
                self.assertEqual(box.preview_series.module_key, "cable_accel")
                self.assertEqual(band.preview_series.point_id, "CURRENT-POINT")
                self.assertEqual(box.preview_series.point_id, "CURRENT-POINT")
                draft = band.draft()
                self.assertEqual(draft.t_range_start, target.t_range_start)
                self.assertEqual(draft.t_range_end, target.t_range_end)
                self.assertIn("外部参考曲线", band.preview_path_label.text())
                self.assertIn("未绑定当前任务", box.preview_path_label.text())
            finally:
                band.close()
                box.close()

    def test_external_reference_does_not_fill_an_empty_target_time_window(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            preview = root / "external_curve.json"
            _write_preview(preview, root=root, bridge_id="other_bridge")
            target = CleaningThresholdRow(
                "per_point", "cable_accel", "CURRENT-POINT", -3.0, 3.0
            )
            band = ThresholdBandDialog(
                target,
                accepted_preview_point_ids=("CURRENT-POINT",),
                expected_bridge_id="current_bridge",
            )
            try:
                band.load_reference_preview_path(preview)
                draft = band.draft()
                self.assertEqual(draft.t_range_start, "")
                self.assertEqual(draft.t_range_end, "")
            finally:
                band.close()

    def test_failed_current_task_reload_keeps_external_reference_identity(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            preview = root / "external_curve.json"
            _write_preview(preview, root=root, bridge_id="other_bridge")
            target = CleaningThresholdRow(
                "per_point", "cable_accel", "CURRENT-POINT", -3.0, 3.0
            )
            common = {
                "accepted_preview_point_ids": ("CURRENT-POINT",),
                "expected_config_sha256": "b" * 64,
                "expected_bridge_id": "current_bridge",
                "expected_data_root": str(root / "current"),
                "expected_start_date": "2026-06-01",
                "expected_end_date": "2026-06-30",
                "automatic_preview_resolver": lambda: preview,
            }
            band = ThresholdBandDialog(target, **common)
            box = BoxThresholdDialog(target, side=LOWER_SIDE, **common)
            try:
                band.load_reference_preview_path(preview)
                box.load_reference_preview_path(preview)
                band_series = band.preview_series
                box_series = box.preview_series
                self.assertFalse(band._load_automatic_preview(silent=True))
                self.assertFalse(box._load_automatic_preview(silent=True))
                self.assertTrue(band.external_reference_mode)
                self.assertTrue(box.external_reference_mode)
                self.assertIs(band.preview_series, band_series)
                self.assertIs(box.preview_series, box_series)
                self.assertFalse(band.preview_identity_verified)
                self.assertFalse(box.preview_identity_verified)
                self.assertIn("保留外部参考曲线", band.preview_path_label.text())
                self.assertIn("保留外部参考曲线", box.preview_path_label.text())
            finally:
                band.close()
                box.close()

    def test_missing_curve_action_navigates_to_minimal_auto_suggestion_run(self) -> None:
        window = WorkbenchWindow(PROJECT_ROOT)
        try:
            window.cleaning_editor.auto_threshold_requested.emit("acceleration")
            self.app.processEvents()
            self.assertIs(window.tabs.currentWidget(), window.config_tabs)
            self.assertIs(
                window.config_tabs.currentWidget(), window.auto_threshold_editor
            )
            selected = window.auto_threshold_editor._selected_modules()
            self.assertEqual(selected, ["acceleration"])
            self.assertIn("请点击", window.auto_threshold_editor.status_label.text())
        finally:
            window.poll_timer.stop()
            window.close()


if __name__ == "__main__":
    unittest.main()
