from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
import zipfile
from pathlib import Path
from typing import Any


SMOKE_MARKER = "bridge_analysis_runner_cache_cleanup_policy_smoke_v1"
CLEANUP_CONFIRMATION = "DELETE_VERIFIED_EXTRACTED_CSV"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate compiled Runner cache cleanup defaults and unsafe-policy rejection"
        )
    )
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--runner", type=Path, default=None)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=300)
    parser.add_argument("--replace", action="store_true")
    return parser


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"expected a JSON object: {path}")
    return payload


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _snapshot(path: Path) -> dict[str, Any]:
    stat = path.stat()
    return {
        "path": str(path.resolve()),
        "bytes": stat.st_size,
        "mtime_ns": stat.st_mtime_ns,
        "sha256": _sha256(path),
    }


def _assert_snapshot_unchanged(path: Path, before: dict[str, Any]) -> None:
    if not path.is_file():
        raise RuntimeError(f"input file was deleted: {path}")
    after = _snapshot(path)
    for field in ("bytes", "mtime_ns", "sha256"):
        if after[field] != before[field]:
            raise RuntimeError(
                f"input file changed ({field}): before={before[field]} after={after[field]} path={path}"
            )


def _assert_inside(root: Path, path: Path) -> None:
    root = root.resolve()
    path = path.resolve()
    try:
        path.relative_to(root)
    except ValueError as exc:
        raise RuntimeError(f"smoke path escapes output root: {path}") from exc


def _remove_marked_output_root(
    output_root: Path,
    *,
    attempts: int = 12,
    delay_seconds: float = 0.5,
) -> None:
    """Remove an already marker-validated smoke root despite transient Win32 locks."""
    if attempts < 1:
        raise ValueError("attempts must be at least 1")
    last_error: PermissionError | None = None
    for attempt in range(attempts):
        try:
            shutil.rmtree(output_root)
            return
        except PermissionError as exc:
            last_error = exc
            if attempt + 1 >= attempts:
                break
            time.sleep(delay_seconds)
    assert last_error is not None
    raise last_error


def _prepare_output_root(output_root: Path, *, replace: bool) -> None:
    marker = output_root / ".cache_cleanup_policy_smoke_root.json"
    if output_root.exists():
        if not replace:
            raise RuntimeError(f"output root already exists: {output_root}")
        if not marker.is_file():
            raise RuntimeError(
                f"refusing to replace an unmarked output root: {output_root}"
            )
        payload = _read_json(marker)
        if (
            payload.get("marker") != SMOKE_MARKER
            or Path(str(payload.get("output_root") or "")).resolve()
            != output_root.resolve()
        ):
            raise RuntimeError(f"invalid cleanup smoke marker: {marker}")
        _remove_marked_output_root(output_root)
    output_root.mkdir(parents=True)
    marker.write_text(
        json.dumps(
            {"marker": SMOKE_MARKER, "output_root": str(output_root.resolve())},
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def _module_records(payload: dict[str, Any]) -> list[dict[str, Any]]:
    raw = payload.get("module_results") or []
    if isinstance(raw, dict):
        raw = [raw]
    if not isinstance(raw, list):
        raise RuntimeError("analysis manifest module_results must be an object or array")
    return [item for item in raw if isinstance(item, dict)]


def _record_artifact_path(
    record: dict[str, Any],
    manifest_path: Path,
    *,
    role: str,
) -> Path:
    raw_artifacts = record.get("artifacts") or []
    if isinstance(raw_artifacts, dict):
        raw_artifacts = [raw_artifacts]
    if not isinstance(raw_artifacts, list):
        raise RuntimeError(f"module artifacts must be an object or array: {record}")
    matches = [
        item
        for item in raw_artifacts
        if isinstance(item, dict) and str(item.get("role") or "") == role
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"expected one module artifact with role {role!r}, found {len(matches)}"
        )
    raw_path = str(matches[0].get("path") or "").strip()
    if not raw_path:
        raise RuntimeError(f"module artifact path is empty for role {role!r}")
    path = Path(raw_path)
    if not path.is_absolute():
        path = (manifest_path.parent / path).resolve()
    if not path.is_file():
        raise RuntimeError(f"module artifact is missing for role {role!r}: {path}")
    return path


def _run_runner(
    runner: Path,
    project_root: Path,
    request_path: Path,
    *,
    timeout_seconds: int,
) -> tuple[int, Path, Path]:
    stdout_path = request_path.with_name("runner_stdout.log")
    stderr_path = request_path.with_name("runner_stderr.log")
    creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        completed = subprocess.run(
            [str(runner), str(request_path)],
            cwd=project_root,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=False,
            timeout=max(1, int(timeout_seconds)),
            creationflags=creation_flags,
        )
    except subprocess.TimeoutExpired as exc:
        stdout_path.write_bytes(exc.stdout or b"")
        stderr_path.write_bytes(exc.stderr or b"")
        raise RuntimeError(
            f"compiled cleanup policy smoke timed out after {timeout_seconds}s: {request_path}"
        ) from exc
    stdout_path.write_bytes(completed.stdout)
    stderr_path.write_bytes(completed.stderr)
    return completed.returncode, stdout_path, stderr_path


def _base_config(data_root: Path) -> dict[str, Any]:
    return {
        "vendor": "jiulongjiang",
        "bridge": {
            "id": "jiulongjiang",
            "name": "Jiulongjiang cleanup policy smoke",
        },
        "data_layout": "jlj_daily_export",
        "notify": {"enabled": False},
        "gui": {"auto_configure_result_folders": False},
        "data_adapter": {
            "vendor": "jiulongjiang",
            "cache": {"enabled": True, "dir": "cache", "validate": "mtime_size"},
        },
        "cache_prebuild": {
            "manifest_dir": str(data_root / "run_logs"),
            "force_rebuild": False,
            "max_workers": 1,
            "min_free_gib": 0,
            "min_free_fraction": 0,
            "estimated_cache_ratio": 1.25,
        },
    }


def _request(
    project_root: Path,
    data_root: Path,
    status_path: Path,
    run_id: str,
    options: dict[str, Any],
    config: dict[str, Any],
) -> dict[str, Any]:
    return {
        "request_type": "analysis",
        "project_root": str(project_root),
        "data_root": str(data_root),
        "start_date": "2026-06-01",
        "end_date": "2026-06-01",
        "config_path": "",
        "config_sha256": "",
        "stop_file": "",
        "async_status_file": str(status_path),
        "async_run_id": run_id,
        "options": options,
        "config": config,
    }


def _write_request(path: Path, payload: dict[str, Any]) -> None:
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _find_failed_manifest(data_root: Path) -> Path:
    matches = sorted((data_root / "run_logs").glob("analysis_manifest_*.json"))
    failed = [path for path in matches if str(_read_json(path).get("status") or "").lower() == "failed"]
    if len(failed) != 1:
        raise RuntimeError(f"expected one failed manifest, found {len(failed)}: {matches}")
    return failed[0]


def _assert_no_cleanup_side_effects(data_root: Path) -> None:
    if list(data_root.rglob(".bms_cache_source_cleanup_receipt.json")):
        raise RuntimeError("cleanup receipt exists where cleanup must not have run")
    if [path for path in data_root.rglob("*") if ".bmsdelete." in path.name]:
        raise RuntimeError("temporary cleanup deletion files exist")
    lock_roots = list(data_root.rglob(".bms_daily_export_mutation_locks"))
    if any(any(path.rglob("*")) for path in lock_roots if path.is_dir()):
        raise RuntimeError("daily mutation lock files remain after Runner exit")


def _assert_no_transient_cleanup_artifacts(data_root: Path) -> None:
    if [path for path in data_root.rglob("*") if ".bmsdelete." in path.name]:
        raise RuntimeError("temporary cleanup deletion files remain after commit")
    if list(data_root.rglob("_staging")):
        raise RuntimeError("output staging directory remains after Runner exit")
    lock_roots = list(data_root.rglob(".bms_daily_export_mutation_locks"))
    if any(any(path.rglob("*")) for path in lock_roots if path.is_dir()):
        raise RuntimeError("daily mutation lock files remain after Runner exit")


def _default_off_case(
    root: Path, runner: Path, project_root: Path, timeout_seconds: int
) -> dict[str, Any]:
    data_root = root / "data"
    csv_dir = data_root / "data_jlj_2026-06-01" / "data" / "jlj" / "csv"
    csv_dir.mkdir(parents=True)
    csv_path = csv_dir / "POINT-DEFAULT.csv"
    csv_path.write_text(
        "ts,value_x,value_y,value_z\n"
        "2026-06-01 00:00:00.000,1,11,21\n"
        "2026-06-01 00:00:01.000,2,12,22\n",
        encoding="utf-8",
    )
    before = _snapshot(csv_path)
    status_path = root / "analysis_status.json"
    request_path = root / "run_request.json"
    _write_request(
        request_path,
        _request(
            project_root,
            data_root,
            status_path,
            "compiled_cleanup_default_off",
            {"doCachePrebuild": True},
            _base_config(data_root),
        ),
    )
    exit_code, stdout_path, stderr_path = _run_runner(
        runner, project_root, request_path, timeout_seconds=timeout_seconds
    )
    if exit_code != 0:
        raise RuntimeError(
            f"default-off cache run failed: exit={exit_code}; stdout={stdout_path}; stderr={stderr_path}"
        )
    status = _read_json(status_path)
    if str(status.get("status") or "").lower() != "completed":
        raise RuntimeError(f"default-off cache status is not completed: {status}")
    manifest_path = Path(str(status.get("manifest_path") or ""))
    if not manifest_path.is_absolute():
        manifest_path = (status_path.parent / manifest_path).resolve()
    manifest = _read_json(manifest_path)
    records = [
        item
        for item in _module_records(manifest)
        if str(item.get("key") or "").lower() == "cache_prebuild"
    ]
    if len(records) != 1 or str(records[0].get("status") or "").lower() != "ok":
        raise RuntimeError(f"default-off cache module did not complete: {records}")
    summary_path = _record_artifact_path(
        records[0], manifest_path, role="cache_prebuild_summary"
    )
    summary = _read_json(summary_path)
    if (
        summary.get("source_cleanup_enabled") is not False
        or int(summary.get("created_count", -1)) != 1
        or int(summary.get("failed_count", -1)) != 0
    ):
        raise RuntimeError(f"default-off cache summary is invalid: {summary_path}")
    _assert_snapshot_unchanged(csv_path, before)
    cache_path = csv_dir / "cache" / "POINT-DEFAULT.mat"
    meta_path = Path(str(cache_path) + ".meta.json")
    if not cache_path.is_file() or not meta_path.is_file():
        raise RuntimeError("default-off cache pair was not created")
    meta = _read_json(meta_path)
    if not str(meta.get("pair_id") or "") or int(meta.get("mat_bytes", -1)) != cache_path.stat().st_size:
        raise RuntimeError(f"cache pair metadata is not closed: {meta_path}")
    _assert_no_cleanup_side_effects(data_root)
    return {
        "ok": True,
        "runner_exit_code": exit_code,
        "analysis_status_path": str(status_path.resolve()),
        "manifest_path": str(manifest_path.resolve()),
        "cache_summary_path": str(summary_path.resolve()),
        "source_cleanup_enabled": False,
        "source_snapshot": before,
        "cache_path": str(cache_path.resolve()),
        "cache_meta_path": str(meta_path.resolve()),
    }


def _unsafe_policy_case(
    root: Path, runner: Path, project_root: Path, timeout_seconds: int
) -> dict[str, Any]:
    source_root = root / "source"
    data_root = root / "data"
    csv_dir = data_root / "data_jlj_2026-06-01" / "data" / "jlj" / "csv"
    source_root.mkdir(parents=True)
    csv_dir.mkdir(parents=True)
    csv_path = csv_dir / "POINT-UNSAFE.csv"
    csv_content = (
        "ts,value_x,value_y,value_z\n"
        "2026-06-01 00:00:00.000,1,11,21\n"
        "2026-06-01 00:00:01.000,2,12,22\n"
    )
    csv_path.write_text(csv_content, encoding="utf-8")
    zip_path = source_root / "data_jlj_2026-06-01.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("data/jlj/csv/POINT-UNSAFE.csv", csv_content)
    csv_before = _snapshot(csv_path)
    zip_before = _snapshot(zip_path)

    config = _base_config(data_root)
    config["preprocessing"] = {
        "unzip": {
            "source_root": str(source_root),
            "output_root": str(data_root),
            "max_workers": 1,
            "min_free_gib": 0,
            "min_free_fraction": 0,
            "delete_archives_after_verify": False,
            "overwrite_existing": False,
            "summary_file": str(root / "archive_extract_summary.json"),
        }
    }
    options = {
        "doUnzip": True,
        "doCachePrebuild": True,
        "doRemoveHeader": True,
        "cache_source_cleanup": {
            "enabled": True,
            "mode": "verified_extracted_csv",
            "commit_scope": "day",
            "recovery_policy": "verified_archive",
            "confirmation": CLEANUP_CONFIRMATION,
            "confirmed_at": "2026-07-16T00:00:00+08:00",
        },
    }
    status_path = root / "analysis_status.json"
    request_path = root / "run_request.json"
    _write_request(
        request_path,
        _request(
            project_root,
            data_root,
            status_path,
            "compiled_cleanup_unsafe_policy",
            options,
            config,
        ),
    )
    exit_code, stdout_path, stderr_path = _run_runner(
        runner, project_root, request_path, timeout_seconds=timeout_seconds
    )
    if exit_code == 0:
        raise RuntimeError("unsafe cleanup policy unexpectedly returned exit code 0")
    status = _read_json(status_path)
    if str(status.get("status") or "").lower() != "failed":
        raise RuntimeError(f"unsafe cleanup status is not failed: {status}")
    if status.get("error_id") != "BMS:CacheSourceCleanup:DedicatedTaskRequired":
        raise RuntimeError(f"unsafe cleanup returned the wrong error id: {status}")
    if "dedicated preprocessing task" not in str(status.get("message") or ""):
        raise RuntimeError(f"unsafe cleanup returned the wrong message: {status}")
    _assert_snapshot_unchanged(csv_path, csv_before)
    _assert_snapshot_unchanged(zip_path, zip_before)
    if (root / "archive_extract_summary.json").exists():
        raise RuntimeError("unsafe cleanup reached archive extraction")
    if list(data_root.rglob(".bms_extract_manifest.json")):
        raise RuntimeError("unsafe cleanup published an extraction manifest")
    if list(csv_dir.rglob("cache/*.mat")) or list(csv_dir.rglob("cache/*.meta.json")):
        raise RuntimeError("unsafe cleanup reached cache generation")
    if list(data_root.rglob("_staging")):
        raise RuntimeError("unsafe cleanup created an output staging directory")
    _assert_no_cleanup_side_effects(data_root)
    manifest_path = _find_failed_manifest(data_root)
    manifest = _read_json(manifest_path)
    if _module_records(manifest):
        raise RuntimeError("unsafe cleanup executed modules before policy rejection")
    return {
        "ok": True,
        "runner_exit_code": exit_code,
        "error_id": status["error_id"],
        "analysis_status_path": str(status_path.resolve()),
        "manifest_path": str(manifest_path.resolve()),
        "csv_snapshot": csv_before,
        "zip_snapshot": zip_before,
        "stdout_path": str(stdout_path.resolve()),
        "stderr_path": str(stderr_path.resolve()),
    }


def _enabled_cleanup_case(
    root: Path, runner: Path, project_root: Path, timeout_seconds: int
) -> dict[str, Any]:
    source_root = root / "source"
    data_root = root / "data"
    source_root.mkdir(parents=True)
    data_root.mkdir(parents=True)
    configured_content = (
        "ts,value_x,value_y,value_z\n"
        "2026-06-01 00:00:00.000,1,11,21\n"
        "2026-06-01 00:00:01.000,2,12,22\n"
    )
    unconfigured_content = (
        "ts,value_x,value_y,value_z\n"
        "2026-06-01 00:00:00.000,101,111,121\n"
        "2026-06-01 00:00:01.000,102,112,122\n"
    )
    zip_path = source_root / "data_jlj_2026-06-01.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr("data/jlj/csv/POINT-CLEANUP.csv", configured_content)
        archive.writestr("data/jlj/csv/UNCONFIGURED.csv", unconfigured_content)
    zip_before = _snapshot(zip_path)

    config = _base_config(data_root)
    config["points"] = {"temperature": ["POINT-CLEANUP"]}
    config["preprocessing"] = {
        "unzip": {
            "source_root": str(source_root),
            "output_root": str(data_root),
            "max_workers": 1,
            "min_free_gib": 0,
            "min_free_fraction": 0,
            "delete_archives_after_verify": False,
            "overwrite_existing": False,
            "summary_file": str(data_root / "run_logs" / "archive_extract_summary.json"),
        }
    }
    options = {
        "doUnzip": True,
        "doCachePrebuild": True,
        "cache_source_cleanup": {
            "enabled": True,
            "mode": "verified_extracted_csv",
            "commit_scope": "day",
            "recovery_policy": "verified_archive",
            "confirmation": CLEANUP_CONFIRMATION,
            "confirmed_at": "2026-07-16T00:00:00+08:00",
        },
    }
    status_path = root / "analysis_status.json"
    request_path = root / "run_request.json"
    _write_request(
        request_path,
        _request(
            project_root,
            data_root,
            status_path,
            "compiled_cleanup_enabled",
            options,
            config,
        ),
    )
    exit_code, stdout_path, stderr_path = _run_runner(
        runner, project_root, request_path, timeout_seconds=timeout_seconds
    )
    if exit_code != 0:
        raise RuntimeError(
            f"enabled cleanup run failed: exit={exit_code}; stdout={stdout_path}; stderr={stderr_path}"
        )
    status = _read_json(status_path)
    if str(status.get("status") or "").lower() != "completed":
        raise RuntimeError(f"enabled cleanup status is not completed: {status}")
    manifest_path = Path(str(status.get("manifest_path") or ""))
    if not manifest_path.is_absolute():
        manifest_path = (status_path.parent / manifest_path).resolve()
    manifest = _read_json(manifest_path)
    records = _module_records(manifest)
    by_key = {
        str(item.get("key") or "").lower(): item
        for item in records
        if str(item.get("key") or "").lower() in {"unzip", "cache_prebuild"}
    }
    if set(by_key) != {"unzip", "cache_prebuild"} or any(
        str(item.get("status") or "").lower() != "ok" for item in by_key.values()
    ):
        raise RuntimeError(f"enabled cleanup modules did not complete: {by_key}")
    combined_summary_path = _record_artifact_path(
        by_key["cache_prebuild"],
        manifest_path,
        role="daily_archive_cache_cleanup_summary",
    )
    combined = _read_json(combined_summary_path)
    raw_days = combined.get("days") or []
    days = [raw_days] if isinstance(raw_days, dict) else raw_days
    if (
        str(combined.get("status") or "").lower() != "ok"
        or int(combined.get("completed_days", -1)) != 1
        or not isinstance(days, list)
        or len(days) != 1
        or int(days[0].get("deleted_count", -1)) != 1
    ):
        raise RuntimeError(f"enabled cleanup summary is invalid: {combined_summary_path}")

    day_root = data_root / "data_jlj_2026-06-01"
    csv_dir = day_root / "data" / "jlj" / "csv"
    configured_path = csv_dir / "POINT-CLEANUP.csv"
    unconfigured_path = csv_dir / "UNCONFIGURED.csv"
    cache_path = csv_dir / "cache" / "POINT-CLEANUP.mat"
    meta_path = Path(str(cache_path) + ".meta.json")
    unconfigured_cache = csv_dir / "cache" / "UNCONFIGURED.mat"
    receipt_path = day_root / ".bms_cache_source_cleanup_receipt.json"
    extract_manifest_path = day_root / ".bms_extract_manifest.json"
    _assert_snapshot_unchanged(zip_path, zip_before)
    if configured_path.exists():
        raise RuntimeError("configured CSV was not removed after verified caching")
    if (
        not unconfigured_path.is_file()
        or unconfigured_path.read_bytes() != unconfigured_content.encode("utf-8")
    ):
        raise RuntimeError("unconfigured CSV was not preserved byte-for-byte")
    if unconfigured_cache.exists() or Path(str(unconfigured_cache) + ".meta.json").exists():
        raise RuntimeError("unconfigured CSV unexpectedly received a cleanup-authorized cache")
    if not cache_path.is_file() or not meta_path.is_file():
        raise RuntimeError("configured CSV cache pair is missing after cleanup")
    meta = _read_json(meta_path)
    if not str(meta.get("pair_id") or "") or int(meta.get("mat_bytes", -1)) != cache_path.stat().st_size:
        raise RuntimeError(f"enabled cleanup cache pair is not closed: {meta_path}")
    if not extract_manifest_path.is_file():
        raise RuntimeError("verified extraction manifest is missing")
    receipt = _read_json(receipt_path)
    archive_proof = receipt.get("archive_proof")
    if (
        str(receipt.get("status") or "").lower() != "committed"
        or int(receipt.get("deleted_count", -1)) != 1
        or not isinstance(archive_proof, dict)
        or archive_proof.get("source_archive_preserved") is not True
    ):
        raise RuntimeError(f"enabled cleanup receipt is not committed: {receipt_path}")
    _assert_no_transient_cleanup_artifacts(data_root)
    return {
        "ok": True,
        "runner_exit_code": exit_code,
        "analysis_status_path": str(status_path.resolve()),
        "manifest_path": str(manifest_path.resolve()),
        "combined_summary_path": str(combined_summary_path.resolve()),
        "source_archive_snapshot": zip_before,
        "configured_csv_deleted": True,
        "unconfigured_csv_preserved": True,
        "cache_path": str(cache_path.resolve()),
        "cache_meta_path": str(meta_path.resolve()),
        "receipt_path": str(receipt_path.resolve()),
        "receipt_status": str(receipt["status"]),
        "deleted_count": int(receipt["deleted_count"]),
        "extraction_manifest_path": str(extract_manifest_path.resolve()),
        "stdout_path": str(stdout_path.resolve()),
        "stderr_path": str(stderr_path.resolve()),
    }


def main() -> int:
    args = _parser().parse_args()
    project_root = args.project_root.resolve()
    output_root = args.output_root.resolve()
    runner = (
        args.runner.resolve()
        if args.runner is not None
        else project_root / "bin" / "BridgeAnalysisRunner" / "BridgeAnalysisRunner.exe"
    )
    if not runner.is_file():
        raise SystemExit(f"compiled analysis Runner is missing: {runner}")
    try:
        _prepare_output_root(output_root, replace=args.replace)
        for path in (
            output_root,
            output_root / "default_off",
            output_root / "unsafe_policy",
            output_root / "enabled_cleanup",
        ):
            _assert_inside(output_root, path)
        default_root = output_root / "default_off"
        unsafe_root = output_root / "unsafe_policy"
        enabled_root = output_root / "enabled_cleanup"
        default_root.mkdir()
        unsafe_root.mkdir()
        enabled_root.mkdir()
        default_result = _default_off_case(
            default_root, runner, project_root, args.timeout_seconds
        )
        unsafe_result = _unsafe_policy_case(
            unsafe_root, runner, project_root, args.timeout_seconds
        )
        enabled_result = _enabled_cleanup_case(
            enabled_root, runner, project_root, args.timeout_seconds
        )
        summary = {
            "ok": True,
            "marker": SMOKE_MARKER,
            "runner_path": str(runner),
            "default_off": default_result,
            "unsafe_policy": unsafe_result,
            "enabled_cleanup": enabled_result,
        }
        summary_path = output_root / "cleanup_policy_contract_summary.json"
        summary_path.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        raise SystemExit(f"compiled Runner cache cleanup policy smoke failed: {exc}") from exc
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
