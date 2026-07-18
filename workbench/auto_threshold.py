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
from .threshold_series import PreviewSeries


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
    stop: Path
    stdout: Path
    stderr: Path


@dataclass
class AutoThresholdRun:
    paths: AutoThresholdPaths
    process: subprocess.Popen[bytes]
    config_sha256: str
    bridge_id: str
    data_root: str
    start_date: str
    end_date: str


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
    bridge_id: str,
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
    bridge_id = str(bridge_id or "").strip()
    if not bridge_id:
        raise AutoThresholdError("桥梁编号不能为空")
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
        stop=root / "auto_threshold_stop.flag",
        stdout=root / "auto_threshold_stdout.log",
        stderr=root / "auto_threshold_stderr.log",
    )
    config_hash = config_dependency_sha256(config_path)
    selected_modules = options.get("module_keys", [])
    module_total = len(selected_modules) if isinstance(selected_modules, list) else 0
    payload = {
        "schema_version": 1,
        "request_type": "auto_threshold_proposal",
        "request_id": run_id,
        "bridge_id": bridge_id,
        "data_root": str(data_root),
        "config_path": str(config_path),
        "config_sha256": config_hash,
        "start_date": start_date,
        "end_date": end_date,
        "options": options,
        "status_path": str(paths.status),
        "result_path": str(paths.result),
        "preview_path": str(paths.preview),
        "stop_file": str(paths.stop),
    }
    _write_json(paths.request, payload)
    _write_json(
        paths.status,
        {
            "schema_version": 1,
            "status": "prepared",
            "request_type": "auto_threshold_proposal",
            "request_id": run_id,
            "request_path": str(paths.request),
            "module_key": "",
            "point_id": "",
            "module_index": 0,
            "module_total": module_total,
            "point_index": 0,
            "point_total": 0,
            "stage": "prepared",
            "current_date": "",
            "processed_dates": 0,
            "total_dates": 0,
            "progress_fraction": 0.0,
            "progress_percent": 0.0,
            "elapsed_seconds": 0.0,
            "stop_file": str(paths.stop),
            "stop_requested": False,
        },
    )
    return paths, payload


def launch(project_root: Path, paths: AutoThresholdPaths, config_sha256: str) -> AutoThresholdRun:
    runner = resolve_runner(project_root.resolve())
    try:
        request = json.loads(paths.request.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AutoThresholdError(f"自动清洗建议请求无法读取：{exc}") from exc
    if not isinstance(request, dict):
        raise AutoThresholdError("自动清洗建议请求格式无效")
    declared_stop = str(request.get("stop_file") or "")
    if _normalized_context_path(declared_stop) != _normalized_context_path(paths.stop):
        raise AutoThresholdError("自动清洗建议请求的停止标志不属于本任务")
    paths.stop.unlink(missing_ok=True)
    creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with paths.stdout.open("wb") as stdout, paths.stderr.open("wb") as stderr:
        process = subprocess.Popen(
            [str(runner), str(paths.request)],
            stdin=subprocess.DEVNULL,
            stdout=stdout,
            stderr=stderr,
            creationflags=creationflags,
        )
    return AutoThresholdRun(
        paths,
        process,
        config_sha256,
        str(request.get("bridge_id") or ""),
        str(request.get("data_root") or ""),
        str(request.get("start_date") or ""),
        str(request.get("end_date") or ""),
    )


def read_status(path: Path) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        return {"status": "status_read_failed", "message": str(exc)}
    if not isinstance(payload, dict):
        return {"status": "status_read_failed"}
    stop_file = str(payload.get("stop_file") or "")
    payload["stop_file"] = stop_file
    if "progress_fraction" not in payload and "progress_percent" in payload:
        try:
            payload["progress_fraction"] = float(payload["progress_percent"]) / 100.0
        except (TypeError, ValueError):
            pass
    if "progress_percent" not in payload and "progress_fraction" in payload:
        try:
            payload["progress_percent"] = float(payload["progress_fraction"]) * 100.0
        except (TypeError, ValueError):
            pass
    return payload


def request_stop(
    paths: AutoThresholdPaths,
    *,
    reason: str = "用户请求安全停止自动清洗建议",
) -> Path:
    """Request cooperative stop without terminating an unrelated process."""

    try:
        request = json.loads(paths.request.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AutoThresholdError(f"自动清洗建议请求无法读取，未写入停止标志：{exc}") from exc
    if not isinstance(request, dict) or request.get("request_type") != "auto_threshold_proposal":
        raise AutoThresholdError("自动清洗建议请求类型无效，未写入停止标志")
    declared_stop = str(request.get("stop_file") or "")
    if (
        _normalized_context_path(declared_stop)
        != _normalized_context_path(paths.stop)
        or paths.stop.parent != paths.root
    ):
        raise AutoThresholdError("停止标志路径不属于本次自动清洗建议任务，未执行停止")
    _write_json(
        paths.stop,
        {
            "schema_version": 1,
            "request_type": "auto_threshold_proposal",
            "request_id": str(request.get("request_id") or ""),
            "requested_at": datetime.now().astimezone().isoformat(),
            "reason": str(reason or "用户请求安全停止自动清洗建议"),
        },
    )
    return paths.stop


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
    raise AutoThresholdError("自动清洗预览 curve_records 必须是对象数组")


def _artifact_series_rows(payload: dict[str, Any]) -> list[dict[str, Any]]:
    """Read the sole current Beta preview-series field."""

    if "curve_records" not in payload:
        raise AutoThresholdError("自动清洗预览缺少 curve_records")
    return _series_rows(payload.get("curve_records"))


def _normalized_context_path(value: str | Path) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    return os.path.normcase(
        os.path.normpath(str(Path(text).expanduser().resolve(strict=False)))
    )


def _normalized_context_date(value: Any, field_label: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    try:
        return datetime.strptime(text, "%Y-%m-%d").date().isoformat()
    except ValueError as exc:
        raise AutoThresholdError(
            f"自动清洗预览的 {field_label} 不是有效的 YYYY-MM-DD 日期：{text}"
        ) from exc


def load_preview_artifact(
    path: Path,
    *,
    expected_sha256: str = "",
    expected_request_id: str = "",
    expected_config_sha256: str = "",
    expected_bridge_id: str = "",
    expected_data_root: str | Path = "",
    expected_start_date: str = "",
    expected_end_date: str = "",
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
    if not isinstance(payload, dict):
        raise AutoThresholdError("曲线预览文件格式无效")
    artifact_type = str(payload.get("artifact_type") or "")
    if artifact_type != "auto_threshold_preview":
        raise AutoThresholdError("自动清洗预览文件类型无效")
    if int(payload.get("schema_version") or 0) != 1:
        raise AutoThresholdError("不支持的曲线预览文件版本")
    if str(payload.get("request_type") or "") != "auto_threshold_proposal":
        raise AutoThresholdError("自动清洗预览 request_type 无效")
    if expected_request_id and str(payload.get("request_id") or "") != expected_request_id:
        raise AutoThresholdError("自动清洗预览 request_id 与建议结果不一致")
    if expected_config_sha256 and str(payload.get("config_sha256") or "").lower() != expected_config_sha256.lower():
        raise AutoThresholdError("自动清洗预览所用配置版本与建议结果不一致")
    if expected_bridge_id:
        artifact_bridge_id = str(payload.get("bridge_id") or "").strip()
        if not artifact_bridge_id:
            raise AutoThresholdError("自动清洗预览缺少桥梁编号，不能确认它属于当前任务")
        if artifact_bridge_id.casefold() != str(expected_bridge_id).strip().casefold():
            raise AutoThresholdError("自动清洗预览的桥梁编号与当前任务不一致")
    if expected_data_root:
        artifact_data_root = str(payload.get("data_root") or "").strip()
        if not artifact_data_root:
            raise AutoThresholdError("自动清洗预览缺少数据目录，不能确认它属于当前任务")
        if _normalized_context_path(artifact_data_root) != _normalized_context_path(
            expected_data_root
        ):
            raise AutoThresholdError("自动清洗预览的数据目录与当前任务不一致")
    expected_dates = (
        ("start_date", expected_start_date, "开始日期"),
        ("end_date", expected_end_date, "结束日期"),
    )
    for field_name, expected_value, field_label in expected_dates:
        if not str(expected_value or "").strip():
            continue
        artifact_value = payload.get(field_name)
        if not str(artifact_value or "").strip():
            raise AutoThresholdError(
                f"自动清洗预览缺少{field_label}，不能确认它属于当前任务"
            )
        if _normalized_context_date(
            artifact_value, field_label
        ) != _normalized_context_date(expected_value, f"预期{field_label}"):
            raise AutoThresholdError(
                f"自动清洗预览的{field_label}与当前任务不一致"
            )

    result: dict[tuple[str, str], PreviewSeries] = {}
    for row in _artifact_series_rows(payload):
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
