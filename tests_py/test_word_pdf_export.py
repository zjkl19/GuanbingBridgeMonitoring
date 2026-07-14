from __future__ import annotations

import os
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[1]
REPORTING = ROOT / "reporting"
if str(REPORTING) not in sys.path:
    sys.path.insert(0, str(REPORTING))

from word_pdf_export import export_authoritative_word_pdf  # noqa: E402


class WordPdfExportTests(unittest.TestCase):
    def test_environment_switch_skips_word_without_touching_com(self) -> None:
        with tempfile.TemporaryDirectory() as folder, patch.dict(
            os.environ, {"BMS_NO_WORD": "1"}
        ):
            docx = Path(folder) / "report.docx"
            docx.write_bytes(b"docx")
            result = export_authoritative_word_pdf(docx)

        self.assertEqual(result.status, "skipped")
        self.assertFalse(result.authoritative)
        self.assertIsNone(result.path)

    def test_export_uses_dispatch_ex_and_atomically_publishes_pdf(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            docx = root / "report.docx"
            pdf = root / "report.pdf"
            docx.write_bytes(b"docx")

            fields = types.SimpleNamespace(Update=Mock())
            document = types.SimpleNamespace(
                StoryRanges=[],
                TablesOfContents=[],
                TablesOfFigures=[],
                TablesOfAuthorities=[],
                Fields=fields,
                Save=Mock(),
                Close=Mock(),
            )

            def export_as_pdf(path: str, _format: int) -> None:
                Path(path).write_bytes(b"%PDF-1.4\nword-export\n")

            document.ExportAsFixedFormat = Mock(side_effect=export_as_pdf)
            documents = types.SimpleNamespace(Open=Mock(return_value=document))
            word = types.SimpleNamespace(
                Visible=True,
                DisplayAlerts=1,
                Documents=documents,
                Quit=Mock(),
            )
            client = types.ModuleType("win32com.client")
            client.DispatchEx = Mock(return_value=word)
            win32com = types.ModuleType("win32com")
            win32com.client = client
            pythoncom = types.ModuleType("pythoncom")
            pythoncom.CoInitialize = Mock()
            pythoncom.CoUninitialize = Mock()

            with patch.object(os, "name", "nt"), patch.dict(
                os.environ, {"BMS_NO_WORD": "0"}
            ), patch.dict(
                sys.modules,
                {
                    "pythoncom": pythoncom,
                    "win32com": win32com,
                    "win32com.client": client,
                },
            ):
                result = export_authoritative_word_pdf(docx, pdf)

            self.assertEqual(result.status, "passed")
            self.assertTrue(result.authoritative)
            self.assertEqual(result.path, pdf.resolve())
            self.assertTrue(pdf.is_file())
            client.DispatchEx.assert_called_once_with("Word.Application")
            documents.Open.assert_called_once_with(
                str(docx.resolve()),
                ReadOnly=False,
                AddToRecentFiles=False,
                Visible=False,
            )
            document.ExportAsFixedFormat.assert_called_once()
            document.Close.assert_called_once_with(SaveChanges=False)
            word.Quit.assert_called_once_with()
            pythoncom.CoInitialize.assert_called_once_with()
            pythoncom.CoUninitialize.assert_called_once_with()


if __name__ == "__main__":
    unittest.main()
