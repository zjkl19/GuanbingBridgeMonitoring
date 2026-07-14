from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORTING = ROOT / "reporting"
if str(REPORTING) not in sys.path:
    sys.path.insert(0, str(REPORTING))

from build_jlj_monthly_report import load_json as load_jlj_config
from build_monthly_report import load_json as load_hongtang_config
from build_quarterly_wim_sample import load_json as load_wim_config
from build_shuixianhua_monthly_report import load_json as load_shuixianhua_config
from config_loader import load_report_config


class ReportingConfigLayerTests(unittest.TestCase):
    def test_all_report_loaders_receive_the_same_merged_config(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            base = root / "base.json"
            points = root / "points.json"
            entry = root / "project.json"
            base.write_text(
                json.dumps({"bridge": {"id": "unit"}, "defaults": {"gap": 1}}),
                encoding="utf-8",
            )
            points.write_text(
                json.dumps({"P1": {"alarm_bounds": {"level1": [-1, 1]}}}),
                encoding="utf-8",
            )
            entry.write_text(
                json.dumps({
                    "extends": "base.json",
                    "includes": {"per_point": "points.json"},
                    "defaults": {"gap": 2},
                }),
                encoding="utf-8",
            )

            expected = load_report_config(entry)
            for loader in (
                load_hongtang_config,
                load_jlj_config,
                load_shuixianhua_config,
                load_wim_config,
            ):
                self.assertEqual(loader(entry), expected)
            self.assertEqual(expected["defaults"]["gap"], 2)
            self.assertIn("P1", expected["per_point"])


if __name__ == "__main__":
    unittest.main()
