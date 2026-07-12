from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from workbench.updater import (
    UpdateError,
    file_sha256,
    install_staged_update,
    stage_verified_update,
    validate_release_package,
)


def _tree_fingerprint(root: Path) -> dict[str, str]:
    return {
        path.relative_to(root).as_posix(): file_sha256(path)
        for path in sorted(root.rglob("*"))
        if path.is_file()
    }


def _write_legacy_install(path: Path) -> dict[str, str]:
    path.mkdir(parents=True)
    (path / "BridgeMonitoringWorkbench.exe").write_bytes(b"legacy-workbench")
    (path / "_internal").mkdir()
    (path / "_internal" / "obsolete.dll").write_bytes(b"obsolete-runtime")
    (path / "config").mkdir()
    (path / "config" / "operator_override.json").write_text(
        '{"owner":"site-operator","preserve":true}\n', encoding="utf-8"
    )
    (path / "operator_notes.txt").write_text("preserve unmanaged operator note\n", encoding="utf-8")
    (path / "release_manifest.json").write_text('{"schema_version":1}\n', encoding="utf-8")
    return _tree_fingerprint(path)


def _read_expected_checksum(path: Path) -> str:
    value = path.read_text(encoding="utf-8-sig").strip().split()
    if not value or len(value[0]) != 64:
        raise UpdateError(f"invalid checksum file: {path}")
    return value[0].lower()


def native_qt_environment() -> dict[str, str]:
    environment = dict(os.environ)
    environment.pop("QT_QPA_PLATFORM", None)
    return environment


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate a real packaged workbench update transaction.")
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--checksum", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument(
        "--output-root",
        type=Path,
        default=ROOT / "tmp" / "workbench_update_cycle" / "validation",
    )
    parser.add_argument("--keep-runtime-copies", action="store_true")
    args = parser.parse_args(argv)
    started = time.perf_counter()
    output = args.output_root.expanduser().resolve()
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    archive = args.archive.expanduser().resolve()
    checksum = args.checksum.expanduser().resolve()
    expected_archive_sha = _read_expected_checksum(checksum)
    actual_archive_sha = file_sha256(archive)
    if actual_archive_sha != expected_archive_sha:
        raise UpdateError("release ZIP checksum does not match its .sha256 asset")

    staged = stage_verified_update(
        archive,
        args.version,
        actual_archive_sha,
        output / "staged",
    )
    staged_manifest = validate_release_package(staged.package_root, expected_version=args.version)

    install = output / "installed"
    _write_legacy_install(install)
    success_log = output / "success_install.json"
    command = [
        str(staged.executable_path),
        "--install-staged-update",
        "--install-source", str(staged.package_root),
        "--install-root", str(install),
        "--install-version", args.version,
        "--install-log", str(success_log),
    ]
    completed = subprocess.run(command, timeout=180, check=False)
    if completed.returncode != 0:
        raise UpdateError(f"frozen staged installer failed with exit code {completed.returncode}")
    installed_manifest = validate_release_package(
        install,
        expected_version=args.version,
        allow_config_overrides=True,
        allow_extra_files=True,
    )
    success_payload = json.loads(success_log.read_text(encoding="utf-8-sig"))
    backup = Path(success_payload["backup_root"])
    config_preserved = (
        json.loads((install / "config" / "operator_override.json").read_text(encoding="utf-8"))
        == {"owner": "site-operator", "preserve": True}
    )
    unmanaged_preserved = (install / "operator_notes.txt").is_file()
    stale_runtime_removed = not (install / "_internal" / "obsolete.dll").exists()

    smoke_path = output / "installed_smoke.json"
    smoke_process = subprocess.run(
        [str(install / "BridgeMonitoringWorkbench.exe"), "--smoke-test", "--smoke-output", str(smoke_path)],
        timeout=120,
        check=False,
    )
    smoke = json.loads(smoke_path.read_text(encoding="utf-8-sig")) if smoke_path.is_file() else {}
    if smoke_process.returncode != 0 or smoke.get("ok") is not True:
        raise UpdateError("installed workbench smoke test failed")
    screenshot = output / "installed_workbench.png"
    screenshot_process = subprocess.run(
        [
            str(install / "BridgeMonitoringWorkbench.exe"),
            "--profile-id", "hongtang",
            "--initial-tab", "3",
            "--screenshot-output", str(screenshot),
            "--screenshot-tab", "3",
        ],
        env=native_qt_environment(),
        timeout=120,
        check=False,
    )
    if screenshot_process.returncode != 0 or not screenshot.is_file():
        raise UpdateError("installed workbench screenshot test failed")
    with Image.open(screenshot).convert("RGB") as rendered:
        pixels = rendered.get_flattened_data()
        black_count = sum(1 for red, green, blue in pixels if red < 8 and green < 8 and blue < 8)
        screenshot_black_ratio = black_count / max(1, rendered.width * rendered.height)
        screenshot_size = [rendered.width, rendered.height]
    if screenshot_black_ratio > 0.05:
        raise UpdateError(f"installed screenshot contains abnormal black regions: {screenshot_black_ratio:.4f}")

    rollback_install = output / "rollback_installed"
    rollback_before = _write_legacy_install(rollback_install)
    rollback_log = output / "rollback_install.json"
    try:
        install_staged_update(
            staged.package_root,
            rollback_install,
            args.version,
            restart=False,
            log_path=rollback_log,
            failure_point="after_backup_rename",
        )
    except Exception as exc:  # noqa: BLE001
        rollback_error = str(exc)
    else:
        raise UpdateError("fault-injected update unexpectedly succeeded")
    rollback_after = _tree_fingerprint(rollback_install)
    rollback_payload = json.loads(rollback_log.read_text(encoding="utf-8-sig"))

    result: dict[str, Any] = {
        "schema_version": 1,
        "status": "passed",
        "version": args.version,
        "archive": str(archive),
        "archive_sha256": actual_archive_sha,
        "staged_manifest_schema": staged_manifest.get("schema_version"),
        "staged_file_inventory_count": staged_manifest.get("file_inventory_count"),
        "installed_executable_sha256": file_sha256(install / "BridgeMonitoringWorkbench.exe"),
        "installed_manifest_executable_sha256": installed_manifest.get("executable_sha256"),
        "config_preserved": config_preserved,
        "unmanaged_file_preserved": unmanaged_preserved,
        "stale_runtime_removed": stale_runtime_removed,
        "backup_created": backup.is_dir(),
        "installed_smoke": smoke,
        "installed_screenshot": str(screenshot),
        "installed_screenshot_size": screenshot_size,
        "installed_screenshot_black_ratio": round(screenshot_black_ratio, 6),
        "rollback_error": rollback_error,
        "rollback_log": rollback_payload,
        "rollback_exact": rollback_before == rollback_after,
        "elapsed_sec": round(time.perf_counter() - started, 3),
    }
    required = (
        result["config_preserved"],
        result["unmanaged_file_preserved"],
        result["stale_runtime_removed"],
        result["backup_created"],
        result["rollback_exact"],
        result["installed_executable_sha256"] == result["installed_manifest_executable_sha256"],
    )
    if not all(required):
        result["status"] = "failed"
    result_path = output / "update_cycle_result.json"
    result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if not args.keep_runtime_copies:
        for path in (backup, install, rollback_install, staged.package_root.parent):
            shutil.rmtree(path, ignore_errors=True)
        result["runtime_copies_cleaned"] = True
        result_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(result_path)
    return 0 if result["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
