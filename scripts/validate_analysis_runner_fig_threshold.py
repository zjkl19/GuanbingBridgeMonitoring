from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any


_MARKER_NAME = ".analysis_runner_fig_threshold_smoke_root.json"
_SUMMARY_NAME = "fig_threshold_contract_summary.json"


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Validate scripted band/lower-box/upper-box FIG threshold requests "
            "through the compiled BridgeAnalysisRunner"
        )
    )
    parser.add_argument("--project-root", type=Path, default=Path.cwd())
    parser.add_argument("--runner", type=Path, default=None)
    parser.add_argument("--matlab", default="matlab")
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=300)
    parser.add_argument("--replace", action="store_true")
    return parser


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise RuntimeError(f"expected a JSON object: {path}")
    return payload


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _canonical_text(path: Path) -> str:
    return os.path.normcase(str(path.resolve()))


def _prepare_output_root(output_root: Path, *, replace: bool) -> None:
    marker = output_root / _MARKER_NAME
    if output_root.exists():
        if not replace:
            raise RuntimeError(f"output root already exists: {output_root}")
        if not marker.is_file():
            raise RuntimeError(
                "refusing to replace an unmarked FIG-threshold smoke root: "
                f"{output_root}"
            )
        shutil.rmtree(output_root)
    output_root.mkdir(parents=True)
    _write_json(
        output_root / _MARKER_NAME,
        {
            "schema_version": 1,
            "artifact_type": "analysis_runner_fig_threshold_smoke_root",
        },
    )


def _matlab_quote(path: Path) -> str:
    return str(path.resolve()).replace("'", "''")


def _create_fig_fixture(
    matlab: str,
    output_root: Path,
    *,
    timeout_seconds: int,
) -> Path:
    fig_path = output_root / "synthetic_threshold_source.fig"
    fixture_script = output_root / "create_fig_threshold_fixture.m"
    stdout_path = output_root / "fixture_matlab_stdout.log"
    stderr_path = output_root / "fixture_matlab_stderr.log"
    fixture_script.write_text(
        "\n".join(
            (
                "fig = figure('Visible', 'off');",
                "cleanupFig = onCleanup(@() close(fig));",
                "ax = axes('Parent', fig);",
                "x = datenum(datetime(2026, 5, 1) + days(0:4));",
                "plot(ax, x, [-5 -2 0 3 8], 'DisplayName', 'SOURCE-1', 'LineWidth', 1.0);",
                "title(ax, 'Synthetic threshold source');",
                "xlabel(ax, 'Time');",
                "ylabel(ax, 'Value');",
                f"savefig(fig, '{_matlab_quote(fig_path)}');",
                "clear cleanupFig;",
            )
        )
        + "\n",
        encoding="utf-8",
    )
    command = [matlab, "-batch", f"run('{_matlab_quote(fixture_script)}')"]
    creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        completed = subprocess.run(
            command,
            cwd=output_root,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=False,
            timeout=max(1, timeout_seconds),
            creationflags=creation_flags,
        )
    except subprocess.TimeoutExpired as exc:
        stdout_path.write_bytes(exc.stdout or b"")
        stderr_path.write_bytes(exc.stderr or b"")
        raise RuntimeError(
            f"MATLAB FIG fixture generation timed out after {timeout_seconds}s"
        ) from exc
    stdout_path.write_bytes(completed.stdout)
    stderr_path.write_bytes(completed.stderr)
    if completed.returncode != 0 or not fig_path.is_file():
        raise RuntimeError(
            "MATLAB failed to generate the FIG fixture: "
            f"exit={completed.returncode}; stdout={stdout_path}; stderr={stderr_path}"
        )
    return fig_path


def _visibility_dispatch_contract(project_root: Path) -> dict[str, Any]:
    source_path = project_root / "run_request_cli.m"
    source = source_path.read_text(encoding="utf-8-sig")
    fragments = (
        "if strcmp(requestType, 'fig_threshold_interaction')",
        "originalFigureVisible = char(string(get(groot, 'DefaultFigureVisible')))",
        "set(groot, 'DefaultFigureVisible', 'on')",
        "@() set(groot, 'DefaultFigureVisible', originalFigureVisible)",
        "bms.app.FigThresholdRequestRunner.runFile(requestPath)",
    )
    missing = [fragment for fragment in fragments if fragment not in source]
    if missing:
        raise RuntimeError(
            "run_request_cli.m is missing the FIG visibility/dispatch contract: "
            + "; ".join(missing)
        )
    return {
        "ok": True,
        "request_type": "fig_threshold_interaction",
        "default_figure_visible_forced_on": True,
        "default_figure_visible_restore_guard": True,
        "compiled_dispatch_present": True,
        "source_path": str(source_path.resolve()),
        "source_sha256": _sha256(source_path),
    }


def _request_payload(
    operation: str,
    operation_root: Path,
    fig_path: Path,
    fig_sha256: str,
    fig_bytes: int,
    scripted_selection: dict[str, Any],
) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "request_type": "fig_threshold_interaction",
        "request_id": f"compiled_fig_threshold_{operation}",
        "operation": operation,
        "fig_path": str(fig_path.resolve()),
        "fig_sha256": fig_sha256,
        "fig_size_bytes": fig_bytes,
        "status_path": str((operation_root / "status.json").resolve()),
        "result_path": str((operation_root / "result.json").resolve()),
        "target_module": "acceleration",
        "target_point": "TARGET-1",
        "scripted_selection": scripted_selection,
    }


def _expected_cases() -> dict[str, dict[str, Any]]:
    common_box = {
        "axis_index": 1,
        "curve_index": 1,
        "selection_start": "2026-05-01 00:00:00",
        "selection_end": "2026-05-05 00:00:00",
    }
    return {
        "band": {
            "selection": {
                "axis_index": 1,
                "curve_index": 1,
                "lower": -2.5,
                "upper": 4.5,
                "t_range_start": "2026-05-02 00:00:00",
                "t_range_end": "2026-05-04 00:00:00",
            },
            "candidate": {
                "lower": -2.5,
                "upper": 4.5,
                "t_range_start": "2026-05-02 00:00:00",
                "t_range_end": "2026-05-04 00:00:00",
            },
        },
        "box_lower": {
            "selection": {
                **common_box,
                "selection_min": -10,
                "selection_max": 0,
            },
            "candidate": {
                "side": "lower",
                "value": 0,
                "selected_sample_count": 3,
                "selection_start": "2026-05-01 00:00:00",
                "selection_end": "2026-05-05 00:00:00",
            },
        },
        "box_upper": {
            "selection": {
                **common_box,
                "selection_min": 0,
                "selection_max": 10,
            },
            "candidate": {
                "side": "upper",
                "value": 0,
                "selected_sample_count": 3,
                "selection_start": "2026-05-01 00:00:00",
                "selection_end": "2026-05-05 00:00:00",
            },
        },
    }


def validate_operation(
    *,
    operation: str,
    runner_exit_code: int,
    status_path: Path,
    result_path: Path,
    request: dict[str, Any],
    expected_candidate: dict[str, Any],
    fig_sha256: str,
    fig_bytes: int,
) -> dict[str, Any]:
    if runner_exit_code != 0:
        raise RuntimeError(f"{operation} Runner exit code is {runner_exit_code}")
    if not status_path.is_file() or not result_path.is_file():
        raise RuntimeError(f"{operation} did not publish status and result JSON")
    status = _read_json(status_path)
    result = _read_json(result_path)
    checks = {
        "analysis_status_completed": status.get("status") == "completed",
        "status_result_ok": status.get("result_status") == "ok",
        "request_identity_matches": (
            status.get("request_id") == request["request_id"]
            and result.get("request_id") == request["request_id"]
            and status.get("operation") == operation
            and result.get("operation") == operation
        ),
        "result_contract_matches": (
            result.get("schema_version") == 1
            and result.get("artifact_type") == "fig_threshold_result"
            and result.get("request_type") == "fig_threshold_interaction"
            and result.get("status") == "ok"
            and result.get("target_module") == "acceleration"
            and result.get("target_point") == "TARGET-1"
        ),
        "candidate_matches": result.get("candidate") == expected_candidate,
        "source_curve_matches": result.get("source_curve")
        == {
            "axis_title": "Synthetic threshold source",
            "curve_label": "SOURCE-1",
            "sample_count": 5,
        },
        "source_hash_matches": str(
            (result.get("source_fig") or {}).get("sha256") or ""
        ).lower()
        == fig_sha256,
        "source_size_matches": (result.get("source_fig") or {}).get("size")
        == fig_bytes,
        "source_path_matches": _canonical_text(
            Path(str((result.get("source_fig") or {}).get("path") or ""))
        )
        == _canonical_text(Path(str(request["fig_path"]))),
        "source_mtime_recorded": bool(
            str((result.get("source_fig") or {}).get("mtime") or "").strip()
        ),
    }
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        raise RuntimeError(f"{operation} contract checks failed: {', '.join(failed)}")
    return {
        "ok": True,
        "runner_exit_code": runner_exit_code,
        **checks,
        "status_path": str(status_path.resolve()),
        "result_path": str(result_path.resolve()),
    }


def _run_operation(
    runner: Path,
    project_root: Path,
    output_root: Path,
    operation: str,
    case: dict[str, Any],
    fig_path: Path,
    fig_sha256: str,
    fig_bytes: int,
    *,
    timeout_seconds: int,
) -> dict[str, Any]:
    operation_root = output_root / operation
    operation_root.mkdir()
    request = _request_payload(
        operation,
        operation_root,
        fig_path,
        fig_sha256,
        fig_bytes,
        case["selection"],
    )
    request_path = operation_root / "request.json"
    status_path = Path(request["status_path"])
    result_path = Path(request["result_path"])
    stdout_path = operation_root / "runner_stdout.log"
    stderr_path = operation_root / "runner_stderr.log"
    _write_json(request_path, request)
    creation_flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    started = time.monotonic()
    try:
        completed = subprocess.run(
            [str(runner), str(request_path)],
            cwd=project_root,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            check=False,
            timeout=max(1, timeout_seconds),
            creationflags=creation_flags,
        )
    except subprocess.TimeoutExpired as exc:
        stdout_path.write_bytes(exc.stdout or b"")
        stderr_path.write_bytes(exc.stderr or b"")
        raise RuntimeError(
            f"compiled Runner {operation} timed out after {timeout_seconds}s"
        ) from exc
    stdout_path.write_bytes(completed.stdout)
    stderr_path.write_bytes(completed.stderr)
    evidence = validate_operation(
        operation=operation,
        runner_exit_code=completed.returncode,
        status_path=status_path,
        result_path=result_path,
        request=request,
        expected_candidate=case["candidate"],
        fig_sha256=fig_sha256,
        fig_bytes=fig_bytes,
    )
    evidence.update(
        {
            "request_path": str(request_path.resolve()),
            "stdout_path": str(stdout_path.resolve()),
            "stderr_path": str(stderr_path.resolve()),
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "scripted_no_manual_ui": True,
        }
    )
    return evidence


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
        visibility = _visibility_dispatch_contract(project_root)
        fig_path = _create_fig_fixture(
            args.matlab,
            output_root,
            timeout_seconds=max(1, int(args.timeout_seconds)),
        )
        fig_sha256_before = _sha256(fig_path)
        fig_stat_before = fig_path.stat()
        operations: dict[str, dict[str, Any]] = {}
        for operation, case in _expected_cases().items():
            operations[operation] = _run_operation(
                runner,
                project_root,
                output_root,
                operation,
                case,
                fig_path,
                fig_sha256_before,
                fig_stat_before.st_size,
                timeout_seconds=max(1, int(args.timeout_seconds)),
            )
        fig_sha256_after = _sha256(fig_path)
        fig_stat_after = fig_path.stat()
        source_fig_unchanged = (
            fig_sha256_after == fig_sha256_before
            and fig_stat_after.st_size == fig_stat_before.st_size
            and fig_stat_after.st_mtime_ns == fig_stat_before.st_mtime_ns
        )
        if not source_fig_unchanged:
            raise RuntimeError("compiled FIG interactions changed the source FIG")
        summary = {
            "schema_version": 1,
            "artifact_type": "analysis_runner_fig_threshold_smoke",
            "ok": True,
            "runner_path": str(runner),
            "source_fig_path": str(fig_path.resolve()),
            "source_fig_sha256": fig_sha256_before,
            "source_fig_bytes": fig_stat_before.st_size,
            "source_fig_unchanged": True,
            "scripted_no_manual_ui": True,
            "compiled_operation_count": len(operations),
            "visibility_dispatch": visibility,
            "operations": operations,
        }
        _write_json(output_root / _SUMMARY_NAME, summary)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        raise SystemExit(f"compiled FIG-threshold contract smoke failed: {exc}") from exc
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
