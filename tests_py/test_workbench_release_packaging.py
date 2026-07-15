from __future__ import annotations

import copy
import hashlib
import json
import shutil
import subprocess
import tempfile
import time
import unittest
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_SCRIPT = REPO_ROOT / "scripts" / "package_workbench_github_release.ps1"
VERSION = "v1.8.1-rc3"
OPERATOR_GUIDE_NAME = "\u4f7f\u7528\u8bf4\u660e.md"
CACHE_PREBUILD_STEM = "\u9884\u751f\u6210\u5206\u6790\u7f13\u5b58"
THRESHOLD_PREVIEW_STEM = "\u6253\u5f00\u66f2\u7ebf\u9884\u89c8\u5e76\u62d6\u7ebf\u8bbe\u7f6e"


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class WorkbenchReleasePackagingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.powershell = shutil.which("powershell.exe") or shutil.which("powershell")
        if self.powershell is None:
            self.skipTest("Windows PowerShell is unavailable")
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.repo = Path(self.temporary_directory.name)
        (self.repo / "scripts").mkdir(parents=True)
        (self.repo / "docs" / "releases").mkdir(parents=True)
        self.dist = self.repo / "dist" / "BridgeMonitoringWorkbench"
        self.dist.mkdir(parents=True)
        shutil.copy2(PACKAGE_SCRIPT, self.repo / "scripts" / PACKAGE_SCRIPT.name)
        (self.repo / "VERSION").write_text(VERSION, encoding="utf-8")
        (self.repo / "docs" / "releases" / f"{VERSION}.md").write_text(
            "# release fixture\n", encoding="utf-8"
        )
        self.smoke = {
            "ok": True,
            "version": VERSION,
            "config_tab_count": 9,
            "manual_threshold_controls_available": True,
            "offset_effective_range_seconds_available": True,
            "gap_override_column_count": 6,
            "unzip_settings_available": True,
        }
        (self.dist / "workbench_smoke.json").write_text(
            json.dumps(self.smoke, ensure_ascii=False), encoding="utf-8"
        )
        (self.dist / "VERSION").write_text(VERSION, encoding="utf-8")
        (self.dist / "桥梁健康监测工作台.exe").write_bytes(b"fixture-executable")
        (self.dist / "asset.txt").write_text("fixture asset", encoding="utf-8")
        (self.dist / OPERATOR_GUIDE_NAME).write_text(
            f"# Guide\n{CACHE_PREBUILD_STEM}\n"
            f"{THRESHOLD_PREVIEW_STEM}\u9608\u503c\uff08\u53cc\u5411\uff09\n",
            encoding="utf-8",
        )
        self.manifest = self._base_manifest()
        self._write_manifest()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def _base_manifest(self) -> dict:
        inventory = []
        total_bytes = 0
        for path in sorted(self.dist.iterdir(), key=lambda value: value.name.casefold()):
            if path.name == "release_manifest.json":
                continue
            payload = path.read_bytes()
            inventory.append(
                {
                    "path": path.name,
                    "bytes": len(payload),
                    "sha256": hashlib.sha256(payload).hexdigest(),
                }
            )
            total_bytes += len(payload)
        return {
            "schema_version": 3,
            "version": VERSION,
            "executable": "桥梁健康监测工作台.exe",
            "executable_sha256": _sha256(self.dist / "桥梁健康监测工作台.exe"),
            "auto_threshold_preview_runner_smoke": True,
            "analysis_runner_failure_exit_smoke": True,
            "installed_profile_matrix_smoke": True,
            "invalid_cli_smoke": True,
            "task_history_smoke": True,
            "native_screenshot_smoke": True,
            "native_focus_smoke": True,
            "native_dpi_smoke": True,
            "native_font_smoke": True,
            "native_icon_smoke": True,
            "screenshot_mode": "native_windows",
            "native_gui_acceptance": {
                "foreground_window_matches": True,
                "focus_owned_by_process": True,
                "native_window_icon": True,
                "dpi_awareness_code": 2,
                "window_dpi": 120,
                "physical_width": 2018,
                "physical_height": 1122,
            },
            "operator_feature_contract_smoke": True,
            "operator_feature_contract_version": 1,
            "includes_analysis_runner": True,
            "report_runtime": "embedded_headless_worker",
            "standalone_report_builder_included": False,
            "includes_report_builder": True,
            "report_builder_context_smoke": True,
            "embedded_report_runtime_smoke": True,
            "embedded_report_job_smoke": True,
            "report_gate_contract_smoke": True,
            "report_visual_qc_smoke": True,
            "file_inventory_count": len(inventory),
            "file_count_excluding_manifest": len(inventory),
            "total_bytes_excluding_manifest": total_bytes,
            "file_inventory": inventory,
            "smoke": copy.deepcopy(self.smoke),
        }

    def _write_manifest(self) -> None:
        (self.dist / "release_manifest.json").write_text(
            json.dumps(self.manifest, ensure_ascii=False, indent=2), encoding="utf-8-sig"
        )

    def _run(self, output: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                self.powershell,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(self.repo / "scripts" / PACKAGE_SCRIPT.name),
                "-Version",
                VERSION,
                "-OutputDir",
                str(output),
                "-SkipBuild",
                "-AllowDevelopmentVersion",
            ],
            cwd=self.repo,
            check=False,
            capture_output=True,
            encoding="utf-8",
            errors="replace",
            timeout=60,
        )

    def test_valid_fixture_is_packaged_with_exact_file_hashes(self) -> None:
        output = self.repo / "release-output"
        completed = self._run(output)
        self.assertEqual(0, completed.returncode, msg=completed.stderr)
        archive_path = output / f"BridgeMonitoringWorkbench-{VERSION}-win-x64.zip"
        self.assertTrue(archive_path.is_file())

        expected = {
            f"BridgeMonitoringWorkbench/{entry['path']}": (
                entry["bytes"],
                entry["sha256"],
            )
            for entry in self.manifest["file_inventory"]
        }
        manifest_bytes = (self.dist / "release_manifest.json").read_bytes()
        expected["BridgeMonitoringWorkbench/release_manifest.json"] = (
            len(manifest_bytes),
            hashlib.sha256(manifest_bytes).hexdigest(),
        )
        with zipfile.ZipFile(archive_path) as archive:
            self.assertEqual(set(expected), set(archive.namelist()))
            for name, (expected_bytes, expected_hash) in expected.items():
                payload = archive.read(name)
                self.assertEqual(expected_bytes, len(payload), name)
                self.assertEqual(expected_hash, hashlib.sha256(payload).hexdigest(), name)
        self.assertFalse((output / ".workbench_release_package.lock").exists())

    def test_operator_guide_is_required(self) -> None:
        (self.dist / OPERATOR_GUIDE_NAME).unlink()
        completed = self._run(self.repo / "missing-operator-guide")
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("Operator guide not found", completed.stderr)

    def test_operator_guide_requires_each_workflow_stem(self) -> None:
        cases = (
            ("missing-cache", f"# Guide\n{THRESHOLD_PREVIEW_STEM}\u9608\u503c\n"),
            ("missing-threshold", f"# Guide\n{CACHE_PREBUILD_STEM}\n"),
        )
        for name, content in cases:
            with self.subTest(name=name):
                (self.dist / OPERATOR_GUIDE_NAME).write_text(
                    content,
                    encoding="utf-8",
                )
                completed = self._run(self.repo / name)
                self.assertNotEqual(0, completed.returncode)
                self.assertIn(
                    "Operator guide is missing required user workflow text",
                    completed.stderr,
                )

    def test_output_directory_inside_dist_is_rejected_before_creation(self) -> None:
        output = self.dist / "nested" / "release"
        completed = self._run(output)
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("outside the workbench distribution", completed.stderr)
        self.assertFalse(output.exists())

    def test_output_directory_trailing_space_alias_is_rejected(self) -> None:
        output = Path(f"{self.dist} ") / "child"
        completed = self._run(output)
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("segment ending in a space or dot", completed.stderr)
        self.assertFalse((self.dist / "child").exists())

    def test_output_directory_reparse_point_is_rejected(self) -> None:
        target = self.repo / "actual-output"
        target.mkdir()
        junction = self.repo / "junction-output"
        completed_link = subprocess.run(
            ["cmd.exe", "/d", "/c", "mklink", "/J", str(junction), str(target)],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        if completed_link.returncode != 0:
            self.skipTest(f"unable to create a test junction: {completed_link.stderr}")
        try:
            completed = self._run(junction)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("contains a reparse point", completed.stderr)
        finally:
            if junction.exists():
                junction.rmdir()

    def test_release_gate_requires_exact_boolean_types_and_schema(self) -> None:
        cases = (
            ("native_screenshot_smoke", "true", "must be the Boolean value"),
            ("native_focus_smoke", "true", "must be the Boolean value"),
            ("native_dpi_smoke", 1, "must be the Boolean value"),
            ("standalone_report_builder_included", 0, "must be the Boolean value"),
            ("schema_version", "3", "must be an integer"),
            ("schema_version", 4, "schema must be exactly 3"),
        )
        for index, (field, value, expected_message) in enumerate(cases):
            with self.subTest(field=field, value=value):
                self.manifest = self._base_manifest()
                self.manifest[field] = value
                self._write_manifest()
                completed = self._run(self.repo / f"invalid-{index}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn(expected_message, completed.stderr)

    def test_native_gui_evidence_is_strictly_validated(self) -> None:
        cases = (
            ("foreground_window_matches", False, "must be the Boolean value True"),
            ("focus_owned_by_process", "true", "must be the Boolean value"),
            ("native_window_icon", False, "must be the Boolean value True"),
            ("dpi_awareness_code", 1, "acceptance evidence is incomplete"),
            ("window_dpi", 95, "acceptance evidence is incomplete"),
            ("physical_width", 999, "acceptance evidence is incomplete"),
            ("physical_height", 699, "acceptance evidence is incomplete"),
        )
        for index, (field, value, expected_message) in enumerate(cases):
            with self.subTest(field=field, value=value):
                self.manifest = self._base_manifest()
                self.manifest["native_gui_acceptance"][field] = value
                self._write_manifest()
                completed = self._run(self.repo / f"invalid-native-gui-{index}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn(expected_message, completed.stderr)

    def test_executable_must_be_a_safe_inventory_bound_path(self) -> None:
        outside = self.repo / "outside.exe"
        outside.write_bytes(b"fixture-executable")
        self.manifest["executable"] = "../outside.exe"
        self._write_manifest()
        completed = self._run(self.repo / "unsafe-executable")
        self.assertNotEqual(0, completed.returncode)
        self.assertIn("Unsafe relative package path", completed.stderr)

    def test_singleton_array_cannot_impersonate_a_string_field(self) -> None:
        for field in ("version", "executable", "executable_sha256", "screenshot_mode"):
            with self.subTest(field=field):
                self.manifest = self._base_manifest()
                self.manifest[field] = [self.manifest[field]]
                self._write_manifest()
                completed = self._run(self.repo / f"array-{field}")
                self.assertNotEqual(0, completed.returncode)
                self.assertIn("must be a string", completed.stderr)

    def test_failed_gate_preserves_existing_publication_assets(self) -> None:
        output = self.repo / "existing-output"
        output.mkdir()
        archive = output / f"BridgeMonitoringWorkbench-{VERSION}-win-x64.zip"
        checksum = Path(f"{archive}.sha256")
        publication = output / f"publish_{VERSION}.json"
        sentinels = {
            archive: b"old archive",
            checksum: b"old checksum",
            publication: b"old publication",
        }
        for path, payload in sentinels.items():
            path.write_bytes(payload)

        self.manifest["native_screenshot_smoke"] = "true"
        self._write_manifest()
        completed = self._run(output)
        self.assertNotEqual(0, completed.returncode)
        for path, payload in sentinels.items():
            self.assertEqual(payload, path.read_bytes(), path.name)
        self.assertEqual([], list(output.glob(".*.tmp")))

    def test_existing_publication_symlink_is_rejected(self) -> None:
        output = self.repo / "symlink-output"
        output.mkdir()
        target = self.repo / "publication-target.bin"
        target.write_bytes(b"do not replace")
        archive = output / f"BridgeMonitoringWorkbench-{VERSION}-win-x64.zip"
        completed_link = subprocess.run(
            ["cmd.exe", "/d", "/c", "mklink", str(archive), str(target)],
            check=False,
            capture_output=True,
            text=True,
            timeout=15,
        )
        if completed_link.returncode != 0:
            self.skipTest(f"unable to create a test file symlink: {completed_link.stderr}")
        try:
            completed = self._run(output)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("Publication destination is a reparse point", completed.stderr)
            self.assertEqual(b"do not replace", target.read_bytes())
        finally:
            archive.unlink(missing_ok=True)

    def test_concurrent_packager_lock_fails_closed(self) -> None:
        output = self.repo / "locked-output"
        output.mkdir()
        lock_path = output / ".workbench_release_package.lock"
        ready_path = output / ".lock-ready"
        holder_script = output / "hold_lock.ps1"
        holder_script.write_text(
            f'''$stream = [IO.File]::Open(
    "{str(lock_path).replace(chr(34), chr(34) * 2)}",
    [IO.FileMode]::OpenOrCreate,
    [IO.FileAccess]::ReadWrite,
    [IO.FileShare]::None
)
try {{
    [IO.File]::WriteAllText("{str(ready_path).replace(chr(34), chr(34) * 2)}", "ready")
    Start-Sleep -Seconds 30
}}
finally {{
    $stream.Dispose()
}}
''',
            encoding="utf-8-sig",
        )
        creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        holder = subprocess.Popen(
            [
                self.powershell,
                "-NoLogo",
                "-NoProfile",
                "-NonInteractive",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(holder_script),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=creation_flags,
        )
        try:
            deadline = time.monotonic() + 5
            while not ready_path.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue(ready_path.exists(), "lock holder did not become ready")
            completed = self._run(output)
            self.assertNotEqual(0, completed.returncode)
            self.assertIn("Another workbench release packaging process", completed.stderr)
        finally:
            holder.terminate()
            try:
                holder.wait(timeout=5)
            except subprocess.TimeoutExpired:
                holder.kill()
                holder.wait(timeout=5)

    def test_publication_set_rolls_back_earlier_replacements(self) -> None:
        package_source = PACKAGE_SCRIPT.read_text(encoding="utf-8-sig")
        function_start = package_source.index("function Publish-VerifiedFileSet")
        function_end = package_source.index("\n$repo =", function_start)
        helper_source = package_source[function_start:function_end]
        root = self.repo / "rollback-fixture"
        root.mkdir()
        script_path = root / "exercise_rollback.ps1"
        script_path.write_text(
            f'''$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
{helper_source}
$root = "{str(root).replace(chr(34), chr(34) * 2)}"
$temp1 = Join-Path $root "temp1"
$temp2 = Join-Path $root "temp2"
$temp3 = Join-Path $root "temp3"
$dest1 = Join-Path $root "dest1"
$dest2 = Join-Path $root "dest2"
$blockedDestination = Join-Path $root "blocked"
[IO.File]::WriteAllText($temp1, "new1")
[IO.File]::WriteAllText($temp2, "new2")
[IO.File]::WriteAllText($temp3, "new3")
[IO.File]::WriteAllText($dest1, "old1")
[IO.File]::WriteAllText($dest2, "old2")
[IO.Directory]::CreateDirectory($blockedDestination) | Out-Null
try {{
    Publish-VerifiedFileSet @(
        [pscustomobject]@{{ temporary = $temp1; destination = $dest1 }},
        [pscustomobject]@{{ temporary = $temp2; destination = $dest2 }},
        [pscustomobject]@{{ temporary = $temp3; destination = $blockedDestination }}
    )
    exit 91
}}
catch {{
    if ([IO.File]::ReadAllText($dest1) -ne "old1" `
            -or [IO.File]::ReadAllText($dest2) -ne "old2") {{
        Write-Error "publication rollback did not restore prior assets"
        exit 92
    }}
}}
exit 0
''',
            encoding="utf-8-sig",
        )
        completed = subprocess.run(
            [
                self.powershell,
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
            encoding="utf-8",
            errors="replace",
            timeout=30,
        )
        self.assertEqual(
            0,
            completed.returncode,
            msg=f"stdout={completed.stdout}\nstderr={completed.stderr}",
        )


if __name__ == "__main__":
    unittest.main()
