from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtWidgets import QApplication
from PySide6.QtWidgets import QLabel

from workbench.threshold_curve import (
    ThresholdCurveRecordMetadata,
    prepare_threshold_curve_request,
)
from workbench.threshold_curve_history import ThresholdCurveHistoryDialog
from workbench.threshold_curve_task_dialog import ThresholdCurveTaskDialog


PROJECT_ROOT = Path(__file__).resolve().parents[1]
class ThresholdCurveUiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_manual_curve_modules_import_without_beta_implementation(self) -> None:
        probe = """
import json
import sys
import tempfile
from pathlib import Path

import workbench.manual_threshold_dialog
import workbench.box_threshold_dialog
from workbench.threshold_curve import load_threshold_curve_reference

with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / "threshold_curve_preview.json"
    path.write_text(json.dumps({
        "schema_version": 1,
        "artifact_type": "threshold_curve_preview",
        "request_type": "threshold_curve_generation",
        "request_id": "manual-import-contract",
        "bridge_id": "unit_bridge",
        "data_root": folder,
        "config_sha256": "a" * 64,
        "start_date": "2026-01-01",
        "end_date": "2026-01-01",
        "module_key": "temperature",
        "point_id": "T-1",
        "sensor_type": "temperature",
        "curve_records": [{
            "module_key": "temperature",
            "point_id": "T-1",
            "sensor_type": "temperature",
            "times": ["2026-01-01T00:00:00"],
            "values": [20.0],
            "sample_count": 1,
            "source_sample_count": 1,
            "finite_sample_count": 1,
        }],
    }), encoding="utf-8")
    assert ("temperature", "T-1") in load_threshold_curve_reference(path)
assert "workbench.auto_threshold" not in sys.modules
"""
        completed = subprocess.run(
            [
                os.fspath(Path(os.sys.executable)),
                "-c",
                probe,
            ],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)

    def test_history_dialog_uses_bridge_month_module_point_lists(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            preview = root / "run_logs" / "workbench" / "curve1" / "threshold_curve_preview.json"
            preview.parent.mkdir(parents=True)
            preview.write_text("{}", encoding="utf-8")
            record = ThresholdCurveRecordMetadata(
                record_path=preview.with_name("threshold_curve_record.json"),
                preview_path=preview,
                request_id="curve1",
                bridge_id="bridge_a",
                data_root=root,
                start_date="2026-06-01",
                end_date="2026-06-30",
                config_sha256="a" * 64,
                module_key="acceleration",
                point_id="A-01",
                sensor_type="acceleration",
                sample_count=20000,
                source_sample_count=120000,
                finite_sample_count=119000,
                created_at="2026-07-18T12:00:00+08:00",
                source_kind="threshold_curve_record",
            )
            with patch(
                "workbench.threshold_curve_history.discover_threshold_curve_history",
                return_value=(record,),
            ):
                dialog = ThresholdCurveHistoryDialog(
                    (root,),
                    target_module="acceleration",
                    target_point_ids=("A-01",),
                )
            try:
                self.assertEqual(dialog.bridge_filter.currentData(), "")
                self.assertEqual(dialog.module_filter.currentData(), "acceleration")
                self.assertEqual(dialog.point_filter.currentData(), "A-01")
                self.assertEqual(dialog.table.rowCount(), 1)
                self.assertEqual(dialog.table.item(0, 1).text(), "2026-06-01 至 2026-06-30")
                self.assertEqual(dialog.selected_preview_path(), preview)
                self.assertNotIn("JSON", dialog.windowTitle())
                label_text = "\n".join(label.text() for label in dialog.findChildren(QLabel))
                self.assertIn("不需要辨认 JSON", label_text)
            finally:
                dialog.close()

    def test_task_dialog_renders_real_progress_and_only_writes_safe_stop(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            config.write_text('{"bridge_id":"unit_bridge"}', encoding="utf-8")
            paths, _payload = prepare_threshold_curve_request(
                bridge_id="unit_bridge",
                data_root=data,
                config_path=config,
                start_date="2026-01-01",
                end_date="2026-01-31",
                module_key="acceleration",
                point_id="A-01",
                request_id="curve_ui_stop",
            )
            context = {
                "bridge_id": "unit_bridge",
                "data_root": str(data),
                "config_path": str(config),
                "start_date": "2026-01-01",
                "end_date": "2026-01-31",
            }
            with patch(
                "workbench.threshold_curve_task_dialog.QTimer.singleShot"
            ):
                dialog = ThresholdCurveTaskDialog(
                    PROJECT_ROOT, context, "acceleration", "A-01"
                )

            class ProcessWithoutTerminate:
                def poll(self) -> None:
                    return None

            try:
                state = dialog._update_status(
                    {
                        "status": "running",
                        "stage": "load_cache_date",
                        "current_date": "2026-01-17",
                        "processed_dates": 17,
                        "total_dates": 31,
                        "progress_fraction": 0.55,
                        "elapsed_seconds": 12.75,
                    }
                )
                self.assertEqual(state, "running")
                self.assertEqual(dialog.progress.value(), 550)
                self.assertEqual(dialog.current_date_label.text(), "2026-01-17")
                self.assertEqual(dialog.date_count_label.text(), "17/31")
                self.assertEqual(dialog.elapsed_label.text(), "13 秒")
                self.assertTrue(dialog.stop_button.property("destructiveAction"))

                dialog.current_run = SimpleNamespace(
                    paths=paths,
                    process=ProcessWithoutTerminate(),
                )
                dialog.stop_button.setEnabled(True)
                with patch(
                    "workbench.threshold_curve_task_dialog.request_stop"
                ) as safe_stop:
                    dialog.stop()
                safe_stop.assert_called_once_with(
                    paths,
                    reason="用户在工作平台请求安全停止当前测点曲线任务",
                )
                self.assertFalse(dialog.stop_button.isEnabled())
                self.assertIn("安全边界", dialog.message_label.text())
            finally:
                dialog._finish_terminal()
                dialog.close()


if __name__ == "__main__":
    unittest.main()
