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
    _docx_contains_broken_reference_text,
    _patch_report_number_in_docx,
    period_report_number,
    update_fields_with_word,
)
from report_build_manifest import build_report_manifest  # noqa: E402
from report_context import ReportBuildContext  # noqa: E402


class TestBuildPeriodReportWordUpdate(unittest.TestCase):
    def test_period_report_number_uses_quarter_suffix(self):
        from datetime import date

        self.assertEqual(period_report_number(date(2026, 1, 1), date(2026, 3, 31)), "BG02FQJC2600002-J1")
        self.assertEqual(period_report_number(date(2026, 4, 1), date(2026, 6, 30)), "BG02FQJC2600002-J2")

    def test_report_build_manifest_keeps_report_number_extra(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            docx = root / "report.docx"
            with zipfile.ZipFile(docx, "w") as z:
                z.writestr("word/document.xml", "<w:document />")
            context = ReportBuildContext.from_inputs(
                template=root / "template.docx",
                result_root=root,
                analysis_root=root,
                output_dir=root / "out",
            )

            payload = build_report_manifest(
                context=context,
                report_type="hongtang_period",
                output_docx=docx,
                timestamp="20260707_000000",
                extra={"report_number": "BG02FQJC2600002-J2"},
            )

            self.assertEqual(payload["report_number"], "BG02FQJC2600002-J2")

    def test_patch_report_number_docx_headers_and_body(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            document_xml = (
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                "<w:t>报告编号：BG02FQJC2600002-J1</w:t>"
                "</w:document>"
            )
            header_xml = (
                '<w:hdr xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                "<w:t>报告编号：BG02FQJC2600002-J1</w:t>"
                "</w:hdr>"
            )
            with zipfile.ZipFile(docx, "w") as z:
                z.writestr("word/document.xml", document_xml)
                z.writestr("word/header1.xml", header_xml)

            count = _patch_report_number_in_docx(docx, "BG02FQJC2600002-J2")

            self.assertEqual(count, 2)
            with zipfile.ZipFile(docx) as z:
                patched_body = z.read("word/document.xml").decode("utf-8")
                patched_header = z.read("word/header1.xml").decode("utf-8")
            self.assertIn("BG02FQJC2600002-J2", patched_body)
            self.assertIn("BG02FQJC2600002-J2", patched_header)
            self.assertNotIn("BG02FQJC2600002-J1", patched_body + patched_header)

    def test_broken_reference_detection_joins_split_runs(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            document_xml = (
                '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
                '<w:p><w:r><w:t>错误: 引用源</w:t></w:r><w:r><w:t>未找到</w:t></w:r></w:p>'
                '</w:document>'
            )
            with zipfile.ZipFile(docx, "w") as archive:
                archive.writestr("word/document.xml", document_xml)

            self.assertTrue(_docx_contains_broken_reference_text(docx))

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
                    self.assertNotIn("Replace-HardcodedTotalPages", script_text)
                    self.assertNotIn("Replace-TotalPagesText", script_text)
                    self.assertNotIn("ComputeStatistics(2)", script_text)
                    self.assertIn("KWPS.Application", script_text)
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

    def test_relative_docx_path_is_resolved_before_word_update(self):
        seen = []

        def fake_python_update(path):
            seen.append(path)
            return True, ""

        env = {k: v for k, v in os.environ.items() if k != "BMS_NO_WORD"}
        with (
            patch.dict(os.environ, env, clear=True),
            patch("build_period_report._run_python_word_field_update", side_effect=fake_python_update),
        ):
            warnings = update_fields_with_word(Path("relative-output") / "report.docx")

        self.assertEqual(warnings, [])
        self.assertEqual(len(seen), 1)
        self.assertTrue(seen[0].is_absolute())
        self.assertEqual(seen[0].name, "report.docx")

    def test_broken_reference_update_is_rejected_and_original_restored(self):
        with tempfile.TemporaryDirectory() as tmp:
            docx = Path(tmp) / "report.docx"
            original = b"original-placeholder"
            docx.write_bytes(original)

            def fake_run(args, **kwargs):
                docx.write_bytes(b"corrupted-by-field-engine")
                return SimpleNamespace(returncode=0, stdout="BMS_WORD_PAGE_COUNT=10", stderr="")

            env = {k: v for k, v in os.environ.items() if k != "BMS_NO_WORD"}
            with (
                patch.dict(os.environ, env, clear=True),
                patch("subprocess.run", side_effect=fake_run),
                patch("build_period_report._docx_contains_broken_reference_text", return_value=True),
            ):
                warnings = update_fields_with_word(docx)

            self.assertEqual(docx.read_bytes(), original)
            self.assertEqual(len(warnings), 1)
            self.assertIn("broken reference", warnings[0])


if __name__ == "__main__":
    unittest.main()
