from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
REPORTING_ROOT = REPO_ROOT / "reporting"
for candidate in (REPO_ROOT, REPORTING_ROOT):
    if str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

from reporting.analysis_manifest import (
    analysis_manifest_context,
    find_latest_analysis_manifest,
    manifest_missing_modules,
    manifest_precheck_warnings,
    missing_module_summary_items,
)


class AnalysisManifestTests(unittest.TestCase):
    def test_latest_manifest_and_missing_modules(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_logs = root / "run_logs"
            run_logs.mkdir()
            manifest_path = run_logs / "analysis_manifest_20260101_010101.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "module_preflight": [
                            {"key": "strain", "label": "应变分析", "status": "missing", "message": "missing stats"}
                        ],
                        "module_logs": [
                            {"key": "wind", "label": "风速风向分析", "status": "fail", "message": "read failed"}
                        ],
                        "module_results": [
                            {"key": "eq", "label": "地震动分析", "status": "skip", "message": "no data"}
                        ],
                        "run_request": {"data_root": "E:/data"},
                        "run_preflight": {"status": "warning"},
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            self.assertEqual(find_latest_analysis_manifest(root), manifest_path)
            context = analysis_manifest_context(root)
            missing = manifest_missing_modules(context["manifest"])
            self.assertEqual({item["key"] for item in missing}, {"strain", "eq"})
            self.assertEqual(context["run_request"]["data_root"], "E:/data")
            self.assertEqual(context["run_preflight"]["status"], "warning")
            summary = missing_module_summary_items(context)
            self.assertTrue(any("应变分析" in item for item in summary))
            self.assertTrue(any("地震动分析" in item for item in summary))

    def test_manifest_precheck_warnings(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            run_logs = root / "run_logs"
            run_logs.mkdir()
            (run_logs / "analysis_manifest_20260101_010101.json").write_text(
                json.dumps(
                    {
                        "status": "failed",
                        "missing_expected_stats": ["E:/data/stats/strain_stats.xlsx"],
                        "run_preflight": {"warnings": ["WIM input missing for 202601"]},
                        "module_results": [
                            {"key": "strain", "label": "应变分析", "status": "fail", "message": "read failed"}
                        ],
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            warnings = manifest_precheck_warnings(root)
            joined = "\n".join(warnings)
            self.assertIn("analysis manifest status is failed", joined)
            self.assertIn("应变分析", joined)
            self.assertIn("strain_stats.xlsx", joined)
            self.assertIn("WIM input missing", joined)

    def test_missing_manifest_warning(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            warnings = manifest_precheck_warnings(Path(tmp))

            self.assertEqual(len(warnings), 1)
            self.assertIn("analysis manifest not found", warnings[0])


if __name__ == "__main__":
    unittest.main()
