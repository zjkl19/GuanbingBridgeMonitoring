from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate that a failed compiled analysis run returns a non-zero exit code"
    )
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--runner", type=Path, default=None)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=180)
    parser.add_argument("--replace", action="store_true")
    return parser


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"expected a JSON object: {path}")
    return payload


def _module_records(payload: dict[str, Any]) -> list[dict[str, Any]]:
    raw = payload.get("module_results") or []
    if isinstance(raw, dict):
        raw = [raw]
    if not isinstance(raw, list):
        raise RuntimeError("analysis manifest module_results must be an object or array")
    return [item for item in raw if isinstance(item, dict)]


def validate_failure_contract(status_path: Path, runner_exit_code: int) -> dict[str, Any]:
    """Validate the durable failure evidence left by the compiled Runner."""

    if runner_exit_code == 0:
        raise RuntimeError("compiled Runner returned exit code 0 for a failed analysis")
    if not status_path.is_file():
        raise RuntimeError(f"analysis status was not written: {status_path}")

    status = _read_json(status_path)
    if str(status.get("status") or "").lower() != "failed":
        raise RuntimeError(f"analysis status is not failed: {status}")
    raw_manifest_path = str(status.get("manifest_path") or "").strip()
    if not raw_manifest_path:
        raise RuntimeError("failed analysis status did not retain manifest_path")
    manifest_path = Path(raw_manifest_path)
    if not manifest_path.is_absolute():
        manifest_path = (status_path.parent / manifest_path).resolve()
    if not manifest_path.is_file():
        raise RuntimeError(f"failed analysis manifest does not exist: {manifest_path}")

    manifest = _read_json(manifest_path)
    if str(manifest.get("status") or "").lower() != "failed":
        raise RuntimeError(f"analysis manifest is not failed: {manifest_path}")
    records = _module_records(manifest)
    unzip_records = [
        item for item in records if str(item.get("key") or "").lower() == "unzip"
    ]
    if not unzip_records:
        raise RuntimeError("failed analysis manifest has no unzip module result")
    unzip_status = str(unzip_records[-1].get("status") or "").lower()
    if unzip_status not in {"fail", "failed"}:
        raise RuntimeError(f"unzip module did not fail: {unzip_records[-1]}")

    return {
        "ok": True,
        "runner_exit_code": int(runner_exit_code),
        "analysis_status_path": str(status_path.resolve()),
        "manifest_path": str(manifest_path.resolve()),
        "manifest_status": str(manifest["status"]),
        "failed_module_key": "unzip",
        "failed_module_status": unzip_status,
    }


def _failure_request(project_root: Path, data_root: Path, status_path: Path) -> dict[str, Any]:
    # This intentionally uses a real Jiulongjiang unzip request against an
    # existing but empty data root.  The unzip step must record NoArchives as a
    # module failure, retain the manifest, and then make the compiled process
    # fail rather than silently returning success.
    return {
        "project_root": str(project_root),
        "data_root": str(data_root),
        "start_date": "2026-05-01",
        "end_date": "2026-05-01",
        "config_path": "",
        "config_sha256": "",
        "stop_file": "",
        "async_status_file": str(status_path),
        "async_run_id": "compiled_failure_exit_contract",
        "options": {"doUnzip": True},
        "config": {
            "vendor": "jiulongjiang",
            "bridge": {"id": "jiulongjiang", "name": "Jiulongjiang"},
            "data_layout": "dated_folders",
            "notify": {"enabled": False},
            "preprocessing": {
                "unzip": {
                    "source_root": str(data_root),
                    "output_root": str(data_root),
                    "max_workers": 1,
                    "min_free_gib": 0,
                    "min_free_fraction": 0,
                    "summary_file": str(
                        data_root / "run_logs" / "archive_extract_summary.json"
                    ),
                }
            },
        },
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
    if output_root.exists():
        if not args.replace:
            raise SystemExit(f"output root already exists: {output_root}")
        shutil.rmtree(output_root)

    data_root = output_root / "empty_jiulongjiang_data"
    data_root.mkdir(parents=True)
    status_path = output_root / "analysis_status.json"
    request_path = output_root / "run_request.json"
    stdout_path = output_root / "runner_stdout.log"
    stderr_path = output_root / "runner_stderr.log"
    summary_path = output_root / "failure_exit_summary.json"
    request_path.write_text(
        json.dumps(
            _failure_request(project_root, data_root, status_path),
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        completed = subprocess.run(
            [str(runner), str(request_path)],
            cwd=project_root,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=False,
            timeout=max(1, int(args.timeout_seconds)),
            creationflags=creation_flags,
        )
    except subprocess.TimeoutExpired as exc:
        stdout_path.write_bytes(exc.stdout or b"")
        stderr_path.write_bytes(exc.stderr or b"")
        raise SystemExit(
            f"compiled analysis Runner failure-exit smoke timed out after {args.timeout_seconds}s"
        ) from exc
    stdout_path.write_bytes(completed.stdout)
    stderr_path.write_bytes(completed.stderr)

    try:
        summary = validate_failure_contract(status_path, completed.returncode)
    except RuntimeError as exc:
        raise SystemExit(
            f"compiled analysis Runner failure-exit contract failed: {exc}; "
            f"stdout={stdout_path}; stderr={stderr_path}"
        ) from exc
    summary.update(
        {
            "runner_path": str(runner),
            "request_path": str(request_path),
            "stdout_path": str(stdout_path),
            "stderr_path": str(stderr_path),
        }
    )
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
