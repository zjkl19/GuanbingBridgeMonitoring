from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO_ROOT / "scripts" / "build_workbench_exe.ps1"
PACKAGE_SCRIPT = REPO_ROOT / "scripts" / "package_workbench_github_release.ps1"
RUNTIME_PACKAGE_SCRIPT = REPO_ROOT / "scripts" / "package_runtime_update.ps1"
HEALTH_SCRIPT = REPO_ROOT / "scripts" / "run_release_health_check.ps1"
REPORT_BUILD_SCRIPT = REPO_ROOT / "reporting" / "build_gui_exe.ps1"
REPORT_PACKAGE_SCRIPT = REPO_ROOT / "scripts" / "package_report_builder.ps1"
MATLAB_GUI = REPO_ROOT / "ui" / "run_gui.m"


class WorkbenchBuildScriptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.build_script = BUILD_SCRIPT.read_text(encoding="utf-8-sig")
        cls.package_script = PACKAGE_SCRIPT.read_text(encoding="utf-8-sig")
        cls.runtime_package_script = RUNTIME_PACKAGE_SCRIPT.read_text(encoding="utf-8-sig")
        cls.health_script = HEALTH_SCRIPT.read_text(encoding="utf-8-sig")
        cls.matlab_gui = MATLAB_GUI.read_text(encoding="utf-8-sig")

    def test_all_direct_python_steps_use_fail_fast_wrapper(self) -> None:
        self.assertIn("function Invoke-NativeChecked", self.build_script)
        self.assertRegex(
            self.build_script,
            r"\$exitCode\s*=\s*\$LASTEXITCODE\s*"
            r"if \(\$exitCode -ne 0\)\s*\{\s*"
            r'throw "\$StepName failed with exit code \$exitCode"',
        )

        # The only direct native invocation belongs inside the checked wrapper;
        # each build/validation subprocess must call that wrapper instead.
        direct_python_invocations = re.findall(r"(?m)^\s*&\s+\$PythonExe\b", self.build_script)
        self.assertEqual([], direct_python_invocations)
        for step_name in (
            "Workbench Python dependency installation",
            "Workbench Python dependency import check",
            "PyInstaller workbench build",
            "Workbench asset copy",
            "Compiled automatic-cleaning preview contract smoke",
            "Frozen all-profile matrix",
        ):
            self.assertIn(f'-StepName "{step_name}"', self.build_script)

    def test_stale_pyinstaller_output_is_removed_before_build(self) -> None:
        generated_assignment = self.build_script.index(
            '$generatedRoot = Join-Path $distParent $bundleName'
        )
        stale_output_removal = self.build_script.index(
            "Remove-Item -LiteralPath $generatedRoot -Recurse -Force"
        )
        pyinstaller_step = self.build_script.index(
            '-StepName "PyInstaller workbench build"'
        )
        output_existence_gate = self.build_script.index(
            "PyInstaller output directory was not produced"
        )
        self.assertLess(generated_assignment, stale_output_removal)
        self.assertLess(stale_output_removal, pyinstaller_step)
        self.assertLess(pyinstaller_step, output_existence_gate)

    def test_release_health_prefers_the_project_python_runtime(self) -> None:
        self.assertIn(
            '$projectPython = Join-Path $repo "reporting\\.venv\\Scripts\\python.exe"',
            self.health_script,
        )
        self.assertGreaterEqual(
            self.health_script.count('-FilePath $projectPython'),
            3,
        )
        self.assertNotIn('-FilePath "python"', self.health_script)

    def test_native_wrapper_rejects_nonzero_exit_code(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")

        helper_start = self.build_script.index("function Invoke-NativeChecked")
        helper_end = self.build_script.index(
            "\nif (-not (Test-Path -LiteralPath $PythonExe", helper_start
        )
        helper_source = self.build_script[helper_start:helper_end]
        fault_injection = f"""\
$ErrorActionPreference = "Stop"
{helper_source}
try {{
    Invoke-NativeChecked `
        -FilePath $env:ComSpec `
        -ArgumentList @("/d", "/c", "exit 23") `
        -StepName "Injected native failure"
    exit 91
}}
catch {{
    if ($_.Exception.Message -ne "Injected native failure failed with exit code 23") {{
        Write-Error $_.Exception.Message
        exit 92
    }}
}}
exit 0
"""
        with tempfile.TemporaryDirectory() as temporary_directory:
            script_path = Path(temporary_directory) / "native_fail_fast.ps1"
            script_path.write_text(fault_injection, encoding="utf-8")
            completed = subprocess.run(
                [
                    powershell,
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(script_path),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )
        self.assertEqual(
            0,
            completed.returncode,
            msg=f"stdout={completed.stdout}\nstderr={completed.stderr}",
        )

    def test_release_package_requires_rc2_report_compatibility_gates(self) -> None:
        self.assertRegex(
            self.package_script,
            r"-or -not \$manifest\.includes_report_builder\s*`",
        )
        self.assertRegex(
            self.package_script,
            r"-or -not \$manifest\.report_builder_context_smoke\s*`",
        )

    def test_release_package_uses_versioned_release_notes(self) -> None:
        self.assertIn(
            '$releaseNotesPath = Join-Path $repo ("docs\\releases\\{0}.md" -f $Version)',
            self.package_script,
        )
        self.assertIn("Release notes are missing", self.package_script)
        self.assertIn("release_notes = $releaseNotesPath", self.package_script)
        self.assertIn('--notes-file `"$releaseNotesPath`"', self.package_script)
        self.assertNotIn("--notes-file RELEASE_NOTES.md", self.package_script)

    def test_release_gates_come_from_real_embedded_report_smoke(self) -> None:
        self.assertIn(
            "-or -not $reportRuntimeSmoke.embedded_report_job",
            self.build_script,
        )
        self.assertIn(
            "embedded_report_job_smoke = [bool]$reportRuntimeSmoke.embedded_report_job",
            self.build_script,
        )
        self.assertIn(
            "report_gate_contract_smoke = [bool]$reportRuntimeSmoke.report_gate_contract",
            self.build_script,
        )
        self.assertIn(
            "report_visual_qc_smoke = [bool]$reportRuntimeSmoke.visual_qc_contract",
            self.build_script,
        )

    def test_retired_report_builder_cannot_reenter_workbench_packages(self) -> None:
        for script in (self.build_script, self.package_script):
            self.assertIn("BridgeReportBuilder.exe", script)
            self.assertIn("MonthlyReportBuilder.exe", script)
            self.assertIn("report_gui", script)
            self.assertIn("retired standalone report entrypoints", script)
        self.assertIn("ZipFile]::OpenRead", self.package_script)
        self.assertIn(".FullName.Replace('\\', '/')", self.package_script)
        self.assertIn("standalone report builder has retired", self.runtime_package_script)
        self.assertIn('$excludeDirNames += "dist"', self.runtime_package_script)
        self.assertIn('$_.Name -ieq "MonthlyReportBuilder.exe"', self.runtime_package_script)
        self.assertIn('$_.Name -ieq "report_gui.py"', self.runtime_package_script)
        self.assertFalse(REPORT_BUILD_SCRIPT.exists())
        self.assertFalse(REPORT_PACKAGE_SCRIPT.exists())
        self.assertNotIn("open_report_builder", self.matlab_gui)
        self.assertNotIn("BridgeReportBuilder.exe", self.matlab_gui)
        self.assertNotIn("report_gui.py", self.matlab_gui)
        self.assertIn("报告已迁移到统一工作台", self.matlab_gui)

    def test_frozen_package_uses_operator_guide_instead_of_developer_readme(self) -> None:
        self.assertIn('docs\\OPERATOR_GUIDE.md', self.build_script)
        self.assertIn('$operatorGuideName = (-join (20351, 29992, 35828, 26126', self.build_script)
        self.assertIn('Join-Path $distRoot $operatorGuideName', self.build_script)
        self.assertNotIn('使用说明.md', self.build_script)
        self.assertNotIn(
            'Join-Path $repo "README.md") -Destination (Join-Path $distRoot "README.md")',
            self.build_script,
        )

    def test_operator_guide_name_is_ascii_safe_for_windows_powershell(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        assignment = re.search(
            r"(?m)^\$operatorGuideName\s*=.*$",
            self.build_script,
        )
        self.assertIsNotNone(assignment)
        completed = subprocess.run(
            [
                powershell,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                f"{assignment.group(0)}; [Console]::OutputEncoding = "
                "[System.Text.UTF8Encoding]::new($false); Write-Output $operatorGuideName",
            ],
            check=False,
            capture_output=True,
            encoding="utf-8",
            timeout=30,
        )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        self.assertEqual("使用说明.md", completed.stdout.strip())

    def test_frozen_package_copies_and_audits_layered_config_dependencies(self) -> None:
        self.assertIn("from workbench.config_layers import load_layered_config", self.build_script)
        self.assertIn("_config, dependencies = load_layered_config", self.build_script)
        self.assertIn("Packaged config dependency must stay inside the project", self.build_script)


if __name__ == "__main__":
    unittest.main()
