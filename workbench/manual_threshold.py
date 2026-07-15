from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime
from typing import Iterable, Mapping

from .auto_threshold import PreviewSeries
from .config_editor import CleaningThresholdRow, ConfigEditorError


LOWER_SIDE = "minimum"
UPPER_SIDE = "maximum"
VALID_SIDES = {LOWER_SIDE, UPPER_SIDE}


def _parse_timestamp(value: str, label: str) -> datetime:
    text = str(value or "").strip().replace("Z", "+00:00")
    if not text:
        raise ConfigEditorError(f"{label}不能为空")
    try:
        return datetime.fromisoformat(text)
    except ValueError as exc:
        raise ConfigEditorError(f"{label}不是有效时间：{value!r}") from exc


def _timestamp_number(value: str, label: str) -> float:
    return _parse_timestamp(value, label).timestamp()


@dataclass(frozen=True)
class OneSidedThresholdDraft:
    """A user-reviewed one-sided cleaning rule for one exact config point."""

    module_key: str
    point_key: str
    side: str
    value: float
    t_range_start: str = ""
    t_range_end: str = ""

    def validated(self) -> "OneSidedThresholdDraft":
        module_key = self.module_key.strip()
        point_key = self.point_key.strip()
        side = self.side.strip()
        if not module_key:
            raise ConfigEditorError("单边阈值缺少分析类型")
        if not point_key:
            raise ConfigEditorError("单边阈值缺少测点编号")
        if side not in VALID_SIDES:
            raise ConfigEditorError(f"单边阈值方向无效：{side!r}")
        try:
            value = float(self.value)
        except (TypeError, ValueError) as exc:
            raise ConfigEditorError("阈值必须是数值") from exc
        if not math.isfinite(value):
            raise ConfigEditorError("阈值必须是有限数值")

        start = str(self.t_range_start or "").strip()
        end = str(self.t_range_end or "").strip()
        if bool(start) != bool(end):
            raise ConfigEditorError("时间窗必须同时填写开始和结束")
        if start:
            parsed_start = _timestamp_number(start, "开始时间")
            parsed_end = _timestamp_number(end, "结束时间")
            if parsed_end < parsed_start:
                raise ConfigEditorError("结束时间不能早于开始时间")
        return OneSidedThresholdDraft(module_key, point_key, side, value, start, end)

    @property
    def direction_text(self) -> str:
        return "下限（删除低于此值）" if self.side == LOWER_SIDE else "上限（删除高于此值）"

    @property
    def time_window_text(self) -> str:
        if not self.t_range_start:
            return "全时段"
        return f"{self.t_range_start} ～ {self.t_range_end}"


@dataclass(frozen=True)
class ThresholdEstimate:
    preview_sample_count: int
    finite_count: int
    applicable_count: int
    removed_count: int

    @property
    def removed_ratio(self) -> float:
        return self.removed_count / self.applicable_count if self.applicable_count else 0.0

    def summary_text(self) -> str:
        return (
            f"基于 {self.preview_sample_count} 个预览样本（有限值 {self.finite_count} 个，"
            f"时间窗内 {self.applicable_count} 个），预计删除 {self.removed_count} 个，"
            f"占时间窗内有限值 {self.removed_ratio:.2%}。"
            "预览序列可能经过抽样；正式删除数和比例必须在保存后使用完整缓存复算。"
        )


def accepted_point_ids(payload: Mapping[str, object], point_key: str) -> tuple[str, ...]:
    """Return exact accepted identities without fuzzy point-name matching."""

    values = [point_key.strip()]
    name_map = payload.get("name_map_global", {})
    if isinstance(name_map, Mapping):
        original = str(name_map.get(point_key, "") or "").strip()
        if original:
            values.append(original)
    return tuple(dict.fromkeys(value for value in values if value))


def select_preview_series(
    previews: Mapping[tuple[str, str], PreviewSeries],
    *,
    module_key: str,
    point_ids: Iterable[str],
) -> PreviewSeries:
    module_key = module_key.strip()
    identities = {str(value).strip() for value in point_ids if str(value).strip()}
    matches = [
        series
        for (module, point), series in previews.items()
        if module == module_key and point in identities
    ]
    if not matches:
        expected = "、".join(sorted(identities)) or "（无测点编号）"
        available = "、".join(
            f"{module}/{point}" for module, point in sorted(previews)
        ) or "（文件中没有曲线）"
        raise ConfigEditorError(
            f"曲线预览与当前规则身份不一致；需要 {module_key}/{expected}，"
            f"文件中可用的是：{available}"
        )
    if len(matches) != 1:
        raise ConfigEditorError(
            f"曲线预览中有多条可映射到 {module_key}/{'、'.join(sorted(identities))} 的曲线，"
            "无法唯一确定测点"
        )
    return matches[0]


def estimate_one_sided_rule(
    series: PreviewSeries,
    draft: OneSidedThresholdDraft,
    *,
    accepted_preview_point_ids: Iterable[str],
) -> ThresholdEstimate:
    draft = draft.validated()
    identities = {str(value).strip() for value in accepted_preview_point_ids}
    if series.module_key != draft.module_key or series.point_id not in identities:
        raise ConfigEditorError(
            f"曲线身份 {series.module_key}/{series.point_id} 与当前规则 "
            f"{draft.module_key}/{draft.point_key} 不一致"
        )
    if len(series.times) != len(series.values):
        raise ConfigEditorError("曲线预览的时间和值数量不一致")

    start = end = None
    if draft.t_range_start:
        start = _timestamp_number(draft.t_range_start, "开始时间")
        end = _timestamp_number(draft.t_range_end, "结束时间")

    finite_count = applicable_count = removed_count = 0
    for raw_time, raw_value in zip(series.times, series.values):
        if raw_value is None:
            continue
        value = float(raw_value)
        if not math.isfinite(value):
            continue
        finite_count += 1
        if start is not None:
            timestamp = _timestamp_number(raw_time, "曲线时间")
            if timestamp < start or timestamp > end:
                continue
        applicable_count += 1
        if draft.side == LOWER_SIDE:
            removed_count += int(value < draft.value)
        else:
            removed_count += int(value > draft.value)
    return ThresholdEstimate(
        len(series.values), finite_count, applicable_count, removed_count
    )


def merge_one_sided_rule(
    rows: Iterable[CleaningThresholdRow],
    *,
    selected_index: int,
    draft: OneSidedThresholdDraft,
) -> tuple[list[CleaningThresholdRow], int, bool]:
    """Append or replace a one-sided rule while enforcing exact identity/dedup."""

    normalized = [row.validated() for row in rows]
    if selected_index < 0 or selected_index >= len(normalized):
        raise ConfigEditorError("请先选择一条测点专用清洗规则")
    selected = normalized[selected_index]
    draft = draft.validated()
    if selected.scope != "per_point":
        raise ConfigEditorError("拖线设置单边阈值只适用于测点专用规则")
    if selected.module_key != draft.module_key or selected.point_key != draft.point_key:
        raise ConfigEditorError(
            "单边阈值目标与当前选中规则的分析类型或测点编号不一致"
        )

    minimum = draft.value if draft.side == LOWER_SIDE else None
    maximum = draft.value if draft.side == UPPER_SIDE else None
    candidate = CleaningThresholdRow(
        selected.scope,
        selected.module_key,
        selected.point_key,
        minimum,
        maximum,
        draft.t_range_start,
        draft.t_range_end,
        selected.zero_to_nan,
        selected.outlier_window_sec,
        selected.outlier_threshold_factor,
    ).validated()

    selected_is_empty = selected.minimum is None and selected.maximum is None
    selected_is_same_side = (
        draft.side == LOWER_SIDE
        and selected.minimum is not None
        and selected.maximum is None
    ) or (
        draft.side == UPPER_SIDE
        and selected.maximum is not None
        and selected.minimum is None
    )
    replace = selected_is_empty or selected_is_same_side
    result = list(normalized)
    if replace:
        result[selected_index] = candidate
        result_index = selected_index
    else:
        result.append(candidate)
        result_index = len(result) - 1

    identity = (
        candidate.scope,
        candidate.module_key,
        candidate.point_key,
        candidate.minimum,
        candidate.maximum,
        candidate.t_range_start,
        candidate.t_range_end,
    )
    duplicates = 0
    for row in result:
        row_identity = (
            row.scope,
            row.module_key,
            row.point_key,
            row.minimum,
            row.maximum,
            row.t_range_start,
            row.t_range_end,
        )
        duplicates += int(row_identity == identity)
    if duplicates > 1:
        raise ConfigEditorError(
            f"相同单边阈值规则已存在：{candidate.module_key}/{candidate.point_key}/"
            f"{draft.direction_text}/{draft.time_window_text}"
        )
    return result, result_index, replace
