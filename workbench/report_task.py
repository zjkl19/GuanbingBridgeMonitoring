from __future__ import annotations

import json
import os
import subprocess
import sys
import time
import uuid
import copy
from contextlib import ExitStack
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from .models import JobContext
from .process_utils import (
    atomic_write_json,
    assert_no_live_process_lease,
    capture_spawned_process_identity,
    exclusive_file_lock,
    pid_running,
    process_identity_state,
    publish_process_lease,
    read_process_lease,
    terminate_exact_process,
)


TERMINAL_REPORT_STATES = {
    "completed",
    "disclosure_required",
    "failed",
    "stopped",
    "launch_failed",
}


def _wait_for_process_exit(
    pid: int,
    *,
    timeout_seconds: float = 2.0,
    poll_interval_seconds: float = 0.05,
) -> bool:
    """Wait briefly for an already-signalled process to leave the PID table."""

    deadline = time.monotonic() + max(0.0, timeout_seconds)
    while pid_running(pid):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return False
        time.sleep(min(max(0.001, poll_interval_seconds), remaining))
    return True


@dataclass(frozen=True)
class ReportLaunchResult:
    command: tuple[str, ...]
    pid: int
    status_path: Path
    result_path: Path


def report_job_command(
    project_root: Path,
    context_path: Path,
    status_path: Path,
    result_path: Path,
    launch_id: str = "",
) -> tuple[str, ...]:
    venv_python = project_root / "reporting" / ".venv" / "Scripts" / "python.exe"
    common = (
        "--run-report-job",
        "--project-root", str(project_root),
        "--job-context", str(context_path),
        "--report-status", str(status_path),
        "--report-result", str(result_path),
    )
    if launch_id:
        common = (*common, "--report-launch-id", launch_id)
    if getattr(sys, "frozen", False):
        return (sys.executable, *common)
    python = venv_python if venv_python.is_file() else Path(sys.executable)
    return (str(python), "-m", "workbench", *common)


def launch_report_job(
    context: JobContext,
    context_path: Path | None = None,
    *,
    runtime_root: Path | None = None,
) -> ReportLaunchResult:
    path = (context_path or context.context_path).resolve()
    canonical = JobContext.read(path) if path.is_file() else context
    if canonical.job_id != context.job_id:
        raise RuntimeError(
            "当前任务文件已被替换为另一任务；请重新打开后再生成报告。"
        )
    if canonical.analysis_binding() != context.analysis_binding():
        raise RuntimeError(
            "任务方案中的桥梁、数据目录、日期或分析配置已变化；请重新打开后再生成报告。"
        )
    lock_paths = _report_lock_paths(context, data_root=canonical.data_root)
    lease_paths = _report_lease_paths(context, data_root=canonical.data_root)
    with ExitStack() as stack:
        for lock_path in lock_paths:
            stack.enter_context(exclusive_file_lock(lock_path))
        if path.is_file():
            latest = JobContext.read(path)
            if latest.analysis_binding() != canonical.analysis_binding():
                raise RuntimeError(
                    "任务方案在等待资源锁期间已更新；请重新打开后再生成报告。"
                )
        assert_no_live_process_lease(
            _report_resource_guard_dir(canonical) / ".analysis_active.json",
            "分析任务",
        )
        for lease_path in lease_paths:
            assert_no_live_process_lease(lease_path, "报告任务")
        _refuse_active_report_launch(path)
        return _launch_report_job_locked(
            context,
            path,
            lease_paths,
            (runtime_root or _runtime_project_root()).expanduser().resolve(),
        )


def _launch_report_job_locked(
    context: JobContext,
    path: Path,
    lease_paths: tuple[Path, ...],
    runtime_root: Path,
) -> ReportLaunchResult:
    if path.is_file():
        latest = JobContext.read(path)
        if latest.job_id != context.job_id:
            raise RuntimeError(
                "当前任务文件已被替换为另一任务；请重新打开后再生成报告。"
            )
        if str(latest.report.launch_id or "") != str(
            context.report.launch_id or ""
        ):
            raise RuntimeError(
                "当前窗口不是任务文件的最新轮次；请重新打开后再生成报告。"
            )
        if latest.analysis_binding() != context.analysis_binding():
            raise RuntimeError(
                "任务方案中的桥梁、数据目录、日期或分析配置已变化；请重新打开后再生成报告。"
            )
        # Canonical analysis and approval bindings are authoritative. Only the
        # explicitly user-editable report destination/template fields are
        # taken from the current UI, then saved under this same resource lock.
        requested_report_type = context.report.report_type
        requested_template_path = context.report.template_path
        requested_template_sha256 = context.report.template_sha256
        requested_output_dir = context.report.output_dir
        context.analysis = copy.deepcopy(latest.analysis)
        context.report = copy.deepcopy(latest.report)
        context.report.report_type = requested_report_type
        context.report.template_path = requested_template_path
        context.report.template_sha256 = requested_template_sha256
        context.report.output_dir = requested_output_dir
    job_dir = _report_runtime_dir(context, path)
    job_dir.mkdir(parents=True, exist_ok=True)
    context.project_root = str(runtime_root)
    context.report.launch_id = uuid.uuid4().hex
    request_snapshot_path = job_dir / f"report_request.{context.report.launch_id}.json"
    status_path = job_dir / f"report_status.{context.report.launch_id}.json"
    result_path = job_dir / f"report_result.{context.report.launch_id}.json"
    stdout_path = job_dir / f"report_stdout.{context.report.launch_id}.log"
    stderr_path = job_dir / f"report_stderr.{context.report.launch_id}.log"
    context.report.status_path = str(status_path)
    context.report.result_path = str(result_path)
    context.report.stdout_log = str(stdout_path)
    context.report.stderr_log = str(stderr_path)
    context.report.state = "launching"
    context.report.pid = None
    context.report.process_creation_time_100ns = None
    context.report.process_executable = ""
    context.report.manifest_path = ""
    context.report.output_docx = ""
    context.report.output_pdf = ""
    context.report.qc_state = ""
    context.report.visual_qc_dir = ""
    context.report.visual_contact_sheet = ""
    try:
        for stale in (status_path, result_path):
            stale.unlink(missing_ok=True)
        context.write(path)
        atomic_write_json(request_snapshot_path, context.to_dict())
        command = report_job_command(
            runtime_root,
            request_snapshot_path,
            status_path,
            result_path,
            context.report.launch_id,
        )
    except Exception as exc:
        _publish_report_launch_failure(
            context, path, status_path, result_path, "prepare", exc
        )
        raise
    creationflags = 0
    if os.name == "nt":
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
    try:
        with stdout_path.open("ab") as stdout, stderr_path.open("ab") as stderr:
            process = subprocess.Popen(
                command,
                cwd=str(runtime_root),
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                creationflags=creationflags,
            )
    except Exception as exc:
        _publish_report_launch_failure(
            context, path, status_path, result_path, "process_start", exc
        )
        raise
    try:
        identity = capture_spawned_process_identity(process)
        if identity is None:
            terminal = _terminal_report_payload(
                status_path, result_path, context.report.launch_id
            )
            if terminal is not None:
                _sync_terminal_report_context(
                    context, terminal, persist=False
                )
                context.write(path)
                return ReportLaunchResult(
                    command, int(process.pid), status_path, result_path
                )
            raise RuntimeError(
                "无法取得新报告子进程的创建时间和可执行文件；已安全取消启动。"
            )
        context.report.state = "launched"
        context.report.pid = int(process.pid)
        context.report.process_creation_time_100ns = int(
            identity["creation_time_100ns"]
        )
        context.report.process_executable = str(identity["executable"])
        for lease_path in lease_paths:
            publish_process_lease(
                lease_path,
                task_type="report",
                launch_id=context.report.launch_id,
                pid=int(process.pid),
                process_creation_time_100ns=int(identity["creation_time_100ns"]),
                process_executable=str(identity["executable"]),
                context_path=path,
                job_id=context.job_id,
            )
        context.write(path)
    except Exception as exc:
        _terminate_report_spawned_process(process)
        _publish_report_launch_failure(
            context, path, status_path, result_path, "identity_or_context", exc
        )
        raise
    return ReportLaunchResult(command, int(process.pid), status_path, result_path)


def _report_runtime_dir(context: JobContext, context_path: Path | None = None) -> Path:
    return (context_path or context.context_path).expanduser().resolve().parent


def _runtime_project_root() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[1]


def _report_lock_path(context: JobContext) -> Path:
    return _report_resource_guard_dir(context) / ".task_launch.lock"


def _report_lease_path(context: JobContext) -> Path:
    return _report_resource_guard_dir(context) / ".report_active.json"


def _report_output_guard_dir(context: JobContext) -> Path:
    return (
        Path(context.report.output_dir).expanduser().resolve()
        / ".guanbing_workbench"
        / "_active"
    )


def _report_lock_paths(
    context: JobContext, *, data_root: str | Path | None = None
) -> tuple[Path, ...]:
    paths = {
        (_report_resource_guard_dir(context, data_root=data_root) / ".task_launch.lock").resolve(),
        (_report_output_guard_dir(context) / ".task_launch.lock").resolve(),
    }
    return tuple(sorted(paths, key=lambda item: str(item).casefold()))


def _report_lease_paths(
    context: JobContext, *, data_root: str | Path | None = None
) -> tuple[Path, ...]:
    paths = {
        (_report_resource_guard_dir(context, data_root=data_root) / ".report_active.json").resolve(),
        (_report_output_guard_dir(context) / ".report_active.json").resolve(),
    }
    return tuple(sorted(paths, key=lambda item: str(item).casefold()))


def _report_resource_guard_dir(
    context: JobContext, *, data_root: str | Path | None = None
) -> Path:
    return (
        Path(data_root or context.data_root).expanduser().resolve()
        / "run_logs"
        / "workbench"
        / "_active"
    )


def _refuse_active_report_launch(context_path: Path) -> None:
    if not context_path.is_file():
        return
    try:
        existing = JobContext.read(context_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise RuntimeError(
            f"无法核验已有任务状态，未启动重复报告：{context_path}"
        ) from exc
    state = str(read_report_status(existing).get("state") or "").lower()
    if state not in {"launching", "launched", "running", "stopping"}:
        return
    if existing.report.pid and _report_process_running(existing):
        raise RuntimeError("该任务已有报告进程正在运行，未启动重复任务。")
    if not existing.report.pid:
        raise RuntimeError(
            "已有报告仍处于启动阶段且缺少可核验 PID；请先检查任务状态，未启动重复任务。"
        )


def _terminate_report_spawned_process(process: subprocess.Popen[Any]) -> None:
    try:
        process.terminate()
        process.wait(timeout=2)
    except Exception:
        try:
            process.kill()
            process.wait(timeout=2)
        except Exception:
            pass


def _publish_report_launch_failure(
    context: JobContext,
    context_path: Path,
    status_path: Path,
    result_path: Path,
    stage: str,
    error: Exception,
) -> None:
    failure = {
        "state": "launch_failed",
        "launch_id": context.report.launch_id,
        "stage": stage,
        "progress_fraction": 0.0,
        "message": str(error),
    }
    for target in (status_path, result_path):
        try:
            atomic_write_json(target, failure)
        except Exception:
            pass
    previous = copy.deepcopy(context.report)
    candidate = copy.deepcopy(context.report)
    candidate.state = "launch_failed"
    candidate.pid = None
    candidate.process_creation_time_100ns = None
    candidate.process_executable = ""
    context.report = candidate
    try:
        context.write(context_path)
    except Exception:
        context.report = previous


def _read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        return payload if isinstance(payload, dict) else {}
    except (OSError, ValueError):
        return {"state": "status_read_failed", "message": f"无法读取 {path}"}


def read_report_status(context: JobContext) -> dict[str, Any]:
    if _report_context_superseded(context):
        return {
            "state": "superseded",
            "stage": "stale_window",
            "context_superseded": True,
            "progress_fraction": 0.0,
            "message": "该任务已在另一个工作平台实例中重新启动；本窗口仅保留旧轮次只读状态。",
        }
    status_path = Path(context.report.status_path) if context.report.status_path else context.context_path.parent / "report_status.json"
    result_path = Path(context.report.result_path) if context.report.result_path else context.context_path.parent / "report_result.json"
    status = _read_json(status_path)
    result = _read_json(result_path)
    status = _report_payload_for_launch(status, context.report.launch_id)
    result = _report_payload_for_launch(result, context.report.launch_id)
    if result and str(result.get("state") or "").lower() in TERMINAL_REPORT_STATES:
        merged = dict(status)
        merged.update(result)
        if context.report.pid and _report_process_running(context):
            return {
                **merged,
                "process_cleanup_pending": True,
                "stage": "process_cleanup",
                "message": "报告结果已发布，后台进程正在完成退出清理。",
            }
        _sync_terminal_report_context(context, merged)
        return merged
    status_state = str(status.get("state") or "").lower()
    if status and status_state in TERMINAL_REPORT_STATES - {"completed"}:
        if context.report.pid and _report_process_running(context):
            return {
                **status,
                "process_cleanup_pending": True,
                "stage": "process_cleanup",
                "message": "报告结果已发布，后台进程正在完成退出清理。",
            }
        _sync_terminal_report_context(context, status)
        return status
    if status_state == "completed":
        # Success is committed only by result.json.  A status-only completed
        # marker is an older/partial writer and remains non-terminal until the
        # result is durable.
        status = {
            **status,
            "state": "running",
            "stage": "finalizing",
            "message": "报告正在发布最终结果，请稍候。",
        }
    current = status or {"state": context.report.state or "blocked", "progress_fraction": 0.0}
    state = str(current.get("state") or "").lower()
    context_state = str(context.report.state or "").lower()
    if (
        state == "status_read_failed"
        and context.report.pid
        and context_state in {"launched", "running", "stopping"}
        and _report_process_running(context)
    ):
        return {
            "state": context_state,
            "stage": "status_retry",
            "progress_fraction": 0.0,
            "message": current.get("message") or "report status is temporarily unreadable; retrying",
        }
    if (
        state in {"launched", "running"}
        and context.report.pid
        and not _report_process_running(context)
    ):
        # The process may have published its terminal result between the first
        # read and the liveness probe.  Re-read once before classifying it as an
        # abnormal exit so a genuine completion is never overwritten.
        latest_terminal = _terminal_report_payload(
            status_path, result_path, context.report.launch_id
        )
        if latest_terminal is not None:
            _sync_terminal_report_context(context, latest_terminal)
            return latest_terminal
        failure = {
            **current,
            "state": "launch_failed",
            "launch_id": context.report.launch_id,
            "stage": "process_exit",
            "message": "报告子进程已退出，但未写入终态结果；请检查 stderr 日志。",
        }
        atomic_write_json(status_path, failure)
        atomic_write_json(result_path, failure)
        _sync_terminal_report_context(context, failure)
        return failure
    return current


def _report_payload_for_launch(
    payload: dict[str, Any], expected_launch_id: str
) -> dict[str, Any]:
    if not payload or not expected_launch_id:
        return payload
    if str(payload.get("state") or "").lower() == "status_read_failed":
        return payload
    if str(payload.get("launch_id") or "") != expected_launch_id:
        return {}
    return payload


def _report_process_running(context: JobContext) -> bool:
    if (
        context.report.launch_id
        and context.report.process_creation_time_100ns
        and context.report.process_executable
    ):
        return process_identity_state(
            context.report.pid,
            context.report.process_creation_time_100ns,
            context.report.process_executable,
        ) in {"matching", "unverifiable"}
    return pid_running(context.report.pid)


def _report_context_superseded(context: JobContext) -> bool:
    expected = str(context.report.launch_id or "")
    path = context.context_path
    if path.is_file():
        try:
            raw = json.loads(path.read_text(encoding="utf-8-sig"))
            actual = str((raw.get("report") or {}).get("launch_id") or "")
            if actual != expected:
                return True
        except (OSError, ValueError, AttributeError):
            pass
    if not expected:
        return False
    try:
        lease = read_process_lease(
            _report_lease_path(context), task_label="报告任务"
        )
    except RuntimeError:
        return True
    if (
        lease is None
        or str(lease.get("job_id") or "") != context.job_id
        or str(lease.get("launch_id") or "") == expected
    ):
        return False
    created = lease.get("process_creation_time_100ns")
    executable = str(lease.get("process_executable") or "")
    if created and executable:
        return process_identity_state(
            int(lease["pid"]), int(created), executable
        ) in {"matching", "unverifiable"}
    return pid_running(int(lease["pid"]))


def _persist_report_context_if_current(context: JobContext) -> bool:
    try:
        with exclusive_file_lock(_report_lock_path(context)):
            if _report_context_superseded(context):
                return False
            path = context.context_path
            if path.is_file():
                current = JobContext.read(path)
                if str(current.report.launch_id or "") != str(
                    context.report.launch_id or ""
                ):
                    return False
                current.report = copy.deepcopy(context.report)
                current.write(path)
                context.analysis = copy.deepcopy(current.analysis)
            else:
                context.write(path)
            return True
    except (OSError, RuntimeError):
        return False


def persist_report_state(context: JobContext) -> bool:
    """Persist only the report field without clobbering analysis progress."""

    if _persist_report_context_if_current(context):
        return True
    try:
        latest = JobContext.read(context.context_path)
        context.analysis = copy.deepcopy(latest.analysis)
        context.report = copy.deepcopy(latest.report)
    except (OSError, ValueError):
        pass
    return False


def _terminal_report_payload(
    status_path: Path, result_path: Path, expected_launch_id: str = ""
) -> dict[str, Any] | None:
    """Return an already-published terminal report state without rewriting it."""

    status = _report_payload_for_launch(_read_json(status_path), expected_launch_id)
    result = _report_payload_for_launch(_read_json(result_path), expected_launch_id)
    result_state = str(result.get("state") or "").lower()
    if result and result_state in TERMINAL_REPORT_STATES:
        merged = dict(status)
        merged.update(result)
        return merged
    status_state = str(status.get("state") or "").lower()
    if status and status_state in TERMINAL_REPORT_STATES - {"completed"}:
        return status
    return None


def _sync_terminal_report_context(
    context: JobContext, payload: dict[str, Any], *, persist: bool = True
) -> None:
    state = str(payload.get("state") or "").lower()
    if state not in TERMINAL_REPORT_STATES:
        raise ValueError(f"Not a terminal report payload: {payload}")
    previous = copy.deepcopy(context.report)
    candidate = copy.deepcopy(context.report)
    changed = (
        candidate.state != state
        or candidate.pid is not None
        or candidate.process_creation_time_100ns is not None
        or bool(candidate.process_executable)
    )
    candidate.state = state
    candidate.pid = None
    candidate.process_creation_time_100ns = None
    candidate.process_executable = ""
    manifest_path = str(payload.get("manifest_path") or "").strip()
    if manifest_path and candidate.manifest_path != manifest_path:
        candidate.manifest_path = manifest_path
        changed = True
    if changed:
        context.report = candidate
        if persist and not _persist_report_context_if_current(context):
            context.report = previous


def terminate_report_job(context: JobContext) -> str:
    context_path = context.context_path
    with exclusive_file_lock(_report_lock_path(context)):
        lease = read_process_lease(
            _report_lease_path(context), task_label="报告任务"
        )
        expected = str(context.report.launch_id or "")
        lease_launch = str((lease or {}).get("launch_id") or "")
        if lease_launch and lease_launch != expected:
            raise RuntimeError(
                "任务已由另一个工作平台实例重新启动；当前窗口状态已过期，未停止新报告。"
            )
        current = JobContext.read(context_path) if context_path.is_file() else context
        if str(current.report.launch_id or "") != str(context.report.launch_id or ""):
            raise RuntimeError(
                "任务已由另一个工作平台实例重新启动；当前窗口状态已过期，未停止新报告。"
            )
        outcome = _terminate_report_job_locked(current)
        current.write()
        context.report = current.report
        return outcome


def _terminate_report_job_locked(context: JobContext) -> str:
    status_path = (
        Path(context.report.status_path)
        if context.report.status_path
        else context.context_path.parent / "report_status.json"
    )
    result_path = (
        Path(context.report.result_path)
        if context.report.result_path
        else context.context_path.parent / "report_result.json"
    )
    terminal = _terminal_report_payload(
        status_path, result_path, context.report.launch_id
    )
    if terminal is not None:
        terminal_state = str(terminal.get("state") or "").lower()
        if context.report.pid and _report_process_running(context):
            # The result won the race, but the exact owner is still cleaning
            # up. Preserve its identity so subsequent polls can verify exit.
            context.report.state = terminal_state
            return f"{terminal_state}_cleanup_pending"
        _sync_terminal_report_context(context, terminal, persist=False)
        return terminal_state

    pid = context.report.pid
    if not pid:
        if str(context.report.state or "").lower() in TERMINAL_REPORT_STATES:
            return str(context.report.state or "").lower()
        raise RuntimeError("报告任务没有可核验的子进程 PID，未执行停止操作。")

    if not (
        context.report.launch_id
        and context.report.process_creation_time_100ns
        and context.report.process_executable
    ):
        raise RuntimeError(
            "报告任务缺少本次启动的进程身份记录；为避免误杀其他程序，未执行强制停止。"
        )
    termination_error = ""
    try:
        terminated = terminate_exact_process(
            pid,
            context.report.process_creation_time_100ns,
            context.report.process_executable,
        )
    except TimeoutError as exc:
        raise RuntimeError(
            "已向报告进程发送停止请求，但进程尚未确认退出；任务状态保持不变，"
            "请稍后刷新后再判断。"
        ) from exc
    except OSError as exc:
        terminated = False
        termination_error = str(exc)

    if not terminated:
        # A report can complete naturally just before the exact process handle
        # is opened.  Give its atomic terminal publication a brief opportunity
        # to win before reporting a safe refusal.
        for _ in range(4):
            terminal = _terminal_report_payload(
                status_path, result_path, context.report.launch_id
            )
            if terminal is not None:
                terminal_state = str(terminal.get("state") or "").lower()
                if context.report.pid and _report_process_running(context):
                    context.report.state = terminal_state
                    return f"{terminal_state}_cleanup_pending"
                _sync_terminal_report_context(context, terminal, persist=False)
                return terminal_state
            time.sleep(0.05)
        detail = f"：{termination_error}" if termination_error else ""
        raise RuntimeError(
            "报告任务 PID 已退出、被系统复用或无法在同一进程句柄内安全终止；"
            f"未执行不安全的按 PID 强杀{detail}"
        )

    # POSIX compatibility paths signal through pidfd/kill and still need a
    # bounded exit wait.  Windows already waited on the exact retained HANDLE.
    if os.name != "nt" and not _wait_for_process_exit(pid):
        raise RuntimeError("报告子进程仍在运行，停止失败")

    # The worker may have completed naturally while the stop request was being
    # delivered. Preserve that authoritative terminal result instead of
    # replacing a successful report with a synthetic ``stopped`` record.
    terminal = _terminal_report_payload(
        status_path, result_path, context.report.launch_id
    )
    if terminal is not None:
        _sync_terminal_report_context(context, terminal, persist=False)
        return str(terminal.get("state") or "").lower()

    previous = _read_json(status_path)
    stopped = {
        "schema_version": 1,
        "state": "stopped",
        "launch_id": context.report.launch_id,
        "stage": "stopped",
        "progress_fraction": previous.get("progress_fraction", 0.0),
        "message": "报告任务已由用户停止。",
        "pid": pid,
        "stopped_at": datetime.now().astimezone().isoformat(timespec="seconds"),
    }
    atomic_write_json(status_path, stopped)
    atomic_write_json(result_path, stopped)
    context.report.state = "stopped"
    context.report.pid = None
    context.report.process_creation_time_100ns = None
    context.report.process_executable = ""
    context.write()
    return "stopped"
