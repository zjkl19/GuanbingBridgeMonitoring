from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys

REPO_ROOT = Path(__file__).resolve().parents[1]
REPORTING_ROOT = REPO_ROOT / "reporting"
for candidate in (REPO_ROOT, REPORTING_ROOT):
    if str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

from reporting.build_jlj_monthly_report import ImageItem, SectionContent, collect_missing_items


class JiulongjiangMissingItemsTests(unittest.TestCase):
    def test_unavailable_section_is_reported(self) -> None:
        section_map = {
            "main_eq": SectionContent(
                narrative="本月未获取到主桥地震动有效数据。",
                summary_sentence="本月未获取到主桥地震动有效数据。",
                available=False,
            )
        }

        rows = collect_missing_items(section_map)

        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["category"], "章节内容缺失")
        self.assertIn("地震动监测", rows[0]["section"])
        self.assertIn("地震动", rows[0]["detail"])

    def test_missing_image_is_reported_but_existing_image_is_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            existing = Path(tmp) / "exists.jpg"
            existing.write_bytes(b"fake")
            missing = Path(tmp) / "missing.jpg"
            section_map = {
                "main_wind": SectionContent(
                    narrative="",
                    summary_sentence="",
                    image_items=[
                        ImageItem("已存在图片", existing),
                        ImageItem("缺失图片", missing),
                    ],
                )
            }

            rows = collect_missing_items(section_map)

            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["category"], "图表/资源缺失")
            self.assertEqual(rows[0]["item"], "缺失图片")
            self.assertIn("风向风速监测", rows[0]["section"])


if __name__ == "__main__":
    unittest.main()
