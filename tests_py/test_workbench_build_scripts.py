from __future__ import annotations

import importlib.util
import json
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


REPO_ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = REPO_ROOT / "scripts" / "build_workbench_exe.ps1"
PACKAGE_SCRIPT = REPO_ROOT / "scripts" / "package_workbench_github_release.ps1"
RUNTIME_PACKAGE_SCRIPT = REPO_ROOT / "scripts" / "package_runtime_update.ps1"
HEALTH_SCRIPT = REPO_ROOT / "scripts" / "run_release_health_check.ps1"
FAILURE_EXIT_SCRIPT = REPO_ROOT / "scripts" / "validate_analysis_runner_failure_exit.py"
CLEANUP_POLICY_SCRIPT = (
    REPO_ROOT / "scripts" / "validate_analysis_runner_cache_cleanup_policy.py"
)
CAPTURE_SCRIPT = REPO_ROOT / "scripts" / "capture_workbench_window.ps1"
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
        cls.capture_script = CAPTURE_SCRIPT.read_text(encoding="utf-8-sig")
        cls.matlab_gui = MATLAB_GUI.read_text(encoding="utf-8-sig")

    @staticmethod
    def _failure_exit_module():
        spec = importlib.util.spec_from_file_location(
            "validate_analysis_runner_failure_exit", FAILURE_EXIT_SCRIPT
        )
        if spec is None or spec.loader is None:
            raise RuntimeError(f"unable to load {FAILURE_EXIT_SCRIPT}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    @staticmethod
    def _cleanup_policy_module():
        spec = importlib.util.spec_from_file_location(
            "validate_analysis_runner_cache_cleanup_policy", CLEANUP_POLICY_SCRIPT
        )
        if spec is None or spec.loader is None:
            raise RuntimeError(f"unable to load {CLEANUP_POLICY_SCRIPT}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

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
            "Compiled analysis failure-exit contract smoke",
            "Compiled analysis cache-cleanup policy smoke",
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
        self.assertIn('"includes_report_builder"', self.package_script)
        self.assertIn('"report_builder_context_smoke"', self.package_script)
        self.assertIn("Assert-ExactBoolean $property.Value $true", self.package_script)

    def test_build_and_package_gate_compiled_analysis_failure_exit(self) -> None:
        self.assertIn(
            'scripts\\validate_analysis_runner_failure_exit.py', self.build_script
        )
        self.assertIn(
            "analysis_runner_failure_exit_smoke = $analysisRunnerFailureExitSmoke",
            self.build_script,
        )
        self.assertIn('"analysis_runner_failure_exit_smoke"', self.package_script)
        runner_check = self.build_script.index("Analysis runner is missing")
        failure_exit_gate = self.build_script.index(
            '-StepName "Compiled analysis failure-exit contract smoke"'
        )
        runner_copy = self.build_script.index(
            '$runnerTarget = Join-Path $distRoot "bin\\BridgeAnalysisRunner"'
        )
        self.assertLess(runner_check, failure_exit_gate)
        self.assertLess(failure_exit_gate, runner_copy)

    def test_build_and_package_gate_compiled_analysis_cache_cleanup_policy(self) -> None:
        self.assertIn(
            "validate_analysis_runner_cache_cleanup_policy.py", self.build_script
        )
        self.assertIn(
            "analysis_runner_cache_cleanup_policy_smoke = $analysisRunnerCacheCleanupPolicySmoke",
            self.build_script,
        )
        self.assertIn(
            '"analysis_runner_cache_cleanup_policy_smoke"', self.package_script
        )
        self.assertIn("configured_csv_deleted", self.build_script)
        self.assertIn("unconfigured_csv_preserved", self.build_script)
        self.assertIn("enabled_cleanup_dated_folders", self.build_script)
        self.assertIn("enabled_cleanup_hongtang_period", self.build_script)
        self.assertIn("source_archives_preserved", self.build_script)
        self.assertIn("workbook_and_wim_preserved", self.build_script)
        self.assertIn("BMS:CacheSourceCleanup:DedicatedTaskRequired", self.package_script)
        cleanup_gate = self.build_script.index(
            '-StepName "Compiled analysis cache-cleanup policy smoke"'
        )
        runner_copy = self.build_script.index(
            '$runnerTarget = Join-Path $distRoot "bin\\BridgeAnalysisRunner"'
        )
        self.assertLess(cleanup_gate, runner_copy)

    def test_cleanup_policy_smoke_replace_is_marker_bounded(self) -> None:
        module = self._cleanup_policy_module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            marked = root / "marked"
            module._prepare_output_root(marked, replace=False)
            marker = marked / ".cache_cleanup_policy_smoke_root.json"
            self.assertTrue(marker.is_file())
            (marked / "evidence.txt").write_text("old", encoding="utf-8")
            module._prepare_output_root(marked, replace=True)
            self.assertTrue(marker.is_file())
            self.assertFalse((marked / "evidence.txt").exists())

            unmarked = root / "unmarked"
            unmarked.mkdir()
            (unmarked / "user-data.txt").write_text("preserve", encoding="utf-8")
            with self.assertRaises(RuntimeError):
                module._prepare_output_root(unmarked, replace=True)
            self.assertEqual(
                (unmarked / "user-data.txt").read_text(encoding="utf-8"),
                "preserve",
            )

    def test_cleanup_policy_smoke_retries_only_transient_permission_error(self) -> None:
        module = self._cleanup_policy_module()
        output_root = Path("C:/marked-smoke")
        with (
            patch.object(
                module.shutil,
                "rmtree",
                side_effect=[PermissionError("busy"), None],
            ) as remove,
            patch.object(module.time, "sleep") as sleep,
        ):
            module._remove_marked_output_root(
                output_root,
                attempts=2,
                delay_seconds=0.01,
            )
        self.assertEqual(remove.call_count, 2)
        sleep.assert_called_once_with(0.01)

        with (
            patch.object(module.shutil, "rmtree", side_effect=OSError("fatal")),
            patch.object(module.time, "sleep") as sleep,
        ):
            with self.assertRaisesRegex(OSError, "fatal"):
                module._remove_marked_output_root(output_root, attempts=3)
        sleep.assert_not_called()

    def test_cleanup_policy_smoke_resolves_summary_from_manifest_artifact(self) -> None:
        module = self._cleanup_policy_module()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            manifest = root / "analysis_manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            summary = root / "cache_summary.json"
            summary.write_text("{}", encoding="utf-8")
            record = {
                "stats_path": "",
                "artifacts": {
                    "kind": "manifest",
                    "path": summary.name,
                    "role": "cache_prebuild_summary",
                },
            }
            self.assertEqual(
                module._record_artifact_path(
                    record,
                    manifest,
                    role="cache_prebuild_summary",
                ),
                summary,
            )

            record["artifacts"] = []
            with self.assertRaisesRegex(RuntimeError, "expected one module artifact"):
                module._record_artifact_path(
                    record,
                    manifest,
                    role="cache_prebuild_summary",
                )

    def test_build_and_package_gate_current_operator_features(self) -> None:
        self.assertIn("$smoke.config_tab_count -eq 9", self.build_script)
        for field in (
            "manual_threshold_controls_available",
            "threshold_band_control_available",
            "lower_box_threshold_control_available",
            "upper_box_threshold_control_available",
            "offset_effective_range_seconds_available",
            "gap_override_column_count",
            "unzip_settings_available",
            "analysis_result_location_visible",
            "analysis_result_open_control_available",
            "threshold_preview_auto_locator_available",
            "cache_source_cleanup_control_available",
            "cache_source_cleanup_default_off",
            "cache_source_cleanup_confirmation_empty",
            "cache_source_cleanup_confirmation_required",
            "cache_source_cleanup_task_option_present",
            "cache_source_cleanup_supported_data_layout",
            "cache_source_cleanup_supported_data_layouts",
        ):
            self.assertIn(field, self.build_script)
            self.assertIn(field, self.package_script)
        self.assertIn("operator_feature_contract_smoke", self.build_script)
        self.assertIn("operator_feature_contract_smoke", self.package_script)
        self.assertIn("operator_feature_contract_version = 4", self.build_script)
        self.assertIn(
            '"manifest.operator_feature_contract_version" 1) -lt 4',
            self.package_script,
        )
        self.assertIn("cache_source_cleanup_contract_smoke", self.build_script)
        self.assertIn("cache_source_cleanup_contract_smoke", self.package_script)
        self.assertIn("workbench_cache_source_cleanup.png", self.build_script)
        self.assertIn("[switch]$DemoCacheSourceCleanup", self.capture_script)
        self.assertIn('--demo-cache-source-cleanup', self.capture_script)
        self.assertIn("workbench_unzip_settings.png", self.build_script)
        self.assertIn("reporting\\requirements-build.txt", self.build_script)

    def test_offscreen_audit_build_never_impersonates_native_screenshot_gate(self) -> None:
        self.assertIn("[switch]$OffscreenScreenshots", self.build_script)
        self.assertIn("$captureMode.Offscreen = $true", self.build_script)
        self.assertIn('screenshot_mode = if ($OffscreenScreenshots)', self.build_script)
        self.assertIn("native_screenshot_smoke = -not $OffscreenScreenshots", self.build_script)
        self.assertIn("native_focus_smoke = -not $OffscreenScreenshots", self.build_script)
        self.assertIn("native_dpi_smoke = -not $OffscreenScreenshots", self.build_script)
        self.assertIn('"native_screenshot_smoke"', self.package_script)
        self.assertIn('"native_focus_smoke"', self.package_script)
        self.assertIn('"native_dpi_smoke"', self.package_script)
        self.assertIn('"native_font_smoke"', self.package_script)
        self.assertIn('"native_icon_smoke"', self.package_script)
        self.assertIn("native_gui_acceptance", self.package_script)
        self.assertIn('Get-StrictString $manifest.screenshot_mode', self.package_script)

    def test_native_capture_requires_foreground_focus_and_real_dpi(self) -> None:
        for contract in (
            "GetForegroundWindow",
            "GetGUIThreadInfo",
            "AttachThreadInput",
            "SetFocus",
            "Workbench did not become the native foreground window",
            "Workbench did not receive native keyboard focus",
            "GetDpiForWindow",
            "Unexpected native workbench DPI",
            "GetWindowDpiAwarenessContext",
            "Workbench is not per-monitor DPI aware",
            "Workbench native window icon is missing",
            "EvidencePath",
        ):
            self.assertIn(contract, self.capture_script)
        self.assertIn("$bitmap = $null", self.capture_script)
        self.assertIn("if (-not $process.HasExited)", self.capture_script)
        self.assertIn("$process.CloseMainWindow()", self.capture_script)
        self.assertIn("[switch]$Offscreen", self.capture_script)
        self.assertIn('$env:QT_QPA_PLATFORM = "offscreen"', self.capture_script)
        self.assertIn("Remove-Item Env:QT_QPA_PLATFORM", self.capture_script)
        self.assertIn("$totalSamples * 0.20", self.capture_script)
        self.assertIn("$totalSamples * 0.10", self.capture_script)
        self.assertIn("$denseTotalSamples * 0.03", self.capture_script)

    def test_release_package_revalidates_every_dist_file_before_compression(self) -> None:
        for marker in (
            "$expectedInventory = @($manifest.file_inventory)",
            "Get-FileHash -LiteralPath $path -Algorithm SHA256",
            "Workbench manifest file changed before packaging",
            "$actualFiles.Count -ne $manifestFileCount",
            "$expectedTotalBytes -ne $manifestTotalBytes",
            "Workbench dist inventory is not closed immediately before packaging",
            "Release archive entry failed size/SHA verification",
            "BridgeMonitoringWorkbench/release_manifest.json",
            "Publish-VerifiedFileSet",
        ):
            self.assertIn(marker, self.package_script)
        inventory_gate = self.package_script.index("$expectedInventory =")
        compression = self.package_script.index("$zip.CreateEntry")
        self.assertLess(inventory_gate, compression)

    def test_build_and_package_inventory_include_hidden_files_and_reject_reparse_points(self) -> None:
        for script in (self.build_script, self.package_script):
            self.assertIn("Get-ChildItem -LiteralPath $distRoot -Recurse -Force", script)
            self.assertIn("[System.IO.FileAttributes]::ReparsePoint", script)
            self.assertIn("distribution contains reparse points", script)

    def test_release_package_requires_all_version_records_to_match(self) -> None:
        self.assertIn("$distVersion -ne $Version", self.package_script)
        self.assertIn('Get-StrictString $manifest.smoke.version "manifest.smoke.version"', self.package_script)
        self.assertIn('Get-StrictString $smokeResult.version "smoke.version"', self.package_script)

    def test_build_and_release_are_bound_to_a_git_source_commit(self) -> None:
        for script in (self.build_script, self.package_script):
            self.assertIn("function Get-GitSourceState", script)
            self.assertIn("rev-parse --verify HEAD", script)
            self.assertIn("status --porcelain=v1 --untracked-files=all", script)
            self.assertIn("source_git_commit", script)
            self.assertIn("source_tree_clean", script)
        self.assertIn(
            "The source Git commit changed during the workbench build",
            self.build_script,
        )
        self.assertIn(
            "Stable releases require a clean Git working tree",
            self.package_script,
        )
        self.assertIn(
            "Release manifest source commit differs from the current Git HEAD",
            self.package_script,
        )

    def test_failure_exit_validator_checks_durable_failed_manifest(self) -> None:
        module = self._failure_exit_module()
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            manifest_path = root / "analysis_manifest.json"
            status_path = root / "analysis_status.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "status": "failed",
                        "module_results": [
                            {"key": "unzip", "status": "fail", "message": "NoArchives"}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            status_path.write_text(
                json.dumps({"status": "failed", "manifest_path": str(manifest_path)}),
                encoding="utf-8",
            )

            result = module.validate_failure_contract(status_path, 1)
            self.assertTrue(result["ok"])
            self.assertEqual("unzip", result["failed_module_key"])
            self.assertEqual("fail", result["failed_module_status"])
            with self.assertRaisesRegex(RuntimeError, "exit code 0"):
                module.validate_failure_contract(status_path, 0)

    def test_failure_exit_request_is_empty_jiulongjiang_unzip_run(self) -> None:
        module = self._failure_exit_module()
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            data_root = root / "empty_data"
            status_path = root / "analysis_status.json"
            request = module._failure_request(REPO_ROOT, data_root, status_path)

        self.assertEqual("jiulongjiang", request["config"]["vendor"])
        self.assertEqual({"doUnzip": True}, request["options"])
        self.assertEqual(str(data_root), request["data_root"])
        self.assertEqual(str(status_path), request["async_status_file"])
        summary_file = request["config"]["preprocessing"]["unzip"]["summary_file"]
        self.assertTrue(Path(summary_file).is_absolute())

    def test_release_package_uses_versioned_release_notes(self) -> None:
        self.assertIn(
            '$releaseNotesPath = Join-Path $repo ("docs\\releases\\{0}.md" -f $Version)',
            self.package_script,
        )
        self.assertIn("Release notes are missing", self.package_script)
        self.assertIn("release_notes = $releaseNotesPath", self.package_script)
        self.assertIn('--notes-file `"$releaseNotesPath`"', self.package_script)
        self.assertNotIn("--notes-file RELEASE_NOTES.md", self.package_script)

    def test_current_release_notes_are_utf8_and_free_of_known_mojibake(self) -> None:
        version = (REPO_ROOT / "VERSION").read_text(encoding="utf-8-sig").strip()
        release_notes = REPO_ROOT / "docs" / "releases" / f"{version}.md"
        text = release_notes.read_text(encoding="utf-8-sig")

        self.assertIn("DELETE_VERIFIED_EXTRACTED_CSV", text)
        self.assertIn("unconfigured CSVs", text)
        for marker in ("鈥滈", "缂撳瓨", "锟斤拷", "ï»¿"):
            self.assertNotIn(marker, text)

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
        self.assertIn("ZipArchive]::new", self.package_script)
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
        self.assertIn('$packagedOperatorGuide = Join-Path $distRoot $operatorGuideName', self.build_script)
        self.assertNotIn('使用说明.md', self.build_script)
        self.assertNotIn(
            'Join-Path $repo "README.md") -Destination (Join-Path $distRoot "README.md")',
            self.build_script,
        )

    def test_build_validates_operator_guide_before_and_after_copy(self) -> None:
        source_assignment = self.build_script.index(
            '$operatorGuideSource = Join-Path $repo "docs\\OPERATOR_GUIDE.md"'
        )
        source_gate = self.build_script.index(
            "Assert-OperatorGuideContract -Path $operatorGuideSource"
        )
        copy_step = self.build_script.index(
            "Copy-Item -LiteralPath $operatorGuideSource -Destination $packagedOperatorGuide"
        )
        packaged_gate = self.build_script.index(
            "Assert-OperatorGuideContract -Path $packagedOperatorGuide"
        )
        self.assertLess(source_assignment, source_gate)
        self.assertLess(source_gate, copy_step)
        self.assertLess(copy_step, packaged_gate)
        self.assertIn(
            "39044, 29983, 25104, 20998, 26512, 32531, 23384",
            self.build_script,
        )
        self.assertIn(
            "25171, 24320, 26354, 32447, 39044, 35272, 24182, 25302, 32447, 35774, 32622",
            self.build_script,
        )
        self.assertIn("function Assert-OperatorGuideContract", self.package_script)
        self.assertIn(
            "Assert-OperatorGuideContract -Path (Join-Path $distRoot $operatorGuideName)",
            self.package_script,
        )
        package_gate = self.package_script.index(
            "Assert-OperatorGuideContract -Path (Join-Path $distRoot $operatorGuideName)"
        )
        compression = self.package_script.index("$zip.CreateEntry")
        self.assertLess(package_gate, compression)
        for fragment_code_points in (
            "39044, 29983, 25104, 20998, 26512, 32531, 23384",
            "25171, 24320, 26354, 32447, 39044, 35272, 24182, 25302, 32447, 35774, 32622",
            "25302, 32447, 35774, 32622, 19978, 19979, 38480",
            "19979, 20391, 26694, 36873, 21462, 26694, 20013, 23454, 38469, 26377, 38480, 26679, 26412, 30340, 26368, 39640, 20540",
            "19978, 20391, 26694, 36873, 21462, 26694, 20013, 23454, 38469, 26377, 38480, 26679, 26412, 30340, 26368, 20302, 20540",
            "31561, 20110, 20505, 36873, 38408, 20540, 30340, 28857, 20445, 30041",
            "39640, 39118, 38505, 12289, 40664, 35748, 20851, 38381",
            "21482, 20445, 23384, 22312, 24403, 21069, 20219, 21153, 26041, 26696, 20013",
            "19981, 20889, 20837, 26725, 26753, 20844, 20849, 37197, 32622",
            "26412, 27425, 35745, 31639, 32467, 26524, 22312, 21738, 37324",
            "33258, 21160, 21305, 37197, 24403, 21069, 20219, 21153, 26354, 32447, 39044, 35272",
            "26222, 36890, 27969, 31243, 26080, 38656, 36873, 25321, 20219, 20309, 25991, 20214",
            "20174, 20854, 20182, 20219, 21153, 47, 39033, 30446, 23548, 20837, 21442, 32771, 26354, 32447",
        ):
            self.assertIn(fragment_code_points, self.package_script)

    def test_operator_guide_contract_accepts_full_caption_and_rejects_missing_workflows(self) -> None:
        powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if powershell is None:
            self.skipTest("Windows PowerShell is unavailable")

        cache_caption = "\u9884\u751f\u6210\u5206\u6790\u7f13\u5b58"
        threshold_caption_stem = "\u6253\u5f00\u66f2\u7ebf\u9884\u89c8\u5e76\u62d6\u7ebf\u8bbe\u7f6e"
        required_fragments = (
            cache_caption,
            threshold_caption_stem,
            "拖线设置上下限",
            "下侧框选取框中实际有限样本的最高值",
            "上侧框选取框中实际有限样本的最低值",
            "删除严格低于该值的数据",
            "删除严格高于该值的数据",
            "等于候选阈值的点保留",
            "高风险、默认关闭",
            "只保存在当前任务方案中",
            "不写入桥梁公共配置",
            "本次计算结果在哪里",
            "自动匹配当前任务曲线预览",
            "普通流程无需选择任何文件",
            "从其他任务/项目导入参考曲线",
            "stats",
            "run_logs",
            "DOCX/PDF",
            "jlj_daily_export",
            "DELETE_VERIFIED_EXTRACTED_CSV",
        )

        helper_sources = {}
        for script_name, script_text, next_marker in (
            (
                "build",
                self.build_script,
                "\nif (-not (Test-Path -LiteralPath $PythonExe",
            ),
            (
                "package",
                self.package_script,
                "\nfunction Get-NormalizedSha256",
            ),
        ):
            helper_start = script_text.index("function Assert-OperatorGuideContract")
            helper_end = script_text.index(next_marker, helper_start)
            helper_sources[script_name] = script_text[helper_start:helper_end]

        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            cases = {
                "complete": (
                    "# Guide\n" + "\n".join(required_fragments) + "\n",
                    True,
                ),
            }
            cases.update(
                {
                    f"missing_{index}": "# Guide\n"
                    + "\n".join(
                        fragment
                        for candidate_index, fragment in enumerate(required_fragments)
                        if candidate_index != index
                    )
                    for index in range(len(required_fragments))
                }
            )
            for script_name, helper_source in helper_sources.items():
                for name, payload in cases.items():
                    if isinstance(payload, tuple):
                        content, should_pass = payload
                    else:
                        content, should_pass = payload, False
                    guide_path = root / f"{script_name}_{name}.md"
                    guide_path.write_text(content, encoding="utf-8")
                    script_path = root / f"validate_{script_name}_{name}.ps1"
                    escaped_path = str(guide_path).replace("'", "''")
                    script_path.write_text(
                        "$ErrorActionPreference = 'Stop'\n"
                        f"{helper_source}\n"
                        f"Assert-OperatorGuideContract -Path '{escaped_path}'\n",
                        encoding="utf-8",
                    )
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
                    if should_pass:
                        self.assertEqual(
                            0,
                            completed.returncode,
                            msg=f"stdout={completed.stdout}\nstderr={completed.stderr}",
                        )
                    else:
                        self.assertNotEqual(0, completed.returncode)
                        self.assertIn(
                            "missing required user workflow text",
                            completed.stderr,
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
