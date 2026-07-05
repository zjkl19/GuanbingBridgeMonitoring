import os
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "reporting"))

from build_period_report import update_fields_with_word  # noqa: E402


class TestBuildPeriodReportWordUpdate(unittest.TestCase):
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
