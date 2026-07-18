from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Any, Iterable, Mapping, Sequence


PROGRESS_SCHEMA_VERSION = 2
MODULE_STATUSES = frozenset(
    {"pending", "running", "completed", "failed", "skipped", "stopped"}
)
FINISHED_MODULE_STATUSES = frozenset(
    {"completed", "failed", "skipped", "stopped"}
)
TERMINAL_ANALYSIS_STATUSES = frozenset(
    {"completed", "failed", "stopped", "launch_failed"}
)

_COMPLETED_ALIASES = frozenset(
    {"ok", "success", "succeeded", "complete", "completed", "pass", "passed"}
)
_FAILED_ALIASES = frozenset(
    {"fail", "failed", "failure", "error", "errored", "read_failed"}
)
_SKIPPED_ALIASES = frozenset(
    {
        "skip",
        "skipped",
        "not_applicable",
        "not-applicable",
        "no_data",
        "no-data",
        "no_valid_data",
        "no-valid-data",
    }
)
_STOPPED_ALIASES = frozenset({"stop", "stopped", "cancelled", "canceled"})
_RUNNING_ALIASES = frozenset(
    {"run", "running", "active", "in_progress", "in-progress"}
)
_PENDING_ALIASES = frozenset(
    {"", "pending", "queued", "waiting", "prepared", "not_started", "not-started"}
)


@dataclass(frozen=True)
class ModuleProgressStep:
    key: str
    label: str
    index: int
    status: str
    stage: str = ""
    current_point_id: str = ""
    current_date: str = ""
    processed_dates: int = 0
    total_dates: int = 0
    elapsed_seconds: float | None = None
    message: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "key": self.key,
            "label": self.label,
            "index": self.index,
            "status": self.status,
            "stage": self.stage,
            "current_point_id": self.current_point_id,
            "current_date": self.current_date,
            "processed_dates": self.processed_dates,
            "total_dates": self.total_dates,
            "elapsed_seconds": self.elapsed_seconds,
            "message": self.message,
        }


@dataclass(frozen=True)
class ModuleProgressSnapshot:
    steps: tuple[ModuleProgressStep, ...]
    completed_count: int
    total_count: int
    current_step: ModuleProgressStep | None
    progress_fraction: float
    authority: str
    overall_status: str
    stage: str = ""
    elapsed_seconds: float | None = None

    @property
    def summary_text(self) -> str:
        if not self.steps:
            return "模块进度：暂无模块明细"
        nonpassing_finished = sum(
            step.status in {"failed", "skipped", "stopped"} for step in self.steps
        )
        count_label = "已处理" if nonpassing_finished else "已完成"
        if self.current_step is not None:
            return (
                f"{count_label}{self.completed_count}/{self.total_count}；"
                f"当前{self.current_step.index}/{self.total_count}："
                f"{self.current_step.label}"
            )
        if nonpassing_finished:
            failed = sum(step.status == "failed" for step in self.steps)
            skipped = sum(step.status == "skipped" for step in self.steps)
            stopped = sum(step.status == "stopped" for step in self.steps)
            details = "，".join(
                text
                for count, text in (
                    (failed, f"失败{failed}"),
                    (skipped, f"跳过{skipped}"),
                    (stopped, f"已停止{stopped}"),
                )
                if count
            )
            return (
                f"模块进度：已处理{self.completed_count}/{self.total_count}"
                f"（{details}）"
            )
        suffix = "（全部通过）" if self.completed_count == self.total_count else ""
        return f"模块进度：已完成{self.completed_count}/{self.total_count}{suffix}"

    def status_fields(self) -> dict[str, Any]:
        current = self.current_step
        return {
            "progress_schema_version": PROGRESS_SCHEMA_VERSION,
            "progress_authority": self.authority,
            "module_steps": [step.to_dict() for step in self.steps],
            "completed_modules": self.completed_count,
            "module_total": self.total_count,
            "module_index": current.index if current is not None else None,
            "current_module_key": current.key if current is not None else "",
            "current_module_label": current.label if current is not None else "",
            "current_module_status": current.status if current is not None else "",
            "current_point_id": current.current_point_id if current is not None else "",
            "current_date": current.current_date if current is not None else "",
            "processed_dates": current.processed_dates if current is not None else None,
            "total_dates": current.total_dates if current is not None else None,
            "progress_fraction": self.progress_fraction,
            "elapsed_seconds": self.elapsed_seconds,
        }


def normalize_module_progress(
    status: Mapping[str, Any],
    manifest: Mapping[str, Any] | None = None,
    *,
    selected_modules: Iterable[str] = (),
) -> ModuleProgressSnapshot:
    """Normalize runtime progress and optional terminal-manifest results.

    Version-2 runtime payloads are allowed to describe completed steps. Older
    scalar payloads are deliberately conservative: ``completed_modules`` and
    ``progress_fraction`` never become per-module success claims. When a
    terminal analysis status is paired with a manifest, ``module_results`` is
    authoritative for every terminal module state.
    """

    raw_status = status if isinstance(status, Mapping) else {}
    overall_status = _text(raw_status.get("status")).casefold() or "unknown"
    schema_version = _integer(raw_status.get("progress_schema_version"))
    is_v2 = schema_version == PROGRESS_SCHEMA_VERSION

    if is_v2:
        steps = _runtime_v2_steps(raw_status)
        declared_authority = _text(raw_status.get("progress_authority"))
        authority = (
            declared_authority
            if declared_authority in {"runtime", "analysis_manifest"}
            else "runtime"
        )
    else:
        steps = _legacy_steps(raw_status, selected_modules)
        authority = "legacy_status"

    manifest_records = _manifest_records(manifest)
    if overall_status in TERMINAL_ANALYSIS_STATUSES and manifest_records is not None:
        steps = _manifest_steps(manifest_records, steps, selected_modules)
        authority = "analysis_manifest"

    current = _current_step(raw_status, steps, overall_status)
    # ``completed_count`` means modules whose execution reached any terminal
    # state, including failed/skipped/stopped. It is a module-progress count,
    # never a pass count.
    completed = sum(step.status in FINISHED_MODULE_STATUSES for step in steps)
    total = len(steps)
    # The overall bar is deliberately a module counter, not a time or work
    # estimate. Per-date progress remains visible on the running module row,
    # but must not make the bar jump backwards when the next point starts.
    fraction = float(completed) / float(total) if total else 0.0
    return ModuleProgressSnapshot(
        steps=steps,
        completed_count=completed,
        total_count=total,
        current_step=current,
        progress_fraction=fraction,
        authority=authority,
        overall_status=overall_status,
        stage=_text(raw_status.get("stage")),
        elapsed_seconds=_number(
            raw_status.get("elapsed_seconds", raw_status.get("elapsed_sec"))
        ),
    )


def _runtime_v2_steps(status: Mapping[str, Any]) -> tuple[ModuleProgressStep, ...]:
    records = _records(status.get("module_steps"))
    if records is None:
        return ()
    result: list[ModuleProgressStep] = []
    seen: set[str] = set()
    for ordinal, raw in enumerate(records, 1):
        if not isinstance(raw, Mapping):
            continue
        step = _step_from_mapping(raw, ordinal, source="runtime")
        identity = step.key or f"#{step.index}"
        if identity in seen:
            continue
        seen.add(identity)
        result.append(step)

    current_key = _text(status.get("current_module_key"))
    current_index = _positive_integer(status.get("module_index"))
    return tuple(
        _merge_top_level_detail(step, status)
        if (current_key and step.key == current_key)
        or (not current_key and current_index == step.index)
        else step
        for step in result
    )


def _legacy_steps(
    status: Mapping[str, Any], selected_modules: Iterable[str]
) -> tuple[ModuleProgressStep, ...]:
    keys = list(_unique_keys(selected_modules))
    current_key = _text(status.get("current_module_key"))
    if current_key and current_key not in keys:
        keys.append(current_key)
    current_label = _text(status.get("current_module_label"))
    overall = _text(status.get("status")).casefold()

    result: list[ModuleProgressStep] = []
    for index, key in enumerate(keys, 1):
        step_status = "pending"
        if key == current_key:
            if overall in {"failed", "launch_failed"}:
                step_status = "failed"
            elif overall == "stopped":
                step_status = "stopped"
            elif overall in {"prepared", "launching", "launched", "running", "stopping"}:
                step_status = "running"
        result.append(
            ModuleProgressStep(
                key=key,
                label=current_label if key == current_key and current_label else key,
                index=index,
                status=step_status,
                stage=_text(status.get("stage")) if key == current_key else "",
                current_point_id=_top_point_id(status) if key == current_key else "",
                current_date=_text(status.get("current_date")) if key == current_key else "",
                processed_dates=_top_processed_dates(status) if key == current_key else 0,
                total_dates=_top_total_dates(status) if key == current_key else 0,
                elapsed_seconds=_number(
                    status.get("elapsed_seconds", status.get("elapsed_sec"))
                )
                if key == current_key
                else None,
                message=_text(status.get("message")) if key == current_key else "",
            )
        )
    return tuple(result)


def _manifest_records(
    manifest: Mapping[str, Any] | None,
) -> Sequence[Any] | None:
    if not isinstance(manifest, Mapping):
        return None
    if "module_results" in manifest:
        return _records(manifest.get("module_results"))
    return _records(manifest.get("module_logs"))


def _manifest_steps(
    records: Sequence[Any],
    runtime_steps: tuple[ModuleProgressStep, ...],
    selected_modules: Iterable[str],
) -> tuple[ModuleProgressStep, ...]:
    manifest_steps: list[ModuleProgressStep] = []
    by_key: dict[str, ModuleProgressStep] = {}
    for ordinal, raw in enumerate(records, 1):
        if not isinstance(raw, Mapping):
            continue
        step = _step_from_mapping(raw, ordinal, source="manifest")
        if step.key and step.key in by_key:
            continue
        manifest_steps.append(step)
        if step.key:
            by_key[step.key] = step

    base_steps = runtime_steps
    if not base_steps:
        base_steps = tuple(
            ModuleProgressStep(key=key, label=key, index=index, status="pending")
            for index, key in enumerate(_unique_keys(selected_modules), 1)
        )
    if not base_steps:
        return tuple(replace(step, index=index) for index, step in enumerate(manifest_steps, 1))

    merged: list[ModuleProgressStep] = []
    consumed: set[str] = set()
    for base in base_steps:
        manifest_step = by_key.get(base.key)
        if manifest_step is None:
            merged.append(
                replace(
                    base,
                    status="failed",
                    stage="manifest_reconciliation",
                    message=base.message or "最终分析清单缺少该模块结果",
                )
            )
            continue
        consumed.add(base.key)
        merged.append(
            replace(
                manifest_step,
                label=manifest_step.label or base.label,
                index=base.index,
                stage=manifest_step.stage or base.stage,
                current_point_id=(
                    manifest_step.current_point_id or base.current_point_id
                ),
                current_date=manifest_step.current_date or base.current_date,
                processed_dates=(
                    manifest_step.processed_dates or base.processed_dates
                ),
                total_dates=manifest_step.total_dates or base.total_dates,
                elapsed_seconds=(
                    manifest_step.elapsed_seconds
                    if manifest_step.elapsed_seconds is not None
                    else base.elapsed_seconds
                ),
                message=manifest_step.message or base.message,
            )
        )
    for step in manifest_steps:
        if step.key and step.key in consumed:
            continue
        merged.append(replace(step, index=len(merged) + 1))
    return tuple(merged)


def _step_from_mapping(
    raw: Mapping[str, Any], ordinal: int, *, source: str
) -> ModuleProgressStep:
    key = _text(raw.get("key") or raw.get("module_key") or raw.get("module"))
    label = _text(raw.get("label") or raw.get("module_label")) or key or "未命名模块"
    status = _canonical_status(raw.get("status"), source=source)
    return ModuleProgressStep(
        key=key,
        label=label,
        index=_positive_integer(raw.get("index") or raw.get("module_index")) or ordinal,
        status=status,
        stage=_text(raw.get("stage")),
        current_point_id=_text(
            raw.get("current_point_id") or raw.get("point_id") or raw.get("current_point")
        ),
        current_date=_text(raw.get("current_date") or raw.get("date")),
        processed_dates=_integer_or_zero(
            raw.get("processed_dates", raw.get("processed_date_count"))
        ),
        total_dates=_integer_or_zero(
            raw.get("total_dates", raw.get("total_date_count"))
        ),
        elapsed_seconds=_number(
            raw.get("elapsed_seconds", raw.get("elapsed_sec", raw.get("elapsed")))
        ),
        message=_text(raw.get("message") or raw.get("error_type")),
    )


def _merge_top_level_detail(
    step: ModuleProgressStep, status: Mapping[str, Any]
) -> ModuleProgressStep:
    return replace(
        step,
        stage=_text(status.get("stage")) or step.stage,
        current_point_id=_top_point_id(status) or step.current_point_id,
        current_date=_text(status.get("current_date")) or step.current_date,
        processed_dates=_top_processed_dates(status) or step.processed_dates,
        total_dates=_top_total_dates(status) or step.total_dates,
        elapsed_seconds=_number(
            status.get("elapsed_seconds", status.get("elapsed_sec"))
        )
        if _number(status.get("elapsed_seconds", status.get("elapsed_sec"))) is not None
        else step.elapsed_seconds,
        message=_text(status.get("message")) or step.message,
    )


def _current_step(
    status: Mapping[str, Any],
    steps: tuple[ModuleProgressStep, ...],
    overall_status: str,
) -> ModuleProgressStep | None:
    if overall_status in TERMINAL_ANALYSIS_STATUSES:
        return None
    current_key = _text(status.get("current_module_key"))
    if current_key:
        for step in steps:
            if step.key == current_key and step.status == "running":
                return step
    current_index = _positive_integer(status.get("module_index"))
    if current_index is not None:
        for step in steps:
            if step.index == current_index and step.status == "running":
                return step
    return next((step for step in steps if step.status == "running"), None)


def _canonical_status(value: Any, *, source: str) -> str:
    raw = _text(value).casefold().replace(" ", "_")
    if raw in _COMPLETED_ALIASES:
        return "completed"
    if raw in _FAILED_ALIASES:
        return "failed"
    if raw in _SKIPPED_ALIASES:
        return "skipped"
    if raw in _STOPPED_ALIASES:
        return "stopped"
    if raw in _RUNNING_ALIASES:
        return "running"
    if raw in _PENDING_ALIASES:
        return "pending"
    # A terminal manifest must never turn an unrecognized result into a
    # benign pending row. Runtime writers can still introduce a future state
    # without making the UI claim success.
    return "failed" if source == "manifest" else "pending"


def _unique_keys(values: Iterable[str]) -> tuple[str, ...]:
    result: list[str] = []
    seen: set[str] = set()
    for value in values:
        key = _text(value)
        if not key or key in seen:
            continue
        seen.add(key)
        result.append(key)
    return tuple(result)


def _top_point_id(status: Mapping[str, Any]) -> str:
    return _text(
        status.get("current_point_id")
        or status.get("point_id")
        or status.get("current_point")
    )


def _top_processed_dates(status: Mapping[str, Any]) -> int:
    return _integer_or_zero(
        status.get("processed_dates", status.get("processed_date_count"))
    )


def _top_total_dates(status: Mapping[str, Any]) -> int:
    return _integer_or_zero(
        status.get("total_dates", status.get("total_date_count"))
    )


def _sequence(value: Any) -> bool:
    return isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray))


def _records(value: Any) -> tuple[Any, ...] | None:
    # MATLAB jsonencode emits a single struct as an object and a multi-element
    # struct array as an array. Both representations are the same contract.
    if isinstance(value, Mapping):
        return (value,)
    if _sequence(value):
        return tuple(value)
    return None


def _text(value: Any) -> str:
    return str(value).strip() if value is not None else ""


def _integer(value: Any) -> int | None:
    try:
        if value is None or isinstance(value, bool):
            return None
        return int(value)
    except (TypeError, ValueError, OverflowError):
        return None


def _positive_integer(value: Any) -> int | None:
    parsed = _integer(value)
    return parsed if parsed is not None and parsed > 0 else None


def _integer_or_none(value: Any) -> int | None:
    parsed = _integer(value)
    return parsed if parsed is not None and parsed >= 0 else None


def _integer_or_zero(value: Any) -> int:
    return _integer_or_none(value) or 0


def _number(value: Any) -> float | None:
    try:
        if value is None or isinstance(value, bool):
            return None
        parsed = float(value)
    except (TypeError, ValueError, OverflowError):
        return None
    if parsed != parsed or parsed in {float("inf"), float("-inf")}:
        return None
    return max(0.0, parsed)
