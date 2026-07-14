from __future__ import annotations

import json
import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .models import JobContext
from .config_layers import config_dependency_sha256, load_layered_config


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
    return json.loads(path.read_text(encoding="utf-8-sig"))


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
            "async_run_id": context.job_id,
            "stop_file": context.analysis.stop_path,
            "async_status_file": context.analysis.status_path,
        }

    def write(self, context: JobContext) -> Path:
        target = Path(context.analysis.request_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(self.build(context), ensure_ascii=False, indent=2), encoding="utf-8")
        Path(context.analysis.status_path).write_text(
            json.dumps({"status": "prepared", "async_run_id": context.job_id}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
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
        AnalysisRequestBuilder().write(context)
        command = self.command(context, executor)
        stdout_path = Path(context.analysis.stdout_log)
        stderr_path = Path(context.analysis.stderr_log)
        stdout_path.parent.mkdir(parents=True, exist_ok=True)
        creationflags = 0
        if os.name == "nt":
            creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_NO_WINDOW
        with stdout_path.open("ab") as stdout, stderr_path.open("ab") as stderr:
            process = self._popen(
                command,
                cwd=str(self.project_root),
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                creationflags=creationflags,
            )
        context.analysis.state = "launched"
        context.analysis.executor_type = executor.kind
        context.analysis.executable = str(executor.executable)
        context.analysis.pid = int(process.pid)
        context.write()
        return LaunchResult(int(process.pid), executor, command)

    @staticmethod
    def request_stop(context: JobContext) -> Path:
        stop_path = Path(context.analysis.stop_path)
        stop_path.parent.mkdir(parents=True, exist_ok=True)
        stop_path.write_text("stop requested by PySide6 workbench\n", encoding="utf-8")
        context.analysis.state = "stopping"
        context.write()
        return stop_path


def read_analysis_status(context: JobContext) -> dict[str, Any]:
    path = Path(context.analysis.status_path)
    if not path.is_file():
        return {"status": context.analysis.state or "unknown"}
    try:
        return _read_json(path)
    except (OSError, json.JSONDecodeError) as exc:
        return {"status": "status_read_failed", "message": str(exc)}
