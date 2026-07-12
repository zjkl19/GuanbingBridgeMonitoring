from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from unittest.mock import patch

from scripts.validate_fresh_report_profiles import _comparison, _console_progress, _historical_by_bridge


class FreshReportProfileValidationTests(unittest.TestCase):
    def test_comparison_records_page_and_media_deltas(self) -> None:
        fresh = {"page_count": 46, "media_count": 57}
        historical = {
            "docx_path": "accepted.docx",
            "status": "passed",
            "visual": {"page_count": 47, "contact_sheet": "accepted.png"},
            "package": {"media_count": 59},
        }
        result = _comparison(fresh, historical)
        self.assertTrue(result["historical_available"])
        self.assertEqual(result["page_count_delta"], -1)
        self.assertEqual(result["media_count_delta"], -2)
        self.assertEqual(result["historical_contact_sheet"], "accepted.png")

    def test_historical_matrix_requires_object_records(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "matrix.json"
            path.write_text(
                '{"records":[{"bridge_id":"zhishan","status":"passed"},42]}',
                encoding="utf-8",
            )
            result = _historical_by_bridge(path)
            self.assertEqual(set(result), {"zhishan"})
            self.assertEqual(result["zhishan"]["status"], "passed")

    def test_detached_stdout_does_not_fail_long_validation(self) -> None:
        with patch("builtins.print", side_effect=OSError(22, "detached")):
            _console_progress("zhishan", "rendering", 0.82)


if __name__ == "__main__":
    unittest.main()
