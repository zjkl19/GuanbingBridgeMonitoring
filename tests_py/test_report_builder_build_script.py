from __future__ import annotations

import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO_ROOT / "reporting" / "build_gui_exe.ps1"


class ReportBuilderBuildScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.script = BUILD_SCRIPT.read_text(encoding="utf-8-sig")

    def test_all_external_build_steps_are_exit_code_gated(self) -> None:
        self.assertIn("$exitCode = $LASTEXITCODE", self.script)
        self.assertRegex(self.script, r"if \(\$exitCode -ne 0\)\s*\{\s*throw")

        checked_steps = re.findall(
            r"Invoke-NativeBuildStep\s+`\s*"
            r'-StepName\s+"([^"]+)"\s+`\s*'
            r"-Executable\s+\$PythonExe\s+`\s*"
            r"-Arguments\s+@(\([\s\S]*?\))",
            self.script,
        )
        self.assertEqual(3, len(checked_steps))
        arguments = "\n".join(argument_text for _, argument_text in checked_steps)
        self.assertIn('"pip", "install", "pyinstaller"', arguments)
        self.assertIn('"pip", "install", "-r", "reporting\\requirements.txt"', arguments)
        self.assertIn('"-m", "PyInstaller"', arguments)

        # Keep the existing gate for the template/asset copy subprocess too.
        self.assertRegex(
            self.script,
            r"& \$PythonExe \$copyReportsScriptPath \| Out-Host\s*"
            r"if \(\$LASTEXITCODE -ne 0\)",
        )

    def test_named_mutex_guards_shared_build_directories(self) -> None:
        self.assertIn('"reporting\\dist"', self.script)
        self.assertIn('"reporting\\build"', self.script)
        self.assertIn('"Global\\Guanbing_BridgeReportBuilder_Build_$lockDigest"', self.script)
        self.assertIn("[System.Threading.Mutex]::new", self.script)
        self.assertIn("$buildMutex.WaitOne(0)", self.script)
        self.assertIn("catch [System.Threading.AbandonedMutexException]", self.script)
        self.assertIn("$buildMutex.ReleaseMutex()", self.script)
        self.assertIn("$buildMutex.Dispose()", self.script)


if __name__ == "__main__":
    unittest.main()
