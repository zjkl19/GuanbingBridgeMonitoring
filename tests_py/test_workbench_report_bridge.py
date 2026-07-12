from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from workbench.report_bridge import report_gui_command


class WorkbenchReportBridgeTests(unittest.TestCase):
    def test_development_runtime_prefers_current_venv_over_stale_packaged_exe(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            reporting = root / "reporting"
            script = reporting / "report_gui.py"
            python = reporting / ".venv" / "Scripts" / "python.exe"
            packaged = reporting / "dist" / "BridgeReportBuilder" / "BridgeReportBuilder.exe"
            for path in (script, python, packaged):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"fake")
            context = root / "job_context.json"
            command = report_gui_command(root, context)
            self.assertEqual(command[0], str(python))
            self.assertEqual(command[1], str(script))
            self.assertEqual(command[-2:], ("--job-context", str(context)))

    def test_frozen_runtime_accepts_packaged_report_builder_without_source_script(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            packaged = root / "reporting" / "dist" / "BridgeReportBuilder" / "BridgeReportBuilder.exe"
            packaged.parent.mkdir(parents=True)
            packaged.write_bytes(b"fake")
            context = root / "job_context.json"
            with patch("workbench.report_bridge.sys.frozen", True, create=True):
                command = report_gui_command(root, context)
            self.assertEqual(command, (str(packaged), "--job-context", str(context)))


if __name__ == "__main__":
    unittest.main()
