from __future__ import annotations

import argparse
import ctypes
import json
import os
import shutil
import subprocess
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Iterable


MIB = 1024 * 1024
SMOKE_MARKER = "bridge_analysis_runner_manifest_resilience_smoke_v1"
DEFAULT_WARNING_COUNT = 1200
DEFAULT_WARNING_CHARS = 480


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate compiled Runner publication of a >1 MiB JSON manifest "
            "and its valid failed-manifest fallback"
        )
    )
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--runner", type=Path, default=None)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=300)
    parser.add_argument("--warning-count", type=int, default=DEFAULT_WARNING_COUNT)
    parser.add_argument("--warning-chars", type=int, default=DEFAULT_WARNING_CHARS)
    parser.add_argument("--replace", action="store_true")
    return parser


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"expected a JSON object: {path}")
    return payload


def _json_records(payload: dict[str, Any], field: str) -> list[dict[str, Any]]:
    raw = payload.get(field) or []
    if isinstance(raw, dict):
        raw = [raw]
    if not isinstance(raw, list):
        raise RuntimeError(f"{field} must be an object or array")
    return [item for item in raw if isinstance(item, dict)]


def _resolve_manifest_path(status: dict[str, Any], status_path: Path) -> Path:
    raw = str(status.get("manifest_path") or "").strip()
    if not raw:
        raise RuntimeError(f"analysis status did not retain manifest_path: {status_path}")
    path = Path(raw)
    if not path.is_absolute():
        path = (status_path.parent / path).resolve()
    if not path.is_file():
        raise RuntimeError(f"analysis manifest does not exist: {path}")
    return path


def _assert_no_json_temps(root: Path) -> None:
    leftovers = sorted(root.rglob("*.json.tmp"))
    if leftovers:
        raise RuntimeError(
            "temporary JSON files were not cleaned up: "
            + "; ".join(str(path) for path in leftovers)
        )


def _prepare_output_root(output_root: Path, *, replace: bool) -> None:
    marker = output_root / ".manifest_resilience_smoke_root.json"
    if output_root.exists():
        if not replace:
            raise RuntimeError(f"output root already exists: {output_root}")
        if not marker.is_file():
            raise RuntimeError(f"refusing to replace an unmarked output root: {output_root}")
        payload = _read_json(marker)
        if (
            payload.get("marker") != SMOKE_MARKER
            or Path(str(payload.get("output_root") or "")).resolve()
            != output_root.resolve()
        ):
            raise RuntimeError(f"invalid manifest-resilience smoke marker: {marker}")
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True)
    marker.write_text(
        json.dumps(
            {"marker": SMOKE_MARKER, "output_root": str(output_root.resolve())},
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )


def _warning_payloads(count: int, chars: int) -> list[str]:
    if count < 1:
        raise ValueError("warning count must be positive")
    if chars < 80:
        raise ValueError("warning length must be at least 80 characters")
    values: list[str] = []
    for index in range(count):
        prefix = f"compiled-runner-large-json-{index:05d}:"
        values.append(prefix + ("x" * max(0, chars - len(prefix))))
    return values


def _base_config(warnings: Iterable[str] = ()) -> dict[str, Any]:
    # Use a known bridge identity but keep every analysis module disabled.  The
    # smoke exercises the ordinary analysis request path without touching real
    # data or introducing a production-only diagnostic request type.
    return {
        "config_schema_version": 1,
        "vendor": "donghua",
        "bridge": {"id": "guanbing", "name": "Manifest resilience smoke"},
        "data_layout": "dated_folders",
        "defaults": {},
        "subfolders": {},
        "file_patterns": {},
        "points": {},
        "plot_styles": {},
        "per_point": {},
        "post_filter_thresholds": {},
        "plot_common": {
            "append_timestamp": False,
            "gap_mode": "connect",
            "dynamic_raw_sampling_mode": "capped",
        },
        "reporting": {},
        "gui": {"show_warnings": False},
        "wim": {},
        "notify": {"enabled": False},
        "run_health": {"enabled": False},
        "stats_inventory": {"enabled": False},
        "data_index": {"enabled": False},
        "warnings": list(warnings),
    }


def build_analysis_request(
    project_root: Path,
    data_root: Path,
    status_path: Path,
    *,
    async_run_id: str,
    warnings: Iterable[str] = (),
) -> dict[str, Any]:
    return {
        "request_type": "analysis",
        "project_root": str(project_root.resolve()),
        "data_root": str(data_root.resolve()),
        "start_date": "2026-01-01",
        "end_date": "2026-01-01",
        "config_path": "",
        "config_sha256": "",
        "stop_file": "",
        "async_status_file": str(status_path.resolve()),
        "async_run_id": async_run_id,
        "options": {},
        "config": _base_config(warnings),
    }


def write_request(path: Path, request: dict[str, Any]) -> int:
    encoded = (
        json.dumps(request, ensure_ascii=False, separators=(",", ":")) + "\n"
    ).encode("utf-8")
    path.write_bytes(encoded)
    return len(encoded)


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
            f"compiled Runner timed out after {timeout_seconds}s: {request_path}"
        ) from exc
    stdout_path.write_bytes(completed.stdout)
    stderr_path.write_bytes(completed.stderr)
    return int(completed.returncode), stdout_path, stderr_path


def validate_large_manifest_contract(
    status_path: Path,
    *,
    runner_exit_code: int,
    warning_count: int,
    minimum_manifest_bytes: int = MIB + 1,
) -> dict[str, Any]:
    if runner_exit_code != 0:
        raise RuntimeError(
            f"large-manifest Runner returned non-zero exit code {runner_exit_code}"
        )
    status = _read_json(status_path)
    if str(status.get("status") or "").lower() != "completed":
        raise RuntimeError(f"large-manifest async status is not completed: {status}")
    manifest_path = _resolve_manifest_path(status, status_path)
    manifest_bytes = manifest_path.stat().st_size
    if manifest_bytes < minimum_manifest_bytes:
        raise RuntimeError(
            "compiled manifest did not cross the validation boundary: "
            f"{manifest_bytes} < {minimum_manifest_bytes} bytes"
        )
    manifest = _read_json(manifest_path)
    if str(manifest.get("status") or "").lower() != "ok":
        raise RuntimeError(f"large compiled manifest is not successful: {manifest_path}")
    if str(manifest.get("manifest_type") or "") != "analysis_run":
        raise RuntimeError(f"unexpected large manifest type: {manifest.get('manifest_type')}")

    result_records = _json_records(manifest, "module_results")
    log_records = _json_records(manifest, "module_logs")
    result_warning_count = sum(
        1
        for item in result_records
        if str(item.get("key") or "") == "config"
        and str(item.get("status") or "").lower() == "warn"
    )
    log_warning_count = sum(
        1
        for item in log_records
        if str(item.get("key") or "") == "config"
        and str(item.get("status") or "").lower() == "warn"
    )
    if result_warning_count != warning_count or log_warning_count != warning_count:
        raise RuntimeError(
            "large-manifest warning records are incomplete: "
            f"results={result_warning_count}, logs={log_warning_count}, expected={warning_count}"
        )
    _assert_no_json_temps(status_path.parent.parent)
    return {
        "ok": True,
        "runner_exit_code": runner_exit_code,
        "analysis_status": str(status["status"]),
        "analysis_status_path": str(status_path.resolve()),
        "manifest_path": str(manifest_path.resolve()),
        "manifest_status": str(manifest["status"]),
        "manifest_type": str(manifest["manifest_type"]),
        "manifest_bytes": manifest_bytes,
        "minimum_manifest_bytes": minimum_manifest_bytes,
        "warning_count": warning_count,
        "module_result_warning_count": result_warning_count,
        "module_log_warning_count": log_warning_count,
        "temporary_json_file_count": 0,
    }


def candidate_manifest_paths(
    log_dir: Path,
    now: datetime,
    *,
    past_seconds: int = 30,
    future_seconds: int = 360,
) -> list[Path]:
    if past_seconds < 0 or future_seconds < 0:
        raise ValueError("manifest lock window must be non-negative")
    return [
        log_dir / f"analysis_manifest_{(now + timedelta(seconds=offset)):%Y%m%d_%H%M%S}.json"
        for offset in range(-past_seconds, future_seconds + 1)
    ]


class WindowsNoWriteDeleteLocks:
    """Hold destination files without write/delete sharing during one smoke."""

    GENERIC_READ = 0x80000000
    FILE_SHARE_READ = 0x00000001
    OPEN_ALWAYS = 4
    FILE_ATTRIBUTE_NORMAL = 0x00000080
    INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

    def __init__(self, paths: Iterable[Path]) -> None:
        self.paths = [Path(path).resolve() for path in paths]
        self._handles: list[int] = []

    def __enter__(self) -> "WindowsNoWriteDeleteLocks":
        if os.name != "nt":
            raise RuntimeError("failed-manifest lock smoke requires Windows")
        from ctypes import wintypes

        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        create_file = kernel32.CreateFileW
        create_file.argtypes = [
            wintypes.LPCWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.LPVOID,
            wintypes.DWORD,
            wintypes.DWORD,
            wintypes.HANDLE,
        ]
        create_file.restype = wintypes.HANDLE
        self._close_handle = kernel32.CloseHandle
        self._close_handle.argtypes = [wintypes.HANDLE]
        self._close_handle.restype = wintypes.BOOL

        for path in self.paths:
            path.parent.mkdir(parents=True, exist_ok=True)
            handle = create_file(
                str(path),
                self.GENERIC_READ,
                self.FILE_SHARE_READ,
                None,
                self.OPEN_ALWAYS,
                self.FILE_ATTRIBUTE_NORMAL,
                None,
            )
            value = int(handle) if handle is not None else self.INVALID_HANDLE_VALUE
            if value == self.INVALID_HANDLE_VALUE:
                error_code = ctypes.get_last_error()
                self.close()
                raise OSError(error_code, f"unable to lock manifest destination: {path}")
            self._handles.append(value)
        return self

    def close(self) -> None:
        close_handle = getattr(self, "_close_handle", None)
        if close_handle is not None:
            for handle in reversed(self._handles):
                close_handle(handle)
        self._handles.clear()

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> None:
        self.close()


def validate_write_failure_contract(
    status_path: Path,
    *,
    runner_exit_code: int,
    locked_candidates: Iterable[Path] = (),
) -> dict[str, Any]:
    if runner_exit_code == 0:
        raise RuntimeError("compiled Runner returned exit code 0 for fallback manifest")
    status = _read_json(status_path)
    if str(status.get("status") or "").lower() != "failed":
        raise RuntimeError(f"fallback async status is not failed: {status}")
    manifest_path = _resolve_manifest_path(status, status_path)
    if not manifest_path.name.endswith("_write_failure.json"):
        raise RuntimeError(f"fallback manifest has an unexpected name: {manifest_path}")
    manifest = _read_json(manifest_path)
    expected = {
        "status": "failed",
        "manifest_type": "analysis_run_write_failure",
        "requested_status": "ok",
        "error_type": "manifest_write_error",
        "write_error_identifier": "bms:Logger:JsonPublishFailed",
    }
    for field, value in expected.items():
        if str(manifest.get(field) or "") != value:
            raise RuntimeError(
                f"fallback manifest {field} mismatch: {manifest.get(field)!r} != {value!r}"
            )
    records = _json_records(manifest, "module_results")
    for record in records:
        artifacts = record.get("artifacts") or []
        if artifacts:
            raise RuntimeError("fallback manifest retained bulky module artifacts")
        if int(record.get("artifact_count") or 0) != 0:
            raise RuntimeError("fallback manifest retained a non-zero artifact count")

    blocked_target = manifest_path.with_name(
        manifest_path.name.replace("_write_failure.json", ".json")
    ).resolve()
    candidate_set = {Path(path).resolve() for path in locked_candidates}
    if candidate_set and blocked_target not in candidate_set:
        raise RuntimeError(
            f"fallback did not correspond to a locked manifest destination: {blocked_target}"
        )
    _assert_no_json_temps(status_path.parent.parent)
    return {
        "ok": True,
        "runner_exit_code": runner_exit_code,
        "analysis_status": str(status["status"]),
        "analysis_status_path": str(status_path.resolve()),
        "manifest_path": str(manifest_path.resolve()),
        "manifest_status": str(manifest["status"]),
        "manifest_type": str(manifest["manifest_type"]),
        "requested_status": str(manifest["requested_status"]),
        "write_error_identifier": str(manifest["write_error_identifier"]),
        "blocked_manifest_path": str(blocked_target),
        "module_result_count": len(records),
        "temporary_json_file_count": 0,
    }


def _remove_lock_placeholders(paths: Iterable[Path]) -> None:
    for path in paths:
        try:
            if path.is_file() and path.stat().st_size == 0:
                path.unlink()
        except FileNotFoundError:
            continue


def _run_large_manifest_case(
    runner: Path,
    project_root: Path,
    case_root: Path,
    *,
    timeout_seconds: int,
    warning_count: int,
    warning_chars: int,
) -> dict[str, Any]:
    data_root = case_root / "data"
    data_root.mkdir(parents=True)
    status_path = case_root / "analysis_status.json"
    request_path = case_root / "run_request.json"
    warnings = _warning_payloads(warning_count, warning_chars)
    request = build_analysis_request(
        project_root,
        data_root,
        status_path,
        async_run_id="compiled_manifest_large_json",
        warnings=warnings,
    )
    request_bytes = write_request(request_path, request)
    if request_bytes >= MIB:
        raise RuntimeError(
            "large-manifest request itself crossed 1 MiB; the smoke must isolate final publication: "
            f"{request_bytes} bytes"
        )
    exit_code, stdout_path, stderr_path = _run_runner(
        runner, project_root, request_path, timeout_seconds=timeout_seconds
    )
    result = validate_large_manifest_contract(
        status_path,
        runner_exit_code=exit_code,
        warning_count=warning_count,
    )
    result.update(
        {
            "request_path": str(request_path.resolve()),
            "request_bytes": request_bytes,
            "stdout_path": str(stdout_path.resolve()),
            "stderr_path": str(stderr_path.resolve()),
        }
    )
    return result


def _run_write_failure_case(
    runner: Path,
    project_root: Path,
    case_root: Path,
    *,
    timeout_seconds: int,
) -> dict[str, Any]:
    data_root = case_root / "data"
    data_root.mkdir(parents=True)
    status_path = case_root / "analysis_status.json"
    request_path = case_root / "run_request.json"
    request = build_analysis_request(
        project_root,
        data_root,
        status_path,
        async_run_id="compiled_manifest_write_failure",
    )
    write_request(request_path, request)
    candidates = candidate_manifest_paths(data_root / "run_logs", datetime.now())
    try:
        with WindowsNoWriteDeleteLocks(candidates):
            exit_code, stdout_path, stderr_path = _run_runner(
                runner, project_root, request_path, timeout_seconds=timeout_seconds
            )
    finally:
        _remove_lock_placeholders(candidates)
    result = validate_write_failure_contract(
        status_path,
        runner_exit_code=exit_code,
        locked_candidates=candidates,
    )
    result.update(
        {
            "request_path": str(request_path.resolve()),
            "stdout_path": str(stdout_path.resolve()),
            "stderr_path": str(stderr_path.resolve()),
            "locked_candidate_count": len(candidates),
        }
    )
    return result


def main() -> int:
    args = _parser().parse_args()
    if os.name != "nt":
        raise SystemExit("compiled manifest-resilience smoke requires Windows")
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
        large = _run_large_manifest_case(
            runner,
            project_root,
            output_root / "large_manifest",
            timeout_seconds=args.timeout_seconds,
            warning_count=args.warning_count,
            warning_chars=args.warning_chars,
        )
        fallback = _run_write_failure_case(
            runner,
            project_root,
            output_root / "write_failure_fallback",
            timeout_seconds=args.timeout_seconds,
        )
        summary = {
            "ok": True,
            "runner_path": str(runner),
            "large_manifest": large,
            "write_failure_fallback": fallback,
        }
        summary_path = output_root / "manifest_resilience_contract_summary.json"
        summary_path.write_text(
            json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0
    except (OSError, RuntimeError, ValueError) as exc:
        raise SystemExit(f"compiled manifest-resilience smoke failed: {exc}") from exc


if __name__ == "__main__":
    raise SystemExit(main())
