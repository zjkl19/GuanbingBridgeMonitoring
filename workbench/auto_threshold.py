from __future__ import annotations

import json
import math
import os
import subprocess
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from .models import file_sha256
from .config_layers import config_dependency_sha256


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
    preview: Path
    stdout: Path
    stderr: Path


@dataclass
class AutoThresholdRun:
    paths: AutoThresholdPaths
    process: subprocess.Popen[bytes]
    config_sha256: str


@dataclass(frozen=True)
class PreviewSeries:
    module_key: str
    point_id: str
    sensor_type: str
    times: tuple[str, ...]
    values: tuple[float | None, ...]

    @property
    def key(self) -> tuple[str, str]:
        return self.module_key, self.point_id


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
        "未找到自动清洗建议所需的后台分析程序；请重新安装或修复核心分析组件"
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
        preview=root / "auto_threshold_preview.json",
        stdout=root / "auto_threshold_stdout.log",
        stderr=root / "auto_threshold_stderr.log",
    )
    config_hash = config_dependency_sha256(config_path)
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
        "preview_path": str(paths.preview),
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


def _series_rows(value: Any) -> list[dict[str, Any]]:
    if value is None:
        return []
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list) and all(isinstance(row, dict) for row in value):
        return value
    raise AutoThresholdError("自动清洗预览 preview_series 必须是对象数组")


def load_preview_artifact(
    path: Path,
    *,
    expected_sha256: str = "",
    expected_request_id: str = "",
    expected_config_sha256: str = "",
    expected_series_count: int | None = None,
) -> dict[tuple[str, str], PreviewSeries]:
    path = path.expanduser().resolve()
    if not path.is_file():
        raise AutoThresholdError(f"自动清洗预览文件不存在：{path}")
    if expected_sha256 and file_sha256(path).lower() != expected_sha256.lower():
        raise AutoThresholdError("自动清洗预览文件完整性校验码与后台分析结果不一致")
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AutoThresholdError(f"自动清洗预览文件无法读取：{exc}") from exc
    if not isinstance(payload, dict) or payload.get("artifact_type") != "auto_threshold_preview":
        raise AutoThresholdError("自动清洗预览文件类型无效")
    if int(payload.get("schema_version") or 0) != 1:
        raise AutoThresholdError("不支持的自动清洗预览文件版本")
    if expected_request_id and str(payload.get("request_id") or "") != expected_request_id:
        raise AutoThresholdError("自动清洗预览 request_id 与建议结果不一致")
    if expected_config_sha256 and str(payload.get("config_sha256") or "").lower() != expected_config_sha256.lower():
        raise AutoThresholdError("自动清洗预览所用配置版本与建议结果不一致")

    result: dict[tuple[str, str], PreviewSeries] = {}
    for row in _series_rows(payload.get("preview_series")):
        module_key = str(row.get("module_key") or "").strip()
        point_id = str(row.get("point_id") or "").strip()
        times = row.get("times")
        values = row.get("values")
        if not module_key or not point_id or not isinstance(times, list) or not isinstance(values, list):
            raise AutoThresholdError("自动清洗预览序列缺少模块、测点、时间或数值")
        if len(times) != len(values) or int(row.get("sample_count") or 0) != len(values):
            raise AutoThresholdError(f"自动清洗预览序列点数不闭合：{module_key}/{point_id}")
        if len(values) > 50_000:
            raise AutoThresholdError(f"自动清洗预览序列超过 50000 点上限：{module_key}/{point_id}")
        normalized_values: list[float | None] = []
        for value in values:
            if value is None:
                normalized_values.append(None)
                continue
            try:
                number = float(value)
            except (TypeError, ValueError) as exc:
                raise AutoThresholdError(f"自动清洗预览含非数值：{module_key}/{point_id}") from exc
            normalized_values.append(number if math.isfinite(number) else None)
        series = PreviewSeries(
            module_key=module_key,
            point_id=point_id,
            sensor_type=str(row.get("sensor_type") or ""),
            times=tuple(str(value) for value in times),
            values=tuple(normalized_values),
        )
        if series.key in result:
            raise AutoThresholdError(f"自动清洗预览含重复序列：{module_key}/{point_id}")
        result[series.key] = series
    if expected_series_count is not None and len(result) != expected_series_count:
        raise AutoThresholdError(
            f"自动清洗预览序列数与后台分析结果不一致：{len(result)} != {expected_series_count}"
        )
    return result
