from __future__ import annotations

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
HEALTH_SCRIPT = REPO_ROOT / "scripts" / "run_release_health_check.ps1"
GUI_TEST = REPO_ROOT / "tests" / "test_main_gui_smoke.m"
RUN_TESTS = REPO_ROOT / "run_tests.m"


class ReleaseHealthMatlabIsolationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.health = HEALTH_SCRIPT.read_text(encoding="utf-8-sig")
        cls.gui_test = GUI_TEST.read_text(encoding="utf-8-sig")
        cls.run_tests = RUN_TESTS.read_text(encoding="utf-8-sig")

    def test_powershell_script_parses(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        escaped_path = str(HEALTH_SCRIPT).replace("'", "''")
        completed = subprocess.run(
            [
                powershell,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-Command",
                "$ErrorActionPreference='Stop'; "
                f"$null=[scriptblock]::Create([IO.File]::ReadAllText('{escaped_path}'))",
            ],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)

    def test_non_gui_and_gui_runs_use_distinct_isolated_prefdirs(self) -> None:
        self.assertIn("function New-IsolatedMatlabPrefDir", self.health)
        self.assertIn("function Invoke-IsolatedExternal", self.health)
        self.assertIn("MATLAB_PREFDIR = $prefDir", self.health)
        self.assertIn('BMS_RELEASE_HEALTH_NON_GUI = $(if ($NonGui)', self.health)
        for role in (
            '"config_lint_nongui"',
            '"full_core_nongui"',
            '"cleanup_contracts_nongui"',
            '"default_nongui"',
            '"gui_smoke"',
        ):
            self.assertIn(role, self.health)
        self.assertIn('Invoke-IsolatedExternal -Name "validate-configs"', self.health)
        self.assertIn("run_tests({'tests/test_main_gui_smoke.m'})", self.health)
        self.assertIn("BMS_RELEASE_HEALTH_NON_GUI", self.gui_test)
        self.assertIn("tc.assumeFalse", self.gui_test)

    def test_external_process_receives_explicit_environment_on_windows_powershell(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        helper_start = self.health.index("function Invoke-Step")
        helper_end = self.health.index('Invoke-Step "Validate configs"', helper_start)
        helper = self.health[helper_start:helper_end]
        escaped_repo = str(REPO_ROOT).replace("'", "''")
        script = (
            "$ErrorActionPreference='Stop'\n"
            f"$repo='{escaped_repo}'\n"
            f"{helper}\n"
            "Invoke-External -Name 'environment-smoke' "
            "-FilePath 'powershell' "
            "-Arguments @('-NoLogo','-NoProfile','-NonInteractive','-Command',"
            "\"if (`$env:BMS_HEALTH_ENV_SMOKE -ne 'ok') { exit 19 }\") "
            "-TimeoutSeconds 30 "
            "-EnvironmentVariables @{BMS_HEALTH_ENV_SMOKE='ok'}\n"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "environment_smoke.ps1"
            path.write_text(script, encoding="utf-8")
            completed = subprocess.run(
                [
                    powershell,
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(path),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=45,
            )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)

    def test_python_compile_uses_an_isolated_cache(self) -> None:
        self.assertIn("PYTHONPYCACHEPREFIX = $pyCache", self.health)
        self.assertIn('"GuanbingReleaseHealth\\pycache_{0}"', self.health)
        self.assertIn("Remove-Item -LiteralPath $pyCache -Recurse -Force", self.health)

    def test_gui_smoke_has_read_only_session_guard_and_no_global_kill(self) -> None:
        self.assertIn("function Get-LiveProcessByExactName", self.health)
        self.assertIn("function Get-MatlabSessionSnapshot", self.health)
        self.assertIn('Get-Process -Name $Name', self.health)
        self.assertIn('Get-LiveProcessByExactName -Name "MATLAB"', self.health)
        self.assertIn('Get-LiveProcessByExactName -Name "MATLABWindow"', self.health)
        self.assertIn('("ProcessId={0}" -f [int]$process.Id)', self.health)
        self.assertIn("exact CIM record is absent", self.health)
        self.assertIn("zero threads and handles", self.health)
        self.assertIn("function Assert-MatlabGuiSessionIsClean", self.health)
        self.assertIn("interactive MATLAB session is open", self.health)
        self.assertIn("pre-existing headless MATLAB/MATLABWindow processes", self.health)
        self.assertIn("No process was terminated", self.health)
        self.assertNotIn("Restart-Service", self.health)
        self.assertNotIn("MathWorksServiceHost | Stop-Process", self.health)
        self.assertNotIn("Get-Process -Name MATLAB | Stop-Process", self.health)

    def test_get_process_ghost_is_filtered_by_exact_cim_liveness_check(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        helper_start = self.health.index("function Get-LiveProcessByExactName")
        helper_end = self.health.index("function Format-MatlabProcessList", helper_start)
        helper = self.health[helper_start:helper_end]
        mock_process = (
            "[pscustomobject]@{Id=424242;SessionId=1;"
            "MainWindowHandle=[IntPtr]::Zero;MainWindowTitle='';HasExited=$true}"
        )
        script = (
            "$ErrorActionPreference='Stop'\n"
            f"function Get-Process {{ param($Name, $ErrorAction); return {mock_process} }}\n"
            "function Get-CimInstance { throw 'CIM must not be queried for HasExited=true' }\n"
            f"{helper}\n"
            "$snapshot=Get-MatlabSessionSnapshot\n"
            "if ($snapshot.interactive.Count -ne 0 -or "
            "$snapshot.background.Count -ne 0 -or $snapshot.matlab_windows.Count -ne 0) { exit 9 }\n"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "ghost_filter.ps1"
            path.write_text(script, encoding="utf-8")
            completed = subprocess.run(
                [
                    powershell,
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(path),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
        )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        self.assertIn("ignored exited MATLAB process-table entry", completed.stdout)

    def test_cim_live_interactive_matlab_is_blocked_without_termination(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        helper_start = self.health.index("function Get-LiveProcessByExactName")
        helper_end = self.health.index("function New-IsolatedMatlabPrefDir", helper_start)
        helper = self.health[helper_start:helper_end]
        mock_process = (
            "[pscustomobject]@{Id=434343;SessionId=1;"
            "MainWindowHandle=[IntPtr]123;MainWindowTitle='MATLAB R2024a';HasExited=$false}"
        )
        script = (
            "$ErrorActionPreference='Stop'\n"
            f"function Get-Process {{ param($Name, $ErrorAction); if ($Name -eq 'MATLAB') {{ return {mock_process} }} }}\n"
            "function Get-CimInstance { param($ClassName, $Filter, $ErrorAction); "
            "return [pscustomobject]@{ProcessId=434343} }\n"
            f"{helper}\n"
            "try { Assert-MatlabGuiSessionIsClean; exit 8 } "
            "catch { if ($_.Exception.Message -notmatch 'interactive MATLAB session is open') { throw }; "
            "Write-Output $_.Exception.Message }\n"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "interactive_block.ps1"
            path.write_text(script, encoding="utf-8")
            completed = subprocess.run(
                [
                    powershell,
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(path),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        self.assertIn("No MATLAB process or MathWorks service was restarted", completed.stdout)

    def test_zero_thread_zero_handle_cim_record_is_ignored_as_terminated(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        helper_start = self.health.index("function Get-LiveProcessByExactName")
        helper_end = self.health.index("function Format-MatlabProcessList", helper_start)
        helper = self.health[helper_start:helper_end]
        mock_process = (
            "[pscustomobject]@{Id=454545;SessionId=1;"
            "MainWindowHandle=[IntPtr]::Zero;MainWindowTitle='';HasExited=$false}"
        )
        script = (
            "$ErrorActionPreference='Stop'\n"
            f"function Get-Process {{ param($Name, $ErrorAction); return {mock_process} }}\n"
            "function Get-CimInstance { param($ClassName, $Filter, $ErrorAction); "
            "return [pscustomobject]@{ProcessId=454545;HandleCount=0;ThreadCount=0} }\n"
            f"{helper}\n"
            "$snapshot=Get-MatlabSessionSnapshot\n"
            "if ($snapshot.interactive.Count -ne 0 -or "
            "$snapshot.background.Count -ne 0 -or $snapshot.matlab_windows.Count -ne 0) { exit 9 }\n"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "terminated_filter.ps1"
            path.write_text(script, encoding="utf-8")
            completed = subprocess.run(
                [
                    powershell,
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(path),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        self.assertIn("ignored terminated MATLAB process-table entry", completed.stdout)

    def test_cim_live_headless_matlab_is_blocked_without_blind_kill(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        helper_start = self.health.index("function Get-LiveProcessByExactName")
        helper_end = self.health.index("function New-IsolatedMatlabPrefDir", helper_start)
        helper = self.health[helper_start:helper_end]
        mock_process = (
            "[pscustomobject]@{Id=444444;SessionId=1;"
            "MainWindowHandle=[IntPtr]::Zero;MainWindowTitle='';HasExited=$false}"
        )
        script = (
            "$ErrorActionPreference='Stop'\n"
            f"function Get-Process {{ param($Name, $ErrorAction); if ($Name -eq 'MATLAB') {{ return {mock_process} }} }}\n"
            "function Get-CimInstance { param($ClassName, $Filter, $ErrorAction); "
            "return [pscustomobject]@{ProcessId=444444} }\n"
            f"{helper}\n"
            "try { Assert-MatlabGuiSessionIsClean; exit 8 } "
            "catch { if ($_.Exception.Message -notmatch 'pre-existing headless MATLAB') { throw }; "
            "Write-Output $_.Exception.Message }\n"
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "headless_block.ps1"
            path.write_text(script, encoding="utf-8")
            completed = subprocess.run(
                [
                    powershell,
                    "-NoLogo",
                    "-NoProfile",
                    "-NonInteractive",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(path),
                ],
                check=False,
                capture_output=True,
                text=True,
                timeout=30,
            )
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        self.assertIn("No process was terminated", completed.stdout)

    def test_matlab_tests_run_before_dedicated_gui_process(self) -> None:
        full_index = self.health.index('Invoke-Step "MATLAB full core tests"')
        cleanup_index = self.health.index(
            'Invoke-Step "MATLAB cleanup contract tests"'
        )
        default_index = self.health.index('Invoke-Step "MATLAB default tests"')
        gui_index = self.health.index('Invoke-Step "MATLAB GUI smoke"', full_index)
        self.assertLess(full_index, cleanup_index)
        self.assertLess(cleanup_index, gui_index)
        self.assertLess(full_index, gui_index)
        self.assertLess(default_index, gui_index)

    def test_full_matlab_uses_two_independent_test_modes(self) -> None:
        self.assertIn('-Role "full_core_nongui"', self.health)
        self.assertIn('-BatchCommand "run_tests(\'all-core\')"', self.health)
        self.assertIn('-Role "cleanup_contracts_nongui"', self.health)
        self.assertIn(
            '-BatchCommand "run_tests(\'cleanup-contracts\')"', self.health
        )
        self.assertEqual(1, self.health.count("run_tests('all-core')"))
        self.assertEqual(1, self.health.count("run_tests('cleanup-contracts')"))

    def test_matlab_modes_partition_discovered_tests_without_file_glob_execution(self) -> None:
        self.assertIn('case "all-core"', self.run_tests)
        self.assertIn("suite = testsuite(fullfile(proj, 'tests'));", self.run_tests)
        self.assertIn("res = run(suite(~isCleanupContract));", self.run_tests)
        self.assertIn('case "cleanup-contracts"', self.run_tests)
        self.assertIn(
            "'test_standard_verified_source_csv_cleanup.m'", self.run_tests
        )
        self.assertIn("'test_verified_source_csv_cleanup.m'", self.run_tests)
        self.assertNotIn("dir(fullfile(proj, 'tests', 'test_*.m'))", self.run_tests)

    def test_abnormal_cleanup_is_scoped_to_started_pid_tree(self) -> None:
        self.assertIn("$ownedProcessId = [int]$proc.Id", self.health)
        self.assertIn("Stop-ProcessTree -ProcessId $ownedProcessId", self.health)
        self.assertIn("exact PID started by", self.health)
        self.assertNotIn("Stop-Process -Name MATLAB", self.health)


if __name__ == "__main__":
    unittest.main()
