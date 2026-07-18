from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.auto_threshold import (
    AutoThresholdError,
    PreviewSeries,
    load_result,
    load_preview_artifact,
    prepare_request,
    read_status,
    request_stop,
    resolve_runner,
)
from workbench.models import file_sha256
from workbench.config_editor import CleaningConfigEditorSession, ConfigChangedError

try:
    from PySide6.QtWidgets import QApplication, QMessageBox

    from workbench.auto_threshold_tab import AutoThresholdProposalWidget
except ImportError:  # pragma: no cover
    QApplication = None
    AutoThresholdProposalWidget = None


class WorkbenchAutoThresholdTests(unittest.TestCase):
    def test_prepare_request_pins_config_and_paths(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            paths, payload = prepare_request(
                bridge_id="unit_bridge",
                data_root=data,
                config_path=config,
                start_date="2026-01-01",
                end_date="2026-01-31",
                options={"module_keys": ["temperature"]},
                now=datetime(2026, 7, 12, 15, 0, 0),
                request_id="auto_unit",
            )
            self.assertEqual(payload["request_type"], "auto_threshold_proposal")
            self.assertEqual(payload["request_id"], "auto_unit")
            self.assertEqual(payload["bridge_id"], "unit_bridge")
            self.assertTrue(paths.request.is_file())
            self.assertFalse(paths.request.read_bytes().startswith(b"\xef\xbb\xbf"))
            self.assertEqual(read_status(paths.status)["status"], "prepared")
            self.assertEqual(Path(payload["result_path"]), paths.result)
            self.assertEqual(Path(payload["preview_path"]), paths.preview)
            self.assertEqual(Path(payload["stop_file"]), paths.stop)
            self.assertNotIn("stop_path", payload)
            self.assertEqual(len(payload["config_sha256"]), 64)
            prepared = read_status(paths.status)
            self.assertEqual(prepared["module_total"], 1)
            self.assertEqual(prepared["progress_percent"], 0.0)
            self.assertFalse(prepared["stop_requested"])
            stop_path = request_stop(paths)
            self.assertEqual(stop_path, paths.stop)
            stop_payload = json.loads(stop_path.read_text(encoding="utf-8"))
            self.assertEqual(stop_payload["request_id"], "auto_unit")

    def test_status_uses_only_canonical_progress_and_stop_file(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "status.json"
            path.write_text(
                json.dumps(
                    {
                        "status": "running",
                        "progress_fraction": 0.125,
                        "progress_percent": 12.5,
                        "stop_file": "task/stop.flag",
                    }
                ),
                encoding="utf-8",
            )
            status = read_status(path)
            self.assertEqual(status["progress_fraction"], 0.125)
            self.assertEqual(status["stop_file"], "task/stop.flag")
            self.assertNotIn("stop_path", status)
            path.write_text(
                json.dumps(
                    {
                        "status": "running",
                        "stop_path": "removed/legacy.flag",
                    }
                ),
                encoding="utf-8",
            )
            self.assertEqual(read_status(path)["stop_file"], "")

    def test_resolve_runner_and_result_normalization(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            runner = root / "bin" / "BridgeAnalysisRunner" / "BridgeAnalysisRunner.exe"
            runner.parent.mkdir(parents=True)
            runner.write_bytes(b"exe")
            self.assertEqual(resolve_runner(root), runner.resolve())
            result = root / "result.json"
            result.write_text(
                json.dumps({
                    "request_type": "auto_threshold_proposal",
                    "proposals": {"kind": "review"},
                }),
                encoding="utf-8",
            )
            self.assertEqual(len(load_result(result)["proposals"]), 1)

    def test_preview_artifact_is_hash_pinned_and_count_closed(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data_root = root / "data"
            data_root.mkdir()
            path = root / "preview.json"
            payload = {
                "schema_version": 1,
                "artifact_type": "auto_threshold_preview",
                "request_type": "auto_threshold_proposal",
                "request_id": "unit-preview",
                "bridge_id": "unit_bridge",
                "config_sha256": "a" * 64,
                "data_root": str(data_root.resolve()),
                "start_date": "2026-01-01",
                "end_date": "2026-01-31",
                "curve_records": [{
                    "module_key": "temperature",
                    "point_id": "T-1",
                    "sensor_type": "temperature",
                    "times": ["2026-01-01 00:00:00", "2026-01-01 00:01:00"],
                    "values": [12.5, None],
                    "sample_count": 2,
                    "source_sample_count": 2,
                    "finite_sample_count": 1,
                }],
            }
            path.write_text(json.dumps(payload), encoding="utf-8")
            rows = load_preview_artifact(
                path,
                expected_sha256=file_sha256(path),
                expected_request_id="unit-preview",
                expected_config_sha256="a" * 64,
                expected_bridge_id="UNIT_BRIDGE",
                expected_data_root=data_root / ".",
                expected_start_date="2026-01-01",
                expected_end_date="2026-01-31",
                expected_series_count=1,
            )
            self.assertEqual(rows[("temperature", "T-1")].values, (12.5, None))
            payload["curve_records"][0]["sample_count"] = 3
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(AutoThresholdError, "点数不闭合"):
                load_preview_artifact(path)

    def test_preview_context_validation_fails_closed_for_legacy_or_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data_root = root / "data"
            data_root.mkdir()
            path = root / "preview.json"
            payload = {
                "schema_version": 1,
                "artifact_type": "auto_threshold_preview",
                "request_type": "auto_threshold_proposal",
                "request_id": "legacy-preview",
                "config_sha256": "b" * 64,
                "curve_records": [],
            }
            path.write_text(json.dumps(payload), encoding="utf-8")
            expected = {
                "expected_bridge_id": "unit_bridge",
                "expected_data_root": data_root,
                "expected_start_date": "2026-05-01",
                "expected_end_date": "2026-05-31",
            }
            with self.assertRaisesRegex(AutoThresholdError, "缺少桥梁编号"):
                load_preview_artifact(path, **expected)

            payload.update(
                bridge_id="unit_bridge",
                data_root=str(data_root.resolve()),
                start_date="2026-05-01",
                end_date="2026-05-31",
            )
            path.write_text(json.dumps(payload), encoding="utf-8")
            self.assertEqual(load_preview_artifact(path, **expected), {})
            with self.assertRaisesRegex(AutoThresholdError, "桥梁编号与当前任务不一致"):
                load_preview_artifact(
                    path, **{**expected, "expected_bridge_id": "other_bridge"}
                )
            with self.assertRaisesRegex(AutoThresholdError, "数据目录与当前任务不一致"):
                load_preview_artifact(
                    path, **{**expected, "expected_data_root": root / "other"}
                )
            with self.assertRaisesRegex(AutoThresholdError, "开始日期与当前任务不一致"):
                load_preview_artifact(
                    path, **{**expected, "expected_start_date": "2026-05-02"}
                )
            with self.assertRaisesRegex(AutoThresholdError, "结束日期与当前任务不一致"):
                load_preview_artifact(
                    path, **{**expected, "expected_end_date": "2026-05-30"}
                )

    def test_beta_preview_rejects_removed_preview_series_alias(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            path = root / "auto_threshold_preview.json"
            payload = {
                "schema_version": 1,
                "artifact_type": "auto_threshold_preview",
                "request_type": "auto_threshold_proposal",
                "request_id": "auto-no-alias",
                "bridge_id": "unit_bridge",
                "config_sha256": "a" * 64,
                "data_root": str(root.resolve()),
                "start_date": "2026-01-01",
                "end_date": "2026-01-31",
                "preview_series": [
                    {
                        "module_key": "temperature",
                        "point_id": "T-1",
                        "sensor_type": "temperature",
                        "times": ["2026-01-01T00:00:00"],
                        "values": [12.5],
                        "sample_count": 1,
                        "source_sample_count": 1,
                        "finite_sample_count": 1,
                    }
                ],
            }
            path.write_text(json.dumps(payload), encoding="utf-8")
            with self.assertRaisesRegex(AutoThresholdError, "curve_records"):
                load_preview_artifact(path)

    def test_selected_proposals_use_apply_key_safe_id_and_config_pin(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "config.json"
            payload = {"defaults": {}, "per_point": {}, "plot_common": {"gap_mode": "connect"}}
            path.write_text(json.dumps(payload), encoding="utf-8")
            session = CleaningConfigEditorSession(path)
            proposal = {
                "selected": True,
                "module_key": "dynamic_strain",
                "apply_key": "dynamic_strain",
                "point_id": "SX-1",
                "safe_id": "SX_1",
                "kind": "range",
                "min": -10,
                "max": 10,
                "t_range_start": "",
                "t_range_end": "",
            }
            result = session.save_proposals([proposal], expected_sha256=session.loaded_sha256)
            self.assertTrue(result.changed)
            updated = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(
                updated["per_point"]["dynamic_strain"]["SX_1"]["thresholds"],
                [{"min": -10, "max": 10}],
            )
            self.assertEqual(updated["name_map_global"]["SX_1"], "SX-1")
            stale = CleaningConfigEditorSession(path)
            expected = stale.loaded_sha256
            path.write_text("{}", encoding="utf-8")
            with self.assertRaises(ConfigChangedError):
                stale.save_proposals([proposal], expected_sha256=expected)


@unittest.skipIf(QApplication is None, "PySide6 is not installed")
class WorkbenchAutoThresholdGuiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_widget_builds_options_and_round_trips_proposal_table(self) -> None:
        widget = AutoThresholdProposalWidget(Path.cwd(), lambda: {})
        proposal = {
            "selected": True,
            "module_key": "temperature",
            "apply_key": "temperature",
            "point_id": "T-1",
            "safe_id": "T_1",
            "kind": "range",
            "algorithm": "quantile",
            "min": -5,
            "max": 50,
            "t_range_start": "",
            "t_range_end": "",
            "valid_count": 100,
            "removed_count": 2,
            "removed_ratio": 0.02,
            "score": 1.0,
            "reason": "unit",
        }
        try:
            widget._populate([proposal])
            self.assertEqual(widget.module_list.count(), 15)
            self.assertEqual(widget.table.rowCount(), 1)
            self.assertEqual(widget.proposals()[0]["apply_key"], "temperature")
            self.assertEqual(widget._options()["auto_cut_mode"], "standard")
            self.assertTrue(widget._options()["capture_curve_records"])
            self.assertNotIn("capture_preview_series", widget._options())
            widget.curve_records = {
                ("temperature", "T-1"): PreviewSeries(
                    "temperature",
                    "T-1",
                    "temperature",
                    ("2026-01-01 00:00:00", "2026-01-01 00:01:00"),
                    (10.0, 100.0),
                )
            }
            widget._refresh_preview()
            self.assertIn("T-1", widget.preview.summary_text())
            self.assertTrue(widget.popup_preview_button.isEnabled())
            widget.table.item(0, 6).setText("80")
            self.assertIn("80", widget.preview.summary_text())
        finally:
            widget.close()

    def test_widget_renders_truthful_progress_and_requests_cooperative_stop(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            data = root / "data"
            data.mkdir()
            config = root / "config.json"
            config.write_text("{}", encoding="utf-8")
            paths, _payload = prepare_request(
                bridge_id="unit_bridge",
                data_root=data,
                config_path=config,
                start_date="2026-01-01",
                end_date="2026-01-31",
                options={"module_keys": ["temperature"]},
                request_id="auto_ui_stop",
            )

            class ProcessWithoutTerminate:
                def poll(self) -> None:
                    return None

            widget = AutoThresholdProposalWidget(Path.cwd(), lambda: {})
            try:
                state = widget._render_progress(
                    {
                        "status": "running",
                        "stage": "load_curve",
                        "module_key": "temperature",
                        "point_id": "T-1",
                        "current_date": "2026-01-12",
                        "processed_dates": 12,
                        "total_dates": 31,
                        "progress_fraction": 0.4,
                        "elapsed_seconds": 18.25,
                        "proposal_count": 0,
                    }
                )
                self.assertEqual(state, "running")
                self.assertEqual(widget.progress_bar.value(), 400)
                self.assertIn("T-1", widget.progress_detail.text())
                self.assertIn("读取当前测点曲线", widget.progress_detail.text())
                self.assertNotIn("load_curve", widget.progress_detail.text())
                self.assertIn("12/31", widget.progress_detail.text())
                self.assertIn("18 秒", widget.progress_detail.text())
                self.assertTrue(widget.stop_button.property("destructiveAction"))

                widget.current_run = SimpleNamespace(
                    paths=paths,
                    process=ProcessWithoutTerminate(),
                )
                widget.stop_button.setEnabled(True)
                with (
                    patch(
                        "workbench.auto_threshold_tab.QMessageBox.question",
                        return_value=QMessageBox.Yes,
                    ),
                    patch("workbench.auto_threshold_tab.request_stop") as safe_stop,
                ):
                    widget.stop()
                safe_stop.assert_called_once()
                self.assertFalse(widget.stop_button.isEnabled())
                self.assertIn("等待后台", widget.status_label.text())
            finally:
                widget.close()


if __name__ == "__main__":
    unittest.main()
