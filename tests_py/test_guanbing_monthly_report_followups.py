from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from docx import Document


ROOT = Path(__file__).resolve().parents[1]
REPORTING = ROOT / "reporting"
if str(REPORTING) not in sys.path:
    sys.path.insert(0, str(REPORTING))

from build_guanbing_monthly_report import (  # noqa: E402
    apply_image_updates,
    normalize_acceleration_units,
)


class TestGuanbingMonthlyReportFollowups(unittest.TestCase):
    def test_normalize_acceleration_units_handles_split_legacy_runs(self):
        doc = Document()
        for index in range(200):
            doc.add_paragraph(f"前置段落 {index}")
        table = doc.add_table(rows=1, cols=1)
        paragraph = table.cell(0, 0).paragraphs[0]
        paragraph.add_run("阈值31.5cm/s")
        exponent = paragraph.add_run("2")
        exponent.font.superscript = True
        paragraph.add_run("，另一个为1m/s2。")

        self.assertEqual(normalize_acceleration_units(doc), 2)
        self.assertEqual(paragraph.text, "阈值31.5cm/s²，另一个为1m/s²。")
        self.assertNotIn("m/s2", paragraph.text)

    def test_report_uses_group_directories_for_tilt_and_lowpass_strain(self):
        calls: list[tuple[str, str]] = []

        def fake_find(_root: Path, configured_dir: str, prefix: str) -> Path:
            calls.append((configured_dir, prefix))
            return Path(configured_dir) / f"{prefix}.jpg"

        with tempfile.TemporaryDirectory() as tmp, patch(
            "build_guanbing_monthly_report.find_latest_image", side_effect=fake_find
        ), patch(
            "build_guanbing_monthly_report.build_accel_combined_image", return_value=Path(tmp) / "accel.jpg"
        ), patch(
            "build_guanbing_monthly_report.replace_picture_before_anchor",
            return_value=(True, "mock.jpg"),
        ):
            apply_image_updates(Document(), Path(tmp), Path(tmp) / "assets")

        self.assertIn(("时程曲线_倾角_组图", "Tilt_X"), calls)
        self.assertIn(("时程曲线_倾角_组图", "Tilt_Y"), calls)
        self.assertIn(("时程曲线_动应变_低通滤波_组图", "dynstrain_lp_G05"), calls)
        self.assertIn(("时程曲线_动应变_低通滤波_组图", "dynstrain_lp_G06"), calls)


if __name__ == "__main__":
    unittest.main()
