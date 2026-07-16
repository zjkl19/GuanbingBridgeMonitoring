from __future__ import annotations

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "build" / "job17_proven_start_failure_retry_20260716.ps1"


def _source() -> str:
    return SCRIPT.read_text(encoding="utf-8")


def test_retry_uses_one_direct_scheduled_task_start_and_no_start_process() -> None:
    source = _source()
    assert source.count("Start-ScheduledTask -TaskPath") == 1
    assert not re.search(r"(?m)^\s*Start-Process\b", source)
    assert "New-ScheduledTaskAction -Execute $Runner" in source
    assert "has_triggers = $false" in source
    assert "-MultipleInstances IgnoreNew" in source


def test_retry_authorization_is_durable_before_registration_and_start() -> None:
    source = _source()
    authorization = source.index("Write-JsonNewReadOnly $Authorization")
    registration = source.index("Register-ScheduledTask")
    start = source.index("Start-ScheduledTask -TaskPath")
    assert authorization < registration < start
    assert "Retry evidence root already exists; the one-time authorization is consumed." in source
    assert "maximum_task_start_calls = 1" in source
    assert "ConfirmationToken" in source
    assert "REAUTHORIZE_PROVEN_START_FAILURE_ONCE" in source


def test_retry_requires_the_exact_no_spawn_evidence_and_final_runner() -> None:
    source = _source()
    for value in (
        "4E475C907840BDF0E532C9D4CE443D92B7BD7CBDAB83C82D81FA35C43869EE9A",
        "C6F9E5F0DA518B0C902E8648F630BC88F733CFBB906DB9E4764EF0A7B915112F",
        "D1E9F280D95250DA9D9BD5F3A2E0E73AD4F19FFB324A6C6A8B1AF92E997A5D33",
        "32D441897B0B9FFFAC9B59BE14F79BF2F3DDC812F72C7658238DD076850E155A",
    ):
        assert value in source
    for evidence in (
        "runner_execution_fence_receipt.json",
        "runner_stdout.log",
        "runner_stderr.log",
        "analysis_status.json",
    ):
        assert evidence in source
    assert "Get-Process -Name BridgeAnalysisRunner, MATLAB, ctfxlauncher" in source
    assert "$taskInfo.LastTaskResult -ne 249" in source


def test_finalize_binds_validator_manifest_for_composite_without_relaunch() -> None:
    source = _source()
    assert "validate_spectrum_recovery.py" in source
    assert "cable_accel_spectrum_manifest_for_composite" in source
    assert "runner_launches = 0" in source
    finalize = source[source.index("# Finalize never launches a process") :]
    assert "Start-ScheduledTask" not in finalize
    assert not re.search(r"(?m)^\s*Start-Process\b", finalize)
