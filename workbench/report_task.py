from __future__ import annotations

import json
import os
import subprocess
import sys
import ctypes
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .models import JobContext


TERMINAL_REPORT_STATES = {"completed", "failed", "stopped", "launch_failed"}


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
) -> tuple[str, ...]:
    venv_python = project_root / "reporting" / ".venv" / "Scripts" / "python.exe"
    common = (
        "--run-report-job",
        "--project-root", str(project_root),
        "--job-context", str(context_path),
        "--report-status", str(status_path),
        "--report-result", str(result_path),
    )
    if getattr(sys, "frozen", False):
        return (sys.executable, *common)
    python = venv_python if venv_python.is_file() else Path(sys.executable)
    return (str(python), "-m", "workbench", *common)


def launch_report_job(context: JobContext, context_path: Path | None = None) -> ReportLaunchResult:
    path = (context_path or context.write()).resolve()
    job_dir = path.parent
    status_path = job_dir / "report_status.json"
    result_path = job_dir / "report_result.json"
    stdout_path = job_dir / "report_stdout.log"
    stderr_path = job_dir / "report_stderr.log"
    for stale in (status_path, result_path):
        stale.unlink(missing_ok=True)
    command = report_job_command(Path(context.project_root), path, status_path, result_path)
    creationflags = 0
    if os.name == "nt":
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
    with stdout_path.open("ab") as stdout, stderr_path.open("ab") as stderr:
        process = subprocess.Popen(
            command,
            cwd=context.project_root,
            stdin=subprocess.DEVNULL,
            stdout=stdout,
            stderr=stderr,
            creationflags=creationflags,
        )
    context.report.state = "launched"
    context.report.pid = int(process.pid)
    context.report.status_path = str(status_path)
    context.report.result_path = str(result_path)
    context.report.stdout_log = str(stdout_path)
    context.report.stderr_log = str(stderr_path)
    context.write(path)
    return ReportLaunchResult(command, int(process.pid), status_path, result_path)


def _read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        return payload if isinstance(payload, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {"state": "status_read_failed", "message": f"无法读取 {path}"}


def _pid_running(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    if os.name != "nt":
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    process_query_limited_information = 0x1000
    still_active = 259
    handle = ctypes.windll.kernel32.OpenProcess(  # type: ignore[attr-defined]
        process_query_limited_information, False, int(pid)
    )
    if not handle:
        return False
    try:
        exit_code = ctypes.c_ulong()
        if not ctypes.windll.kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)):  # type: ignore[attr-defined]
            return False
        return exit_code.value == still_active
    finally:
        ctypes.windll.kernel32.CloseHandle(handle)  # type: ignore[attr-defined]


def read_report_status(context: JobContext) -> dict[str, Any]:
    status_path = Path(context.report.status_path) if context.report.status_path else context.context_path.parent / "report_status.json"
    result_path = Path(context.report.result_path) if context.report.result_path else context.context_path.parent / "report_result.json"
    status = _read_json(status_path)
    result = _read_json(result_path)
    if result and str(result.get("state") or "").lower() in TERMINAL_REPORT_STATES:
        merged = dict(status)
        merged.update(result)
        return merged
    current = status or {"state": context.report.state or "blocked", "progress_fraction": 0.0}
    state = str(current.get("state") or "").lower()
    if state in {"launched", "running"} and context.report.pid and not _pid_running(context.report.pid):
        return {
            **current,
            "state": "launch_failed",
            "stage": "process_exit",
            "message": "报告子进程已退出，但未写入终态结果；请检查 stderr 日志。",
        }
    return current


def terminate_report_job(context: JobContext) -> None:
    pid = context.report.pid
    if not pid:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(pid), "/T", "/F"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    else:
        os.kill(pid, 15)
    context.report.state = "stopped"
    context.report.pid = None
    context.write()
