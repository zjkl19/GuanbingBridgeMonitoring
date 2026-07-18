from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .provenance_contract import (
    ProvenanceContractViolation,
    validate_derived_10min_series,
    validate_source_sample_counts,
    validate_source_day_coverage,
)


_FULL_RAW_MODULES = {"acceleration", "cable_accel"}
_RAW_RENDER_MODES = {"line", "dense_band", "band"}
_DERIVED_RENDER_MODES = {"derived_10min_mean", "wind_rose_aggregate"}
_SAMPLING_MODES = {"full", "capped"}
_APPROVED_RENDER_ONLY_REDUCTION_ALGORITHMS = {
    "peak_preserving_bucket_minmax_v1",
}


@dataclass(frozen=True)
class PlotProvenanceRow:
    module_key: str
    path: Path
    status: str
    series_count: int
    source_count: int
    plotted_count: int
    incomplete_days: tuple[str, ...]
    message: str = ""
    failure_code: str = ""
    reason_zh: str = ""
    suggestion_zh: str = ""

    @property
    def closed(self) -> bool:
        return self.status in {"closed", "closed_incomplete_source"}


@dataclass(frozen=True)
class PlotProvenanceSummary:
    rows: tuple[PlotProvenanceRow, ...]

    @property
    def closed_count(self) -> int:
        return sum(row.closed for row in self.rows)

    @property
    def failed_count(self) -> int:
        return sum(not row.closed for row in self.rows)

    @property
    def incomplete_source_count(self) -> int:
        return sum(row.status == "closed_incomplete_source" for row in self.rows)


def _failure_guidance(message: str) -> tuple[str, str, str]:
    """Map low-level contract failures to stable user-facing guidance."""

    normalized = message.lower()
    if "derived series must use full sampling without reduction" in normalized:
        return (
            "derived_reduction_forbidden",
            "10分钟派生序列未按全量模式输出，或被错误标记为抽稀。",
            "只重算风模块，并确认全部10分钟派生点参与绘图且reduction_applied=false。",
        )
    if "derived input/finite/plotted counts do not close" in normalized:
        return (
            "derived_counts_not_closed",
            "10分钟派生输入数、有限值数和实际绘图点数不闭合。",
            "检查10分钟聚合与有限值过滤；正式图必须绘制全部有限派生点。",
        )
    if "raw source/input/finite counts do not close" in normalized:
        return (
            "raw_counts_not_closed",
            "原始序列的源样本数、输入数和有限值数不闭合。",
            "重新生成对应模块图件及来源记录，并核对清洗后有限值计数；来源计数错误不能人工放行。",
        )
    if "source/input/finite counts do not close" in normalized:
        return (
            "source_derived_counts_not_closed",
            "原始样本计数与派生序列计数被混用，或计数次序不可能。",
            "分别记录原始source计数和派生input/finite/plotted计数后重新生成来源记录。",
        )
    if "no plotted finite values" in normalized:
        return (
            "no_plotted_values",
            "该图没有任何可绘制的有限值。",
            "检查源数据覆盖、测点配置和有限值过滤；不要把无有效数据伪装成正常图件。",
        )
    if "does not exist" in normalized or "不存在" in message:
        return (
            "provenance_file_missing",
            "图件对应的来源核验文件不存在。",
            "重新生成对应模块图件及同名.plot.json，不要手工复制旧图放行。",
        )
    return (
        "plot_provenance_invalid",
        "图件来源记录未通过计数或契约核验。",
        "查看技术详情，修正来源记录或重算对应模块；不要人工放行来源计数错误。",
    )


def _artifact_paths(raw: Any) -> Iterable[Path]:
    if isinstance(raw, str):
        yield Path(raw)
    elif isinstance(raw, dict):
        value = raw.get("path") or raw.get("file")
        if value:
            yield Path(str(value))
    elif isinstance(raw, list):
        for item in raw:
            yield from _artifact_paths(item)


def manifest_plot_provenance_paths(payload: dict[str, Any]) -> list[tuple[str, Path]]:
    found: list[tuple[str, Path]] = []
    seen: set[str] = set()
    records = payload.get("module_results") or payload.get("module_logs") or []
    if not isinstance(records, list):
        records = []
    for record in records:
        if not isinstance(record, dict):
            continue
        module = str(record.get("key") or record.get("module") or "")
        for path in _artifact_paths(record.get("artifacts")):
            normalized = str(path.expanduser().resolve(strict=False)).casefold()
            if path.name.lower().endswith(".plot.json") and normalized not in seen:
                found.append((module, path.expanduser().resolve(strict=False)))
                seen.add(normalized)
    for path in _artifact_paths(payload.get("artifacts")):
        normalized = str(path.expanduser().resolve(strict=False)).casefold()
        if path.name.lower().endswith(".plot.json") and normalized not in seen:
            found.append(("", path.expanduser().resolve(strict=False)))
            seen.add(normalized)
    return found


def _nonnegative(value: Any) -> float:
    if isinstance(value, bool):
        raise ValueError("count must be a finite non-negative number")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("count must be a finite non-negative number") from exc
    if not math.isfinite(number) or number < 0:
        raise ValueError("count must be a finite non-negative number")
    return number


def _schema_version(value: Any, *, default: int | None = None) -> int:
    if value is None and default is not None:
        return default
    if isinstance(value, bool):
        raise ValueError("schema_version must be a positive integer")
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError("schema_version must be a positive integer") from exc
    if not math.isfinite(number) or not number.is_integer() or number < 1:
        raise ValueError("schema_version must be a positive integer")
    return int(number)


def _validate_render_only_reduction(
    index: int,
    item: dict[str, Any],
    *,
    provenance_schema_version: int,
    finite_count: float,
    plotted_finite_count: float,
) -> None:
    """Fail closed unless a reduced full plot uses the audited v2 contract."""

    if provenance_schema_version < 2:
        raise ValueError(
            f"series {index} reduced full render requires provenance schema_version>=2"
        )
    if "input_count" not in item:
        raise ValueError(f"series {index} reduced full render requires explicit input_count")
    series_schema = item.get("schema_version")
    if series_schema is not None and _schema_version(series_schema) < 2:
        raise ValueError(
            f"series {index} reduced full render requires series schema_version>=2"
        )
    if str(item.get("reduction_scope") or "").strip().lower() != "render_only":
        raise ValueError(f"series {index} reduced full render must be render_only")
    algorithm = str(item.get("reduction_algorithm") or "").strip().lower()
    if algorithm not in _APPROVED_RENDER_ONLY_REDUCTION_ALGORITHMS:
        raise ValueError(
            f"series {index} uses unsupported render reduction algorithm={algorithm or '<missing>'}"
        )
    if item.get("extrema_preserved") is not True:
        raise ValueError(f"series {index} render reduction must preserve extrema")
    if item.get("first_last_preserved") is not True:
        raise ValueError(f"series {index} render reduction must preserve first/last samples")
    render_vertex_count = _nonnegative(item.get("render_vertex_count"))
    if "render_input_count" not in item:
        raise ValueError(
            f"series {index} reduced full render requires explicit render_input_count"
        )
    if "render_finite_input_count" not in item:
        raise ValueError(
            f"series {index} reduced full render requires explicit render_finite_input_count"
        )
    render_input_count = _nonnegative(item.get("render_input_count"))
    render_finite_input_count = _nonnegative(item.get("render_finite_input_count"))
    if render_vertex_count != plotted_finite_count:
        raise ValueError(
            f"series {index} render/plotted counts do not close: "
            f"render_vertex_count={render_vertex_count}, "
            f"plotted_finite_count={plotted_finite_count}"
        )
    if not (
        finite_count >= render_finite_input_count >= plotted_finite_count
        and item.get("input_count") is not None
        and _nonnegative(item.get("input_count")) >= render_input_count >= render_finite_input_count
    ):
        raise ValueError(
            f"series {index} source/render input counts do not close: "
            f"source_input={item.get('input_count')}, source_finite={finite_count}, "
            f"render_input={render_input_count}, "
            f"render_finite={render_finite_input_count}, plotted={plotted_finite_count}"
        )


def _validate_series_counts(
    index: int,
    item: dict[str, Any],
    module_key: str,
    *,
    provenance_schema_version: int,
) -> tuple[float, float, float, str, str]:
    """Validate plot-domain counts without conflating them with raw-source counts.

    A raw time-history line has a one-to-one relationship with its source
    samples.  Derived 10-minute series and wind-rose aggregates intentionally
    contain fewer plot-domain observations than their raw source, so their
    closure must be checked as two linked but distinct stages.
    """

    input_count = _nonnegative(item.get("input_count", item.get("finite_count")))
    finite = _nonnegative(item.get("finite_count"))
    plotted = _nonnegative(item.get("plotted_finite_count"))
    render_mode = str(item.get("render_mode") or "line").strip().lower()
    sampling_mode = str(item.get("sampling_mode") or "").strip().lower()
    plot_scope = str(item.get("plot_scope") or "").strip().lower()
    reduction_applied = item.get("reduction_applied")
    if render_mode != "derived_10min_mean":
        if sampling_mode not in _SAMPLING_MODES:
            raise ValueError(
                f"series {index} has unsupported sampling_mode={sampling_mode or '<missing>'}"
            )
        if not isinstance(reduction_applied, bool):
            raise ValueError(f"series {index} reduction_applied must be boolean")
    if render_mode == "wind_rose_aggregate":
        if sampling_mode != "full" or reduction_applied:
            raise ValueError(f"series {index} aggregate must use full sampling without reduction")
        if not (input_count >= finite >= plotted):
            raise ValueError(f"series {index} aggregate input/finite/plotted counts do not close")
    elif render_mode == "derived_10min_mean":
        input_count, finite, plotted = validate_derived_10min_series(
            item,
            provenance_schema_version=provenance_schema_version,
        )
    elif render_mode in _RAW_RENDER_MODES:
        normalized_module = module_key.strip().lower()
        if plot_scope and plot_scope not in {"point_time_history", "group_overview"}:
            raise ValueError(f"series {index} has unsupported plot_scope={plot_scope}")
        full_required = (
            normalized_module in _FULL_RAW_MODULES
            and plot_scope != "group_overview"
        )
        if full_required and sampling_mode != "full":
            raise ValueError(
                f"series {index} {normalized_module} raw time history requires full sampling"
            )
        if sampling_mode == "full":
            if reduction_applied:
                if not (input_count >= finite >= plotted):
                    raise ValueError(
                        f"series {index} reduced full raw input/finite/plotted counts do not close"
                    )
                _validate_render_only_reduction(
                    index,
                    item,
                    provenance_schema_version=provenance_schema_version,
                    finite_count=finite,
                    plotted_finite_count=plotted,
                )
            elif not (input_count >= finite == plotted):
                raise ValueError(f"series {index} full raw input/finite/plotted counts do not close")
        else:
            if not normalized_module:
                raise ValueError(f"series {index} capped raw series lacks a manifest module key")
            if not (input_count >= finite >= plotted):
                raise ValueError(f"series {index} capped raw input/finite/plotted counts do not close")
            expected_reduction = plotted < finite
            if reduction_applied != expected_reduction:
                raise ValueError(
                    f"series {index} capped raw reduction flag does not match finite/plotted counts"
                )
    else:
        raise ValueError(f"series {index} has unsupported render_mode={render_mode or '<missing>'}")
    if plotted <= 0:
        raise ValueError(f"series {index} contains no plotted finite values")
    return input_count, finite, plotted, render_mode, sampling_mode


def inspect_plot_provenance(module_key: str, path: Path) -> PlotProvenanceRow:
    try:
        if not path.is_file():
            raise FileNotFoundError(f"图件数据核验文件不存在：{path}")
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(payload, dict):
            raise ValueError("root must be an object")
        provenance_schema_version = _schema_version(payload.get("schema_version"), default=1)
        raw_series = payload.get("series")
        series = [raw_series] if isinstance(raw_series, dict) else raw_series
        if not isinstance(series, list) or not series or not all(isinstance(item, dict) for item in series):
            raise ValueError("series must contain at least one object")
        source_total = 0.0
        plotted_total = 0.0
        incomplete_days: list[str] = []
        has_source = True
        for index, item in enumerate(series, start=1):
            input_count, finite, plotted, render_mode, sampling_mode = _validate_series_counts(
                index,
                item,
                module_key,
                provenance_schema_version=provenance_schema_version,
            )
            plotted_total += plotted
            source = item.get("source")
            if not isinstance(source, dict):
                has_source = False
                source_total += input_count
                continue
            source_count, finite_source = validate_source_sample_counts(
                source,
                input_count=input_count,
                finite_count=finite,
                derived=render_mode in _DERIVED_RENDER_MODES or sampling_mode == "capped",
            )
            incomplete_days.extend(validate_source_day_coverage(source))
            source_total += source_count
        status = "failed" if not has_source else (
            "closed_incomplete_source" if incomplete_days else "closed"
        )
        message = "部分序列缺少源数据日级核验记录" if not has_source else ""
        return PlotProvenanceRow(
            module_key,
            path,
            status,
            len(series),
            int(source_total),
            int(plotted_total),
            tuple(dict.fromkeys(incomplete_days)),
            message,
            "missing_source_provenance" if not has_source else "",
            "部分曲线没有可核验的原始数据覆盖记录。" if not has_source else "",
            "重新生成对应模块图件及来源记录后再进行正式图核验。" if not has_source else "",
        )
    except Exception as exc:  # noqa: BLE001
        technical_message = str(exc)
        if isinstance(exc, ProvenanceContractViolation):
            code = exc.code
            reason_zh = exc.reason_zh
            suggestion_zh = exc.suggestion_zh
        else:
            code, reason_zh, suggestion_zh = _failure_guidance(technical_message)
        message = (
            f"{technical_message}；用户可读原因：{reason_zh}；修复建议：{suggestion_zh}"
        )
        return PlotProvenanceRow(
            module_key,
            path,
            "failed",
            0,
            0,
            0,
            (),
            message,
            code,
            reason_zh,
            suggestion_zh,
        )


def inspect_manifest_plot_provenance(path: Path) -> PlotProvenanceSummary:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError("分析结果清单格式无效")
    rows = tuple(
        inspect_plot_provenance(module, provenance)
        for module, provenance in manifest_plot_provenance_paths(payload)
    )
    return PlotProvenanceSummary(rows)
