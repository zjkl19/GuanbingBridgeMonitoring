from __future__ import annotations

import json
import os
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from workbench.auto_threshold import (
    load_result,
    prepare_request,
    read_status,
    resolve_runner,
)
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
            self.assertTrue(paths.request.is_file())
            self.assertFalse(paths.request.read_bytes().startswith(b"\xef\xbb\xbf"))
            self.assertEqual(read_status(paths.status)["status"], "prepared")
            self.assertEqual(Path(payload["result_path"]), paths.result)
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
        finally:
            widget.close()


if __name__ == "__main__":
    unittest.main()
