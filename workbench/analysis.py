from __future__ import annotations

import json
import os
import shutil
import subprocess
import uuid
import copy
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .models import JobContext
from .module_progress import normalize_module_progress
from .report_disclosures import invalidate_disclosure_approval
from .config_layers import config_dependency_sha256, load_layered_config
from .process_utils import (
    atomic_write_json,
    assert_no_live_process_lease,
    capture_spawned_process_identity,
    exclusive_file_lock,
    pid_running,
    process_identity_state,
    publish_process_lease,
    read_process_lease,
)


TERMINAL_ANALYSIS_STATES = {"completed", "failed", "stopped", "launch_failed"}
ACTIVE_ANALYSIS_STATES = {"prepared", "launching", "launched", "running"}


@dataclass(frozen=True)
class Executor:
    kind: str
    executable: Path


@dataclass(frozen=True)
class LaunchResult:
    pid: int
    executor: Executor
    command: tuple[str, ...]


def _matlab_quote(value: str) -> str:
    return value.replace("'", "''")


def _read_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return payload


class ExecutorResolver:
    def __init__(self, project_root: Path) -> None:
        self.project_root = project_root.resolve()

    def resolve(self, *, runner: Path | None = None, matlab: Path | None = None) -> Executor:
        if runner:
            candidate = runner.expanduser().resolve()
            if not candidate.is_file():
                raise FileNotFoundError(f"Compiled runner does not exist: {candidate}")
            return Executor("compiled_runner", candidate)
        exe_name = "BridgeAnalysisRunner.exe" if os.name == "nt" else "BridgeAnalysisRunner"
        for candidate in (
            self.project_root / "bin" / "BridgeAnalysisRunner" / exe_name,
            self.project_root / "dist" / "BridgeAnalysisRunner" / exe_name,
        ):
            if candidate.is_file():
                return Executor("compiled_runner", candidate.resolve())
        if matlab:
            candidate = matlab.expanduser().resolve()
            if candidate.is_file():
                return Executor("matlab_batch", candidate)
            raise FileNotFoundError(f"MATLAB executable does not exist: {candidate}")
        discovered = shutil.which("matlab")
        if discovered:
            return Executor("matlab_batch", Path(discovered).resolve())
        raise FileNotFoundError("No BridgeAnalysisRunner or MATLAB executable is available")


class AnalysisRequestBuilder:
    def build(self, context: JobContext) -> dict[str, Any]:
        config_path = Path(context.config_path)
        if not config_path.is_file():
            raise FileNotFoundError(f"Config file does not exist: {config_path}")
        actual_hash = config_dependency_sha256(config_path)
        if actual_hash != context.config_sha256:
            raise RuntimeError(
                f"Config changed after job creation: expected={context.config_sha256}, actual={actual_hash}"
            )
        config, _ = load_layered_config(config_path)
        config["source"] = str(config_path)
        return {
            "project_root": context.project_root,
            "data_root": context.data_root,
            "start_date": context.start_date,
            "end_date": context.end_date,
            "config_path": context.config_path,
            "config_sha256": actual_hash,
            "options": context.options,
            "config": config,
            "async_run_id": context.analysis.launch_id or context.job_id,
            "stop_file": context.analysis.stop_path,
            "async_status_file": context.analysis.status_path,
        }

    def write(self, context: JobContext) -> Path:
        target = Path(context.analysis.request_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        atomic_write_json(target, self.build(context))
        atomic_write_json(context.analysis.status_path, {
            "status": "prepared",
            "async_run_id": context.analysis.launch_id or context.job_id,
        })
        return target


class AnalysisLauncher:
    def __init__(
        self,
        project_root: Path,
        *,
        popen: Callable[..., subprocess.Popen[Any]] = subprocess.Popen,
    ) -> None:
        self.project_root = project_root.resolve()
        self._popen = popen

    def command(self, context: JobContext, executor: Executor) -> tuple[str, ...]:
        request_path = str(Path(context.analysis.request_path))
        if executor.kind == "compiled_runner":
            return (str(executor.executable), request_path)
        if executor.kind != "matlab_batch":
            raise ValueError(f"Unsupported executor kind: {executor.kind}")
        paths = (
            self.project_root,
            self.project_root / "ui",
            self.project_root / "config",
            self.project_root / "pipeline",
            self.project_root / "analysis",
            self.project_root / "scripts",
        )
        code = "".join(f"addpath('{_matlab_quote(str(path))}','-begin');" for path in paths)
        code += f"run_request_cli('{_matlab_quote(request_path)}');"
        return (str(executor.executable), "-nosplash", "-nodesktop", "-batch", code)

    def launch(self, context: JobContext, executor: Executor) -> LaunchResult:
        canonical = (
            JobContext.read(context.context_path)
            if context.context_path.is_file()
            else context
        )
        if canonical.job_id != context.job_id:
            raise RuntimeError(
                "当前任务文件已被替换为另一任务；请重新打开后再启动分析。"
            )
        if canonical.analysis_binding() != context.analysis_binding():
            raise RuntimeError(
                "任务方案中的桥梁、数据目录、日期或分析配置已变化；请重新打开后再启动分析。"
            )
        with exclusive_file_lock(_analysis_lock_path(canonical)):
            if context.context_path.is_file():
                latest = JobContext.read(context.context_path)
                if latest.analysis_binding() != canonical.analysis_binding():
                    raise RuntimeError(
                        "任务方案在等待资源锁期间已更新；请重新打开后再启动分析。"
                    )
            assert_no_live_process_lease(
                _analysis_lease_path(canonical), "分析任务"
            )
            assert_no_live_process_lease(
                _analysis_resource_guard_dir(canonical) / ".report_active.json",
                "报告任务",
            )
            _refuse_active_analysis_launch(context.context_path)
            return self._launch_locked(context, executor)

    def _launch_locked(
        self, context: JobContext, executor: Executor
    ) -> LaunchResult:
        if context.context_path.is_file():
            latest = JobContext.read(context.context_path)
            if latest.job_id != context.job_id:
                raise RuntimeError(
                    "当前任务文件已被替换为另一任务；请重新打开后再启动分析。"
                )
            if str(latest.analysis.launch_id or "") != str(
                context.analysis.launch_id or ""
            ):
                raise RuntimeError(
                    "当前窗口不是任务文件的最新轮次；请重新打开后再启动分析。"
                )
            if latest.analysis_binding() != context.analysis_binding():
                raise RuntimeError(
                    "任务方案中的桥梁、数据目录、日期或分析配置已变化；请重新打开后再启动分析。"
                )
            # Analysis launch owns only the analysis field. Preserve any
            # report progress written by another window before this lock was
            # acquired instead of overwriting the whole context with a stale
            # in-memory copy.
            context.report = copy.deepcopy(latest.report)
        previous_stop_path = Path(context.analysis.stop_path)
        # The file the operator actually opened/saved is authoritative.  A
        # copied task must keep all per-launch protocol files beside that file
        # instead of writing back to an embedded path from another computer.
        job_dir = _analysis_runtime_dir(context)
        context.project_root = str(self.project_root)
        context.analysis.launch_id = uuid.uuid4().hex
        context.analysis.request_path = str(
            job_dir / f"run_request.{context.analysis.launch_id}.json"
        )
        context.analysis.status_path = str(
            job_dir / f"analysis_status.{context.analysis.launch_id}.json"
        )
        context.analysis.stop_path = str(
            job_dir / f"stop.{context.analysis.launch_id}.flag"
        )
        context.analysis.stdout_log = str(
            job_dir / f"analysis_stdout.{context.analysis.launch_id}.log"
        )
        context.analysis.stderr_log = str(
            job_dir / f"analysis_stderr.{context.analysis.launch_id}.log"
        )
        context.analysis.state = "launching"
        context.analysis.pid = None
        context.analysis.process_creation_time_100ns = None
        context.analysis.process_executable = ""
        context.analysis.executor_type = executor.kind
        context.analysis.executable = str(executor.executable)
        context.analysis.manifest_path = ""
        context.analysis.manifest_sha256 = ""
        context.report.plots_approved = False
        invalidate_disclosure_approval(context.report)
        context.report.state = "blocked"
        context.report.launch_id = ""
        context.report.pid = None
        context.report.process_creation_time_100ns = None
        context.report.process_executable = ""
        context.report.status_path = str(
            job_dir / f"report_status.pending.{context.analysis.launch_id}.json"
        )
        context.report.result_path = str(
            job_dir / f"report_result.pending.{context.analysis.launch_id}.json"
        )
        context.report.stdout_log = ""
        context.report.stderr_log = ""
        context.report.manifest_path = ""
        context.report.derived_artifact_manifest_path = ""
        context.report.derived_artifact_manifest_sha256 = ""
        context.report.output_docx = ""
        context.report.output_pdf = ""
        context.report.qc_state = ""
        context.report.visual_qc_dir = ""
        context.report.visual_contact_sheet = ""
        try:
            # A saved task can be launched again after a previous stop request.
            # The runner treats this file as level-triggered state, so leaving
            # it behind would stop the new process immediately.
            previous_stop_path.unlink(missing_ok=True)
            Path(context.analysis.stop_path).unlink(missing_ok=True)
            context.write()
            AnalysisRequestBuilder().write(context)
            command = self.command(context, executor)
            stdout_path = Path(context.analysis.stdout_log)
            stderr_path = Path(context.analysis.stderr_log)
            stdout_path.parent.mkdir(parents=True, exist_ok=True)
        except Exception as exc:
            _publish_analysis_launch_failure(context, "prepare", exc)
            raise
        creationflags = 0
        if os.name == "nt":
            creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        try:
            with stdout_path.open("ab") as stdout, stderr_path.open("ab") as stderr:
                process = self._popen(
                    command,
                    cwd=str(self.project_root),
                    stdin=subprocess.DEVNULL,
                    stdout=stdout,
                    stderr=stderr,
                    creationflags=creationflags,
                )
        except Exception as exc:
            _publish_analysis_launch_failure(context, "process_start", exc)
            raise
        try:
            identity = capture_spawned_process_identity(process)
            if identity is None:
                terminal = _latest_terminal_analysis_status(
                    Path(context.analysis.status_path), context.analysis.launch_id
                )
                if terminal is not None:
                    _sync_terminal_analysis_context(
                        context, terminal, persist=False
                    )
                    context.write()
                    return LaunchResult(int(process.pid), executor, command)
                raise RuntimeError(
                    "无法取得新分析子进程的创建时间和可执行文件；已安全取消启动。"
                )
            context.analysis.state = "launched"
            context.analysis.pid = int(process.pid)
            context.analysis.process_creation_time_100ns = int(
                identity["creation_time_100ns"]
            )
            context.analysis.process_executable = str(identity["executable"])
            publish_process_lease(
                _analysis_lease_path(context),
                task_type="analysis",
                launch_id=context.analysis.launch_id,
                pid=int(process.pid),
                process_creation_time_100ns=int(identity["creation_time_100ns"]),
                process_executable=str(identity["executable"]),
                context_path=context.context_path,
                job_id=context.job_id,
            )
            context.write()
        except Exception as exc:
            # A detached worker without a durable context is unmanageable.
            # Compensate immediately while the Popen handle still identifies
            # the exact child, then durably close the launch transaction.
            _terminate_spawned_process(process)
            _publish_analysis_launch_failure(context, "identity_or_context", exc)
            raise
        return LaunchResult(int(process.pid), executor, command)

    @staticmethod
    def request_stop(context: JobContext) -> Path:
        context_path = context.context_path
        with exclusive_file_lock(_analysis_lock_path(context)):
            lease = read_process_lease(
                _analysis_lease_path(context), task_label="分析任务"
            )
            expected = str(context.analysis.launch_id or "")
            lease_launch = str((lease or {}).get("launch_id") or "")
            if lease_launch and lease_launch != expected:
                raise RuntimeError(
                    "任务已由另一个工作平台实例重新启动；当前窗口状态已过期，未写入停止标志。"
                )
            current = (
                JobContext.read(context_path) if context_path.is_file() else context
            )
            actual = str(current.analysis.launch_id or "")
            if expected != actual:
                raise RuntimeError(
                    "任务已由另一个工作平台实例重新启动；当前窗口状态已过期，未写入停止标志。"
                )
            if str(current.analysis.state or "").lower() in TERMINAL_ANALYSIS_STATES:
                raise RuntimeError("分析任务已经结束，无需再次请求停止。")
            stop_path = Path(current.analysis.stop_path)
            stop_path.parent.mkdir(parents=True, exist_ok=True)
            stop_path.write_text(
                f"stop requested by PySide6 workbench; launch_id={actual}\n",
                encoding="utf-8",
            )
            current.analysis.state = "stopping"
            current.write()
            context.analysis.state = "stopping"
            return stop_path


def _analysis_runtime_dir(context: JobContext) -> Path:
    return context.context_path.expanduser().resolve().parent


def _analysis_lock_path(context: JobContext) -> Path:
    return _analysis_resource_guard_dir(context) / ".task_launch.lock"


def _analysis_lease_path(context: JobContext) -> Path:
    return _analysis_resource_guard_dir(context) / ".analysis_active.json"


def _analysis_resource_guard_dir(context: JobContext) -> Path:
    return (
        Path(context.data_root).expanduser().resolve()
        / "run_logs"
        / "workbench"
        / "_active"
    )


def _terminate_spawned_process(process: subprocess.Popen[Any]) -> None:
    """Best-effort compensation while the exact Popen handle is still held."""

    try:
        process.terminate()
        process.wait(timeout=2)
    except Exception:
        try:
            process.kill()
            process.wait(timeout=2)
        except Exception:
            pass


def _refuse_active_analysis_launch(context_path: Path) -> None:
    if not context_path.is_file():
        return
    try:
        existing = JobContext.read(context_path)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        raise RuntimeError(
            f"无法核验已有任务状态，未启动重复分析：{context_path}"
        ) from exc
    state = str(read_analysis_status(existing).get("status") or "").lower()
    if state not in ACTIVE_ANALYSIS_STATES and state != "stopping":
        return
    if existing.analysis.pid and _analysis_process_running(existing):
        raise RuntimeError("该任务已有分析进程正在运行，未启动重复任务。")
    if not existing.analysis.pid and existing.analysis.launch_id:
        raise RuntimeError(
            "已有任务仍处于启动阶段且缺少可核验 PID；请先检查任务状态，未启动重复任务。"
        )


def _publish_analysis_launch_failure(
    context: JobContext, stage: str, error: Exception
) -> None:
    failure = {
        "status": "launch_failed",
        "async_run_id": context.analysis.launch_id,
        "stage": stage,
        "message": str(error),
    }
    try:
        atomic_write_json(context.analysis.status_path, failure)
    except Exception:
        pass
    previous = copy.deepcopy(context.analysis)
    candidate = copy.deepcopy(context.analysis)
    candidate.state = "launch_failed"
    candidate.pid = None
    candidate.process_creation_time_100ns = None
    candidate.process_executable = ""
    context.analysis = candidate
    try:
        context.write()
    except Exception:
        # Restore the previous in-memory state so a later status poll retries
        # terminal persistence instead of mistaking the failed write for a
        # durable transition.
        context.analysis = previous


def read_analysis_status(context: JobContext) -> dict[str, Any]:
    if _analysis_context_superseded(context):
        return {
            "status": "superseded",
            "stage": "stale_window",
            "context_superseded": True,
            "message": "该任务已在另一个工作平台实例中重新启动；本窗口仅保留旧轮次只读状态。",
        }
    path = Path(context.analysis.status_path)
    read_error = ""
    if not path.is_file():
        status: dict[str, Any] = {"status": context.analysis.state or "unknown"}
    else:
        try:
            status = _read_json(path)
        except (OSError, ValueError) as exc:
            read_error = str(exc)
            status = {"status": "status_read_failed", "message": read_error}
    expected_launch_id = str(context.analysis.launch_id or "")
    actual_launch_id = str(status.get("async_run_id") or "")
    if (
        not read_error
        and path.is_file()
        and expected_launch_id
        and actual_launch_id != expected_launch_id
    ):
        read_error = (
            "analysis status belongs to another launch: "
            f"expected={expected_launch_id}, actual={actual_launch_id or '<missing>'}"
        )
        status = {
            "status": "status_read_failed",
            "stage": "stale_launch",
            "message": read_error,
        }
    state = str(status.get("status") or "").lower()
    context_state = str(context.analysis.state or "").lower()

    if state in TERMINAL_ANALYSIS_STATES:
        status = _reconcile_terminal_module_progress(context, status)
        if context.analysis.pid and _analysis_process_running(context):
            return {
                **status,
                "process_cleanup_pending": True,
                "stage": "process_cleanup",
                "message": "分析结果已发布，后台进程正在完成退出清理。",
            }
        _sync_terminal_analysis_context(context, status)
        return status

    # A transient read failure must not make the Start button available while
    # the detached worker is still alive.  Preserve the durable lifecycle state
    # and ask the UI to retry on its next poll instead.
    if (
        read_error
        and context.analysis.pid
        and _analysis_process_running(context)
        and (context_state in ACTIVE_ANALYSIS_STATES or context_state == "stopping")
    ):
        retry_state = (
            "stopping"
            if context_state == "stopping"
            else ("launched" if context_state in {"prepared", "launching"} else context_state)
        )
        return {
            "status": retry_state,
            "stage": "status_retry",
            "message": f"状态文件暂时无法读取，将自动重试：{read_error}",
        }

    # A cooperative stop request is durable in the task context.  The runner
    # may still publish one last ``running`` heartbeat before it notices the
    # stop flag, so the operator-facing state must not regress to running.
    if context_state == "stopping" and state not in TERMINAL_ANALYSIS_STATES:
        if context.analysis.pid and _analysis_process_running(context):
            return {
                **status,
                "status": "stopping",
                "stage": "stop_requested",
                "message": "已请求停止，正在等待分析子进程安全退出。",
            }
        latest = _latest_terminal_analysis_status(path, expected_launch_id)
        if latest is not None:
            latest = _reconcile_terminal_module_progress(context, latest)
            _sync_terminal_analysis_context(context, latest)
            return latest
        stopped = {
            **status,
            "status": "stopped",
            "async_run_id": expected_launch_id,
            "stage": "stop_requested",
            "message": "分析子进程已响应停止请求并退出。",
        }
        atomic_write_json(path, stopped)
        _sync_terminal_analysis_context(context, stopped)
        return stopped

    if (
        state not in TERMINAL_ANALYSIS_STATES
        and (state in ACTIVE_ANALYSIS_STATES or context_state in ACTIVE_ANALYSIS_STATES)
        and context.analysis.pid
        and not _analysis_process_running(context)
    ):
        # The worker can publish its terminal status after our first read but
        # before the PID probe observes process exit. Re-read before writing a
        # synthetic failure so the authoritative terminal result wins.
        latest = _latest_terminal_analysis_status(path, expected_launch_id)
        if latest is not None:
            latest = _reconcile_terminal_module_progress(context, latest)
            _sync_terminal_analysis_context(context, latest)
            return latest
        failure = {
            **status,
            "status": "launch_failed",
            "async_run_id": expected_launch_id,
            "stage": "process_exit",
            "message": "分析子进程已退出，但未写入终态结果；请检查错误日志。",
        }
        atomic_write_json(path, failure)
        _sync_terminal_analysis_context(context, failure)
        return failure
    return status


def _latest_terminal_analysis_status(
    path: Path, expected_launch_id: str = ""
) -> dict[str, Any] | None:
    if not path.is_file():
        return None
    try:
        latest = _read_json(path)
    except (OSError, ValueError):
        return None
    if not isinstance(latest, dict):
        return None
    if expected_launch_id and str(latest.get("async_run_id") or "") != expected_launch_id:
        return None
    state = str(latest.get("status") or "").lower()
    return latest if state in TERMINAL_ANALYSIS_STATES else None


def _reconcile_terminal_module_progress(
    context: JobContext, status: dict[str, Any]
) -> dict[str, Any]:
    """Overlay terminal module states from the exact published manifest.

    This is intentionally a display/progress reconciliation only. Existing
    launch-id validation, process cleanup, and durable task-state transitions
    continue to use the runner status payload exactly as before.
    """

    raw_path = str(
        status.get("manifest_path") or context.analysis.manifest_path or ""
    ).strip()
    if not raw_path:
        return status
    manifest_path = Path(raw_path).expanduser()
    if not manifest_path.is_absolute():
        manifest_path = Path(context.analysis.status_path).parent / manifest_path
    try:
        manifest = _read_json(manifest_path)
    except (OSError, ValueError, UnicodeError):
        return status
    progress = normalize_module_progress(
        status,
        manifest,
        selected_modules=context.selected_modules,
    )
    if progress.authority != "analysis_manifest":
        return status
    return {**status, **progress.status_fields()}


def _analysis_process_running(context: JobContext) -> bool:
    if (
        context.analysis.launch_id
        and context.analysis.process_creation_time_100ns
        and context.analysis.process_executable
    ):
        return process_identity_state(
            context.analysis.pid,
            context.analysis.process_creation_time_100ns,
            context.analysis.process_executable,
        ) in {"matching", "unverifiable"}
    return pid_running(context.analysis.pid)


def _analysis_context_superseded(context: JobContext) -> bool:
    expected = str(context.analysis.launch_id or "")
    path = context.context_path
    if path.is_file():
        try:
            raw = json.loads(path.read_text(encoding="utf-8-sig"))
            actual = str((raw.get("analysis") or {}).get("launch_id") or "")
            if actual != expected:
                return True
        except (OSError, ValueError, AttributeError):
            pass
    # An empty launch id is still a valid optimistic-concurrency token for a
    # first launch.  If the canonical file is also empty no process lease can
    # belong to this not-yet-started round, so there is nothing further to do.
    if not expected:
        return False
    try:
        lease = read_process_lease(
            _analysis_lease_path(context), task_label="分析任务"
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


def _persist_analysis_context_if_current(context: JobContext) -> bool:
    try:
        with exclusive_file_lock(_analysis_lock_path(context)):
            if _analysis_context_superseded(context):
                return False
            path = context.context_path
            if path.is_file():
                current = JobContext.read(path)
                if str(current.analysis.launch_id or "") != str(
                    context.analysis.launch_id or ""
                ):
                    return False
                current.analysis = copy.deepcopy(context.analysis)
                current.write(path)
                context.report = copy.deepcopy(current.report)
            else:
                context.write(path)
            return True
    except (OSError, RuntimeError):
        # A concurrent launch owns the lock.  It is safer to leave this older
        # poll result in memory than to overwrite the new launch transaction.
        return False


def persist_analysis_state(context: JobContext) -> bool:
    """Persist only the analysis field without clobbering report progress."""

    if _persist_analysis_context_if_current(context):
        return True
    try:
        latest = JobContext.read(context.context_path)
        context.analysis = copy.deepcopy(latest.analysis)
        context.report = copy.deepcopy(latest.report)
    except (OSError, ValueError):
        pass
    return False


def bind_analysis_manifest(
    context: JobContext,
    manifest_path: Path,
    manifest_sha256: str,
    *,
    analysis_state: str | None = None,
    invalidate_report_approval: bool = False,
) -> bool:
    """Atomically bind an exact result manifest and related review state."""

    canonical = (
        JobContext.read(context.context_path)
        if context.context_path.is_file()
        else context
    )
    try:
        with exclusive_file_lock(_analysis_lock_path(canonical)):
            current = (
                JobContext.read(context.context_path)
                if context.context_path.is_file()
                else copy.deepcopy(context)
            )
            if current.analysis_binding() != context.analysis_binding():
                return False
            if str(current.analysis.launch_id or "") != str(
                context.analysis.launch_id or ""
            ):
                return False
            if str(current.report.state or "").lower() in {
                "launching",
                "launched",
                "running",
                "stopping",
            }:
                return False
            current.analysis.manifest_path = str(manifest_path.expanduser().resolve())
            current.analysis.manifest_sha256 = str(manifest_sha256).upper()
            if analysis_state:
                current.analysis.state = str(analysis_state).lower()
            if invalidate_report_approval:
                current.report.plots_approved = False
                invalidate_disclosure_approval(current.report)
                current.report.state = "blocked"
            current.write(context.context_path)
            context.analysis = copy.deepcopy(current.analysis)
            context.report = copy.deepcopy(current.report)
            return True
    except (OSError, RuntimeError, ValueError):
        try:
            latest = JobContext.read(context.context_path)
            context.analysis = copy.deepcopy(latest.analysis)
            context.report = copy.deepcopy(latest.report)
        except (OSError, ValueError):
            pass
        return False


def _sync_terminal_analysis_context(
    context: JobContext, payload: dict[str, Any], *, persist: bool = True
) -> None:
    state = str(payload.get("status") or "").lower()
    if state not in TERMINAL_ANALYSIS_STATES:
        raise ValueError(f"Not a terminal analysis payload: {payload}")
    previous = copy.deepcopy(context.analysis)
    candidate = copy.deepcopy(context.analysis)
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
        context.analysis = candidate
        if persist and not _persist_analysis_context_if_current(context):
            # Keep the durable state retryable.  The caller still returns the
            # authoritative terminal status to the UI for this poll.
            context.analysis = previous
