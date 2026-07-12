from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from workbench.manifest import find_latest_manifest, load_manifest_summary, manifest_context_issues


class WorkbenchManifestTests(unittest.TestCase):
    def test_manifest_summary_normalizes_module_records(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "analysis_manifest_1.json"
            path.write_text(json.dumps({
                "status": "ok",
                "artifact_count": 12,
                "bridge_profile": {"bridge_id": "hongtang"},
                "run_request": {
                    "data_root": str(Path(folder) / "data"),
                    "start_date": "2026-04-01",
                    "end_date": "2026-06-30"
                },
                "module_results": [
                    {"key": "temperature", "label": "温度", "status": "ok", "elapsed_sec": 1.2, "stats_path": "temp.xlsx"},
                    {"key": "wind", "label": "风", "status": "failed", "message": "missing source"},
                ],
            }, ensure_ascii=False), encoding="utf-8")
            summary = load_manifest_summary(path)
            self.assertEqual(summary.status, "ok")
            self.assertEqual(summary.artifact_count, 12)
            self.assertEqual(len(summary.modules), 2)
            self.assertEqual(summary.failed_modules[0].key, "wind")
            self.assertEqual(summary.missing_selected_modules(["temperature", "wind"]), ())
            self.assertEqual(summary.missing_selected_modules(["temperature", "strain"]), ("strain",))
            self.assertEqual(summary.bridge_id, "hongtang")
            self.assertEqual(
                manifest_context_issues(
                    summary,
                    bridge_id="hongtang",
                    data_root=Path(folder) / "data",
                    start_date="2026-04-01",
                    end_date="2026-06-30",
                ),
                [],
            )
            issues = manifest_context_issues(
                summary,
                bridge_id="zhishan",
                data_root=Path(folder) / "other",
                start_date="2026-05-01",
                end_date="2026-05-31",
            )
            self.assertEqual(len(issues), 4)

    def test_find_latest_manifest_uses_run_logs(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            logs = root / "run_logs"
            logs.mkdir()
            first = logs / "analysis_manifest_1.json"
            second = logs / "analysis_manifest_2.json"
            first.write_text("{}", encoding="utf-8")
            second.write_text("{}", encoding="utf-8")
            first.touch()
            second.touch()
            self.assertIn(find_latest_manifest(root), {first, second})


if __name__ == "__main__":
    unittest.main()
