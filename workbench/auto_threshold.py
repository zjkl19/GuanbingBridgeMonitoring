from __future__ import annotations

import json
import os
import subprocess
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from .models import file_sha256


class AutoThresholdError(RuntimeError):
    pass


DEFAULT_MODULE_KEYS = (
    "temperature",
    "humidity",
    "rainfall",
    "wind_speed",
    "earthquake",
    "deflection",
    "bearing_displacement",
    "tilt",
    "gnss",
    "acceleration",
    "cable_accel",
    "strain",
    "dynamic_strain",
    "dynamic_strain_lowpass",
    "crack",
)


@dataclass(frozen=True)
class AutoThresholdPaths:
    root: Path
    request: Path
    status: Path
    result: Path
    stdout: Path
    stderr: Path


@dataclass
class AutoThresholdRun:
    paths: AutoThresholdPaths
    process: subprocess.Popen[bytes]
    config_sha256: str


def _write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def resolve_runner(project_root: Path) -> Path:
    names = ("BridgeAnalysisRunner.exe", "BridgeAnalysisRunner")
    roots = (
        project_root / "bin" / "BridgeAnalysisRunner",
        project_root / "dist" / "BridgeAnalysisRunner",
    )
    for root in roots:
        for name in names:
            candidate = root / name
            if candidate.is_file():
                return candidate.resolve()
    raise AutoThresholdError(
        "未找到支持自动清洗建议的 BridgeAnalysisRunner；请先重新构建核心 Runner"
    )


def prepare_request(
    *,
    data_root: Path,
    config_path: Path,
    start_date: str,
    end_date: str,
    options: dict[str, Any],
    now: datetime | None = None,
    request_id: str | None = None,
) -> tuple[AutoThresholdPaths, dict[str, Any]]:
    data_root = data_root.expanduser().resolve()
    config_path = config_path.expanduser().resolve()
    if not data_root.is_dir():
        raise AutoThresholdError(f"数据目录不存在：{data_root}")
    if not config_path.is_file():
        raise AutoThresholdError(f"配置文件不存在：{config_path}")
    stamp = (now or datetime.now()).strftime("%Y%m%d_%H%M%S")
    run_id = request_id or f"auto_threshold_{stamp}_{uuid.uuid4().hex[:8]}"
    root = data_root / "run_logs" / "workbench" / run_id
    paths = AutoThresholdPaths(
        root=root,
        request=root / "auto_threshold_request.json",
        status=root / "auto_threshold_status.json",
        result=root / "auto_threshold_result.json",
        stdout=root / "auto_threshold_stdout.log",
        stderr=root / "auto_threshold_stderr.log",
    )
    config_hash = file_sha256(config_path)
    payload = {
        "schema_version": 1,
        "request_type": "auto_threshold_proposal",
        "request_id": run_id,
        "data_root": str(data_root),
        "config_path": str(config_path),
        "config_sha256": config_hash,
        "start_date": start_date,
        "end_date": end_date,
        "options": options,
        "status_path": str(paths.status),
        "result_path": str(paths.result),
    }
    _write_json(paths.request, payload)
    _write_json(
        paths.status,
        {
            "status": "prepared",
            "request_type": "auto_threshold_proposal",
            "request_id": run_id,
            "request_path": str(paths.request),
        },
    )
    return paths, payload


def launch(project_root: Path, paths: AutoThresholdPaths, config_sha256: str) -> AutoThresholdRun:
    runner = resolve_runner(project_root.resolve())
    creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with paths.stdout.open("wb") as stdout, paths.stderr.open("wb") as stderr:
        process = subprocess.Popen(
            [str(runner), str(paths.request)],
            stdin=subprocess.DEVNULL,
            stdout=stdout,
            stderr=stderr,
            creationflags=creationflags,
        )
    return AutoThresholdRun(paths, process, config_sha256)


def read_status(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        return {"status": "status_read_failed", "message": str(exc)}
    return payload if isinstance(payload, dict) else {"status": "status_read_failed"}


def load_result(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict) or payload.get("request_type") != "auto_threshold_proposal":
        raise AutoThresholdError("自动清洗建议结果格式无效")
    proposals = payload.get("proposals", [])
    if proposals is None:
        payload["proposals"] = []
    elif isinstance(proposals, dict):
        payload["proposals"] = [proposals]
    elif not isinstance(proposals, list):
        raise AutoThresholdError("自动清洗建议 proposals 必须是数组")
    return payload
