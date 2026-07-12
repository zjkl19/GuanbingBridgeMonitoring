from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "reporting"))

from report_visual_qc import analyze_page_image, create_contact_sheet


class ReportVisualQcTests(unittest.TestCase):
    def test_page_analysis_detects_blank_content_and_edge_touch(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            blank = root / "blank.png"
            content = root / "content.png"
            edge = root / "edge.png"
            Image.new("RGB", (200, 300), "white").save(blank)
            page = Image.new("RGB", (200, 300), "white")
            draw = ImageDraw.Draw(page)
            draw.rectangle((40, 60, 160, 240), fill="black")
            page.save(content)
            page = Image.new("RGB", (200, 300), "white")
            ImageDraw.Draw(page).rectangle((0, 60, 160, 240), fill="black")
            page.save(edge)
            self.assertTrue(analyze_page_image(blank)["blank"])
            self.assertFalse(analyze_page_image(content)["blank"])
            self.assertFalse(analyze_page_image(content)["edge_touch"])
            self.assertTrue(analyze_page_image(edge)["edge_touch"])

    def test_contact_sheet_contains_every_page(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            pages = []
            for index in range(5):
                path = root / f"page-{index + 1}.png"
                Image.new("RGB", (200, 300), (255, 255 - index * 20, 255)).save(path)
                pages.append(path)
            output = create_contact_sheet(pages, root / "contact.png", columns=4)
            self.assertTrue(output.is_file())
            with Image.open(output) as sheet:
                self.assertGreater(sheet.width, 1000)
                self.assertGreater(sheet.height, 700)


if __name__ == "__main__":
    unittest.main()
