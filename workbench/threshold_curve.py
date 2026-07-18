from __future__ import annotations

import json
import math
import os
import re
import subprocess
import uuid
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterable, Mapping

from .config_layers import config_dependency_sha256, load_layered_config
from .models import file_sha256
from .threshold_series import PreviewSeries


REQUEST_TYPE = "threshold_curve_generation"
PREVIEW_ARTIFACT_TYPE = "threshold_curve_preview"
RECORD_ARTIFACT_TYPE = "threshold_curve_record"
SCHEMA_VERSION = 1
_SHA256_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")
_REQUEST_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")


class ThresholdCurveError(RuntimeError):
    """A lightweight threshold-curve task or artifact failed validation."""


@dataclass(frozen=True)
class ThresholdCurvePaths:
    root: Path
    request: Path
    status: Path
    result: Path
    preview: Path
    record: Path
    stop: Path
    stdout: Path
    stderr: Path


@dataclass
class ThresholdCurveRun:
    paths: ThresholdCurvePaths
    process: subprocess.Popen[bytes]
    request_id: str
    config_sha256: str
    bridge_id: str
    data_root: str
    start_date: str
    end_date: str
    module_key: str
    point_id: str


@dataclass(frozen=True)
class ThresholdCurveRecordMetadata:
    record_path: Path | None
    preview_path: Path
    request_id: str
    bridge_id: str
    data_root: Path
    start_date: str
    end_date: str
    config_sha256: str
    module_key: str
    point_id: str
    sensor_type: str
    sample_count: int
    source_sample_count: int
    finite_sample_count: int
    created_at: str
    source_kind: str

    @property
    def date_label(self) -> str:
        return (
            self.start_date
            if self.start_date == self.end_date
            else f"{self.start_date} 至 {self.end_date}"
        )


def _read_object(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise ThresholdCurveError(f"{label}不存在：{path}") from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise ThresholdCurveError(f"{label}无法读取：{path}（{exc}）") from exc
    if not isinstance(payload, dict):
        raise ThresholdCurveError(f"{label}必须是 JSON 对象：{path}")
    return payload


def _write_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_text(
            json.dumps(dict(payload), ensure_ascii=False, indent=2, allow_nan=False)
            + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def resolve_runner(project_root: Path) -> Path:
    for root in (
        project_root / "bin" / "BridgeAnalysisRunner",
        project_root / "dist" / "BridgeAnalysisRunner",
    ):
        for name in ("BridgeAnalysisRunner.exe", "BridgeAnalysisRunner"):
            candidate = root / name
            if candidate.is_file():
                return candidate.resolve()
    raise ThresholdCurveError(
        "未找到生成当前测点曲线所需的后台分析程序；请修复核心分析组件"
    )


def _required_text(payload: Mapping[str, Any], field: str, label: str) -> str:
    value = str(payload.get(field) or "").strip()
    if not value:
        raise ThresholdCurveError(f"{label}缺少{field}")
    return value


def _normalized_date(value: Any, label: str) -> str:
    text = str(value or "").strip()
    try:
        return datetime.strptime(text, "%Y-%m-%d").date().isoformat()
    except ValueError as exc:
        raise ThresholdCurveError(f"{label}不是有效的 YYYY-MM-DD 日期：{text or '<空>'}") from exc


def _validated_dates(start_date: Any, end_date: Any, label: str) -> tuple[str, str]:
    start = _normalized_date(start_date, f"{label}开始日期")
    end = _normalized_date(end_date, f"{label}结束日期")
    if start > end:
        raise ThresholdCurveError(f"{label}开始日期不能晚于结束日期")
    return start, end


def _path_identity(value: str | Path) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    return os.path.normcase(
        os.path.normpath(str(Path(text).expanduser().resolve(strict=False)))
    )


def _same_path(left: str | Path, right: str | Path) -> bool:
    return _path_identity(left) == _path_identity(right)


def _inclusive_date_count(start_date: str, end_date: str) -> int:
    return (
        date.fromisoformat(end_date) - date.fromisoformat(start_date)
    ).days + 1


def _nonnegative_integer(value: Any, label: str) -> int:
    if isinstance(value, bool):
        raise ThresholdCurveError(f"{label}不是非负整数")
    try:
        number = int(value)
    except (TypeError, ValueError) as exc:
        raise ThresholdCurveError(f"{label}不是非负整数") from exc
    if number < 0 or isinstance(value, float) and not value.is_integer():
        raise ThresholdCurveError(f"{label}不是非负整数")
    return number


def prepare_threshold_curve_request(
    *,
    bridge_id: str,
    data_root: Path,
    config_path: Path,
    start_date: str,
    end_date: str,
    module_key: str,
    point_id: str,
    now: datetime | None = None,
    request_id: str | None = None,
) -> tuple[ThresholdCurvePaths, dict[str, Any]]:
    """Prepare one cache-first curve task without any threshold algorithm options."""

    bridge_id = str(bridge_id or "").strip()
    module_key = str(module_key or "").strip()
    point_id = str(point_id or "").strip()
    if not bridge_id:
        raise ThresholdCurveError("桥梁编号不能为空")
    if not module_key:
        raise ThresholdCurveError("当前模块不能为空")
    if not point_id:
        raise ThresholdCurveError("当前测点不能为空")
    start_date, end_date = _validated_dates(start_date, end_date, "曲线任务")
    data_root = data_root.expanduser().resolve()
    config_path = config_path.expanduser().resolve()
    if not data_root.is_dir():
        raise ThresholdCurveError(f"数据目录不存在：{data_root}")
    if not config_path.is_file():
        raise ThresholdCurveError(f"配置文件不存在：{config_path}")

    stamp = (now or datetime.now()).strftime("%Y%m%d_%H%M%S")
    run_id = str(
        request_id or f"threshold_curve_{stamp}_{uuid.uuid4().hex[:8]}"
    ).strip()
    if not _REQUEST_ID_PATTERN.fullmatch(run_id):
        raise ThresholdCurveError(
            "request_id 只能包含字母、数字、点、下划线和连字符，且长度不超过 128"
        )
    root = data_root / "run_logs" / "workbench" / run_id
    paths = ThresholdCurvePaths(
        root=root,
        request=root / "threshold_curve_request.json",
        status=root / "threshold_curve_status.json",
        result=root / "threshold_curve_result.json",
        preview=root / "threshold_curve_preview.json",
        record=root / "threshold_curve_record.json",
        stop=root / "threshold_curve_stop.flag",
        stdout=root / "threshold_curve_stdout.log",
        stderr=root / "threshold_curve_stderr.log",
    )
    config_payload, _ = load_layered_config(config_path)
    configured_bridge = str(config_payload.get("bridge_id") or "").strip()
    if configured_bridge and configured_bridge.casefold() != bridge_id.casefold():
        raise ThresholdCurveError(
            "曲线任务桥梁编号与配置中的 bridge_id 不一致"
        )
    config_hash = config_dependency_sha256(config_path)
    total_dates = _inclusive_date_count(start_date, end_date)
    payload: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "request_type": REQUEST_TYPE,
        "request_id": run_id,
        "bridge_id": bridge_id,
        "data_root": str(data_root),
        "config_path": str(config_path),
        "config_sha256": config_hash,
        "start_date": start_date,
        "end_date": end_date,
        "module_key": module_key,
        "point_id": point_id,
        "prefer_mat_cache": True,
        "threshold_algorithm": None,
        "options": {
            "prefer_mat_cache": True,
            "ignore_existing_cleaning": True,
            "preview_sample_count": 20_000,
        },
        "status_path": str(paths.status),
        "result_path": str(paths.result),
        "preview_path": str(paths.preview),
        "record_path": str(paths.record),
        "stop_file": str(paths.stop),
    }
    _write_json(paths.request, payload)
    _write_json(
        paths.status,
        {
            "schema_version": SCHEMA_VERSION,
            "request_type": REQUEST_TYPE,
            "request_id": run_id,
            "request_path": str(paths.request),
            "status": "prepared",
            "stage": "prepared",
            "module_key": module_key,
            "module_index": 1,
            "module_total": 1,
            "point_id": point_id,
            "point_index": 1,
            "point_total": 1,
            "current_date": "",
            "processed_dates": 0,
            "total_dates": total_dates,
            "progress_fraction": 0.0,
            "progress_percent": 0.0,
            "elapsed_seconds": 0.0,
            "stop_file": str(paths.stop),
            "stop_requested": False,
        },
    )
    return paths, payload


# Keep the familiar request-builder name for callers while the task type remains distinct.
prepare_request = prepare_threshold_curve_request


def launch(
    project_root: Path,
    paths: ThresholdCurvePaths,
    config_sha256: str,
) -> ThresholdCurveRun:
    request = _read_object(paths.request, "曲线生成请求")
    if request.get("request_type") != REQUEST_TYPE:
        raise ThresholdCurveError("曲线生成请求类型无效")
    for field, expected in (
        ("status_path", paths.status),
        ("result_path", paths.result),
        ("preview_path", paths.preview),
        ("record_path", paths.record),
    ):
        if not _same_path(request.get(field) or "", expected):
            raise ThresholdCurveError(f"曲线生成请求的 {field} 不属于本任务")
    if not _same_path(request.get("stop_file") or "", paths.stop):
        raise ThresholdCurveError("曲线生成请求的停止标志不属于本任务")
    request_id = _required_text(request, "request_id", "曲线生成请求")
    if paths.root.name != request_id:
        raise ThresholdCurveError("曲线生成请求目录与 request_id 不一致")
    bridge_id = _required_text(request, "bridge_id", "曲线生成请求")
    module_key = _required_text(request, "module_key", "曲线生成请求")
    point_id = _required_text(request, "point_id", "曲线生成请求")
    start_date, end_date = _validated_dates(
        request.get("start_date"), request.get("end_date"), "曲线生成请求"
    )
    data_root = Path(_required_text(request, "data_root", "曲线生成请求")).expanduser().resolve(strict=False)
    expected_root = data_root / "run_logs" / "workbench" / request_id
    if not _same_path(paths.root, expected_root):
        raise ThresholdCurveError("曲线生成请求目录不属于声明的数据目录")
    if str(request.get("config_sha256") or "").casefold() != str(config_sha256).casefold():
        raise ThresholdCurveError("曲线生成请求的配置版本已变化")
    config_path = Path(_required_text(request, "config_path", "曲线生成请求"))
    if config_dependency_sha256(config_path).casefold() != str(config_sha256).casefold():
        raise ThresholdCurveError("曲线生成请求使用的配置文件已变化")
    runner = resolve_runner(project_root.expanduser().resolve())
    # Only this freshly prepared task flag may be removed before launch.
    paths.stop.unlink(missing_ok=True)
    creationflags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    try:
        with paths.stdout.open("wb") as stdout, paths.stderr.open("wb") as stderr:
            process = subprocess.Popen(
                [str(runner), str(paths.request)],
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                creationflags=creationflags,
            )
    except OSError as exc:
        raise ThresholdCurveError(f"无法启动当前测点曲线任务：{runner}（{exc}）") from exc
    return ThresholdCurveRun(
        paths=paths,
        process=process,
        request_id=request_id,
        config_sha256=str(config_sha256),
        bridge_id=bridge_id,
        data_root=str(data_root),
        start_date=start_date,
        end_date=end_date,
        module_key=module_key,
        point_id=point_id,
    )


def request_stop(paths: ThresholdCurvePaths, *, reason: str = "用户请求安全停止") -> Path:
    """Write only the unique stop flag bound to this lightweight curve request."""

    request = _read_object(paths.request, "曲线生成请求")
    if request.get("request_type") != REQUEST_TYPE:
        raise ThresholdCurveError("曲线生成请求类型无效，未写入停止标志")
    declared = request.get("stop_file") or ""
    if not _same_path(declared, paths.stop) or paths.stop.parent != paths.root:
        raise ThresholdCurveError("停止标志路径不属于本次曲线任务，未执行停止")
    _write_json(
        paths.stop,
        {
            "schema_version": SCHEMA_VERSION,
            "request_type": REQUEST_TYPE,
            "request_id": str(request.get("request_id") or ""),
            "requested_at": datetime.now().astimezone().isoformat(),
            "reason": str(reason or "用户请求安全停止"),
        },
    )
    return paths.stop


def read_status(path: Path, *, expected_request_id: str = "") -> dict[str, Any]:
    try:
        payload = _read_object(path, "曲线生成状态")
    except ThresholdCurveError as exc:
        return {"status": "status_read_failed", "message": str(exc)}
    if payload.get("request_type") != REQUEST_TYPE:
        return {"status": "status_read_failed", "message": "曲线生成状态类型无效"}
    if expected_request_id and str(payload.get("request_id") or "") != expected_request_id:
        return {"status": "status_read_failed", "message": "曲线生成状态不属于当前任务"}
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


def _curve_rows(payload: Mapping[str, Any]) -> list[dict[str, Any]]:
    value = payload.get("curve_records")
    if isinstance(value, dict):
        return [value]
    if isinstance(value, list) and all(isinstance(row, dict) for row in value):
        return value
    raise ThresholdCurveError("当前测点曲线必须包含 curve_records 对象或数组")


def _load_curve_artifact(
    path: Path,
    *,
    allowed_types: frozenset[str],
    expected_bridge_id: str = "",
    expected_data_root: str | Path = "",
    expected_start_date: str = "",
    expected_end_date: str = "",
    expected_config_sha256: str = "",
    expected_request_id: str = "",
    expected_sha256: str = "",
) -> tuple[dict[str, Any], dict[tuple[str, str], PreviewSeries]]:
    path = path.expanduser().resolve()
    if not path.is_file():
        raise ThresholdCurveError(f"当前测点曲线文件不存在：{path}")
    if expected_sha256:
        if not _SHA256_PATTERN.fullmatch(expected_sha256):
            raise ThresholdCurveError("当前测点曲线的预期 SHA256 格式无效")
        if file_sha256(path).casefold() != expected_sha256.casefold():
            raise ThresholdCurveError("当前测点曲线文件完整性校验失败")
    payload = _read_object(path, "当前测点曲线")
    if int(payload.get("schema_version") or 0) != SCHEMA_VERSION:
        raise ThresholdCurveError("当前测点曲线 schema_version 无效")
    if str(payload.get("artifact_type") or "") not in allowed_types:
        raise ThresholdCurveError("当前测点曲线 artifact_type 无效")
    if payload.get("request_type") != REQUEST_TYPE:
        raise ThresholdCurveError("当前测点曲线 request_type 无效")
    for field, label in (
        ("request_id", "任务编号"),
        ("bridge_id", "桥梁编号"),
        ("data_root", "数据目录"),
        ("config_sha256", "配置 SHA256"),
        ("start_date", "开始日期"),
        ("end_date", "结束日期"),
        ("module_key", "模块"),
        ("point_id", "测点"),
        ("sensor_type", "传感器类型"),
    ):
        _required_text(payload, field, f"当前测点曲线（{label}）")
    config_sha = str(payload["config_sha256"])
    if not _SHA256_PATTERN.fullmatch(config_sha):
        raise ThresholdCurveError("当前测点曲线的 config_sha256 格式无效")
    start, end = _validated_dates(
        payload.get("start_date"), payload.get("end_date"), "当前测点曲线"
    )
    if expected_request_id and str(payload["request_id"]) != expected_request_id:
        raise ThresholdCurveError("当前测点曲线不属于指定任务")
    if expected_config_sha256 and config_sha.casefold() != expected_config_sha256.casefold():
        raise ThresholdCurveError("当前测点曲线的配置版本与当前任务不一致")
    if expected_bridge_id and str(payload["bridge_id"]).casefold() != expected_bridge_id.casefold():
        raise ThresholdCurveError("当前测点曲线的桥梁编号与当前任务不一致")
    if expected_data_root and not _same_path(payload["data_root"], expected_data_root):
        raise ThresholdCurveError("当前测点曲线的数据目录与当前任务不一致")
    if expected_start_date and start != _normalized_date(expected_start_date, "预期开始日期"):
        raise ThresholdCurveError("当前测点曲线的开始日期与当前任务不一致")
    if expected_end_date and end != _normalized_date(expected_end_date, "预期结束日期"):
        raise ThresholdCurveError("当前测点曲线的结束日期与当前任务不一致")

    rows = _curve_rows(payload)
    if len(rows) != 1:
        raise ThresholdCurveError("当前测点曲线必须且只能包含一条曲线")
    row = rows[0]
    module_key = _required_text(row, "module_key", "当前测点曲线记录")
    point_id = _required_text(row, "point_id", "当前测点曲线记录")
    sensor_type = _required_text(row, "sensor_type", "当前测点曲线记录")
    times = row.get("times")
    values = row.get("values")
    if not isinstance(times, list) or not isinstance(values, list):
        raise ThresholdCurveError("当前测点曲线缺少时间或数值数组")
    sample_count = _nonnegative_integer(row.get("sample_count"), "当前测点曲线样本数")
    if len(times) != len(values) or sample_count != len(values):
        raise ThresholdCurveError("当前测点曲线的时间、数值和样本数不闭合")
    if sample_count > 50_000:
        raise ThresholdCurveError("当前测点曲线超过 50000 点上限")
    source_count = _nonnegative_integer(
        row.get("source_sample_count"), "当前测点曲线 source_sample_count"
    )
    finite_count = _nonnegative_integer(
        row.get("finite_sample_count"), "当前测点曲线 finite_sample_count"
    )
    if finite_count > source_count:
        raise ThresholdCurveError("当前测点曲线的有限样本数不能大于源样本数")
    if module_key != str(payload["module_key"]):
        raise ThresholdCurveError("当前测点曲线的模块绑定不闭合")
    if point_id != str(payload["point_id"]):
        raise ThresholdCurveError("当前测点曲线的测点绑定不闭合")
    if sensor_type != str(payload["sensor_type"]):
        raise ThresholdCurveError("当前测点曲线的传感器类型绑定不闭合")
    normalized_values: list[float | None] = []
    for value in values:
        if value is None:
            normalized_values.append(None)
            continue
        try:
            number = float(value)
        except (TypeError, ValueError) as exc:
            raise ThresholdCurveError("当前测点曲线含非数值样本") from exc
        normalized_values.append(number if math.isfinite(number) else None)
    series = PreviewSeries(
        module_key=module_key,
        point_id=point_id,
        sensor_type=sensor_type,
        times=tuple(str(value) for value in times),
        values=tuple(normalized_values),
    )
    return payload, {series.key: series}


def load_threshold_curve_preview(
    path: Path,
    *,
    expected_bridge_id: str,
    expected_data_root: str | Path,
    expected_start_date: str,
    expected_end_date: str,
    expected_config_sha256: str,
    expected_module_key: str,
    expected_point_ids: Iterable[str],
    expected_request_id: str = "",
    expected_sha256: str = "",
) -> dict[tuple[str, str], PreviewSeries]:
    """Load a new preview with exact current-task and exact point binding."""

    point_ids = tuple(
        dict.fromkeys(str(value or "").strip() for value in expected_point_ids if str(value or "").strip())
    )
    if not str(expected_bridge_id or "").strip() or not str(expected_data_root or "").strip():
        raise ThresholdCurveError("当前曲线校验缺少桥梁或数据目录")
    if not _SHA256_PATTERN.fullmatch(str(expected_config_sha256 or "")):
        raise ThresholdCurveError("当前曲线校验缺少有效的配置 SHA256")
    if not str(expected_module_key or "").strip() or not point_ids:
        raise ThresholdCurveError("当前曲线校验缺少模块或测点")
    start, end = _validated_dates(expected_start_date, expected_end_date, "当前任务")
    _, previews = _load_curve_artifact(
        path,
        allowed_types=frozenset((PREVIEW_ARTIFACT_TYPE,)),
        expected_sha256=expected_sha256,
        expected_request_id=expected_request_id,
        expected_config_sha256=expected_config_sha256,
        expected_bridge_id=expected_bridge_id,
        expected_data_root=expected_data_root,
        expected_start_date=start,
        expected_end_date=end,
    )
    module_key = str(expected_module_key).strip()
    matches = [
        series
        for series in previews.values()
        if series.module_key == module_key and series.point_id in point_ids
    ]
    if len(matches) != 1:
        expected = "、".join(point_ids)
        raise ThresholdCurveError(
            f"当前测点曲线身份不一致；需要 {module_key}/{expected}"
        )
    return {matches[0].key: matches[0]}


def _metadata_from_record(path: Path) -> ThresholdCurveRecordMetadata:
    path = path.expanduser().resolve()
    payload = _read_object(path, "曲线历史记录")
    if int(payload.get("schema_version") or 0) != SCHEMA_VERSION:
        raise ThresholdCurveError("曲线历史记录 schema_version 无效")
    if payload.get("artifact_type") != RECORD_ARTIFACT_TYPE or payload.get("request_type") != REQUEST_TYPE:
        raise ThresholdCurveError("曲线历史记录类型无效")
    request_id = _required_text(payload, "request_id", "曲线历史记录")
    bridge_id = _required_text(payload, "bridge_id", "曲线历史记录")
    data_root = Path(_required_text(payload, "data_root", "曲线历史记录")).expanduser().resolve(strict=False)
    config_sha = _required_text(payload, "config_sha256", "曲线历史记录")
    if not _SHA256_PATTERN.fullmatch(config_sha):
        raise ThresholdCurveError("曲线历史记录的 config_sha256 格式无效")
    start, end = _validated_dates(payload.get("start_date"), payload.get("end_date"), "曲线历史记录")
    module_key = _required_text(payload, "module_key", "曲线历史记录")
    point_id = _required_text(payload, "point_id", "曲线历史记录")
    preview_path = Path(
        _required_text(payload, "preview_path", "曲线历史记录")
    ).expanduser().resolve(strict=False)
    preview_sha = _required_text(payload, "preview_sha256", "曲线历史记录")
    if not _SHA256_PATTERN.fullmatch(preview_sha):
        raise ThresholdCurveError("曲线历史记录的 preview_sha256 格式无效")
    if not preview_path.is_file() or file_sha256(preview_path).casefold() != preview_sha.casefold():
        raise ThresholdCurveError("曲线历史记录绑定的预览文件不存在或已变化")
    previews = load_threshold_curve_preview(
        preview_path,
        expected_bridge_id=bridge_id,
        expected_data_root=data_root,
        expected_start_date=start,
        expected_end_date=end,
        expected_config_sha256=config_sha,
        expected_module_key=module_key,
        expected_point_ids=(point_id,),
        expected_request_id=request_id,
        expected_sha256=preview_sha,
    )
    if not _same_path(path.parent, preview_path.parent):
        raise ThresholdCurveError("曲线历史记录与预览不在同一任务目录")
    series = next(iter(previews.values()))
    sensor_type = _required_text(payload, "sensor_type", "曲线历史记录")
    if sensor_type != series.sensor_type:
        raise ThresholdCurveError("曲线历史记录的传感器类型与预览不一致")
    stated_count = payload.get("sample_count")
    if stated_count is not None and _nonnegative_integer(
        stated_count, "曲线历史记录的样本数"
    ) != len(series.values):
        raise ThresholdCurveError("曲线历史记录的样本数与预览不闭合")
    curve_record_count = payload.get("curve_record_count")
    if curve_record_count is not None and _nonnegative_integer(
        curve_record_count, "曲线历史记录的 curve_record_count"
    ) != 1:
        raise ThresholdCurveError("曲线历史记录的 curve_record_count 必须为 1")
    source_count, finite_count = _curve_counts(preview_path)
    record_source = payload.get("source_sample_count")
    record_finite = payload.get("finite_sample_count")
    if record_source is not None and _nonnegative_integer(
        record_source, "曲线历史记录的源样本数"
    ) != source_count:
        raise ThresholdCurveError("曲线历史记录的源样本数与预览不一致")
    if record_finite is not None and _nonnegative_integer(
        record_finite, "曲线历史记录的有限样本数"
    ) != finite_count:
        raise ThresholdCurveError("曲线历史记录的有限样本数与预览不一致")
    return ThresholdCurveRecordMetadata(
        record_path=path,
        preview_path=preview_path,
        request_id=request_id,
        bridge_id=bridge_id,
        data_root=data_root,
        start_date=start,
        end_date=end,
        config_sha256=config_sha,
        module_key=module_key,
        point_id=point_id,
        sensor_type=sensor_type,
        sample_count=len(series.values),
        source_sample_count=source_count,
        finite_sample_count=finite_count,
        created_at=str(payload.get("created_at") or ""),
        source_kind=RECORD_ARTIFACT_TYPE,
    )


def load_threshold_curve_record(path: Path) -> ThresholdCurveRecordMetadata:
    return _metadata_from_record(path)


def load_threshold_curve_reference(
    path: Path,
) -> dict[tuple[str, str], PreviewSeries]:
    """Load a user-selected curve without binding it to the current task.

    Only the independent curve contract is accepted. Beta proposal previews
    must be regenerated as an independent curve before manual use.
    """

    resolved = path.expanduser().resolve()
    payload = _read_object(resolved, "工作平台曲线记录")
    artifact_type = str(payload.get("artifact_type") or "")
    if artifact_type == PREVIEW_ARTIFACT_TYPE:
        _, previews = _load_curve_artifact(
            resolved,
            allowed_types=frozenset((PREVIEW_ARTIFACT_TYPE,)),
        )
        return previews
    if artifact_type == RECORD_ARTIFACT_TYPE:
        metadata = load_threshold_curve_record(resolved)
        _, previews = _load_curve_artifact(
            metadata.preview_path,
            allowed_types=frozenset((PREVIEW_ARTIFACT_TYPE,)),
        )
        return previews
    raise ThresholdCurveError(
        "所选文件不是新版独立曲线记录；旧版自动清洗建议曲线不再兼容，请重新生成当前测点曲线"
    )


def load_current_threshold_curve(
    path: Path,
    *,
    expected_bridge_id: str,
    expected_data_root: str | Path,
    expected_start_date: str,
    expected_end_date: str,
    expected_config_sha256: str,
    expected_module_key: str,
    expected_point_ids: Iterable[str],
) -> dict[tuple[str, str], PreviewSeries]:
    """Load an exactly bound current-task curve from the independent contract."""

    resolved = path.expanduser().resolve()
    payload = _read_object(resolved, "当前任务曲线")
    artifact_type = str(payload.get("artifact_type") or "")
    if artifact_type == PREVIEW_ARTIFACT_TYPE:
        return load_threshold_curve_preview(
            resolved,
            expected_bridge_id=expected_bridge_id,
            expected_data_root=expected_data_root,
            expected_start_date=expected_start_date,
            expected_end_date=expected_end_date,
            expected_config_sha256=expected_config_sha256,
            expected_module_key=expected_module_key,
            expected_point_ids=expected_point_ids,
        )
    if artifact_type == RECORD_ARTIFACT_TYPE:
        metadata = load_threshold_curve_record(resolved)
        return load_threshold_curve_preview(
            metadata.preview_path,
            expected_bridge_id=expected_bridge_id,
            expected_data_root=expected_data_root,
            expected_start_date=expected_start_date,
            expected_end_date=expected_end_date,
            expected_config_sha256=expected_config_sha256,
            expected_module_key=expected_module_key,
            expected_point_ids=expected_point_ids,
            expected_request_id=metadata.request_id,
        )
    raise ThresholdCurveError(
        "当前任务曲线不是新版独立曲线记录；请重新生成当前测点曲线"
    )


def _curve_counts(path: Path) -> tuple[int, int]:
    payload = _read_object(path, "曲线产物")
    rows = payload.get("curve_records")
    if isinstance(rows, dict):
        row = rows
    elif isinstance(rows, list) and len(rows) == 1 and isinstance(rows[0], dict):
        row = rows[0]
    else:
        raise ThresholdCurveError("曲线产物必须且只能包含一条曲线记录")
    source = row.get("source_sample_count")
    finite = row.get("finite_sample_count")
    source_count = _nonnegative_integer(source, "曲线产物 source_sample_count")
    finite_count = _nonnegative_integer(finite, "曲线产物 finite_sample_count")
    if source_count < 0 or finite_count < 0 or finite_count > source_count:
        raise ThresholdCurveError("曲线产物的源样本与有限样本计数无效")
    return source_count, finite_count


def load_result(
    path: Path,
    *,
    expected_request_id: str = "",
    expected_config_sha256: str = "",
) -> dict[str, Any]:
    """Load the runner result and close both record and preview hashes."""

    payload = _read_object(path.expanduser().resolve(), "曲线生成结果")
    if int(payload.get("schema_version") or 0) != SCHEMA_VERSION:
        raise ThresholdCurveError("曲线生成结果 schema_version 无效")
    if payload.get("request_type") != REQUEST_TYPE or payload.get("artifact_type") != "threshold_curve_generation_result":
        raise ThresholdCurveError("曲线生成结果类型无效")
    if expected_request_id and str(payload.get("request_id") or "") != expected_request_id:
        raise ThresholdCurveError("曲线生成结果不属于当前任务")
    config_sha = _required_text(payload, "config_sha256", "曲线生成结果")
    if not _SHA256_PATTERN.fullmatch(config_sha):
        raise ThresholdCurveError("曲线生成结果的 config_sha256 格式无效")
    if expected_config_sha256 and config_sha.casefold() != expected_config_sha256.casefold():
        raise ThresholdCurveError("曲线生成结果的配置版本与请求不一致")
    record_path = Path(_required_text(payload, "record_path", "曲线生成结果")).expanduser().resolve(strict=False)
    record_sha = _required_text(payload, "record_sha256", "曲线生成结果")
    if not _SHA256_PATTERN.fullmatch(record_sha):
        raise ThresholdCurveError("曲线生成结果的 record_sha256 格式无效")
    if not record_path.is_file() or file_sha256(record_path).casefold() != record_sha.casefold():
        raise ThresholdCurveError("曲线生成结果绑定的历史记录不存在或已变化")
    metadata = load_threshold_curve_record(record_path)
    result_preview_path = Path(
        _required_text(payload, "preview_path", "曲线生成结果")
    ).expanduser().resolve(strict=False)
    result_preview_sha = _required_text(payload, "preview_sha256", "曲线生成结果")
    if not _SHA256_PATTERN.fullmatch(result_preview_sha):
        raise ThresholdCurveError("曲线生成结果的 preview_sha256 格式无效")
    if not _same_path(result_preview_path, metadata.preview_path):
        raise ThresholdCurveError("曲线生成结果与历史记录绑定的预览路径不一致")
    if file_sha256(metadata.preview_path).casefold() != result_preview_sha.casefold():
        raise ThresholdCurveError("曲线生成结果绑定的预览文件已变化")
    for field, actual in (
        ("request_id", metadata.request_id),
        ("bridge_id", metadata.bridge_id),
        ("data_root", str(metadata.data_root)),
        ("start_date", metadata.start_date),
        ("end_date", metadata.end_date),
        ("config_sha256", metadata.config_sha256),
        ("module_key", metadata.module_key),
        ("point_id", metadata.point_id),
        ("sensor_type", metadata.sensor_type),
    ):
        expected = str(payload.get(field) or "").strip()
        if field == "data_root":
            matches = bool(expected) and _same_path(expected, actual)
        elif field in {"bridge_id", "config_sha256"}:
            matches = expected.casefold() == str(actual).casefold()
        else:
            matches = expected == str(actual)
        if not matches:
            raise ThresholdCurveError(f"曲线生成结果与历史记录的 {field} 绑定不一致")
    if _nonnegative_integer(
        payload.get("curve_record_count"), "曲线生成结果的 curve_record_count"
    ) != 1:
        raise ThresholdCurveError("曲线生成结果的 curve_record_count 必须为 1")
    if _nonnegative_integer(
        payload.get("source_sample_count"), "曲线生成结果的源样本数"
    ) != metadata.source_sample_count:
        raise ThresholdCurveError("曲线生成结果的源样本数与历史记录不一致")
    if _nonnegative_integer(
        payload.get("finite_sample_count"), "曲线生成结果的有限样本数"
    ) != metadata.finite_sample_count:
        raise ThresholdCurveError("曲线生成结果的有限样本数与历史记录不一致")
    if _nonnegative_integer(
        payload.get("sample_count"), "曲线生成结果的预览样本数"
    ) != metadata.sample_count:
        raise ThresholdCurveError("曲线生成结果的预览样本数与历史记录不一致")
    payload["record_metadata"] = metadata
    return payload


def discover_threshold_curve_records(
    data_roots: str | Path | Iterable[str | Path],
) -> tuple[ThresholdCurveRecordMetadata, ...]:
    """Return validated history metadata for ordinary bridge/date/point lists."""

    roots = (
        (data_roots,)
        if isinstance(data_roots, (str, Path))
        else tuple(data_roots)
    )
    records: list[ThresholdCurveRecordMetadata] = []
    for raw_root in roots:
        root = Path(raw_root).expanduser().resolve(strict=False)
        logs = root / "run_logs"
        if not logs.is_dir():
            continue
        record_paths = sorted(
            logs.rglob("threshold_curve_record*.json"),
            key=lambda item: item.stat().st_mtime_ns if item.is_file() else 0,
            reverse=True,
        )
        for record_path in record_paths:
            try:
                metadata = _metadata_from_record(record_path)
            except (ThresholdCurveError, OSError, ValueError):
                continue
            if not _same_path(metadata.data_root, root):
                continue
            records.append(metadata)
    records.sort(
        key=lambda row: (
            row.created_at,
            row.preview_path.stat().st_mtime_ns if row.preview_path.is_file() else 0,
        ),
        reverse=True,
    )
    return tuple(records)


# A list-layer-friendly synonym; neither API exposes raw JSON to ordinary users.
discover_threshold_curve_history = discover_threshold_curve_records


__all__ = [
    "PREVIEW_ARTIFACT_TYPE",
    "PreviewSeries",
    "RECORD_ARTIFACT_TYPE",
    "REQUEST_TYPE",
    "SCHEMA_VERSION",
    "ThresholdCurveError",
    "ThresholdCurvePaths",
    "ThresholdCurveRecordMetadata",
    "ThresholdCurveRun",
    "discover_threshold_curve_history",
    "discover_threshold_curve_records",
    "launch",
    "load_result",
    "load_current_threshold_curve",
    "load_threshold_curve_preview",
    "load_threshold_curve_record",
    "load_threshold_curve_reference",
    "prepare_request",
    "prepare_threshold_curve_request",
    "read_status",
    "request_stop",
    "resolve_runner",
]
