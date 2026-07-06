import os
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_period_report import (  # noqa: E402
    _parse_word_page_count,
    _patch_hardcoded_total_pages_in_docx,
    _patch_hardcoded_total_pages_xml,
    update_fields_with_word,
)


class TestBuildPeriodReportWordUpdate(unittest.TestCase):
    def test_parse_word_page_count(self):
        self.assertEqual(_parse_word_page_count("BMS_WORD_PAGE_COUNT=79\n"), 79)
        self.assertIsNone(_parse_word_page_count("no page count"))

    def test_patch_hardcoded_total_pages_xml(self):
        xml = (
            '<w:t xml:space="preserve">\u9875 \u5171 </w:t>'
            '<w:r><w:t>63</w:t></w:r>'
            '<w:t xml:space="preserve"> \u9875</w:t>'
        )
        patched, count = _patch_hardcoded_total_pages_xml(xml, 79)

        self.assertEqual(count, 1)
        self.assertIn("<w:t>79</w:t>", patched)
        self.assertNotIn("<w:t>63</w:t>", patched)

    def test_patch_hardcoded_total_pages_docx_headers(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            header_xml = (
                '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                '<w:t xml:space="preserve">\u9875 \u5171 </w:t>'
                '<w:r><w:t>63</w:t></w:r>'
                '<w:t xml:space="preserve"> \u9875</w:t>'
                "</w:hdr>"
            )
            with zipfile.ZipFile(docx, "w") as z:
                z.writestr("word/header2.xml", header_xml)
                z.writestr("word/document.xml", "<w:document />")

            count = _patch_hardcoded_total_pages_in_docx(docx, 79)

            self.assertEqual(count, 1)
            with zipfile.ZipFile(docx) as z:
                patched = z.read("word/header2.xml").decode("utf-8")
            self.assertIn("<w:t>79</w:t>", patched)
            self.assertNotIn("<w:t>63</w:t>", patched)

    def test_powershell_fallback_after_pythoncom_failure(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            docx.write_bytes(b"placeholder")
            calls = []

            def fake_run(args, **kwargs):
                calls.append((args, kwargs))
                exe = Path(args[0]).name.lower()
                if exe in ("python", "python.exe"):
                    return SimpleNamespace(returncode=1, stdout="", stderr="No module named 'pythoncom'")
                if exe in ("powershell.exe", "powershell"):
                    self.assertEqual(kwargs["env"]["BMS_DOCX_PATH"], str(docx))
                    script_text = Path(args[-1]).read_text(encoding="utf-8")
                    self.assertIn("$doc.Repaginate()", script_text)
                    self.assertIn("$section.Headers", script_text)
                    self.assertIn("$section.Footers", script_text)
                    self.assertIn("Update-ShapeFields", script_text)
                    self.assertIn("$header.Shapes", script_text)
                    self.assertIn("Replace-HardcodedTotalPages", script_text)
                    self.assertIn("ComputeStatistics(2)", script_text)
                    return SimpleNamespace(returncode=0, stdout="", stderr="")
                return SimpleNamespace(returncode=1, stdout="", stderr="unexpected")

            env = {k: v for k, v in os.environ.items() if k != "BMS_NO_WORD"}
            with patch.dict(os.environ, env, clear=True), patch("subprocess.run", side_effect=fake_run):
                warnings = update_fields_with_word(docx)

            self.assertEqual(warnings, [])
            self.assertTrue(any(Path(call[0][0]).name.lower() == "powershell.exe" for call in calls))

    def test_failed_field_update_returns_warning(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            docx.write_bytes(b"placeholder")

            def fake_run(args, **kwargs):
                return SimpleNamespace(returncode=1, stdout="", stderr="failed")

            env = {k: v for k, v in os.environ.items() if k != "BMS_NO_WORD"}
            with patch.dict(os.environ, env, clear=True), patch("subprocess.run", side_effect=fake_run):
                warnings = update_fields_with_word(docx)

            self.assertEqual(len(warnings), 1)
            self.assertIn("word_field_update_failed", warnings[0])


if __name__ == "__main__":
    unittest.main()
