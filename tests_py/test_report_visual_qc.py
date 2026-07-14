from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "reporting"))

from report_visual_qc import analyze_page_image, create_contact_sheet, render_docx_visual_qc


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

    def test_visual_qc_prefers_authoritative_pdf_without_libreoffice(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            docx = root / "report.docx"
            pdf = root / "word-export.pdf"
            docx.write_bytes(b"docx-placeholder")
            pdf.write_bytes(b"pdf-placeholder")
            renderer_calls: list[str] = []

            def fake_renderer(name: str) -> str | None:
                renderer_calls.append(name)
                return "pdftoppm" if name == "pdftoppm" else None

            def fake_run(command, **_kwargs):
                page = Path(str(command[-1]) + "-1.png")
                Image.new("RGB", (200, 300), "white").save(page)
                return SimpleNamespace(returncode=0, stderr="", stdout="")

            with patch("report_visual_qc._renderer", side_effect=fake_renderer), patch(
                "report_visual_qc.subprocess.run", side_effect=fake_run
            ):
                result = render_docx_visual_qc(
                    docx,
                    root / "visual",
                    preferred_pdf_path=pdf,
                )

            self.assertEqual(renderer_calls, ["pdftoppm"])
            self.assertEqual(result["renderer"], "authoritative_pdf")
            self.assertTrue(result["pdf_authoritative"])
            self.assertEqual(result["preview_pdf_path"], "")
            self.assertEqual(result["pdf_path"], str(pdf.resolve()))
            self.assertEqual(result["page_count"], 1)

    def test_libreoffice_pdf_is_marked_preview_only(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            docx = root / "report.docx"
            docx.write_bytes(b"docx-placeholder")

            def fake_renderer(name: str) -> str | None:
                return name

            def fake_run(command, **_kwargs):
                if "--convert-to" in command:
                    output_dir = Path(command[command.index("--outdir") + 1])
                    (output_dir / "report.pdf").write_bytes(b"pdf-placeholder")
                else:
                    page = Path(str(command[-1]) + "-1.png")
                    Image.new("RGB", (200, 300), "white").save(page)
                return SimpleNamespace(returncode=0, stderr="", stdout="")

            with patch("report_visual_qc._renderer", side_effect=fake_renderer), patch(
                "report_visual_qc.subprocess.run", side_effect=fake_run
            ):
                result = render_docx_visual_qc(docx, root / "visual")

            self.assertEqual(result["renderer"], "libreoffice_preview")
            self.assertFalse(result["pdf_authoritative"])
            self.assertEqual(result["preview_pdf_path"], result["pdf_path"])
            self.assertEqual(result["page_count"], 1)


if __name__ == "__main__":
    unittest.main()
