from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STARTER = ROOT / "scripts" / "start_word_export_background.ps1"
WORKER = ROOT / "scripts" / "update_word_fields_and_export_pdf.ps1"
PDF_WORKER = ROOT / "scripts" / "export_word_docx_to_pdf.ps1"


def _powershell() -> str:
    executable = shutil.which("powershell.exe") or shutil.which("powershell")
    if not executable:
        raise unittest.SkipTest("Windows PowerShell is unavailable")
    return executable


class WordExportScriptTests(unittest.TestCase):
    def test_scripts_parse_without_powershell_errors(self) -> None:
        powershell_paths = ", ".join(
            "'" + str(path).replace("'", "''") + "'" for path in (STARTER, WORKER)
        )
        command = f"""
$failed = @()
foreach ($path in @({powershell_paths})) {{
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors
    )
    if ($errors.Count -gt 0) {{
        $failed += ($path + ': ' + (($errors | ForEach-Object Message) -join ' | '))
    }}
}}
if ($failed.Count -gt 0) {{
    [Console]::Error.WriteLine(($failed -join [Environment]::NewLine))
    exit 2
}}
"""
        result = subprocess.run(
            [
                _powershell(),
                "-NoProfile",
                "-Command",
                command,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr or result.stdout)

    def test_plan_only_quotes_paths_without_launching_word(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "folder with spaces"
            root.mkdir()
            docx = root / "report with spaces.docx"
            docx.write_bytes(b"not opened in plan-only mode")
            pdf = root / "report with spaces.pdf"
            receipt = root / "receipt with spaces.json"
            status = root / "status with spaces.json"
            stdout = root / "stdout with spaces.log"
            stderr = root / "stderr with spaces.log"
            result = subprocess.run(
                [
                    _powershell(),
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(STARTER),
                    "-DocxPath",
                    str(docx),
                    "-PdfPath",
                    str(pdf),
                    "-ReceiptPath",
                    str(receipt),
                    "-StatusPath",
                    str(status),
                    "-StdoutPath",
                    str(stdout),
                    "-StderrPath",
                    str(stderr),
                    "-PlanOnly",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8-sig",
                errors="strict",
                timeout=20,
            )
            self.assertEqual(result.returncode, 0, result.stderr or result.stdout)
            payload = json.loads(result.stdout)
            self.assertEqual(payload["status"], "planned")
            self.assertEqual(Path(payload["docx_path"]), docx.resolve())
            for path in (docx, pdf, receipt, status):
                self.assertIn(f'"{path.resolve()}"', payload["argument_string"])
            self.assertFalse(pdf.exists())
            self.assertFalse(receipt.exists())
            self.assertFalse(status.exists())

    def test_starter_rejects_missing_docx_without_launching_worker(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            missing = Path(folder) / "missing.docx"
            result = subprocess.run(
                [
                    _powershell(),
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(STARTER),
                    "-DocxPath",
                    str(missing),
                    "-PlanOnly",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=20,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("DOCX does not exist", result.stderr)

    def test_worker_preserves_original_until_complete_and_never_accepts_revisions(self) -> None:
        source = WORKER.read_text(encoding="utf-8")
        self.assertIn("Publish-AtomicJson", source)
        self.assertIn("Publish-AtomicFile -Source $tempDocx", source)
        self.assertIn("Copy-Item -LiteralPath $docxFull -Destination $tempDocx", source)
        self.assertNotIn("AcceptAllRevisions", source)

    def test_atomic_replacement_uses_a_real_same_volume_backup_path(self) -> None:
        source = WORKER.read_text(encoding="utf-8")
        self.assertNotIn("[System.IO.File]::Replace($tmp, $Path, $null)", source)
        self.assertNotIn(
            "[System.IO.File]::Replace($Source, $Destination, $null)", source
        )
        self.assertIn(
            "[System.IO.File]::Replace($tmp, $Path, $backup, $true)", source
        )
        self.assertIn(
            "[System.IO.File]::Replace($Source, $Destination, $backup, $true)",
            source,
        )
        self.assertIn("$Path + '.bak.'", source)
        self.assertIn("$Destination + '.bak.'", source)

    def test_pdf_export_uses_a_fresh_powershell_com_apartment(self) -> None:
        source = WORKER.read_text(encoding="utf-8")
        pdf_source = PDF_WORKER.read_text(encoding="utf-8")
        self.assertIn("export_word_docx_to_pdf.ps1", source)
        self.assertIn("& powershell.exe -NoProfile -ExecutionPolicy Bypass", source)
        self.assertIn("[GC]::WaitForPendingFinalizers()", source)
        self.assertIn("[void]$document.SaveAs2($pdfFull, 17)", pdf_source)
        self.assertIn("$word.Documents.Open($docxFull, $false, $true, $false)", pdf_source)
        self.assertNotIn("$document.ExportAsFixedFormat(", source)
        self.assertNotIn("$document.ExportAsFixedFormat(", pdf_source)
        self.assertIn("isolated process", pdf_source)


if __name__ == "__main__":
    unittest.main()
