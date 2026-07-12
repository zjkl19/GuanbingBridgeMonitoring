from __future__ import annotations

import copy
import json
import math
import os
import re
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from .models import file_sha256


LEVEL_PATTERN = re.compile(r"^level([1-9]\d*)$")
GROUP_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_]+$")
OFFSET_MODES = {
    "fixed",
    "constant",
    "first_day_mean",
    "earliest_day_mean",
    "daily_mean",
    "day_mean",
    "daily_median",
    "day_median",
    "hourly_mean",
    "hour_mean",
    "hourly_median",
    "hour_median",
}
GROUP_MODULE_KEYS = (
    "temperature",
    "humidity",
    "strain",
    "strain_timeseries",
    "dynamic_strain",
    "dynamic_strain_lowpass",
    "deflection",
    "bearing_displacement",
    "tilt",
    "acceleration",
    "cable_accel",
    "crack",
)
GROUP_POINT_KEYS = {
    "strain_timeseries": ("strain",),
    "dynamic_strain": ("dynamic_strain", "strain"),
    "dynamic_strain_lowpass": ("dynamic_strain_lowpass", "dynamic_strain", "strain"),
}
GROUP_STYLE_KEYS = {"strain_timeseries": "strain"}


class ConfigEditorError(ValueError):
    pass


class ConfigChangedError(ConfigEditorError):
    pass


@dataclass(frozen=True)
class AlarmBoundRow:
    scope: str
    module_key: str
    point_key: str
    level: str
    lower: float
    upper: float

    def validated(self) -> "AlarmBoundRow":
        scope = self.scope.strip()
        module_key = self.module_key.strip()
        point_key = self.point_key.strip()
        level = self.level.strip()
        if scope not in {"defaults", "per_point"}:
            raise ConfigEditorError(f"scope 必须是 defaults 或 per_point：{scope!r}")
        if not module_key:
            raise ConfigEditorError("module_key 不能为空")
        if scope == "defaults" and point_key:
            raise ConfigEditorError("defaults 行不能填写 point_key")
        if scope == "per_point" and not point_key:
            raise ConfigEditorError("per_point 行必须填写 point_key")
        if not LEVEL_PATTERN.fullmatch(level):
            raise ConfigEditorError(f"level 必须使用 level1、level2…格式：{level!r}")
        try:
            lower = float(self.lower)
            upper = float(self.upper)
        except (TypeError, ValueError) as exc:
            raise ConfigEditorError("lower/upper 必须是数值") from exc
        if not math.isfinite(lower) or not math.isfinite(upper):
            raise ConfigEditorError("lower/upper 必须是有限数值")
        if upper <= lower:
            raise ConfigEditorError(f"upper 必须大于 lower：{lower} >= {upper}")
        lower_value = int(lower) if lower.is_integer() else lower
        upper_value = int(upper) if upper.is_integer() else upper
        return AlarmBoundRow(scope, module_key, point_key, level, lower_value, upper_value)


@dataclass(frozen=True)
class CleaningThresholdRow:
    scope: str
    module_key: str
    point_key: str
    minimum: float | None
    maximum: float | None
    t_range_start: str = ""
    t_range_end: str = ""
    zero_to_nan: bool | None = None
    outlier_window_sec: float | None = None
    outlier_threshold_factor: float | None = None

    def validated(self) -> "CleaningThresholdRow":
        scope = self.scope.strip()
        module_key = self.module_key.strip()
        point_key = self.point_key.strip()
        if scope not in {"defaults", "per_point"}:
            raise ConfigEditorError(f"scope 必须是 defaults 或 per_point：{scope!r}")
        if not module_key:
            raise ConfigEditorError("module_key 不能为空")
        if scope == "defaults" and point_key:
            raise ConfigEditorError("defaults 行不能填写 point_key")
        if scope == "per_point" and not point_key:
            raise ConfigEditorError("per_point 行必须填写 point_key")

        minimum = _optional_finite(self.minimum, "min")
        maximum = _optional_finite(self.maximum, "max")
        start = str(self.t_range_start or "").strip()
        end = str(self.t_range_end or "").strip()
        if bool(start) != bool(end):
            raise ConfigEditorError("时间窗必须同时填写开始和结束")
        for label, value in (("t_range_start", start), ("t_range_end", end)):
            if value:
                try:
                    datetime.strptime(value, "%Y-%m-%d %H:%M:%S")
                except ValueError as exc:
                    raise ConfigEditorError(f"{label} 格式必须为 yyyy-MM-dd HH:mm:ss：{value!r}") from exc
        if start and minimum is None and maximum is None:
            raise ConfigEditorError("时间窗行至少需要 min 或 max")
        if minimum is not None and maximum is not None and minimum > maximum:
            if not (minimum == 1000 and maximum == -1000):
                raise ConfigEditorError(
                    f"min 大于 max 仅允许历史全抑制哨兵 1000/-1000：{minimum}/{maximum}"
                )

        window = _optional_finite(self.outlier_window_sec, "outlier_window_sec")
        factor = _optional_finite(self.outlier_threshold_factor, "outlier_threshold_factor")
        if (window is None) != (factor is None):
            raise ConfigEditorError("移动窗秒数和异常阈值系数必须同时填写")
        if window is not None and (window <= 0 or factor is None or factor <= 0):
            raise ConfigEditorError("移动窗秒数和异常阈值系数必须大于 0")
        zero = self.zero_to_nan
        if zero is not None and not isinstance(zero, bool):
            raise ConfigEditorError("zero_to_nan 必须是 true、false 或留空")
        return CleaningThresholdRow(
            scope,
            module_key,
            point_key,
            minimum,
            maximum,
            start,
            end,
            zero,
            window,
            factor,
        )


@dataclass(frozen=True)
class OffsetCorrectionRow:
    scope: str
    module_key: str
    point_key: str
    mode: str
    value: float | None = None
    start_date: str = ""
    end_date: str = ""
    segmented: bool = False
    segment_index: int = 0
    note: str = ""

    def validated(self) -> "OffsetCorrectionRow":
        scope = self.scope.strip()
        module = self.module_key.strip()
        point = self.point_key.strip()
        mode = self.mode.strip().lower()
        if scope not in {"defaults", "per_point"}:
            raise ConfigEditorError("offset scope 必须是 defaults 或 per_point")
        if not module:
            raise ConfigEditorError("offset module_key 不能为空")
        if scope == "defaults" and point:
            raise ConfigEditorError("defaults 零点修正不能填写 point_key")
        if scope == "per_point" and not point:
            raise ConfigEditorError("per_point 零点修正必须填写 point_key")
        if mode != "scalar" and mode not in OFFSET_MODES:
            raise ConfigEditorError(f"不支持的 offset mode：{mode!r}")
        value = _optional_finite(self.value, "offset value")
        if mode in {"scalar", "fixed", "constant"} and value is None:
            raise ConfigEditorError(f"{mode} 零点修正必须填写有限 value")
        if mode not in {"scalar", "fixed", "constant"} and value is not None:
            raise ConfigEditorError(f"{mode} 零点修正不使用 value，请留空")
        start = str(self.start_date or "").strip()
        end = str(self.end_date or "").strip()
        for label, text in (("start_date", start), ("end_date", end)):
            if text:
                _parse_offset_date(text, label)
        if mode == "scalar" and (start or end or self.segmented):
            raise ConfigEditorError("scalar 零点修正不能设置日期或分段")
        segment_index = int(self.segment_index or 0)
        if self.segmented and segment_index < 1:
            raise ConfigEditorError("分段零点修正的 segment_index 必须从 1 开始")
        if not self.segmented:
            segment_index = 0
        return OffsetCorrectionRow(
            scope,
            module,
            point,
            mode,
            value,
            start,
            end,
            bool(self.segmented),
            segment_index,
            str(self.note or "").strip(),
        )


@dataclass(frozen=True)
class GroupPlotRow:
    module_key: str
    group_key: str
    label: str
    points: tuple[str, ...]

    def validated(self) -> "GroupPlotRow":
        module = self.module_key.strip()
        key = self.group_key.strip()
        if module not in GROUP_MODULE_KEYS:
            raise ConfigEditorError(f"不支持的组图模块：{module!r}")
        if not GROUP_KEY_PATTERN.fullmatch(key):
            raise ConfigEditorError(
                f"group_key 只能使用英文字母、数字和下划线：{key!r}"
            )
        points = tuple(str(point).strip() for point in self.points if str(point).strip())
        if not points:
            raise ConfigEditorError(f"组 {key} 至少需要一个测点")
        if len(points) != len(set(points)):
            raise ConfigEditorError(f"组 {key} 内存在重复测点")
        return GroupPlotRow(module, key, str(self.label or "").strip(), points)


@dataclass(frozen=True)
class ConfigSaveResult:
    path: Path
    sha256: str
    changed: bool
    backup_path: Path | None = None


def _level_sort_key(level: str) -> tuple[int, str]:
    match = LEVEL_PATTERN.fullmatch(level)
    return (int(match.group(1)), level) if match else (2**31 - 1, level)


def _optional_finite(value: Any, label: str) -> int | float | None:
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ConfigEditorError(f"{label} 必须是有限数值或留空") from exc
    if not math.isfinite(number):
        raise ConfigEditorError(f"{label} 必须是有限数值或留空")
    return int(number) if number.is_integer() else number


def _parse_offset_date(value: str, label: str) -> datetime:
    for pattern in ("%Y-%m-%d", "%Y-%m-%d %H:%M:%S"):
        try:
            return datetime.strptime(value, pattern)
        except ValueError:
            pass
    raise ConfigEditorError(f"{label} 必须是 yyyy-MM-dd 或 yyyy-MM-dd HH:mm:ss：{value!r}")


def _bounds_rows(scope: str, module_key: str, point_key: str, raw: Any) -> list[AlarmBoundRow]:
    if raw is None:
        return []
    if not isinstance(raw, dict):
        raise ConfigEditorError(f"{scope}.{module_key}.{point_key}.alarm_bounds 必须是对象")
    rows: list[AlarmBoundRow] = []
    for level, values in raw.items():
        if not isinstance(values, list) or len(values) != 2:
            raise ConfigEditorError(
                f"{scope}.{module_key}.{point_key}.alarm_bounds.{level} 必须是两个数值"
            )
        rows.append(AlarmBoundRow(scope, module_key, point_key, str(level), values[0], values[1]).validated())
    return rows


def extract_alarm_bounds(payload: dict[str, Any]) -> list[AlarmBoundRow]:
    rows: list[AlarmBoundRow] = []
    defaults = payload.get("defaults", {})
    if defaults is not None and not isinstance(defaults, dict):
        raise ConfigEditorError("defaults 必须是对象")
    for module_key, block in (defaults or {}).items():
        if isinstance(block, dict) and "alarm_bounds" in block:
            rows.extend(_bounds_rows("defaults", str(module_key), "", block.get("alarm_bounds")))

    per_point = payload.get("per_point", {})
    if per_point is not None and not isinstance(per_point, dict):
        raise ConfigEditorError("per_point 必须是对象")
    for module_key, points in (per_point or {}).items():
        if not isinstance(points, dict):
            continue
        for point_key, block in points.items():
            if isinstance(block, dict) and "alarm_bounds" in block:
                rows.extend(
                    _bounds_rows("per_point", str(module_key), str(point_key), block.get("alarm_bounds"))
                )
    return sorted(
        rows,
        key=lambda row: (
            0 if row.scope == "defaults" else 1,
            row.module_key.casefold(),
            row.point_key.casefold(),
            _level_sort_key(row.level),
        ),
    )


def apply_alarm_bounds(payload: dict[str, Any], rows: Iterable[AlarmBoundRow]) -> dict[str, Any]:
    validated: list[AlarmBoundRow] = []
    seen: set[tuple[str, str, str, str]] = set()
    for raw_row in rows:
        row = raw_row.validated()
        identity = (row.scope, row.module_key, row.point_key, row.level)
        if identity in seen:
            raise ConfigEditorError(f"同一测点存在重复等级：{'/'.join(identity)}")
        seen.add(identity)
        validated.append(row)

    updated = copy.deepcopy(payload)
    for block in (updated.get("defaults", {}) or {}).values():
        if isinstance(block, dict):
            block.pop("alarm_bounds", None)
    for points in (updated.get("per_point", {}) or {}).values():
        if not isinstance(points, dict):
            continue
        for block in points.values():
            if isinstance(block, dict):
                block.pop("alarm_bounds", None)

    for row in validated:
        root = updated.setdefault(row.scope, {})
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{row.scope} 必须是对象")
        module = root.setdefault(row.module_key, {})
        if not isinstance(module, dict):
            raise ConfigEditorError(f"{row.scope}.{row.module_key} 必须是对象")
        if row.scope == "per_point":
            module = module.setdefault(row.point_key, {})
            if not isinstance(module, dict):
                raise ConfigEditorError(
                    f"per_point.{row.module_key}.{row.point_key} 必须是对象"
                )
        bounds = module.setdefault("alarm_bounds", {})
        if not isinstance(bounds, dict):
            raise ConfigEditorError("alarm_bounds 必须是对象")
        bounds[row.level] = [row.lower, row.upper]
    return updated


def _cleaning_rows_for_block(
    scope: str,
    module_key: str,
    point_key: str,
    block: dict[str, Any],
) -> list[CleaningThresholdRow]:
    managed = {"thresholds", "zero_to_nan", "outlier"}
    if not managed.intersection(block):
        return []
    raw_thresholds = block.get("thresholds")
    if raw_thresholds is None:
        thresholds: list[dict[str, Any]] = []
    elif isinstance(raw_thresholds, dict):
        thresholds = [raw_thresholds]
    elif isinstance(raw_thresholds, list):
        if not all(isinstance(item, dict) for item in raw_thresholds):
            raise ConfigEditorError(f"{scope}.{module_key}.{point_key}.thresholds 必须是对象或对象数组")
        thresholds = raw_thresholds
    else:
        raise ConfigEditorError(f"{scope}.{module_key}.{point_key}.thresholds 必须是对象或对象数组")

    zero = None
    if "zero_to_nan" in block:
        raw_zero = block.get("zero_to_nan")
        if not isinstance(raw_zero, (bool, int, float)):
            raise ConfigEditorError(f"{scope}.{module_key}.{point_key}.zero_to_nan 必须是布尔值")
        zero = bool(raw_zero)
    window = factor = None
    raw_outlier = block.get("outlier")
    if isinstance(raw_outlier, dict):
        window = raw_outlier.get("window_sec")
        factor = raw_outlier.get("threshold_factor")
    elif raw_outlier not in (None, []):
        raise ConfigEditorError(f"{scope}.{module_key}.{point_key}.outlier 必须是对象或空数组")

    if not thresholds:
        thresholds = [{}]
    rows = [
        CleaningThresholdRow(
            scope,
            module_key,
            point_key,
            raw.get("min"),
            raw.get("max"),
            str(raw.get("t_range_start") or ""),
            str(raw.get("t_range_end") or ""),
            zero,
            window,
            factor,
        ).validated()
        for raw in thresholds
    ]
    return rows


def extract_cleaning_thresholds(payload: dict[str, Any]) -> list[CleaningThresholdRow]:
    rows: list[CleaningThresholdRow] = []
    defaults = payload.get("defaults", {}) or {}
    if not isinstance(defaults, dict):
        raise ConfigEditorError("defaults 必须是对象")
    for module_key, block in defaults.items():
        if isinstance(block, dict):
            rows.extend(_cleaning_rows_for_block("defaults", str(module_key), "", block))

    per_point = payload.get("per_point", {}) or {}
    if not isinstance(per_point, dict):
        raise ConfigEditorError("per_point 必须是对象")
    for module_key, points in per_point.items():
        if not isinstance(points, dict):
            continue
        for point_key, block in points.items():
            if isinstance(block, dict):
                rows.extend(
                    _cleaning_rows_for_block("per_point", str(module_key), str(point_key), block)
                )
    return sorted(
        rows,
        key=lambda row: (
            0 if row.scope == "defaults" else 1,
            row.module_key.casefold(),
            row.point_key.casefold(),
            row.t_range_start,
            row.minimum if row.minimum is not None else float("-inf"),
        ),
    )


def _existing_cleaning_block(
    payload: dict[str, Any], identity: tuple[str, str, str]
) -> dict[str, Any] | None:
    scope, module_key, point_key = identity
    root = payload.get(scope)
    if not isinstance(root, dict):
        return None
    module = root.get(module_key)
    if not isinstance(module, dict):
        return None
    if scope == "defaults":
        return module
    block = module.get(point_key)
    return block if isinstance(block, dict) else None


def apply_cleaning_thresholds(
    payload: dict[str, Any], rows: Iterable[CleaningThresholdRow]
) -> dict[str, Any]:
    validated = [row.validated() for row in rows]
    groups: dict[tuple[str, str, str], list[CleaningThresholdRow]] = {}
    seen_rules: set[tuple[Any, ...]] = set()
    for row in validated:
        identity = (row.scope, row.module_key, row.point_key)
        rule_identity = identity + (
            row.minimum,
            row.maximum,
            row.t_range_start,
            row.t_range_end,
        )
        if (row.minimum is not None or row.maximum is not None) and rule_identity in seen_rules:
            raise ConfigEditorError(f"存在重复清洗规则：{'/'.join(identity)}")
        seen_rules.add(rule_identity)
        groups.setdefault(identity, []).append(row)

    updated = copy.deepcopy(payload)
    for root_name in ("defaults", "per_point"):
        root = updated.get(root_name, {}) or {}
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{root_name} 必须是对象")
        modules = root.values()
        for module in modules:
            if not isinstance(module, dict):
                continue
            blocks = [module] if root_name == "defaults" else module.values()
            for block in blocks:
                if isinstance(block, dict):
                    for field in ("thresholds", "zero_to_nan", "outlier"):
                        block.pop(field, None)

    for identity, block_rows in groups.items():
        zero_values = {row.zero_to_nan for row in block_rows}
        outlier_values = {
            (row.outlier_window_sec, row.outlier_threshold_factor) for row in block_rows
        }
        if len(zero_values) > 1:
            raise ConfigEditorError(f"同一配置块的 zero_to_nan 不一致：{'/'.join(identity)}")
        if len(outlier_values) > 1:
            raise ConfigEditorError(f"同一配置块的 outlier 参数不一致：{'/'.join(identity)}")

        scope, module_key, point_key = identity
        root = updated.setdefault(scope, {})
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{scope} 必须是对象")
        module = root.setdefault(module_key, {})
        if not isinstance(module, dict):
            raise ConfigEditorError(f"{scope}.{module_key} 必须是对象")
        target = module
        if scope == "per_point":
            target = module.setdefault(point_key, {})
            if not isinstance(target, dict):
                raise ConfigEditorError(f"per_point.{module_key}.{point_key} 必须是对象")

        active = [row for row in block_rows if row.minimum is not None or row.maximum is not None]
        existing = _existing_cleaning_block(payload, identity)
        existing_thresholds = existing.get("thresholds") if existing else None
        if active:
            rules: list[dict[str, Any]] = []
            for row in active:
                rule: dict[str, Any] = {}
                if row.minimum is not None:
                    rule["min"] = row.minimum
                if row.maximum is not None:
                    rule["max"] = row.maximum
                if row.t_range_start:
                    rule["t_range_start"] = row.t_range_start
                    rule["t_range_end"] = row.t_range_end
                rules.append(rule)
            target["thresholds"] = rules[0] if isinstance(existing_thresholds, dict) and len(rules) == 1 else rules
        elif existing is not None and "thresholds" in existing:
            target["thresholds"] = []

        zero = next(iter(zero_values))
        if zero is not None:
            target["zero_to_nan"] = zero
        window, factor = next(iter(outlier_values))
        if window is not None and factor is not None:
            target["outlier"] = {"window_sec": window, "threshold_factor": factor}
        elif existing is not None and "outlier" in existing and existing.get("outlier") in (None, []):
            target["outlier"] = copy.deepcopy(existing.get("outlier"))
    return updated


def extract_post_filter_thresholds(payload: dict[str, Any]) -> list[CleaningThresholdRow]:
    rows: list[CleaningThresholdRow] = []
    for scope in ("defaults", "per_point"):
        root = payload.get(scope, {}) or {}
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{scope} 必须是对象")
        for module_key, module in root.items():
            if not isinstance(module, dict):
                continue
            blocks = [("", module)] if scope == "defaults" else module.items()
            for point_key, block in blocks:
                if not isinstance(block, dict) or "post_filter_thresholds" not in block:
                    continue
                raw = block.get("post_filter_thresholds")
                if isinstance(raw, dict):
                    rules = [raw]
                elif isinstance(raw, list):
                    if not all(isinstance(item, dict) for item in raw):
                        raise ConfigEditorError(
                            f"{scope}.{module_key}.{point_key}.post_filter_thresholds 必须是对象数组"
                        )
                    rules = raw
                elif raw is None:
                    rules = []
                else:
                    raise ConfigEditorError(
                        f"{scope}.{module_key}.{point_key}.post_filter_thresholds 必须是对象或数组"
                    )
                if not rules:
                    rules = [{}]
                rows.extend(
                    CleaningThresholdRow(
                        scope,
                        str(module_key),
                        str(point_key),
                        rule.get("min"),
                        rule.get("max"),
                        str(rule.get("t_range_start") or ""),
                        str(rule.get("t_range_end") or ""),
                    ).validated()
                    for rule in rules
                )
    return sorted(
        rows,
        key=lambda row: (
            0 if row.scope == "defaults" else 1,
            row.module_key.casefold(),
            row.point_key.casefold(),
            row.t_range_start,
        ),
    )


def apply_post_filter_thresholds(
    payload: dict[str, Any], rows: Iterable[CleaningThresholdRow]
) -> dict[str, Any]:
    validated = [row.validated() for row in rows]
    groups: dict[tuple[str, str, str], list[CleaningThresholdRow]] = {}
    seen: set[tuple[Any, ...]] = set()
    for row in validated:
        if row.zero_to_nan is not None or row.outlier_window_sec is not None:
            raise ConfigEditorError("滤波后二次清洗不支持 zero_to_nan 或 outlier")
        identity = (row.scope, row.module_key, row.point_key)
        rule_id = identity + (row.minimum, row.maximum, row.t_range_start, row.t_range_end)
        if (row.minimum is not None or row.maximum is not None) and rule_id in seen:
            raise ConfigEditorError(f"存在重复滤波后规则：{'/'.join(identity)}")
        seen.add(rule_id)
        groups.setdefault(identity, []).append(row)

    updated = copy.deepcopy(payload)
    for scope in ("defaults", "per_point"):
        root = updated.get(scope, {}) or {}
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{scope} 必须是对象")
        for module in root.values():
            if not isinstance(module, dict):
                continue
            blocks = [module] if scope == "defaults" else module.values()
            for block in blocks:
                if isinstance(block, dict):
                    block.pop("post_filter_thresholds", None)

    for identity, block_rows in groups.items():
        scope, module_key, point_key = identity
        root = updated.setdefault(scope, {})
        module = root.setdefault(module_key, {})
        target = module if scope == "defaults" else module.setdefault(point_key, {})
        if not isinstance(target, dict):
            raise ConfigEditorError(f"配置块不是对象：{'/'.join(identity)}")
        active = [row for row in block_rows if row.minimum is not None or row.maximum is not None]
        existing = _existing_cleaning_block(payload, identity)
        existing_raw = existing.get("post_filter_thresholds") if existing else None
        if active:
            rules: list[dict[str, Any]] = []
            for row in active:
                rule: dict[str, Any] = {}
                if row.minimum is not None:
                    rule["min"] = row.minimum
                if row.maximum is not None:
                    rule["max"] = row.maximum
                if row.t_range_start:
                    rule["t_range_start"] = row.t_range_start
                    rule["t_range_end"] = row.t_range_end
                rules.append(rule)
            target["post_filter_thresholds"] = (
                rules[0] if isinstance(existing_raw, dict) and len(rules) == 1 else rules
            )
        elif existing is not None and "post_filter_thresholds" in existing:
            target["post_filter_thresholds"] = []
    return updated


def _offset_rows_for_value(
    scope: str, module: str, point: str, raw: Any
) -> list[OffsetCorrectionRow]:
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return [OffsetCorrectionRow(scope, module, point, "scalar", raw).validated()]
    if isinstance(raw, str):
        try:
            number = float(raw)
        except ValueError:
            number = math.nan
        if math.isfinite(number):
            return [OffsetCorrectionRow(scope, module, point, "scalar", number).validated()]
        mode = raw.strip().lower()
        if mode in OFFSET_MODES:
            return [OffsetCorrectionRow(scope, module, point, mode).validated()]
    if not isinstance(raw, dict):
        raise ConfigEditorError(
            f"{scope}.{module}.{point}.offset_correction 必须是有限数值或对象"
        )
    mode = str(raw.get("mode") or raw.get("method") or raw.get("type") or "").lower()
    if not mode and any(key in raw for key in ("value", "offset", "offset_value")):
        mode = "fixed"
    note = str(raw.get("note") or "")
    if mode == "segmented" or isinstance(raw.get("segments"), list):
        segments = raw.get("segments")
        if not isinstance(segments, list) or not segments:
            raise ConfigEditorError(f"{scope}.{module}.{point}.offset_correction.segments 不能为空")
        rows: list[OffsetCorrectionRow] = []
        for index, segment in enumerate(segments, 1):
            if not isinstance(segment, dict):
                raise ConfigEditorError("offset_correction.segments 必须是对象数组")
            segment_mode = str(
                segment.get("mode") or segment.get("method") or segment.get("type") or ""
            ).lower()
            if not segment_mode and any(
                key in segment for key in ("value", "offset", "offset_value")
            ):
                segment_mode = "fixed"
            value = segment.get("value", segment.get("offset", segment.get("offset_value")))
            rows.append(
                OffsetCorrectionRow(
                    scope,
                    module,
                    point,
                    segment_mode,
                    value,
                    str(segment.get("start_date") or ""),
                    str(segment.get("end_date") or ""),
                    True,
                    index,
                    note,
                ).validated()
            )
        return rows
    value = raw.get("value", raw.get("offset", raw.get("offset_value")))
    return [
        OffsetCorrectionRow(
            scope,
            module,
            point,
            mode,
            value,
            str(raw.get("start_date") or ""),
            str(raw.get("end_date") or ""),
            False,
            0,
            note,
        ).validated()
    ]


def extract_offset_corrections(payload: dict[str, Any]) -> list[OffsetCorrectionRow]:
    rows: list[OffsetCorrectionRow] = []
    for scope in ("defaults", "per_point"):
        root = payload.get(scope, {}) or {}
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{scope} 必须是对象")
        for module, module_block in root.items():
            if not isinstance(module_block, dict):
                continue
            blocks = [("", module_block)] if scope == "defaults" else module_block.items()
            for point, block in blocks:
                if isinstance(block, dict) and "offset_correction" in block:
                    rows.extend(
                        _offset_rows_for_value(
                            scope, str(module), str(point), block["offset_correction"]
                        )
                    )
    return sorted(
        rows,
        key=lambda row: (
            0 if row.scope == "defaults" else 1,
            row.module_key.casefold(),
            row.point_key.casefold(),
            row.segment_index,
        ),
    )


def _validate_offset_groups(
    rows: Iterable[OffsetCorrectionRow],
) -> dict[tuple[str, str, str], list[OffsetCorrectionRow]]:
    grouped: dict[tuple[str, str, str], list[OffsetCorrectionRow]] = {}
    for raw in rows:
        row = raw.validated()
        grouped.setdefault((row.scope, row.module_key, row.point_key), []).append(row)
    for identity, block_rows in grouped.items():
        segmented = {row.segmented for row in block_rows}
        if len(segmented) != 1:
            raise ConfigEditorError(f"同一零点修正不能混合分段和非分段：{'/'.join(identity)}")
        if not next(iter(segmented)):
            if len(block_rows) != 1:
                raise ConfigEditorError(f"非分段零点修正只能有一行：{'/'.join(identity)}")
            continue
        indexes = [row.segment_index for row in block_rows]
        if len(indexes) != len(set(indexes)):
            raise ConfigEditorError(f"分段序号重复：{'/'.join(identity)}")
        ordered = sorted(block_rows, key=lambda row: row.segment_index)
        if len({row.note for row in ordered}) > 1:
            raise ConfigEditorError("同一 segmented 零点修正的外层备注必须一致")
        intervals: list[tuple[datetime, datetime]] = []
        for row in ordered:
            if not row.start_date or not row.end_date:
                raise ConfigEditorError("分段零点修正必须成对填写 start_date/end_date")
            start = _parse_offset_date(row.start_date, "start_date")
            end = _parse_offset_date(row.end_date, "end_date")
            if end < start:
                raise ConfigEditorError("分段零点修正的 end_date 不能早于 start_date")
            if any(start <= old_end and end >= old_start for old_start, old_end in intervals):
                raise ConfigEditorError(f"分段零点修正日期重叠：{'/'.join(identity)}")
            intervals.append((start, end))
        grouped[identity] = ordered
    return grouped


def apply_offset_corrections(
    payload: dict[str, Any], rows: Iterable[OffsetCorrectionRow]
) -> dict[str, Any]:
    grouped = _validate_offset_groups(rows)
    updated = copy.deepcopy(payload)
    for scope in ("defaults", "per_point"):
        root = updated.get(scope, {}) or {}
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{scope} 必须是对象")
        for module in root.values():
            if not isinstance(module, dict):
                continue
            blocks = [module] if scope == "defaults" else module.values()
            for block in blocks:
                if isinstance(block, dict):
                    block.pop("offset_correction", None)
    for (scope, module_key, point_key), block_rows in grouped.items():
        root = updated.setdefault(scope, {})
        if not isinstance(root, dict):
            raise ConfigEditorError(f"{scope} 必须是对象")
        module = root.setdefault(module_key, {})
        if not isinstance(module, dict):
            raise ConfigEditorError(f"{scope}.{module_key} 必须是对象")
        target = module
        if scope == "per_point":
            target = module.setdefault(point_key, {})
            if not isinstance(target, dict):
                raise ConfigEditorError(f"per_point.{module_key}.{point_key} 必须是对象")
        first = block_rows[0]
        if first.mode == "scalar":
            target["offset_correction"] = first.value
            continue
        if first.segmented:
            segments: list[dict[str, Any]] = []
            for row in block_rows:
                segment: dict[str, Any] = {"mode": row.mode}
                if row.value is not None:
                    segment["value"] = row.value
                if row.start_date:
                    segment["start_date"] = row.start_date
                if row.end_date:
                    segment["end_date"] = row.end_date
                segments.append(segment)
            value: dict[str, Any] = {"mode": "segmented", "segments": segments}
            if first.note:
                value["note"] = first.note
            target["offset_correction"] = value
            continue
        value = {"mode": first.mode}
        if first.value is not None:
            value["value"] = first.value
        if first.start_date:
            value["start_date"] = first.start_date
        if first.end_date:
            value["end_date"] = first.end_date
        if first.note:
            value["note"] = first.note
        target["offset_correction"] = value
    return updated


def _normalize_group_points(raw: Any) -> tuple[str, ...]:
    if isinstance(raw, str):
        text = raw.strip()
        return (text,) if text else ()
    if not isinstance(raw, list):
        return ()
    points: list[str] = []
    for item in raw:
        if isinstance(item, str) and item.strip() and item.strip() not in points:
            points.append(item.strip())
    return tuple(points)


def _group_rows(payload: dict[str, Any], module_key: str) -> list[GroupPlotRow]:
    groups_root = payload.get("groups", {}) or {}
    if not isinstance(groups_root, dict):
        raise ConfigEditorError("groups 必须是对象")
    raw = groups_root.get(module_key)
    if raw is None:
        return []
    labels: dict[str, Any] = {}
    style_key = GROUP_STYLE_KEYS.get(module_key, module_key)
    styles = payload.get("plot_styles", {}) or {}
    if isinstance(styles, dict) and isinstance(styles.get(style_key), dict):
        candidate = styles[style_key].get("group_labels", {})
        if isinstance(candidate, dict):
            labels = candidate
    rows: list[GroupPlotRow] = []
    if isinstance(raw, dict):
        items = raw.items()
    elif isinstance(raw, list):
        items = ((f"G{index}", value) for index, value in enumerate(raw, 1))
    else:
        raise ConfigEditorError(f"groups.{module_key} 必须是对象或数组")
    for key, value in items:
        points = _normalize_group_points(value)
        if not points:
            continue
        rows.append(
            GroupPlotRow(module_key, str(key), str(labels.get(str(key)) or ""), points).validated()
        )
    return rows


def group_plot_modules(payload: dict[str, Any]) -> list[str]:
    candidates: set[str] = set()
    for section in ("groups", "points", "per_point"):
        root = payload.get(section, {}) or {}
        if isinstance(root, dict):
            candidates.update(str(key) for key in root)
    return [key for key in GROUP_MODULE_KEYS if key in candidates]


def extract_group_plots(payload: dict[str, Any]) -> list[GroupPlotRow]:
    rows: list[GroupPlotRow] = []
    for module in group_plot_modules(payload):
        rows.extend(_group_rows(payload, module))
    return rows


def available_group_points(payload: dict[str, Any], module_key: str) -> tuple[str, ...]:
    keys = GROUP_POINT_KEYS.get(module_key, (module_key,))
    points: list[str] = []
    root = payload.get("points", {}) or {}
    if isinstance(root, dict):
        for key in keys:
            for point in _normalize_group_points(root.get(key)):
                if point not in points:
                    points.append(point)
    per_point = payload.get("per_point", {}) or {}
    name_map = payload.get("name_map_global", {}) or {}
    if isinstance(per_point, dict):
        for key in keys:
            block = per_point.get(key)
            if isinstance(block, dict):
                for point in block:
                    display = str(name_map.get(point) or point) if isinstance(name_map, dict) else str(point)
                    if display not in points:
                        points.append(display)
    for row in _group_rows(payload, module_key):
        for point in row.points:
            if point not in points:
                points.append(point)
    return tuple(points)


def apply_group_plots(
    payload: dict[str, Any], module_key: str, rows: Iterable[GroupPlotRow]
) -> dict[str, Any]:
    if module_key not in GROUP_MODULE_KEYS:
        raise ConfigEditorError(f"不支持的组图模块：{module_key!r}")
    normalized = [row.validated() for row in rows]
    if any(row.module_key != module_key for row in normalized):
        raise ConfigEditorError("组图行的 module_key 与当前模块不一致")
    keys = [row.group_key for row in normalized]
    if len(keys) != len(set(keys)):
        raise ConfigEditorError("group_key 不能重复")
    known = set(available_group_points(payload, module_key))
    if known:
        unknown = sorted({point for row in normalized for point in row.points if point not in known})
        if unknown:
            raise ConfigEditorError(f"组图引用未知测点：{', '.join(unknown)}")
    updated = copy.deepcopy(payload)
    groups = updated.setdefault("groups", {})
    if not isinstance(groups, dict):
        raise ConfigEditorError("groups 必须是对象")
    original = groups.get(module_key)
    preserve_list = isinstance(original, list) and all(
        row.group_key == f"G{index}" and not row.label
        for index, row in enumerate(normalized, 1)
    )
    groups[module_key] = (
        [list(row.points) for row in normalized]
        if preserve_list
        else {row.group_key: list(row.points) for row in normalized}
    )
    styles = updated.setdefault("plot_styles", {})
    if not isinstance(styles, dict):
        raise ConfigEditorError("plot_styles 必须是对象")
    style_key = GROUP_STYLE_KEYS.get(module_key, module_key)
    style = styles.setdefault(style_key, {})
    if not isinstance(style, dict):
        raise ConfigEditorError(f"plot_styles.{style_key} 必须是对象")
    had_group_labels = "group_labels" in style
    existing_labels = style.get("group_labels", {})
    if not isinstance(existing_labels, dict):
        existing_labels = {}
    labels = copy.deepcopy(existing_labels)
    for row in _group_rows(payload, module_key):
        labels.pop(row.group_key, None)
    labels.update({row.group_key: row.label for row in normalized if row.label})
    if labels or had_group_labels:
        style["group_labels"] = labels
    return updated


def _encoded_config(payload: dict[str, Any]) -> bytes:
    return (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")


class ConfigEditorSession:
    def __init__(self, path: Path) -> None:
        self.path = path.expanduser().resolve()
        if not self.path.is_file():
            raise FileNotFoundError(f"配置文件不存在：{self.path}")
        self.payload = json.loads(self.path.read_text(encoding="utf-8-sig"))
        if not isinstance(self.payload, dict):
            raise ConfigEditorError("配置文件根节点必须是 JSON 对象")
        self.loaded_sha256 = file_sha256(self.path)

    @property
    def rows(self) -> list[AlarmBoundRow]:
        return extract_alarm_bounds(self.payload)

    def build_payload(self, rows: Iterable[AlarmBoundRow]) -> dict[str, Any]:
        return apply_alarm_bounds(self.payload, rows)

    def save(self, rows: Iterable[AlarmBoundRow], *, target: Path | None = None) -> ConfigSaveResult:
        return self._save_updated(self.build_payload(rows), target=target)

    def _save_updated(
        self, updated: dict[str, Any], *, target: Path | None = None
    ) -> ConfigSaveResult:
        target_path = (target or self.path).expanduser().resolve()
        overwriting_source = target_path == self.path
        if overwriting_source and file_sha256(self.path) != self.loaded_sha256:
            raise ConfigChangedError("配置文件已被其它程序修改，请重新加载后再保存")
        if overwriting_source and updated == self.payload:
            return ConfigSaveResult(self.path, self.loaded_sha256, False)
        encoded = _encoded_config(updated)
        if target_path.is_file():
            try:
                existing = json.loads(target_path.read_text(encoding="utf-8-sig"))
            except (OSError, json.JSONDecodeError):
                existing = None
            if existing == updated:
                return ConfigSaveResult(target_path, file_sha256(target_path), False)

        target_path.parent.mkdir(parents=True, exist_ok=True)
        backup_path: Path | None = None
        if target_path.is_file():
            stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
            backup_path = target_path.with_name(f"{target_path.stem}_backup_workbench_{stamp}{target_path.suffix}")
            shutil.copy2(target_path, backup_path)
        temporary = target_path.with_name(f".{target_path.name}.{os.getpid()}.tmp")
        try:
            temporary.write_bytes(encoded)
            json.loads(temporary.read_text(encoding="utf-8"))
            os.replace(temporary, target_path)
        finally:
            temporary.unlink(missing_ok=True)

        if overwriting_source:
            self.payload = updated
            self.loaded_sha256 = file_sha256(target_path)
        return ConfigSaveResult(target_path, file_sha256(target_path), True, backup_path)


class CleaningConfigEditorSession(ConfigEditorSession):
    @property
    def rows(self) -> list[CleaningThresholdRow]:
        return extract_cleaning_thresholds(self.payload)

    def build_payload(self, rows: Iterable[CleaningThresholdRow]) -> dict[str, Any]:
        normalized = [row.validated() for row in rows]
        # Preserve the original representation byte-for-byte on a no-op save.
        # This matters because production configs mix scalar objects, arrays,
        # empty arrays and one-sided threshold objects.
        if normalized == self.rows:
            return copy.deepcopy(self.payload)
        return apply_cleaning_thresholds(self.payload, normalized)

    def save(
        self, rows: Iterable[CleaningThresholdRow], *, target: Path | None = None
    ) -> ConfigSaveResult:
        return self._save_updated(self.build_payload(rows), target=target)

    def build_payload_with_proposals(self, proposals: Iterable[dict[str, Any]]) -> dict[str, Any]:
        rows = list(self.rows)
        existing = {
            (
                row.scope,
                row.module_key,
                row.point_key,
                row.minimum,
                row.maximum,
                row.t_range_start,
                row.t_range_end,
            )
            for row in rows
            if row.minimum is not None or row.maximum is not None
        }
        names: dict[str, str] = {}
        accepted = 0
        for proposal in proposals:
            if not bool(proposal.get("selected", False)):
                continue
            if str(proposal.get("kind") or "") not in {"range", "window_range"}:
                continue
            module_key = str(proposal.get("apply_key") or "").strip()
            point_key = str(proposal.get("safe_id") or "").strip()
            point_id = str(proposal.get("point_id") or point_key).strip()
            if not module_key or not point_key:
                raise ConfigEditorError("自动建议缺少 apply_key 或 safe_id，拒绝写入")
            row = CleaningThresholdRow(
                "per_point",
                module_key,
                point_key,
                proposal.get("min"),
                proposal.get("max"),
                str(proposal.get("t_range_start") or ""),
                str(proposal.get("t_range_end") or ""),
            ).validated()
            identity = (
                row.scope,
                row.module_key,
                row.point_key,
                row.minimum,
                row.maximum,
                row.t_range_start,
                row.t_range_end,
            )
            if identity not in existing:
                rows.append(row)
                existing.add(identity)
                accepted += 1
            names[point_key] = point_id
        if accepted == 0:
            raise ConfigEditorError("没有新的、可写入的已勾选阈值建议")
        updated = apply_cleaning_thresholds(self.payload, rows)
        name_map = updated.setdefault("name_map_global", {})
        if not isinstance(name_map, dict):
            raise ConfigEditorError("name_map_global 必须是对象")
        name_map.update(names)
        return updated

    def save_proposals(
        self,
        proposals: Iterable[dict[str, Any]],
        *,
        expected_sha256: str,
    ) -> ConfigSaveResult:
        expected = expected_sha256.strip().lower()
        if self.loaded_sha256.lower() != expected or file_sha256(self.path).lower() != expected:
            raise ConfigChangedError("建议生成后配置文件已变化，请重新生成建议")
        return self._save_updated(self.build_payload_with_proposals(proposals))


class PostFilterConfigEditorSession(ConfigEditorSession):
    @property
    def rows(self) -> list[CleaningThresholdRow]:
        return extract_post_filter_thresholds(self.payload)

    def build_payload(self, rows: Iterable[CleaningThresholdRow]) -> dict[str, Any]:
        normalized = [row.validated() for row in rows]
        if normalized == self.rows:
            return copy.deepcopy(self.payload)
        return apply_post_filter_thresholds(self.payload, normalized)

    def save(
        self, rows: Iterable[CleaningThresholdRow], *, target: Path | None = None
    ) -> ConfigSaveResult:
        return self._save_updated(self.build_payload(rows), target=target)


class OffsetConfigEditorSession(ConfigEditorSession):
    @property
    def rows(self) -> list[OffsetCorrectionRow]:
        return extract_offset_corrections(self.payload)

    def build_payload(self, rows: Iterable[OffsetCorrectionRow]) -> dict[str, Any]:
        normalized = [row.validated() for row in rows]
        if normalized == self.rows:
            return copy.deepcopy(self.payload)
        return apply_offset_corrections(self.payload, normalized)

    def save(
        self, rows: Iterable[OffsetCorrectionRow], *, target: Path | None = None
    ) -> ConfigSaveResult:
        return self._save_updated(self.build_payload(rows), target=target)


class GroupPlotConfigEditorSession(ConfigEditorSession):
    @property
    def modules(self) -> list[str]:
        return group_plot_modules(self.payload)

    @property
    def rows(self) -> list[GroupPlotRow]:
        return extract_group_plots(self.payload)

    def rows_for(self, module_key: str) -> list[GroupPlotRow]:
        return _group_rows(self.payload, module_key)

    def available_points(self, module_key: str) -> tuple[str, ...]:
        return available_group_points(self.payload, module_key)

    def build_payload(
        self, module_key: str, rows: Iterable[GroupPlotRow]
    ) -> dict[str, Any]:
        normalized = [row.validated() for row in rows]
        if normalized == self.rows_for(module_key):
            return copy.deepcopy(self.payload)
        return apply_group_plots(self.payload, module_key, normalized)

    def save_module(
        self,
        module_key: str,
        rows: Iterable[GroupPlotRow],
        *,
        target: Path | None = None,
    ) -> ConfigSaveResult:
        return self._save_updated(self.build_payload(module_key, rows), target=target)

    def build_payload_all(
        self, drafts: dict[str, Iterable[GroupPlotRow]]
    ) -> dict[str, Any]:
        normalized_drafts = {
            module: [row.validated() for row in raw_rows]
            for module, raw_rows in drafts.items()
        }
        if "strain" in normalized_drafts and "strain_timeseries" in normalized_drafts:
            box_labels = {row.group_key: row.label for row in normalized_drafts["strain"]}
            time_labels = {
                row.group_key: row.label for row in normalized_drafts["strain_timeseries"]
            }
            conflicts = sorted(
                key
                for key in box_labels.keys() & time_labels.keys()
                if box_labels[key] != time_labels[key]
            )
            if conflicts:
                raise ConfigEditorError(
                    "strain 与 strain_timeseries 共用 group_labels，以下同名组显示名称不一致："
                    + ", ".join(conflicts)
                )
        updated = copy.deepcopy(self.payload)
        changed = False
        for module_key, rows in normalized_drafts.items():
            current = _group_rows(updated, module_key)
            if rows != current:
                updated = apply_group_plots(updated, module_key, rows)
                changed = True
        return updated if changed else copy.deepcopy(self.payload)

    def save_all(
        self,
        drafts: dict[str, Iterable[GroupPlotRow]],
        *,
        target: Path | None = None,
    ) -> ConfigSaveResult:
        return self._save_updated(self.build_payload_all(drafts), target=target)
