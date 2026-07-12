from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from scripts.validate_workbench_update_cycle import native_qt_environment

from workbench.updater import (
    GitHubReleaseClient,
    ReleaseAsset,
    StagedUpdate,
    UpdateInfo,
    UpdatePolicy,
    UpdateSecurityError,
    install_staged_update,
    is_newer_version,
    stage_verified_update,
    validate_release_package,
    write_install_script,
)


class FakeResponse(io.BytesIO):
    def __init__(self, payload: bytes, content_type: str = "application/octet-stream") -> None:
        super().__init__(payload)
        self.headers = {"Content-Length": str(len(payload)), "Content-Type": content_type}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


def package_bytes(version: str = "v1.8.0") -> tuple[bytes, str]:
    executable = b"fake-workbench-executable"
    exe_hash = hashlib.sha256(executable).hexdigest()
    manifest = {
        "schema_version": 2,
        "version": version,
        "executable_sha256": exe_hash,
        "includes_analysis_runner": True,
        "auto_threshold_preview_runner_smoke": True,
        "includes_report_builder": True,
        "report_builder_context_smoke": True,
        "embedded_report_job_smoke": True,
        "report_gate_contract_smoke": True,
        "report_visual_qc_smoke": True,
        "smoke": {"ok": True},
        "file_inventory_count": 1,
        "file_inventory": [{
            "path": "BridgeMonitoringWorkbench.exe",
            "bytes": len(executable),
            "sha256": exe_hash,
        }],
    }
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("BridgeMonitoringWorkbench/BridgeMonitoringWorkbench.exe", executable)
        archive.writestr(
            "BridgeMonitoringWorkbench/release_manifest.json",
            json.dumps(manifest),
        )
    payload = stream.getvalue()
    return payload, hashlib.sha256(payload).hexdigest()


def write_release_package(root: Path, version: str, files: dict[str, bytes]) -> Path:
    package = root / "BridgeMonitoringWorkbench"
    package.mkdir(parents=True)
    inventory = []
    for name, content in files.items():
        target = package / Path(*name.split("/"))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
        inventory.append({
            "path": name,
            "bytes": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
        })
    executable = files["BridgeMonitoringWorkbench.exe"]
    manifest = {
        "schema_version": 2,
        "version": version,
        "executable_sha256": hashlib.sha256(executable).hexdigest(),
        "includes_analysis_runner": True,
        "auto_threshold_preview_runner_smoke": True,
        "includes_report_builder": True,
        "report_builder_context_smoke": True,
        "embedded_report_job_smoke": True,
        "report_gate_contract_smoke": True,
        "report_visual_qc_smoke": True,
        "smoke": {"ok": True},
        "file_inventory_count": len(inventory),
        "file_inventory": inventory,
    }
    (package / "release_manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return package


class WorkbenchUpdaterTests(unittest.TestCase):
    def test_native_update_screenshot_does_not_inherit_offscreen_qt(self) -> None:
        with patch.dict(os.environ, {"QT_QPA_PLATFORM": "offscreen"}):
            self.assertNotIn("QT_QPA_PLATFORM", native_qt_environment())

    def test_version_comparison_does_not_replace_same_base_development_build(self) -> None:
        self.assertFalse(is_newer_version("v1.7.39-dev", "v1.7.39"))
        self.assertTrue(is_newer_version("v1.7.39-dev", "v1.7.40"))
        self.assertFalse(is_newer_version("v1.8.0", "v1.7.99"))

    def test_latest_release_selects_expected_windows_asset(self) -> None:
        archive, digest = package_bytes()
        payload = json.dumps({
            "tag_name": "v1.8.0",
            "name": "Workbench 1.8.0",
            "body": "release notes",
            "html_url": "https://github.com/example/release",
            "published_at": "2026-07-12T00:00:00Z",
            "assets": [
                {
                    "name": "BridgeMonitoringWorkbench-v1.8.0-win-x64.zip",
                    "browser_download_url": "https://example.invalid/package.zip",
                    "size": len(archive),
                    "digest": f"sha256:{digest}",
                }
            ],
        }).encode()

        def opener(_request, timeout=0):
            self.assertGreater(timeout, 0)
            return FakeResponse(payload, "application/json")

        info = GitHubReleaseClient(UpdatePolicy(), opener=opener).latest_release("v1.7.39-dev")
        self.assertTrue(info.update_available)
        self.assertTrue(info.installable)
        self.assertEqual(info.package_asset.name, "BridgeMonitoringWorkbench-v1.8.0-win-x64.zip")

    def test_latest_release_rejects_package_named_for_another_version(self) -> None:
        payload = json.dumps({
            "tag_name": "v1.8.0",
            "assets": [{
                "name": "BridgeMonitoringWorkbench-v1.9.0-win-x64.zip",
                "browser_download_url": "https://example.invalid/wrong.zip",
                "size": 10,
                "digest": f"sha256:{'0' * 64}",
            }],
        }).encode()

        info = GitHubReleaseClient(
            UpdatePolicy(), opener=lambda *_args, **_kwargs: FakeResponse(payload, "application/json")
        ).latest_release("v1.7.39")
        self.assertIsNone(info.package_asset)
        self.assertFalse(info.installable)

    def test_download_checksum_and_stage_package(self) -> None:
        archive, digest = package_bytes()
        package = ReleaseAsset("BridgeMonitoringWorkbench-v1.8.0-win-x64.zip", "https://unit/package", len(archive))
        checksum = ReleaseAsset(f"{package.name}.sha256", "https://unit/checksum", 0)
        info = UpdateInfo("v1.7.39", "v1.8.0", "v1.8.0", "", "", "", package, checksum)

        def opener(request, timeout=0):
            if request.full_url.endswith("package"):
                return FakeResponse(archive)
            return FakeResponse(f"{digest}  {package.name}\n".encode())

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            client = GitHubReleaseClient(UpdatePolicy(), opener=opener)
            archive_path, actual = client.download_verified_package(info, root / "downloads")
            staged = stage_verified_update(archive_path, "v1.8.0", actual, root / "staged")
            self.assertTrue(staged.executable_path.is_file())
            self.assertEqual(staged.archive_sha256, digest)

    def test_stage_rejects_path_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive_path = root / "unsafe.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("../escape.txt", "bad")
            with self.assertRaises(UpdateSecurityError):
                stage_verified_update(archive_path, "v1.8.0", "0" * 64, root / "stage")

    def test_stage_rejects_windows_path_traversal(self) -> None:
        for unsafe_name in (r"..\outside.txt", r"C:\outside.txt"):
            with self.subTest(unsafe_name=unsafe_name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                archive_path = root / "unsafe.zip"
                with zipfile.ZipFile(archive_path, "w") as archive:
                    archive.writestr(unsafe_name, "bad")
                with self.assertRaises(UpdateSecurityError):
                    stage_verified_update(archive_path, "v1.8.0", "0" * 64, root / "stage")

    def test_stage_rejects_duplicate_casefold_paths_and_symbolic_links(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            duplicate = root / "duplicate.zip"
            with zipfile.ZipFile(duplicate, "w") as archive:
                archive.writestr("BridgeMonitoringWorkbench/File.txt", "one")
                archive.writestr("BridgeMonitoringWorkbench/file.txt", "two")
            with self.assertRaisesRegex(UpdateSecurityError, "duplicate path"):
                stage_verified_update(duplicate, "v1.8.0", "0" * 64, root / "stage-duplicate")

            symlink = root / "symlink.zip"
            with zipfile.ZipFile(symlink, "w") as archive:
                info = zipfile.ZipInfo("BridgeMonitoringWorkbench/link")
                info.create_system = 3
                info.external_attr = 0o120777 << 16
                archive.writestr(info, "target")
            with self.assertRaisesRegex(UpdateSecurityError, "symbolic link"):
                stage_verified_update(symlink, "v1.8.0", "0" * 64, root / "stage-symlink")

    def test_stage_uses_safe_short_root_when_windows_target_would_exceed_limit(self) -> None:
        archive, digest = package_bytes()
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive_path = root / "package.zip"
            archive_path.write_bytes(archive)
            long_parent = root / ("long-stage-parent-" * 8)
            staged = stage_verified_update(archive_path, "v1.8.0", digest, long_parent)
            self.assertTrue(staged.executable_path.is_file())
            if os.name == "nt":
                with self.assertRaises(ValueError):
                    staged.package_root.relative_to(long_parent)
            shutil.rmtree(staged.package_root.parent, ignore_errors=True)

    def test_release_inventory_rejects_missing_extra_and_tampered_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            package = write_release_package(root, "v1.8.0", {
                "BridgeMonitoringWorkbench.exe": b"new",
                "_internal/runtime.dll": b"runtime",
            })
            validate_release_package(package, expected_version="v1.8.0")
            (package / "unexpected.txt").write_text("extra", encoding="utf-8")
            with self.assertRaisesRegex(UpdateSecurityError, "file set differs"):
                validate_release_package(package, expected_version="v1.8.0")
            (package / "unexpected.txt").unlink()
            (package / "_internal" / "runtime.dll").write_bytes(b"tampered")
            with self.assertRaisesRegex(UpdateSecurityError, "size mismatch|SHA256 mismatch"):
                validate_release_package(package, expected_version="v1.8.0")

    def test_transactional_install_preserves_configs_and_unmanaged_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            install = root / "installed"
            install.mkdir()
            (install / "BridgeMonitoringWorkbench.exe").write_bytes(b"old")
            (install / "_internal").mkdir()
            (install / "_internal" / "old.dll").write_bytes(b"old-runtime")
            (install / "config").mkdir()
            (install / "config" / "default_config.json").write_text('{"owner":"custom"}', encoding="utf-8")
            (install / "operator_notes.txt").write_text("keep me", encoding="utf-8")
            (install / "release_manifest.json").write_text('{"schema_version":1}', encoding="utf-8")
            package = write_release_package(root / "source", "v1.8.0", {
                "BridgeMonitoringWorkbench.exe": b"new",
                "_internal/new.dll": b"new-runtime",
                "config/default_config.json": b'{"owner":"default"}',
                "config/new_profile.json": b'{"new":true}',
            })
            result = install_staged_update(package, install, "v1.8.0", restart=False)
            self.assertEqual((install / "BridgeMonitoringWorkbench.exe").read_bytes(), b"new")
            self.assertFalse((install / "_internal" / "old.dll").exists())
            self.assertEqual((install / "_internal" / "new.dll").read_bytes(), b"new-runtime")
            self.assertEqual(
                (install / "config" / "default_config.json").read_text(encoding="utf-8"),
                '{"owner":"custom"}',
            )
            self.assertTrue((install / "config" / "new_profile.json").is_file())
            self.assertEqual((install / "operator_notes.txt").read_text(encoding="utf-8"), "keep me")
            self.assertEqual((result.backup_root / "BridgeMonitoringWorkbench.exe").read_bytes(), b"old")
            self.assertEqual(json.loads(result.log_path.read_text(encoding="utf-8"))["status"], "installed")

    def test_transactional_install_rolls_back_after_directory_swap_failure(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            install = root / "installed"
            install.mkdir()
            (install / "BridgeMonitoringWorkbench.exe").write_bytes(b"old")
            (install / "keep.txt").write_text("original", encoding="utf-8")
            rollback_before = {
                path.relative_to(install).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in install.rglob("*") if path.is_file()
            }
            package = write_release_package(root / "source", "v1.8.0", {
                "BridgeMonitoringWorkbench.exe": b"new",
                "_internal/new.dll": b"new-runtime",
            })
            log = root / "rollback.json"
            with self.assertRaisesRegex(Exception, "injected failure"):
                install_staged_update(
                    package,
                    install,
                    "v1.8.0",
                    restart=False,
                    log_path=log,
                    failure_point="after_backup_rename",
                )
            self.assertEqual((install / "BridgeMonitoringWorkbench.exe").read_bytes(), b"old")
            self.assertEqual((install / "keep.txt").read_text(encoding="utf-8"), "original")
            self.assertEqual(json.loads(log.read_text(encoding="utf-8"))["rolled_back"], True)
            self.assertFalse(list(root.glob("installed.pending_*")))

            activation_log = root / "activation_rollback.json"
            with self.assertRaisesRegex(Exception, "injected failure"):
                install_staged_update(
                    package,
                    install,
                    "v1.8.0",
                    restart=False,
                    log_path=activation_log,
                    failure_point="after_activation",
                )
            self.assertEqual({
                path.relative_to(install).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in install.rglob("*") if path.is_file()
            }, rollback_before)

    def test_install_script_preserves_config_and_waits_for_current_process(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            install = root / "install"
            package = root / "stage" / "BridgeMonitoringWorkbench"
            install.mkdir(parents=True)
            package.mkdir(parents=True)
            (install / "BridgeMonitoringWorkbench.exe").write_bytes(b"old")
            staged_exe = package / "BridgeMonitoringWorkbench.exe"
            staged_exe.write_bytes(b"new")
            manifest = package / "release_manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            staged = StagedUpdate("v1.8.0", root / "package.zip", package, staged_exe, manifest, "0" * 64)
            script = write_install_script(staged, install, 12345, script_parent=root / "scripts")
            text = script.read_text(encoding="utf-8-sig")
            self.assertIn("Wait-Process -Id 12345", text)
            self.assertIn("/XD (Join-Path $source 'config')", text)
            self.assertIn("backup_", text)


if __name__ == "__main__":
    unittest.main()
