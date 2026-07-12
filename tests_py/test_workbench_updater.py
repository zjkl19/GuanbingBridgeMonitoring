from __future__ import annotations

import hashlib
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from workbench.updater import (
    GitHubReleaseClient,
    ReleaseAsset,
    StagedUpdate,
    UpdateInfo,
    UpdatePolicy,
    UpdateSecurityError,
    is_newer_version,
    stage_verified_update,
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
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, "w", zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("BridgeMonitoringWorkbench/BridgeMonitoringWorkbench.exe", executable)
        archive.writestr(
            "BridgeMonitoringWorkbench/release_manifest.json",
            json.dumps({"version": version, "executable_sha256": exe_hash}),
        )
    payload = stream.getvalue()
    return payload, hashlib.sha256(payload).hexdigest()


class WorkbenchUpdaterTests(unittest.TestCase):
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
