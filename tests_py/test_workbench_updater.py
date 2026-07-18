from __future__ import annotations

import base64
import hashlib
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path, PurePosixPath
from unittest.mock import patch

from scripts.validate_workbench_update_cycle import native_qt_environment

from workbench.updater import (
    GitHubReleaseClient,
    ReleaseAsset,
    StagedUpdate,
    UpdateInfo,
    UpdatePolicy,
    UpdateError,
    UpdateSecurityError,
    cleanup_update_backups,
    discover_update_backups,
    existing_workbench_executable,
    _migrate_desktop_shortcuts,
    install_staged_update,
    is_newer_version,
    stage_verified_update,
    validate_release_package,
    write_install_script,
)
from workbench.version import (
    APP_DISPLAY_NAME,
    EXECUTABLE_FILENAME,
    LEGACY_CHINESE_EXECUTABLE_FILENAME,
    LEGACY_ENGLISH_EXECUTABLE_FILENAME,
    SUPPORTED_EXECUTABLE_FILENAMES,
)


class FakeResponse(io.BytesIO):
    def __init__(self, payload: bytes, content_type: str = "application/octet-stream") -> None:
        super().__init__(payload)
        self.headers = {"Content-Length": str(len(payload)), "Content-Type": content_type}

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        self.close()


def package_bytes(
    version: str = "v1.8.0",
    *,
    legacy_name_bridge: bool = False,
) -> tuple[bytes, str]:
    executable = b"fake-workbench-executable"
    exe_hash = hashlib.sha256(executable).hexdigest()
    executable_name = (
        LEGACY_CHINESE_EXECUTABLE_FILENAME
        if legacy_name_bridge
        else EXECUTABLE_FILENAME
    )
    files = {EXECUTABLE_FILENAME: executable}
    if legacy_name_bridge:
        files[LEGACY_CHINESE_EXECUTABLE_FILENAME] = executable
    inventory = [
        {
            "path": name,
            "bytes": len(content),
            "sha256": hashlib.sha256(content).hexdigest(),
        }
        for name, content in files.items()
    ]
    manifest = {
        "schema_version": 3,
        "version": version,
        "display_name": APP_DISPLAY_NAME,
        "executable": executable_name,
        "supported_executable_filenames": list(SUPPORTED_EXECUTABLE_FILENAMES),
        "executable_sha256": exe_hash,
        "includes_analysis_runner": True,
        "auto_threshold_preview_runner_smoke": True,
        "installed_profile_matrix_smoke": True,
        "invalid_cli_smoke": True,
        "task_history_smoke": True,
        "report_runtime": "embedded_headless_worker",
        "standalone_report_builder_included": False,
        "includes_report_builder": True,
        "report_builder_context_smoke": True,
        "embedded_report_runtime_smoke": True,
        "embedded_report_job_smoke": True,
        "report_gate_contract_smoke": True,
        "report_visual_qc_smoke": True,
        "smoke": {"ok": True},
        "file_inventory_count": len(inventory),
        "file_inventory": inventory,
    }
    if legacy_name_bridge:
        manifest["canonical_executable_sha256"] = exe_hash
        manifest["executable_migration"] = {
            "mode": "legacy_name_bridge",
            "legacy_entrypoint": LEGACY_CHINESE_EXECUTABLE_FILENAME,
            "canonical_entrypoint": EXECUTABLE_FILENAME,
        }
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, content in files.items():
            archive.writestr(f"BridgeMonitoringWorkbench/{name}", content)
        archive.writestr(
            "BridgeMonitoringWorkbench/release_manifest.json",
            json.dumps(manifest),
        )
    payload = stream.getvalue()
    return payload, hashlib.sha256(payload).hexdigest()


def validate_with_frozen_v1_8_2_stage_contract(
    archive_bytes: bytes,
    version: str,
) -> dict[str, object]:
    """Exercise the executable-name constraints shipped at d5d7ad3.

    The old stage code searched for exactly one ``桥梁健康监测工作台.exe``,
    required the manifest to name that file, then verified the complete
    schema-v3 inventory and the executable SHA.  Keeping this harness local
    makes the otherwise immutable old-to-new hop a release regression gate.
    """

    old_executable = LEGACY_CHINESE_EXECUTABLE_FILENAME
    with zipfile.ZipFile(io.BytesIO(archive_bytes)) as archive:
        names = [name for name in archive.namelist() if not name.endswith("/")]
        matches = [name for name in names if Path(name).name == old_executable]
        if len(matches) != 1:
            raise ValueError("v1.8.2 stage requires exactly one old Chinese executable")
        root = str(PurePosixPath(matches[0]).parent)
        manifest_name = f"{root}/release_manifest.json"
        manifest = json.loads(archive.read(manifest_name))
        if manifest.get("version") != version:
            raise ValueError("v1.8.2 version mismatch")
        if manifest.get("executable") != old_executable:
            raise ValueError("v1.8.2 executable mismatch")
        inventory = list(manifest.get("file_inventory") or [])
        inventory_names = {f"{root}/{item['path']}" for item in inventory}
        actual_names = set(names) - {manifest_name}
        if inventory_names != actual_names:
            raise ValueError("v1.8.2 inventory does not close")
        for item in inventory:
            data = archive.read(f"{root}/{item['path']}")
            if len(data) != int(item["bytes"]):
                raise ValueError("v1.8.2 inventory size mismatch")
            if hashlib.sha256(data).hexdigest() != item["sha256"]:
                raise ValueError("v1.8.2 inventory hash mismatch")
        old_data = archive.read(matches[0])
        if hashlib.sha256(old_data).hexdigest() != manifest.get("executable_sha256"):
            raise ValueError("v1.8.2 executable hash mismatch")
        return manifest


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
    executable = files[EXECUTABLE_FILENAME]
    manifest = {
        "schema_version": 3,
        "version": version,
        "display_name": APP_DISPLAY_NAME,
        "executable": EXECUTABLE_FILENAME,
        "supported_executable_filenames": list(SUPPORTED_EXECUTABLE_FILENAMES),
        "executable_sha256": hashlib.sha256(executable).hexdigest(),
        "includes_analysis_runner": True,
        "auto_threshold_preview_runner_smoke": True,
        "installed_profile_matrix_smoke": True,
        "invalid_cli_smoke": True,
        "task_history_smoke": True,
        "report_runtime": "embedded_headless_worker",
        "standalone_report_builder_included": False,
        "includes_report_builder": True,
        "report_builder_context_smoke": True,
        "embedded_report_runtime_smoke": True,
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
    def test_shortcut_migration_helper_uses_all_managed_names(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            install = Path(folder)
            (install / EXECUTABLE_FILENAME).write_bytes(b"new")
            completed = subprocess.CompletedProcess(
                args=[],
                returncode=0,
                stdout=json.dumps(
                    {"status": "migrated", "shortcut": "unit-test.lnk"},
                    ensure_ascii=False,
                ),
                stderr="",
            )
            with (
                patch("workbench.updater.os.name", "nt"),
                patch("workbench.updater.subprocess.run", return_value=completed) as run,
            ):
                result = _migrate_desktop_shortcuts(install)
            self.assertEqual(result["status"], "migrated")
            command = run.call_args.args[0]
            self.assertEqual(command[-2], "-EncodedCommand")
            script = base64.b64decode(command[-1]).decode("utf-16le")
            self.assertIn(APP_DISPLAY_NAME, script)
            for name in SUPPORTED_EXECUTABLE_FILENAMES:
                self.assertIn(name, script)
            self.assertIn(
                f"{Path(LEGACY_CHINESE_EXECUTABLE_FILENAME).stem}.lnk",
                script,
            )
            self.assertIn(
                f"{Path(LEGACY_ENGLISH_EXECUTABLE_FILENAME).stem}.lnk",
                script,
            )
            self.assertIn("foreach ($item in $legacyPayload)", script)
            self.assertIn("foreach ($item in $supportedPayload)", script)
            self.assertNotIn(
                "$legacyNames = @($LegacyShortcuts | ConvertFrom-Json)",
                script,
            )
            self.assertNotIn(
                "$supportedNames = @($SupportedExecutables | ConvertFrom-Json)",
                script,
            )

    def test_update_policy_publishes_canonical_name_and_migration_aliases(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            config = root / "config"
            config.mkdir()
            (config / "workbench_update.json").write_text(
                json.dumps(
                    {
                        "display_name": APP_DISPLAY_NAME,
                        "supported_executable_filenames": list(
                            SUPPORTED_EXECUTABLE_FILENAMES
                        ),
                    },
                    ensure_ascii=False,
                ),
                encoding="utf-8",
            )
            policy = UpdatePolicy.load(root)
            self.assertEqual(policy.display_name, APP_DISPLAY_NAME)
            self.assertEqual(
                policy.supported_executable_filenames,
                SUPPORTED_EXECUTABLE_FILENAMES,
            )

    def test_current_and_both_legacy_executable_names_are_recognized(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in reversed(SUPPORTED_EXECUTABLE_FILENAMES):
                (root / name).write_bytes(name.encode("utf-8"))
            self.assertEqual(existing_workbench_executable(root).name, EXECUTABLE_FILENAME)
            (root / EXECUTABLE_FILENAME).unlink()
            self.assertEqual(
                existing_workbench_executable(root).name,
                LEGACY_CHINESE_EXECUTABLE_FILENAME,
            )
            (root / LEGACY_CHINESE_EXECUTABLE_FILENAME).unlink()
            self.assertEqual(
                existing_workbench_executable(root).name,
                LEGACY_ENGLISH_EXECUTABLE_FILENAME,
            )

    def test_backup_inventory_and_explicit_retention_cleanup(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            parent = Path(folder)
            install = parent / "BridgeMonitoringWorkbench"
            install.mkdir()
            safe_paths = []
            for old_version, target_version, stamp in (
                ("v1.7.36", "v1.7.37", "20260710_010000"),
                ("v1.7.37", "v1.7.38", "20260711_010000"),
                ("v1.7.38", "v1.7.39", "20260712_010000"),
            ):
                backup = parent / f"BridgeMonitoringWorkbench.backup_{target_version}_{stamp}_abcdef12"
                backup.mkdir()
                (backup / "BridgeMonitoringWorkbench.exe").write_bytes(b"old")
                (backup / "release_manifest.json").write_text(
                    json.dumps({"version": old_version}), encoding="utf-8"
                )
                safe_paths.append(backup)
            invalid = parent / "BridgeMonitoringWorkbench.backup_v1.7.40_20260713_010000_deadbeef"
            invalid.mkdir()
            (invalid / "BridgeMonitoringWorkbench.exe").write_bytes(b"old")
            (invalid / "release_manifest.json").write_text("not-json", encoding="utf-8")
            unrelated = parent / "BridgeMonitoringWorkbench.backup_manual"
            unrelated.mkdir()

            found = discover_update_backups(install)
            self.assertEqual(len(found), 4)
            self.assertEqual(sum(item.safe_to_remove for item in found), 3)
            self.assertEqual(found[1].version, "v1.7.38")
            self.assertEqual(found[1].replaced_by_version, "v1.7.39")
            removed = cleanup_update_backups(install, keep_latest=2)
            self.assertEqual([item.version for item in removed], ["v1.7.36"])
            self.assertFalse(safe_paths[0].exists())
            self.assertTrue(safe_paths[1].is_dir())
            self.assertTrue(safe_paths[2].is_dir())
            self.assertTrue(invalid.is_dir())
            self.assertTrue(unrelated.is_dir())

            with self.assertRaisesRegex(UpdateError, "至少保留 1 个"):
                cleanup_update_backups(install, keep_latest=0)

    def test_native_update_screenshot_does_not_inherit_offscreen_qt(self) -> None:
        with patch.dict(os.environ, {"QT_QPA_PLATFORM": "offscreen"}):
            self.assertNotIn("QT_QPA_PLATFORM", native_qt_environment())

    def test_version_comparison_does_not_replace_same_base_development_build(self) -> None:
        self.assertTrue(is_newer_version("v1.7.39-dev", "v1.7.39"))
        self.assertTrue(is_newer_version("v1.7.39-dev", "v1.7.40"))
        self.assertTrue(is_newer_version("v1.8.0-rc1", "v1.8.0"))
        self.assertTrue(is_newer_version("v1.8.0-rc1", "v1.8.0-rc2"))
        self.assertTrue(is_newer_version("v1.8.0-rc.2", "v1.8.0-rc.10"))
        self.assertFalse(is_newer_version("v1.8.0", "v1.8.0-rc2"))
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

    def test_legacy_name_bridge_crosses_v1_8_2_and_installs_canonical_only(self) -> None:
        archive, digest = package_bytes(legacy_name_bridge=True)
        manifest = validate_with_frozen_v1_8_2_stage_contract(archive, "v1.8.0")
        self.assertEqual(manifest["executable"], LEGACY_CHINESE_EXECUTABLE_FILENAME)

        canonical_archive, _ = package_bytes()
        with self.assertRaisesRegex(ValueError, "old Chinese executable"):
            validate_with_frozen_v1_8_2_stage_contract(canonical_archive, "v1.8.0")

        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive_path = root / "bridge.zip"
            archive_path.write_bytes(archive)
            staged = stage_verified_update(
                archive_path,
                "v1.8.0",
                digest,
                root / "staged",
            )
            self.assertEqual(
                staged.executable_path.name,
                LEGACY_CHINESE_EXECUTABLE_FILENAME,
            )
            install = root / "installed"
            install.mkdir()
            (install / LEGACY_CHINESE_EXECUTABLE_FILENAME).write_bytes(b"old")
            with patch(
                "workbench.updater._migrate_desktop_shortcuts",
                return_value={"status": "migrated"},
            ):
                install_staged_update(
                    staged.package_root,
                    install,
                    "v1.8.0",
                    restart=False,
                )
            self.assertTrue((install / EXECUTABLE_FILENAME).is_file())
            self.assertFalse((install / LEGACY_CHINESE_EXECUTABLE_FILENAME).exists())
            installed_manifest = validate_release_package(
                install,
                expected_version="v1.8.0",
                allow_extra_files=True,
            )
            self.assertEqual(installed_manifest["executable"], EXECUTABLE_FILENAME)
            self.assertNotIn("executable_migration", installed_manifest)

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
                EXECUTABLE_FILENAME: b"new",
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
            (install / LEGACY_ENGLISH_EXECUTABLE_FILENAME).write_bytes(b"old-english")
            (install / LEGACY_CHINESE_EXECUTABLE_FILENAME).write_bytes(b"old-chinese")
            (install / "_internal").mkdir()
            (install / "_internal" / "old.dll").write_bytes(b"old-runtime")
            (install / "config").mkdir()
            (install / "config" / "default_config.json").write_text('{"owner":"custom"}', encoding="utf-8")
            (install / "operator_notes.txt").write_text("keep me", encoding="utf-8")
            (install / "release_manifest.json").write_text('{"schema_version":1}', encoding="utf-8")
            package = write_release_package(root / "source", "v1.8.0", {
                EXECUTABLE_FILENAME: b"new",
                "_internal/new.dll": b"new-runtime",
                "config/default_config.json": b'{"owner":"default"}',
                "config/new_profile.json": b'{"new":true}',
            })
            with patch("workbench.updater._migrate_desktop_shortcuts") as migrate_shortcuts:
                migrate_shortcuts.return_value = {
                    "status": "migrated",
                    "shortcut": "unit-test.lnk",
                }
                result = install_staged_update(package, install, "v1.8.0", restart=False)
            self.assertEqual((install / EXECUTABLE_FILENAME).read_bytes(), b"new")
            self.assertFalse((install / LEGACY_ENGLISH_EXECUTABLE_FILENAME).exists())
            self.assertFalse((install / LEGACY_CHINESE_EXECUTABLE_FILENAME).exists())
            self.assertFalse((install / "_internal" / "old.dll").exists())
            self.assertEqual((install / "_internal" / "new.dll").read_bytes(), b"new-runtime")
            self.assertEqual(
                (install / "config" / "default_config.json").read_text(encoding="utf-8"),
                '{"owner":"custom"}',
            )
            self.assertTrue((install / "config" / "new_profile.json").is_file())
            self.assertEqual((install / "operator_notes.txt").read_text(encoding="utf-8"), "keep me")
            self.assertEqual(
                (result.backup_root / LEGACY_ENGLISH_EXECUTABLE_FILENAME).read_bytes(),
                b"old-english",
            )
            self.assertEqual(
                (result.backup_root / LEGACY_CHINESE_EXECUTABLE_FILENAME).read_bytes(),
                b"old-chinese",
            )
            install_log = json.loads(result.log_path.read_text(encoding="utf-8"))
            self.assertEqual(install_log["status"], "installed")
            self.assertEqual(install_log["shortcut_migration"]["status"], "migrated")

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
                EXECUTABLE_FILENAME: b"new",
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
            staged_exe = package / EXECUTABLE_FILENAME
            staged_exe.write_bytes(b"new")
            manifest = package / "release_manifest.json"
            manifest.write_text("{}", encoding="utf-8")
            staged = StagedUpdate("v1.8.0", root / "package.zip", package, staged_exe, manifest, "0" * 64)
            script = write_install_script(staged, install, 12345, script_parent=root / "scripts")
            text = script.read_text(encoding="utf-8-sig")
            self.assertIn("Wait-Process -Id 12345", text)
            self.assertIn("/XD (Join-Path $source 'config')", text)
            self.assertIn("backup_", text)
            self.assertIn(LEGACY_CHINESE_EXECUTABLE_FILENAME, text)
            self.assertIn(LEGACY_ENGLISH_EXECUTABLE_FILENAME, text)
            self.assertIn(f"{Path(EXECUTABLE_FILENAME).stem}.lnk", text)
            self.assertIn("-not $newShortcutExists -or $newTargetIsManaged", text)


if __name__ == "__main__":
    unittest.main()
