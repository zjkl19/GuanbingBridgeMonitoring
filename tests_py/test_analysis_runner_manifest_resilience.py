from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path

import pytest

from scripts.validate_analysis_runner_manifest_resilience import (
    MIB,
    WindowsNoWriteDeleteLocks,
    _prepare_output_root,
    _warning_payloads,
    build_analysis_request,
    candidate_manifest_paths,
    validate_large_manifest_contract,
    validate_write_failure_contract,
    write_request,
)


def _write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False) + "\n", encoding="utf-8")


def _status(path: Path, status: str, manifest_path: Path) -> None:
    _write_json(path, {"status": status, "manifest_path": str(manifest_path)})


def test_large_request_is_below_boundary_while_preserving_warning_payloads(
    tmp_path: Path,
) -> None:
    warnings = _warning_payloads(1200, 480)
    request = build_analysis_request(
        tmp_path,
        tmp_path / "data",
        tmp_path / "analysis_status.json",
        async_run_id="unit_large_manifest",
        warnings=warnings,
    )
    request_path = tmp_path / "run_request.json"
    request_bytes = write_request(request_path, request)

    assert request_bytes < MIB
    assert len(request["config"]["warnings"]) == 1200
    assert len(set(request["config"]["warnings"])) == 1200
    assert all(len(value) == 480 for value in request["config"]["warnings"])
    assert request["options"] == {}


def test_large_manifest_contract_accepts_valid_json_above_one_mib(
    tmp_path: Path,
) -> None:
    case_root = tmp_path / "large_case"
    status_path = case_root / "analysis_status.json"
    manifest_path = case_root / "data" / "run_logs" / "analysis_manifest_unit.json"
    warning_records = [
        {"key": "config", "status": "warn", "message": f"warning-{index}"}
        for index in range(2)
    ]
    _write_json(
        manifest_path,
        {
            "status": "ok",
            "manifest_type": "analysis_run",
            "module_results": warning_records,
            "module_logs": warning_records,
            "padding": "x" * MIB,
        },
    )
    _status(status_path, "completed", manifest_path)

    result = validate_large_manifest_contract(
        status_path,
        runner_exit_code=0,
        warning_count=2,
    )

    assert result["ok"] is True
    assert result["manifest_bytes"] > MIB
    assert result["module_result_warning_count"] == 2
    assert result["module_log_warning_count"] == 2


def test_large_manifest_contract_rejects_truncated_json(tmp_path: Path) -> None:
    case_root = tmp_path / "truncated_case"
    status_path = case_root / "analysis_status.json"
    manifest_path = case_root / "data" / "run_logs" / "analysis_manifest_unit.json"
    manifest_path.parent.mkdir(parents=True)
    manifest_path.write_text('{"status":"ok","padding":"' + ("x" * MIB), encoding="utf-8")
    _status(status_path, "completed", manifest_path)

    with pytest.raises(json.JSONDecodeError):
        validate_large_manifest_contract(
            status_path,
            runner_exit_code=0,
            warning_count=0,
        )


def test_write_failure_contract_requires_stripped_valid_fallback(
    tmp_path: Path,
) -> None:
    case_root = tmp_path / "fallback_case"
    status_path = case_root / "analysis_status.json"
    fallback_path = (
        case_root
        / "data"
        / "run_logs"
        / "analysis_manifest_20260716_010203_write_failure.json"
    )
    blocked_path = fallback_path.with_name("analysis_manifest_20260716_010203.json")
    _write_json(
        fallback_path,
        {
            "status": "failed",
            "manifest_type": "analysis_run_write_failure",
            "requested_status": "ok",
            "error_type": "manifest_write_error",
            "write_error_identifier": "bms:Logger:JsonPublishFailed",
            "module_results": [
                {"key": "config", "status": "warn", "artifacts": [], "artifact_count": 0}
            ],
        },
    )
    _status(status_path, "failed", fallback_path)

    result = validate_write_failure_contract(
        status_path,
        runner_exit_code=1,
        locked_candidates=[blocked_path],
    )

    assert result["ok"] is True
    assert result["blocked_manifest_path"] == str(blocked_path.resolve())
    assert result["write_error_identifier"] == "bms:Logger:JsonPublishFailed"


def test_write_failure_contract_rejects_retained_artifacts(tmp_path: Path) -> None:
    case_root = tmp_path / "fallback_artifact_case"
    status_path = case_root / "analysis_status.json"
    fallback_path = case_root / "analysis_manifest_unit_write_failure.json"
    _write_json(
        fallback_path,
        {
            "status": "failed",
            "manifest_type": "analysis_run_write_failure",
            "requested_status": "ok",
            "error_type": "manifest_write_error",
            "write_error_identifier": "bms:Logger:JsonPublishFailed",
            "module_results": [
                {
                    "key": "temperature",
                    "status": "ok",
                    "artifacts": [{"path": "too-large.bin"}],
                    "artifact_count": 1,
                }
            ],
        },
    )
    _status(status_path, "failed", fallback_path)

    with pytest.raises(RuntimeError, match="retained bulky module artifacts"):
        validate_write_failure_contract(status_path, runner_exit_code=1)


def test_manifest_lock_candidates_cover_current_second(tmp_path: Path) -> None:
    now = datetime(2026, 7, 16, 1, 2, 3)
    paths = candidate_manifest_paths(
        tmp_path,
        now,
        past_seconds=2,
        future_seconds=3,
    )

    assert len(paths) == 6
    assert tmp_path / "analysis_manifest_20260716_010201.json" == paths[0]
    assert tmp_path / "analysis_manifest_20260716_010203.json" in paths
    assert tmp_path / "analysis_manifest_20260716_010206.json" == paths[-1]


@pytest.mark.skipif(os.name != "nt", reason="Win32 sharing contract")
def test_windows_lock_blocks_destination_replacement(tmp_path: Path) -> None:
    target = tmp_path / "analysis_manifest_20260716_010203.json"
    source = tmp_path / "complete.json.tmp"
    source.write_text('{"status":"ok"}', encoding="utf-8")

    with WindowsNoWriteDeleteLocks([target]):
        with pytest.raises(PermissionError):
            os.replace(source, target)

    os.replace(source, target)
    assert json.loads(target.read_text(encoding="utf-8"))["status"] == "ok"


def test_marked_output_replacement_is_fail_closed(tmp_path: Path) -> None:
    unmarked = tmp_path / "unmarked"
    unmarked.mkdir()
    with pytest.raises(RuntimeError, match="unmarked output root"):
        _prepare_output_root(unmarked, replace=True)

    marked = tmp_path / "marked"
    _prepare_output_root(marked, replace=False)
    (marked / "old.txt").write_text("old", encoding="utf-8")
    _prepare_output_root(marked, replace=True)
    assert not (marked / "old.txt").exists()
    assert (marked / ".manifest_resilience_smoke_root.json").is_file()


def test_workbench_packager_requires_manifest_resilience_evidence() -> None:
    project_root = Path(__file__).resolve().parents[1]
    script = (project_root / "scripts" / "build_workbench_exe.ps1").read_text(
        encoding="utf-8-sig"
    )

    assert "validate_analysis_runner_manifest_resilience.py" in script
    assert "Compiled analysis manifest-resilience smoke" in script
    assert "analysis_runner_manifest_resilience_smoke" in script
    assert "analysis_runner_manifest_resilience = $analysisRunnerManifestResilience" in script
    assert "manifest_bytes -le 1048576" in script
    assert 'write_error_identifier -ne "bms:Logger:JsonPublishFailed"' in script
