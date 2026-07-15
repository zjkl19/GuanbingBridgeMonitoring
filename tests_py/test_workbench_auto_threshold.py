from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.auto_threshold import (
    AutoThresholdError,
    PreviewSeries,
    load_result,
    load_preview_artifact,
    prepare_request,
    read_status,
    resolve_runner,
)
from workbench.models import file_sha256
from workbench.config_editor import CleaningConfigEditorSession, ConfigChangedError

try:
    from PySide6.QtWidgets import QApplication

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
            self.assertEqual(len(payload["config_sha256"]), 64)

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
                "preview_series": [{
                    "module_key": "temperature",
                    "point_id": "T-1",
                    "sensor_type": "temperature",
                    "times": ["2026-01-01 00:00:00", "2026-01-01 00:01:00"],
                    "values": [12.5, None],
                    "sample_count": 2,
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
            payload["preview_series"][0]["sample_count"] = 3
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
                "preview_series": [],
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
            self.assertTrue(widget._options()["capture_preview_series"])
            widget.preview_series = {
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


if __name__ == "__main__":
    unittest.main()
