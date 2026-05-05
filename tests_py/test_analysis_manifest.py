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
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )

            self.assertEqual(find_latest_analysis_manifest(root), manifest_path)
            context = analysis_manifest_context(root)
            missing = manifest_missing_modules(context["manifest"])
            self.assertEqual({item["key"] for item in missing}, {"strain", "wind"})
            summary = missing_module_summary_items(context)
            self.assertTrue(any("应变分析" in item for item in summary))
            self.assertTrue(any("风速风向分析" in item for item in summary))


if __name__ == "__main__":
    unittest.main()
