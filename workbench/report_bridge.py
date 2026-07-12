from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from .models import JobContext


def report_gui_command(project_root: Path, context_path: Path) -> tuple[str, ...]:
    script = project_root / "reporting" / "report_gui.py"
    if not script.is_file():
        raise FileNotFoundError(f"Report GUI entry does not exist: {script}")
    packaged = project_root / "reporting" / "dist" / "BridgeReportBuilder" / "BridgeReportBuilder.exe"
    venv_python = project_root / "reporting" / ".venv" / "Scripts" / "python.exe"
    if venv_python.is_file():
        return (str(venv_python), str(script), "--job-context", str(context_path))
    if not getattr(sys, "frozen", False):
        return (sys.executable, str(script), "--job-context", str(context_path))
    if packaged.is_file():
        return (str(packaged), "--job-context", str(context_path))
    raise FileNotFoundError("No compatible report GUI runtime is available")


def launch_report_gui(context: JobContext, context_path: Path | None = None) -> subprocess.Popen[bytes]:
    path = context_path or context.write()
    command = report_gui_command(Path(context.project_root), path)
    creationflags = subprocess.CREATE_NEW_PROCESS_GROUP if os.name == "nt" else 0
    stdout_path = Path(context.report.stdout_log or path.with_name("report_gui_stdout.log"))
    stderr_path = Path(context.report.stderr_log or path.with_name("report_gui_stderr.log"))
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
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
    context.report.stdout_log = str(stdout_path)
    context.report.stderr_log = str(stderr_path)
    context.write(path)
    return process
