from __future__ import annotations

import json
import math
import os
import re
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Mapping

from .models import file_sha256


REQUEST_TYPE = "fig_threshold_interaction"
SCHEMA_VERSION = 1
SUPPORTED_OPERATIONS = frozenset(("band", "box_lower", "box_upper"))
_SHA256_PATTERN = re.compile(r"^[0-9a-fA-F]{64}$")


class FigThresholdError(RuntimeError):
    """The FIG interaction could not be started or its evidence was invalid."""


class FigThresholdCancelled(FigThresholdError):
    """The operator cancelled the interactive MATLAB FIG operation."""

    def __init__(self, message: str, *, status: Mapping[str, Any] | None = None) -> None:
        super().__init__(message)
        self.status = dict(status or {})


@dataclass(frozen=True)
class FigThresholdPaths:
    root: Path
    request: Path
    status: Path
    result: Path
    stdout: Path
    stderr: Path


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


def _read_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError as exc:
        raise FigThresholdError(f"{label}不存在：{path}") from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise FigThresholdError(f"{label}无法读取：{path}（{exc}）") from exc
    if not isinstance(payload, dict):
        raise FigThresholdError(f"{label}必须是 JSON 对象：{path}")
    return payload


def _canonical_path(value: str | Path) -> Path:
    return Path(value).expanduser().resolve(strict=False)


def _same_path(left: str | Path, right: str | Path) -> bool:
    return os.path.normcase(os.path.normpath(str(_canonical_path(left)))) == os.path.normcase(
        os.path.normpath(str(_canonical_path(right)))
    )


def _application_data_root() -> Path:
    local = str(os.environ.get("LOCALAPPDATA") or "").strip()
    base = Path(local) if local else Path(tempfile.gettempdir())
    return base / "BridgeMonitoringWorkbench" / "fig_threshold"


def resolve_runner(project_root: Path) -> Path:
    """Resolve the existing compiled BridgeAnalysisRunner without building it."""

    project_root = _canonical_path(project_root)
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
    raise FigThresholdError(
        "未找到读取 FIG 所需的 BridgeAnalysisRunner；请修复或重新安装核心分析组件。"
    )


def prepare_fig_threshold_request(
    project_root: Path,
    fig_path: Path,
    operation: str,
    target_module: str,
    target_point: str,
    *,
    request_id: str | None = None,
    run_root: Path | None = None,
    now: datetime | None = None,
) -> tuple[FigThresholdPaths, dict[str, Any]]:
    """Create the immutable request/status files for one FIG interaction."""

    project_root = _canonical_path(project_root)
    if not project_root.is_dir():
        raise FigThresholdError(f"程序目录不存在：{project_root}")

    fig_path = _canonical_path(fig_path)
    if not fig_path.is_file():
        raise FigThresholdError(f"FIG 文件不存在：{fig_path}")
    if fig_path.suffix.casefold() != ".fig":
        raise FigThresholdError("只能直接读取 MATLAB .fig 文件；JPG/PNG 不含可交互曲线数据。")

    operation = str(operation or "").strip().casefold()
    if operation not in SUPPORTED_OPERATIONS:
        supported = "、".join(sorted(SUPPORTED_OPERATIONS))
        raise FigThresholdError(f"不支持的 FIG 操作：{operation or '<空>'}；应为 {supported}")
    target_module = str(target_module or "").strip()
    target_point = str(target_point or "").strip()
    if not target_module:
        raise FigThresholdError("目标分析类型不能为空")
    if not target_point:
        raise FigThresholdError("目标测点不能为空")

    stamp = (now or datetime.now()).strftime("%Y%m%d_%H%M%S")
    interaction_id = str(request_id or f"fig_threshold_{stamp}_{uuid.uuid4().hex[:8]}").strip()
    if not interaction_id:
        raise FigThresholdError("request_id 不能为空")
    root = _canonical_path(run_root) if run_root is not None else _application_data_root() / interaction_id
    paths = FigThresholdPaths(
        root=root,
        request=root / "fig_threshold_request.json",
        status=root / "fig_threshold_status.json",
        result=root / "fig_threshold_result.json",
        stdout=root / "fig_threshold_stdout.log",
        stderr=root / "fig_threshold_stderr.log",
    )
    source_hash = file_sha256(fig_path)
    payload: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "request_type": REQUEST_TYPE,
        "request_id": interaction_id,
        "operation": operation,
        "fig_path": str(fig_path),
        "fig_sha256": source_hash,
        "fig_size_bytes": fig_path.stat().st_size,
        "target_module": target_module,
        "target_point": target_point,
        "status_path": str(paths.status),
        "result_path": str(paths.result),
    }
    _write_json(paths.request, payload)
    _write_json(
        paths.status,
        {
            "status": "prepared",
            "request_type": REQUEST_TYPE,
            "request_id": interaction_id,
            "request_path": str(paths.request),
            "fig_path": str(fig_path),
            "fig_sha256": source_hash,
        },
    )
    return paths, payload


# Short alias for callers that already use a prepare_request convention.
prepare_request = prepare_fig_threshold_request


def _spawn_runner(runner: Path, paths: FigThresholdPaths) -> subprocess.Popen[bytes]:
    creationflags = 0
    if os.name == "nt":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(
            subprocess, "CREATE_NEW_PROCESS_GROUP", 0
        )
    try:
        with paths.stdout.open("wb") as stdout, paths.stderr.open("wb") as stderr:
            return subprocess.Popen(
                [str(runner), str(paths.request)],
                stdin=subprocess.DEVNULL,
                stdout=stdout,
                stderr=stderr,
                creationflags=creationflags,
            )
    except OSError as exc:
        raise FigThresholdError(f"无法启动 FIG 交互后台程序：{runner}（{exc}）") from exc


def _create_fig_wait_dialog(parent: Any, on_cancel: Any) -> Any:
    """Create a small Qt wait/cancel surface for one external FIG process."""

    try:
        from PySide6.QtCore import Qt
        from PySide6.QtWidgets import (
            QApplication,
            QDialog,
            QHBoxLayout,
            QLabel,
            QPushButton,
            QVBoxLayout,
            QWidget,
        )
    except ImportError:  # pragma: no cover - packaged GUI always has PySide6
        return None
    if QApplication.instance() is None or not isinstance(parent, QWidget):
        return None

    dialog = QDialog(parent)
    dialog.setWindowTitle("MATLAB FIG 交互")
    dialog.setWindowModality(Qt.WindowModal)
    dialog.setWindowFlag(Qt.WindowContextHelpButtonHint, False)
    dialog.setWindowFlag(Qt.WindowCloseButtonHint, False)
    dialog.setMinimumWidth(430)
    layout = QVBoxLayout(dialog)
    label = QLabel(
        "正在启动或等待 MATLAB FIG 窗口。请在 MATLAB 窗口中选择曲线并完成拖线/框选；"
        "若窗口被遮挡，请从任务栏切换。"
    )
    label.setWordWrap(True)
    layout.addWidget(label)
    row = QHBoxLayout()
    row.addStretch(1)
    cancel_button = QPushButton("停止本次 FIG 操作")
    cancel_button.setToolTip("仅停止本次由工作台启动的 FIG 交互进程，不影响其它分析任务")
    cancel_button.clicked.connect(on_cancel)
    row.addWidget(cancel_button)
    layout.addLayout(row)
    dialog._fig_wait_label = label  # type: ignore[attr-defined]
    dialog._fig_wait_cancel_button = cancel_button  # type: ignore[attr-defined]
    return dialog


def _mark_fig_wait_dialog_stopping(dialog: Any) -> None:
    if dialog is None:
        return
    label = getattr(dialog, "_fig_wait_label", None)
    button = getattr(dialog, "_fig_wait_cancel_button", None)
    if label is not None:
        label.setText("正在停止本次 FIG 操作，请稍候……")
    if button is not None:
        button.setEnabled(False)


def _terminate_fig_process(process: subprocess.Popen[Any]) -> None:
    """Best-effort stop of the exact Popen handle created for this dialog."""

    if process.poll() is not None:
        return
    try:
        process.terminate()
    except (OSError, ProcessLookupError):
        pass


def _wait_for_process_with_qt(
    process: subprocess.Popen[Any],
    *,
    parent: Any = None,
    poll_interval_ms: int = 50,
) -> int:
    """Wait synchronously while keeping the caller's Qt UI event loop alive."""

    try:
        from PySide6.QtCore import QCoreApplication, QEventLoop, QObject, QTimer
    except ImportError:  # pragma: no cover - the packaged GUI always includes PySide6
        return int(process.wait())

    if QCoreApplication.instance() is None:
        return int(process.wait())
    loop_parent = parent if isinstance(parent, QObject) else None
    loop = QEventLoop(loop_parent)
    timer = QTimer(loop)
    timer.setInterval(max(10, int(poll_interval_ms)))
    cancelled = False
    wait_dialog: Any = None

    def force_kill_if_needed() -> None:
        if not cancelled or process.poll() is not None:
            return
        try:
            process.kill()
        except (OSError, ProcessLookupError):
            pass

    def request_cancel() -> None:
        nonlocal cancelled
        if cancelled:
            return
        cancelled = True
        _mark_fig_wait_dialog_stopping(wait_dialog)
        _terminate_fig_process(process)
        QTimer.singleShot(3000, force_kill_if_needed)

    def poll() -> None:
        if process.poll() is not None:
            timer.stop()
            loop.quit()

    timer.timeout.connect(poll)
    wait_dialog = _create_fig_wait_dialog(parent, request_cancel)
    if wait_dialog is not None:
        wait_dialog.show()
    poll()
    if process.poll() is None:
        timer.start()
        loop.exec()
    return_code = process.poll()
    if wait_dialog is not None:
        wait_dialog.accept()
        wait_dialog.deleteLater()
    if cancelled:
        raise FigThresholdCancelled(
            "已停止本次 MATLAB FIG 操作；当前配置未采用本次候选值。"
        )
    return int(return_code if return_code is not None else process.wait())


def _log_tail(path: Path, limit: int = 4096) -> str:
    try:
        with path.open("rb") as stream:
            stream.seek(0, os.SEEK_END)
            size = stream.tell()
            stream.seek(max(0, size - limit), os.SEEK_SET)
            raw = stream.read()
    except OSError:
        return ""
    for encoding in ("utf-8", "gb18030"):
        try:
            return raw.decode(encoding).strip()
        except UnicodeDecodeError:
            continue
    return raw.decode("utf-8", errors="replace").strip()


def _record_operator_cancelled(
    paths: FigThresholdPaths,
    request: Mapping[str, Any],
    message: str,
) -> None:
    """Durably close a workbench-side cancellation instead of leaving ``running``.

    The compiled runner normally owns the status file.  When the workbench
    terminates that one child process from its cancel button, however, the
    runner may not get enough time to publish its own terminal state.  Record
    the operator decision with the immutable request identity so diagnostics
    never mistake a cancelled interaction for a still-running job.
    """

    previous_status = ""
    try:
        previous = _read_json_object(paths.status, "FIG 状态文件")
        previous_status = str(previous.get("status") or "").strip()
    except FigThresholdError:
        previous_status = "unreadable"
    _write_json(
        paths.status,
        {
            "schema_version": SCHEMA_VERSION,
            "request_type": REQUEST_TYPE,
            "request_id": str(request["request_id"]),
            "operation": str(request["operation"]),
            "request_path": str(paths.request),
            "result_path": str(paths.result),
            "fig_path": str(request["fig_path"]),
            "fig_sha256": str(request["fig_sha256"]),
            "status": "cancelled",
            "message": str(message),
            "runner_status_before_cancel": previous_status,
            "updated_at": datetime.now().astimezone().isoformat(),
        },
    )


def _text(payload: Mapping[str, Any], field: str, label: str) -> str:
    value = str(payload.get(field) or "").strip()
    if not value:
        raise FigThresholdError(f"FIG 结果缺少{label}（{field}）")
    return value


def _finite_number(payload: Mapping[str, Any], field: str, label: str) -> float:
    value = payload.get(field)
    if isinstance(value, bool):
        raise FigThresholdError(f"FIG 结果中的{label}不是有限数值")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise FigThresholdError(f"FIG 结果中的{label}不是有限数值") from exc
    if not math.isfinite(number):
        raise FigThresholdError(f"FIG 结果中的{label}不是有限数值")
    return number


def _nonnegative_integer(payload: Mapping[str, Any], field: str, label: str) -> int:
    value = payload.get(field)
    if isinstance(value, bool):
        raise FigThresholdError(f"FIG 结果中的{label}不是非负整数")
    try:
        number = int(value)
    except (TypeError, ValueError) as exc:
        raise FigThresholdError(f"FIG 结果中的{label}不是非负整数") from exc
    if number < 0 or isinstance(value, float) and not value.is_integer():
        raise FigThresholdError(f"FIG 结果中的{label}不是非负整数")
    return number


def _paired_optional_values(
    payload: Mapping[str, Any], first: str, second: str, label: str
) -> tuple[Any, Any]:
    left = payload.get(first)
    right = payload.get(second)
    left_empty = left is None or isinstance(left, str) and not left.strip()
    right_empty = right is None or isinstance(right, str) and not right.strip()
    if left_empty != right_empty:
        raise FigThresholdError(f"FIG 结果中的{label}起止值必须同时存在或同时为空")
    return ("", "") if left_empty else (left, right)


def _validate_identity(
    payload: Mapping[str, Any],
    *,
    request: Mapping[str, Any],
    label: str,
    require_schema: bool,
) -> None:
    if require_schema and int(payload.get("schema_version") or 0) != SCHEMA_VERSION:
        raise FigThresholdError(f"{label} schema_version 无效")
    if str(payload.get("request_type") or "") != REQUEST_TYPE:
        raise FigThresholdError(f"{label} request_type 与 FIG 请求不一致")
    if str(payload.get("request_id") or "") != str(request["request_id"]):
        raise FigThresholdError(f"{label} request_id 与 FIG 请求不一致")


def _validate_result_payload(
    result: dict[str, Any],
    *,
    request: Mapping[str, Any],
) -> dict[str, Any]:
    _validate_identity(result, request=request, label="FIG 结果", require_schema=True)
    if str(result.get("artifact_type") or "") != "fig_threshold_result":
        raise FigThresholdError("FIG 结果 artifact_type 无效")
    status = str(result.get("status") or "").strip().casefold()
    if status in {"cancelled", "canceled"}:
        raise FigThresholdCancelled("已取消 FIG 阈值设置", status=result)
    if status in {"failed", "error"}:
        message = str(result.get("message") or result.get("error_message") or "FIG 交互失败")
        raise FigThresholdError(message)
    if status not in {"ok", "completed"}:
        raise FigThresholdError(f"FIG 结果状态无效：{status or '<空>'}")

    operation = _text(result, "operation", "操作类型").casefold()
    if operation != request["operation"]:
        raise FigThresholdError("FIG 结果的操作类型与请求不一致")
    if _text(result, "target_module", "目标分析类型") != request["target_module"]:
        raise FigThresholdError("FIG 结果的目标分析类型与请求不一致")
    if _text(result, "target_point", "目标测点") != request["target_point"]:
        raise FigThresholdError("FIG 结果的目标测点与请求不一致")

    source_fig = result.get("source_fig")
    if not isinstance(source_fig, dict):
        raise FigThresholdError("FIG 结果缺少 source_fig 对象")
    source_path = _text(source_fig, "path", "源 FIG 路径")
    if not _same_path(source_path, request["fig_path"]):
        raise FigThresholdError("FIG 结果绑定的源文件路径与请求不一致")
    source_hash = _text(source_fig, "sha256", "源 FIG 完整性校验码")
    if not _SHA256_PATTERN.fullmatch(source_hash):
        raise FigThresholdError("FIG 结果中的源文件 SHA256 格式无效")
    if source_hash.casefold() != str(request["fig_sha256"]).casefold():
        raise FigThresholdError("FIG 结果绑定的源文件 SHA256 与请求不一致")
    source_size = _nonnegative_integer(source_fig, "size", "源 FIG 文件大小")
    if "fig_size_bytes" in request and source_size != int(request["fig_size_bytes"]):
        raise FigThresholdError("FIG 结果绑定的源文件大小与请求不一致")
    _text(source_fig, "mtime", "源 FIG 修改时间")

    source_curve = result.get("source_curve")
    if not isinstance(source_curve, dict):
        raise FigThresholdError("FIG 结果缺少 source_curve 对象")
    axis_title = _text(source_curve, "axis_title", "曲线坐标区标题")
    curve_label = _text(source_curve, "curve_label", "曲线名称")
    sample_count = _nonnegative_integer(source_curve, "sample_count", "曲线样本数")
    if sample_count <= 0:
        raise FigThresholdError("FIG 结果中的曲线样本数必须大于 0")
    source_curve.update(
        {"axis_title": axis_title, "curve_label": curve_label, "sample_count": sample_count}
    )

    candidate = result.get("candidate")
    if not isinstance(candidate, dict):
        raise FigThresholdError("FIG 结果缺少 candidate 对象")
    if operation == "band":
        lower = _finite_number(candidate, "lower", "下限")
        upper = _finite_number(candidate, "upper", "上限")
        if not lower < upper:
            raise FigThresholdError("FIG 双边阈值必须满足下限小于上限")
        start, end = _paired_optional_values(
            candidate, "t_range_start", "t_range_end", "共同时间窗"
        )
        candidate.update(
            {
                "lower": lower,
                "upper": upper,
                "t_range_start": start,
                "t_range_end": end,
            }
        )
    else:
        expected_side = "lower" if operation == "box_lower" else "upper"
        side = _text(candidate, "side", "框选方向").casefold()
        if side != expected_side:
            raise FigThresholdError("FIG 框选结果的方向与请求不一致")
        value = _finite_number(candidate, "value", "框选阈值")
        selected = _nonnegative_integer(candidate, "selected_sample_count", "框选样本数")
        if selected <= 0:
            raise FigThresholdError("FIG 框选必须至少选中 1 个有限样本")
        start, end = _paired_optional_values(
            candidate, "selection_start", "selection_end", "框选横轴范围"
        )
        if start == "" and end == "":
            raise FigThresholdError("FIG 框选结果缺少横轴选择范围")
        candidate.update(
            {
                "side": side,
                "value": value,
                "selected_sample_count": selected,
                "selection_start": start,
                "selection_end": end,
            }
        )
    return result


def _load_and_validate_outcome(
    paths: FigThresholdPaths,
    request: Mapping[str, Any],
    *,
    return_code: int,
) -> dict[str, Any]:
    status = _read_json_object(paths.status, "FIG 状态文件")
    _validate_identity(status, request=request, label="FIG 状态文件", require_schema=False)
    state = str(status.get("status") or "").strip().casefold()
    if state in {"cancelled", "canceled"}:
        raise FigThresholdCancelled(
            str(status.get("message") or "已取消 FIG 阈值设置"), status=status
        )
    if state in {"failed", "error"}:
        message = str(status.get("message") or status.get("error_message") or "FIG 交互失败")
        tail = _log_tail(paths.stderr)
        raise FigThresholdError(f"{message}{f'；后台信息：{tail}' if tail else ''}")
    if return_code != 0:
        tail = _log_tail(paths.stderr)
        detail = f"；后台信息：{tail}" if tail else ""
        raise FigThresholdError(f"FIG 交互后台程序异常退出（代码 {return_code}）{detail}")
    if state not in {"completed", "ok"}:
        raise FigThresholdError(f"FIG 状态文件未记录成功完成：{state or '<空>'}")
    if str(status.get("operation") or "").strip().casefold() != str(
        request["operation"]
    ).casefold():
        raise FigThresholdError("FIG 状态文件的操作类型与请求不一致")
    status_result_path = str(status.get("result_path") or "").strip()
    if not status_result_path or not _same_path(status_result_path, paths.result):
        raise FigThresholdError("FIG 状态文件绑定的结果路径与请求不一致")
    status_result = str(status.get("result_status") or "").strip().casefold()
    if status_result not in {"ok", "cancelled", "canceled"}:
        raise FigThresholdError("FIG 状态文件缺少有效的 result_status")

    result = _read_json_object(paths.result, "FIG 结果文件")
    actual_result_status = str(result.get("status") or "").strip().casefold()
    if status_result != actual_result_status and {
        status_result,
        actual_result_status,
    } != {"cancelled", "canceled"}:
        raise FigThresholdError("FIG 状态文件与结果文件记录的状态不一致")
    validated = _validate_result_payload(result, request=request)
    fig_path = Path(str(request["fig_path"]))
    if not fig_path.is_file():
        raise FigThresholdError("交互完成后源 FIG 文件已不存在，结果不能采用")
    actual_hash = file_sha256(fig_path)
    if actual_hash.casefold() != str(request["fig_sha256"]).casefold():
        raise FigThresholdError("交互期间源 FIG 文件发生变化，结果不能采用")
    return validated


def run_fig_threshold_interaction(
    project_root: Path,
    fig_path: Path,
    operation: str,
    target_module: str,
    target_point: str,
    parent: Any = None,
) -> dict[str, Any]:
    """Run a modal FIG threshold operation and return a strictly bound result.

    The compiled runner owns the native MATLAB FIG interaction.  This function
    hides its console and waits with a nested Qt event loop so the PySide6
    workbench remains responsive.  Operator cancellation is reported with
    :class:`FigThresholdCancelled`, never as a generic processing failure.
    """

    project_root = _canonical_path(project_root)
    runner = resolve_runner(project_root)
    paths, request = prepare_fig_threshold_request(
        project_root, fig_path, operation, target_module, target_point
    )
    process = _spawn_runner(runner, paths)
    try:
        return_code = _wait_for_process_with_qt(process, parent=parent)
    except FigThresholdCancelled as exc:
        _record_operator_cancelled(paths, request, str(exc))
        raise
    return _load_and_validate_outcome(paths, request, return_code=return_code)


__all__ = [
    "FigThresholdCancelled",
    "FigThresholdError",
    "FigThresholdPaths",
    "REQUEST_TYPE",
    "SCHEMA_VERSION",
    "SUPPORTED_OPERATIONS",
    "prepare_fig_threshold_request",
    "prepare_request",
    "resolve_runner",
    "run_fig_threshold_interaction",
]
