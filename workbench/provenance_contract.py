from __future__ import annotations

import math
from collections.abc import Mapping
from typing import Any


class ProvenanceContractViolation(ValueError):
    """A shared plot/source contract failure with operator guidance."""

    def __init__(
        self,
        technical_message: str,
        *,
        code: str,
        reason_zh: str,
        suggestion_zh: str,
    ) -> None:
        super().__init__(technical_message)
        self.code = code
        self.reason_zh = reason_zh
        self.suggestion_zh = suggestion_zh


def _nonnegative_number(value: Any, label: str) -> float:
    if isinstance(value, bool):
        raise ProvenanceContractViolation(
            f"{label} must be a finite non-negative number",
            code="invalid_count",
            reason_zh="来源记录包含无效计数。",
            suggestion_zh="重新生成来源记录，计数必须是有限的非负数。",
        )
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ProvenanceContractViolation(
            f"{label} must be a finite non-negative number",
            code="invalid_count",
            reason_zh="来源记录包含无效计数。",
            suggestion_zh="重新生成来源记录，计数必须是有限的非负数。",
        ) from exc
    if not math.isfinite(number) or number < 0:
        raise ProvenanceContractViolation(
            f"{label} must be a finite non-negative number",
            code="invalid_count",
            reason_zh="来源记录包含无效计数。",
            suggestion_zh="重新生成来源记录，计数必须是有限的非负数。",
        )
    return number


def _positive_integer(value: Any, label: str) -> int:
    number = _nonnegative_number(value, label)
    if not number.is_integer() or number < 1:
        raise ProvenanceContractViolation(
            f"{label} must be a positive integer",
            code="invalid_schema_version",
            reason_zh="来源记录的契约版本无效。",
            suggestion_zh="使用当前程序重新生成图件及来源记录。",
        )
    return int(number)


def strict_nonnegative_integer(value: Any, label: str) -> int:
    number = _nonnegative_number(value, label)
    if not number.is_integer():
        raise ProvenanceContractViolation(
            f"{label} must be a non-negative integer",
            code="invalid_day_count",
            reason_zh="源数据覆盖天数不是非负整数。",
            suggestion_zh="重新统计请求天数、完整天数和不完整天数，不得使用小数或截断值。",
        )
    return int(number)


def strict_sample_count(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ProvenanceContractViolation(
            f"{label} must be a numeric non-negative integer",
            code="invalid_count",
            reason_zh="样本计数不是数值型非负整数。",
            suggestion_zh="重新生成来源记录，不要把样本计数写成文本、布尔值或空值。",
        )
    number = _nonnegative_number(value, label)
    if not number.is_integer():
        raise ProvenanceContractViolation(
            f"{label} must be a non-negative integer",
            code="invalid_count",
            reason_zh="样本计数不是非负整数。",
            suggestion_zh="重新生成来源记录，样本计数不得使用小数或截断值。",
        )
    return int(number)


def validate_derived_10min_series(
    item: Mapping[str, Any],
    *,
    provenance_schema_version: int,
) -> tuple[float, float, float]:
    """Validate raw-to-derived and actual-render closure for a 10-minute plot."""

    if provenance_schema_version < 2:
        raise ProvenanceContractViolation(
            "derived 10-minute series requires provenance schema_version>=2",
            code="derived_schema_too_old",
            reason_zh="10分钟派生图使用旧版来源契约，无法证明实际绘制点数。",
            suggestion_zh="只重算风模块并生成schema_version>=2的来源记录。",
        )
    series_schema = _positive_integer(item.get("schema_version"), "series schema_version")
    if series_schema < 2:
        raise ProvenanceContractViolation(
            "derived 10-minute series requires series schema_version>=2",
            code="derived_schema_too_old",
            reason_zh="10分钟派生序列使用旧版来源契约，无法证明实际绘制点数。",
            suggestion_zh="只重算风模块并生成schema_version>=2的序列记录。",
        )
    sampling_mode = str(item.get("sampling_mode") or "").strip().lower()
    if sampling_mode != "full":
        raise ProvenanceContractViolation(
            "derived series must use full sampling without reduction",
            code="derived_reduction_forbidden",
            reason_zh="10分钟派生序列没有使用全量采样。",
            suggestion_zh="使用全部10分钟派生点并记录sampling_mode=full。",
        )
    reduction_applied = item.get("reduction_applied")
    if not isinstance(reduction_applied, bool):
        raise ProvenanceContractViolation(
            "derived series reduction_applied must be boolean",
            code="invalid_reduction_flag",
            reason_zh="10分钟派生序列的抽稀标记无效。",
            suggestion_zh="重新生成来源记录并写入布尔型reduction_applied=false。",
        )
    if reduction_applied:
        raise ProvenanceContractViolation(
            "derived series must use full sampling without reduction",
            code="derived_reduction_forbidden",
            reason_zh="10分钟派生序列被错误标记为抽稀，无法证明图中使用了全部派生点。",
            suggestion_zh="重新生成风模块图件，使用全部10分钟派生点并记录reduction_applied=false。",
        )

    input_count = strict_sample_count(item.get("input_count"), "derived input_count")
    finite_count = strict_sample_count(item.get("finite_count"), "derived finite_count")
    plotted_count = strict_sample_count(
        item.get("plotted_finite_count"), "derived plotted_finite_count"
    )
    if not (input_count >= finite_count == plotted_count):
        raise ProvenanceContractViolation(
            "derived input/finite/plotted counts do not close",
            code="derived_counts_not_closed",
            reason_zh="10分钟派生输入数、有限值数和实际绘图点数不闭合。",
            suggestion_zh="检查10分钟聚合与有限值过滤；正式图必须绘制全部有限派生点。",
        )

    render_input = strict_sample_count(
        item.get("render_input_count"), "derived render_input_count"
    )
    render_finite = strict_sample_count(
        item.get("render_finite_input_count"), "derived render_finite_input_count"
    )
    render_vertex = strict_sample_count(
        item.get("render_vertex_count"), "derived render_vertex_count"
    )
    if not (
        render_input == input_count
        and render_finite == finite_count
        and render_vertex == plotted_count
    ):
        raise ProvenanceContractViolation(
            "derived render/input/finite/vertex counts do not close",
            code="derived_render_counts_not_closed",
            reason_zh="10分钟派生计数与实际送入绘图、实际绘制的点数不闭合。",
            suggestion_zh="只重算风模块；render_input、render_finite和render_vertex必须分别与派生输入、有限值和绘制点数一致。",
        )
    if plotted_count <= 0:
        raise ProvenanceContractViolation(
            "derived series contains no plotted finite values",
            code="no_plotted_values",
            reason_zh="10分钟派生图没有任何可绘制的有限值。",
            suggestion_zh="检查源数据覆盖和10分钟聚合，不要把无有效数据伪装成正常图件。",
        )
    return input_count, finite_count, plotted_count


def validate_source_sample_counts(
    source: Mapping[str, Any],
    *,
    input_count: float,
    finite_count: float,
    derived: bool,
) -> tuple[int, int]:
    """Validate integer raw-source counts and their plot-domain relationship."""

    source_count = strict_sample_count(
        source.get("source_sample_count"), "source_sample_count"
    )
    finite_source = strict_sample_count(
        source.get("finite_source_sample_count"), "finite_source_sample_count"
    )
    if finite_source > source_count:
        raise ProvenanceContractViolation(
            "finite source count exceeds source count",
            code="source_counts_not_closed",
            reason_zh="原始来源的有限样本数大于原始样本总数。",
            suggestion_zh="只重算对应模块并重新记录原始样本总数与有限样本数。",
        )
    if derived:
        closed = source_count >= input_count and finite_source >= finite_count
        technical_message = "source/input/finite counts do not close"
        code = "source_derived_counts_not_closed"
        reason = "原始风样本计数与10分钟派生序列计数被混用或次序不可能。"
        suggestion = (
            "分别记录原始source计数和派生input/finite/plotted计数；"
            "原始计数应不小于派生计数。"
        )
    else:
        closed = source_count == input_count and finite_source == finite_count
        technical_message = (
            "raw source/input/finite counts differ; source/input counts differ"
        )
        code = "raw_counts_not_closed"
        reason = "原始来源计数与实际送入绘图的原始序列计数不一致。"
        suggestion = "重新生成对应模块图件，使source、input、finite计数逐项闭合。"
    if not closed:
        raise ProvenanceContractViolation(
            technical_message,
            code=code,
            reason_zh=reason,
            suggestion_zh=suggestion,
        )
    return source_count, finite_source


def validate_source_day_coverage(source: Mapping[str, Any]) -> tuple[str, ...]:
    """Validate one source coverage record identically for both consumers."""

    scope = str(source.get("completeness_scope") or "").strip()
    if scope != "required_export_contribution":
        raise ProvenanceContractViolation(
            f"unsupported source completeness_scope={scope or '<missing>'}",
            code="unsupported_completeness_scope",
            reason_zh="源数据完整性记录的适用范围无效。",
            suggestion_zh="按required_export_contribution范围重新生成来源记录。",
        )
    if not isinstance(source.get("internal_gap_coverage_assessed"), bool):
        raise ProvenanceContractViolation(
            "source requires boolean internal_gap_coverage_assessed",
            code="missing_gap_assessment",
            reason_zh="来源记录没有明确说明是否检查了日期内部缺口。",
            suggestion_zh="重新执行源数据覆盖检查并写入布尔型internal_gap_coverage_assessed。",
        )
    requested = strict_nonnegative_integer(
        source.get("calendar_day_count_requested"), "calendar_day_count_requested"
    )
    complete = strict_nonnegative_integer(source.get("complete_day_count"), "complete_day_count")
    incomplete = strict_nonnegative_integer(
        source.get("incomplete_day_count"), "incomplete_day_count"
    )
    if requested != complete + incomplete:
        raise ProvenanceContractViolation(
            "source day counts do not close",
            code="day_counts_not_closed",
            reason_zh="请求天数不等于完整天数与不完整天数之和。",
            suggestion_zh="重新统计数据覆盖天数并保留实际缺口披露。",
        )
    days = source.get("incomplete_days")
    if not (
        isinstance(days, list)
        and all(isinstance(value, str) and value.strip() for value in days)
        and len(days) == incomplete
    ):
        raise ProvenanceContractViolation(
            "source incomplete day list does not close",
            code="incomplete_days_not_closed",
            reason_zh="不完整日期列表与不完整天数不一致。",
            suggestion_zh="逐日核对源数据覆盖并写入完整的不完整日期列表。",
        )
    missing_sources = source.get("missing_required_sources")
    if not (
        isinstance(missing_sources, list)
        and all(isinstance(value, str) and value.strip() for value in missing_sources)
    ):
        raise ProvenanceContractViolation(
            "source missing-required-sources disclosure is invalid",
            code="missing_sources_invalid",
            reason_zh="缺失源文件披露列表无效。",
            suggestion_zh="明确列出缺失的必需源文件；没有缺失时使用空列表。",
        )
    return tuple(str(day) for day in days)
