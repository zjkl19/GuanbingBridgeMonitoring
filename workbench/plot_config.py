from __future__ import annotations

import copy
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from .config_editor import ConfigEditorError, ConfigEditorSession, ConfigSaveResult


PLOT_COMMON_SCHEMA: tuple[tuple[str, str, Any, str], ...] = (
    ("save_fig", "bool", True, "保存可编辑 FIG"),
    ("lightweight_fig", "bool", True, "FIG 使用轻量数据"),
    ("fig_max_points", "int", 50000, "普通图最大绘制点数"),
    ("append_timestamp", "bool", False, "输出文件名追加时间戳"),
    ("gap_mode", "enum:connect|break", "connect", "缺口连接方式"),
    ("gap_break_factor", "float", 5.0, "断线判定采样间隔倍数"),
    ("dynamic_raw_sampling_mode", "enum:capped|full", "capped", "高频原始图采样模式"),
    ("dynamic_raw_fig_max_points", "int", 50000, "capped 模式原始图总点数上限"),
    ("dynamic_raw_min_points_per_day", "int", 0, "capped 模式每日最低点数"),
    ("dynamic_raw_line_width", "float", 1.0, "高频原始曲线线宽"),
    ("dynamic_raw_render_mode", "enum:line|dense_band", "line", "高频原始图渲染方式"),
    ("dynamic_raw_band_bins", "int", 24000, "dense_band 分箱数"),
    ("dynamic_raw_band_line_width", "float", 0.55, "dense_band 边线宽度"),
    ("dynamic_raw_trace_points", "int", 120000, "dense_band 叠加轨迹点数；0 表示关闭"),
)
PLOT_FIELDS = {item[0] for item in PLOT_COMMON_SCHEMA}
SPECTRUM_MODULES = {
    "accel_spectrum": {
        "params_key": "accel_spectrum_params",
        "per_point_key": "accel_spectrum",
        "base_point_keys": ("acceleration", "accel_spectrum"),
        "group_keys": ("acceleration",),
    },
    "cable_accel_spectrum": {
        "params_key": "cable_accel_spectrum_params",
        "per_point_key": "cable_accel_spectrum",
        "base_point_keys": ("cable_accel", "cable_accel_spectrum"),
        "group_keys": ("cable_accel", "cable_force"),
    },
}
FREQUENCY_FIELDS = {
    "peak_orders",
    "target_freqs",
    "tolerance",
    "theor_freqs",
    "theor_labels",
    "peak_labels",
}

# Analysis modules do not always use the same JSON key for their plot style
# and per-point settings.  Keep that compatibility knowledge next to the gap
# resolver so a new, explicit module key wins while established bridge configs
# (for example wind_speed and dynamic_strain) remain effective.
GAP_MODULE_LAYER_KEYS: dict[str, dict[str, tuple[str, ...]]] = {
    "wind": {
        "style": ("wind", "wind_speed"),
        "point": ("wind", "wind_speed", "wind_direction"),
        "legacy": ("wind", "wind_speed"),
    },
    "eq": {
        "style": ("eq", "earthquake"),
        "point": ("eq", "earthquake"),
        "legacy": ("eq", "earthquake"),
    },
    "earthquake": {
        "style": ("earthquake", "eq"),
        "point": ("earthquake", "eq"),
        "legacy": ("earthquake", "eq"),
    },
    "dynamic_strain_highpass": {
        "style": ("dynamic_strain_highpass", "dynamic_strain"),
        "point": ("dynamic_strain_highpass", "dynamic_strain", "strain"),
        "legacy": ("dynamic_strain_highpass", "dynamic_strain"),
    },
    "dynamic_strain": {
        "style": ("dynamic_strain", "dynamic_strain_highpass"),
        "point": ("dynamic_strain", "dynamic_strain_highpass", "strain"),
        "legacy": ("dynamic_strain", "dynamic_strain_highpass"),
    },
    "dynamic_strain_lowpass": {
        "style": ("dynamic_strain_lowpass", "dynamic_strain"),
        "point": (
            "dynamic_strain_lowpass",
            "dynamic_strain",
            "strain",
        ),
        "legacy": ("dynamic_strain_lowpass", "dynamic_strain"),
    },
    "accel_spectrum": {
        "style": ("accel_spectrum", "acceleration"),
        "point": ("accel_spectrum", "acceleration"),
        "legacy": ("accel_spectrum", "acceleration"),
    },
    "cable_accel_spectrum": {
        "style": ("cable_accel_spectrum", "cable_accel"),
        "point": ("cable_accel_spectrum", "cable_accel"),
        "legacy": ("cable_accel_spectrum", "cable_accel"),
    },
}


@dataclass(frozen=True)
class PlotCommonRow:
    field: str
    value_type: str
    explicit: bool
    value: bool | int | float | str
    description: str

    def validated(self) -> "PlotCommonRow":
        if self.field not in PLOT_FIELDS:
            raise ConfigEditorError(f"不支持的 plot_common 字段：{self.field}")
        schema = next(item for item in PLOT_COMMON_SCHEMA if item[0] == self.field)
        expected_type = schema[1]
        value = _parse_typed(self.value, expected_type, self.field)
        _validate_plot_value(self.field, value)
        return PlotCommonRow(
            self.field, expected_type, bool(self.explicit), value, schema[3]
        )


@dataclass(frozen=True)
class GapOverrideRow:
    """One explicit module/point override for time-series gap rendering.

    ``inherit`` is intentionally represented by the absence of a field in
    JSON.  A row may inherit the mode while overriding only the break factor,
    but a completely inherited row is rejected because deleting the row is
    the unambiguous UI operation for that case.
    """

    scope: str
    module_key: str
    point_key: str = ""
    gap_mode: str = "inherit"
    gap_break_factor: float | None = None

    def validated(self) -> "GapOverrideRow":
        scope = str(self.scope or "").strip().lower()
        module = str(self.module_key or "").strip()
        point = str(self.point_key or "").strip()
        mode = str(self.gap_mode or "inherit").strip().lower()
        if scope not in {"module", "point"}:
            raise ConfigEditorError("连线覆盖范围必须是 module 或 point")
        if not module:
            raise ConfigEditorError("连线覆盖必须填写分析模块")
        if scope == "module" and point:
            raise ConfigEditorError("模块级连线覆盖不能填写测点编号")
        if scope == "point" and not point:
            raise ConfigEditorError("测点级连线覆盖必须填写测点编号")
        if mode not in {"inherit", "connect", "break"}:
            raise ConfigEditorError("gap_mode 必须是 inherit/connect/break")
        factor = _optional_finite(self.gap_break_factor, "gap_break_factor")
        if factor is not None and factor < 1.1:
            raise ConfigEditorError("gap_break_factor 不能小于 1.1")
        if mode == "inherit" and factor is None:
            raise ConfigEditorError("完全继承请删除该覆盖行")
        return GapOverrideRow(scope, module, point, mode, factor)


@dataclass(frozen=True)
class SpectrumCoverage:
    module_key: str
    explicit: bool
    points: tuple[str, ...]

    def validated(self) -> "SpectrumCoverage":
        if self.module_key not in SPECTRUM_MODULES:
            raise ConfigEditorError(f"不支持的频谱模块：{self.module_key}")
        points = tuple(_unique_text(self.points))
        if self.explicit and not points:
            raise ConfigEditorError("显式频谱测点清单不能为空；如需回退请取消显式清单")
        return SpectrumCoverage(self.module_key, bool(self.explicit), points)


@dataclass(frozen=True)
class SpectrumPeakOrderRow:
    module_key: str
    scope: str
    point_id: str
    order: float | None
    label: str
    theoretical_hz: float | None
    search_min_hz: float
    search_max_hz: float
    theor_label: str = ""
    enabled: bool = True
    source: str = "peak_orders"

    def validated(self) -> "SpectrumPeakOrderRow":
        module = self.module_key.strip()
        scope = self.scope.strip().lower()
        point = self.point_id.strip()
        if module not in SPECTRUM_MODULES:
            raise ConfigEditorError(f"不支持的频谱模块：{module}")
        if scope not in {"default", "point"}:
            raise ConfigEditorError("频谱 scope 必须是 default 或 point")
        if scope == "default" and point:
            raise ConfigEditorError("default 频谱阶次不能填写 point_id")
        if scope == "point" and not point:
            raise ConfigEditorError("point 频谱阶次必须填写 point_id")
        order = _optional_finite(self.order, "order")
        theoretical = _optional_finite(self.theoretical_hz, "theoretical_hz")
        minimum = _required_finite(self.search_min_hz, "search_min_hz")
        maximum = _required_finite(self.search_max_hz, "search_max_hz")
        if minimum < 0 or maximum <= minimum:
            raise ConfigEditorError("频谱搜索区间必须满足 0 <= min < max")
        if theoretical is not None and theoretical < 0:
            raise ConfigEditorError("theoretical_hz 不能小于 0")
        if order is not None and order <= 0:
            raise ConfigEditorError("order 必须大于 0 或留空")
        return SpectrumPeakOrderRow(
            module,
            scope,
            point,
            order,
            str(self.label or "").strip(),
            theoretical,
            minimum,
            maximum,
            str(self.theor_label or "").strip(),
            bool(self.enabled),
            str(self.source or "").strip(),
        )


def _optional_finite(value: Any, label: str) -> int | float | None:
    if value is None or (isinstance(value, str) and not value.strip()):
        return None
    return _required_finite(value, label)


def _required_finite(value: Any, label: str) -> int | float:
    try:
        number = float(value)
    except (TypeError, ValueError) as exc:
        raise ConfigEditorError(f"{label} 必须是有限数值") from exc
    if not math.isfinite(number):
        raise ConfigEditorError(f"{label} 必须是有限数值")
    return int(number) if number.is_integer() else number


def _parse_bool(value: Any, field: str) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)) and value in {0, 1}:
        return bool(value)
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "on", "是"}:
        return True
    if text in {"false", "0", "no", "off", "否"}:
        return False
    raise ConfigEditorError(f"{field} 必须是 true/false")


def _parse_typed(value: Any, value_type: str, field: str) -> bool | int | float | str:
    if value_type == "bool":
        return _parse_bool(value, field)
    if value_type == "int":
        number = _required_finite(value, field)
        if float(number).is_integer():
            return int(number)
        raise ConfigEditorError(f"{field} 必须是整数")
    if value_type == "float":
        return _required_finite(value, field)
    if value_type.startswith("enum:"):
        allowed = value_type.split(":", 1)[1].split("|")
        text = str(value).strip().lower()
        if text not in allowed:
            raise ConfigEditorError(f"{field} 必须是 {'/'.join(allowed)}")
        return text
    raise ConfigEditorError(f"未知字段类型：{value_type}")


def _validate_plot_value(field: str, value: Any) -> None:
    if field == "fig_max_points" and value < 1000:
        raise ConfigEditorError("fig_max_points 不能小于 1000")
    if field == "gap_break_factor" and value < 1.1:
        raise ConfigEditorError("gap_break_factor 不能小于 1.1")
    if field == "dynamic_raw_fig_max_points" and value < 1000:
        raise ConfigEditorError("dynamic_raw_fig_max_points 不能小于 1000")
    if field == "dynamic_raw_min_points_per_day" and value < 0:
        raise ConfigEditorError("dynamic_raw_min_points_per_day 不能小于 0")
    if field == "dynamic_raw_line_width" and not 0.5 <= value <= 3:
        raise ConfigEditorError("dynamic_raw_line_width 必须在 0.5~3.0")
    if field == "dynamic_raw_band_bins" and not 1000 <= value <= 100000:
        raise ConfigEditorError("dynamic_raw_band_bins 必须在 1000~100000")
    if field == "dynamic_raw_band_line_width" and not 0.1 <= value <= 2:
        raise ConfigEditorError("dynamic_raw_band_line_width 必须在 0.1~2.0")
    if field == "dynamic_raw_trace_points" and not 0 <= value <= 1000000:
        raise ConfigEditorError("dynamic_raw_trace_points 必须在 0~1000000")


def extract_plot_common(payload: dict[str, Any]) -> list[PlotCommonRow]:
    raw = payload.get("plot_common", {}) or {}
    if not isinstance(raw, dict):
        raise ConfigEditorError("plot_common 必须是对象")
    rows: list[PlotCommonRow] = []
    for field, value_type, default, description in PLOT_COMMON_SCHEMA:
        explicit = field in raw
        value = raw.get(field, default)
        rows.append(
            PlotCommonRow(field, value_type, explicit, value, description).validated()
        )
    return rows


def apply_plot_common(
    payload: dict[str, Any], rows: Iterable[PlotCommonRow]
) -> dict[str, Any]:
    normalized = [row.validated() for row in rows]
    if {row.field for row in normalized} != PLOT_FIELDS:
        raise ConfigEditorError("plot_common 编辑表必须包含全部受管字段且不得重复")
    values = {row.field: row for row in normalized}
    sampling = values["dynamic_raw_sampling_mode"]
    render = values["dynamic_raw_render_mode"]
    if (
        sampling.explicit
        and sampling.value == "full"
        and render.explicit
        and render.value != "line"
    ):
        raise ConfigEditorError("full 原始采样会强制 line 渲染，请将 dynamic_raw_render_mode 设为 line")
    updated = copy.deepcopy(payload)
    common = updated.setdefault("plot_common", {})
    if not isinstance(common, dict):
        raise ConfigEditorError("plot_common 必须是对象")
    for field in PLOT_FIELDS:
        common.pop(field, None)
    for row in normalized:
        if row.explicit:
            common[row.field] = row.value
    return updated


def _gap_fields(raw: Any) -> tuple[str, float | int | None] | None:
    if not isinstance(raw, dict):
        return None
    has_mode = "gap_mode" in raw
    has_factor = "gap_break_factor" in raw
    if not has_mode and not has_factor:
        return None
    mode = str(raw.get("gap_mode") or "inherit").strip().lower()
    factor = raw.get("gap_break_factor") if has_factor else None
    return mode, factor


def extract_gap_overrides(payload: dict[str, Any]) -> list[GapOverrideRow]:
    """Read only the new module/point overrides; legacy raw overrides remain intact."""

    rows: list[GapOverrideRow] = []
    styles = payload.get("plot_styles", {}) or {}
    if not isinstance(styles, dict):
        raise ConfigEditorError("plot_styles 必须是对象")
    for module, block in styles.items():
        fields = _gap_fields(block)
        if fields is not None:
            rows.append(
                GapOverrideRow("module", str(module), "", fields[0], fields[1]).validated()
            )

    per_point = payload.get("per_point", {}) or {}
    if not isinstance(per_point, dict):
        raise ConfigEditorError("per_point 必须是对象")
    for module, points in per_point.items():
        if not isinstance(points, dict):
            continue
        for point, block in points.items():
            if not isinstance(block, dict):
                continue
            fields = _gap_fields(block.get("plot"))
            if fields is not None:
                original = str(point)
                name_map = payload.get("name_map_global", {}) or {}
                if isinstance(name_map, dict):
                    original = str(name_map.get(point) or point)
                rows.append(
                    GapOverrideRow(
                        "point", str(module), original, fields[0], fields[1]
                    ).validated()
                )
    return rows


def _generic_point_key(payload: dict[str, Any], module: str, point_id: str) -> str:
    per_root = payload.get("per_point", {}) or {}
    module_block = per_root.get(module, {}) if isinstance(per_root, dict) else {}
    name_map = payload.get("name_map_global", {}) or {}
    candidates = [point_id, point_id.replace("-", "_")]
    if isinstance(name_map, dict):
        candidates.extend(key for key, value in name_map.items() if str(value) == point_id)
    if isinstance(module_block, dict):
        for candidate in candidates:
            if candidate in module_block:
                return candidate
    key = re.sub(r"[^0-9A-Za-z_]", "_", point_id.replace("-", "_"))
    if not key or key[0].isdigit():
        key = "x" + key
    return key


def apply_gap_overrides(
    payload: dict[str, Any], rows: Iterable[GapOverrideRow]
) -> dict[str, Any]:
    normalized = [row.validated() for row in rows]
    identities = [(row.scope, row.module_key, row.point_key) for row in normalized]
    if len(identities) != len(set(identities)):
        raise ConfigEditorError("同一模块或测点存在重复连线覆盖")

    updated = copy.deepcopy(payload)
    styles_raw = updated.get("plot_styles")
    if styles_raw is None:
        styles: dict[str, Any] = {}
    elif not isinstance(styles_raw, dict):
        raise ConfigEditorError("plot_styles 必须是对象")
    else:
        styles = styles_raw
    for block in styles.values():
        if isinstance(block, dict):
            block.pop("gap_mode", None)
            block.pop("gap_break_factor", None)

    per_raw = updated.get("per_point")
    if per_raw is None:
        per_root: dict[str, Any] = {}
    elif not isinstance(per_raw, dict):
        raise ConfigEditorError("per_point 必须是对象")
    else:
        per_root = per_raw
    for points in per_root.values():
        if not isinstance(points, dict):
            continue
        for point_block in points.values():
            if not isinstance(point_block, dict):
                continue
            plot = point_block.get("plot")
            if isinstance(plot, dict):
                plot.pop("gap_mode", None)
                plot.pop("gap_break_factor", None)
                if not plot:
                    point_block.pop("plot", None)

    for row in normalized:
        if row.scope == "module":
            if "plot_styles" not in updated:
                updated["plot_styles"] = styles
            target = styles.setdefault(row.module_key, {})
            if not isinstance(target, dict):
                raise ConfigEditorError(f"plot_styles.{row.module_key} 必须是对象")
        else:
            if "per_point" not in updated:
                updated["per_point"] = per_root
            module_block = per_root.setdefault(row.module_key, {})
            if not isinstance(module_block, dict):
                raise ConfigEditorError(f"per_point.{row.module_key} 必须是对象")
            point_key = _generic_point_key(updated, row.module_key, row.point_key)
            point_block = module_block.setdefault(point_key, {})
            if not isinstance(point_block, dict):
                raise ConfigEditorError(
                    f"per_point.{row.module_key}.{point_key} 必须是对象"
                )
            target = point_block.setdefault("plot", {})
            if not isinstance(target, dict):
                raise ConfigEditorError(
                    f"per_point.{row.module_key}.{point_key}.plot 必须是对象"
                )
            if point_key != row.point_key:
                name_map = updated.setdefault("name_map_global", {})
                if isinstance(name_map, dict):
                    name_map[point_key] = row.point_key
        if row.gap_mode != "inherit":
            target["gap_mode"] = row.gap_mode
        if row.gap_break_factor is not None:
            target["gap_break_factor"] = row.gap_break_factor
    return updated


def resolve_gap_options(
    payload: dict[str, Any], module_key: str = "", point_id: str = ""
) -> dict[str, Any]:
    """Resolve point > module > legacy dynamic module > global gap settings."""

    common = payload.get("plot_common", {}) or {}
    if not isinstance(common, dict):
        common = {}
    result: dict[str, Any] = {
        "gap_mode": str(common.get("gap_mode") or "connect").strip().lower(),
        "gap_break_factor": common.get("gap_break_factor", 5),
        "mode_source": "全局",
        "factor_source": "全局",
    }

    def apply(raw: Any, source: str) -> None:
        if not isinstance(raw, dict):
            return
        if "gap_mode" in raw:
            result["gap_mode"] = str(raw.get("gap_mode") or "").strip().lower()
            result["mode_source"] = source
        if "gap_break_factor" in raw:
            result["gap_break_factor"] = raw.get("gap_break_factor")
            result["factor_source"] = source

    module = str(module_key or "").strip()
    point = str(point_id or "").strip()

    def layer_keys(layer: str) -> tuple[str, ...]:
        configured = GAP_MODULE_LAYER_KEYS.get(module, {}).get(layer, ())
        return tuple(dict.fromkeys((module, *configured))) if module else ()

    def apply_layer(container: Any, layer: str, source: str) -> None:
        if not isinstance(container, dict):
            return
        # Apply compatibility keys first and the actual analysis key last.
        for key in reversed(layer_keys(layer)):
            apply(container.get(key), source)

    dynamic = common.get("dynamic_raw_modules", {})
    apply_layer(dynamic, "legacy", "兼容模块设置")
    styles = payload.get("plot_styles", {}) or {}
    apply_layer(styles, "style", "模块设置")
    per_root = payload.get("per_point", {}) or {}
    if point and isinstance(per_root, dict):
        for point_module in reversed(layer_keys("point")):
            points = per_root.get(point_module, {})
            if not isinstance(points, dict):
                continue
            key = _generic_point_key(payload, point_module, point)
            block = points.get(key)
            if isinstance(block, dict):
                apply(block.get("plot"), "测点设置")

    if result["gap_mode"] not in {"connect", "break"}:
        raise ConfigEditorError("解析后的 gap_mode 必须是 connect 或 break")
    factor = _required_finite(result["gap_break_factor"], "gap_break_factor")
    if factor < 1.1:
        raise ConfigEditorError("解析后的 gap_break_factor 不能小于 1.1")
    result["gap_break_factor"] = factor
    return result


def _unique_text(values: Iterable[Any]) -> list[str]:
    result: list[str] = []
    for value in values:
        text = str(value).strip()
        if text and text not in result:
            result.append(text)
    return result


def _points_from_raw(raw: Any) -> list[str]:
    if isinstance(raw, str):
        return [raw] if raw.strip() else []
    if isinstance(raw, list):
        return _unique_text(item for item in raw if isinstance(item, str))
    return []


def _flatten_groups(raw: Any) -> list[str]:
    points: list[str] = []
    if isinstance(raw, dict):
        values = raw.values()
    elif isinstance(raw, list):
        values = raw
    else:
        return points
    for value in values:
        for point in _points_from_raw(value):
            if point not in points:
                points.append(point)
    return points


def spectrum_available_points(payload: dict[str, Any], module_key: str) -> tuple[str, ...]:
    spec = SPECTRUM_MODULES[module_key]
    points: list[str] = []
    root = payload.get("points", {}) or {}
    if isinstance(root, dict):
        for key in spec["base_point_keys"]:
            points.extend(_points_from_raw(root.get(key)))
    groups = payload.get("groups", {}) or {}
    if isinstance(groups, dict):
        for key in spec["group_keys"]:
            points.extend(_flatten_groups(groups.get(key)))
    per_point = payload.get("per_point", {}) or {}
    name_map = payload.get("name_map_global", {}) or {}
    if isinstance(per_point, dict):
        block = per_point.get(spec["per_point_key"])
        if isinstance(block, dict):
            for key in block:
                points.append(str(name_map.get(key) or key) if isinstance(name_map, dict) else key)
    return tuple(_unique_text(points))


def extract_spectrum_coverage(payload: dict[str, Any], module_key: str) -> SpectrumCoverage:
    points_root = payload.get("points", {}) or {}
    explicit = isinstance(points_root, dict) and module_key in points_root
    points = _points_from_raw(points_root.get(module_key)) if explicit else list(
        spectrum_available_points(payload, module_key)
    )
    return SpectrumCoverage(module_key, explicit, tuple(points)).validated()


def _array(raw: Any) -> list[Any]:
    return raw if isinstance(raw, list) else ([] if raw is None else [raw])


def _index_or_last(values: list[Any], index: int, default: Any) -> Any:
    if not values:
        return default
    return values[min(index, len(values) - 1)]


def _order_rows(
    module_key: str, scope: str, point_id: str, block: dict[str, Any], source: str
) -> list[SpectrumPeakOrderRow]:
    raw_orders = block.get("peak_orders")
    if isinstance(raw_orders, dict):
        orders = [raw_orders]
    elif isinstance(raw_orders, list) and all(isinstance(item, dict) for item in raw_orders):
        orders = raw_orders
    else:
        orders = []
    rows: list[SpectrumPeakOrderRow] = []
    if orders:
        for index, item in enumerate(orders, 1):
            minimum = _optional_finite(
                item.get("search_min_hz", item.get("min_hz", item.get("lower_hz"))),
                "search_min_hz",
            )
            maximum = _optional_finite(
                item.get("search_max_hz", item.get("max_hz", item.get("upper_hz"))),
                "search_max_hz",
            )
            center = _optional_finite(
                item.get("search_center_hz", item.get("target_hz", item.get("frequency_hz"))),
                "search_center_hz",
            )
            half = _optional_finite(
                item.get("search_half_width_hz", item.get("tolerance_hz", item.get("half_width_hz"))),
                "search_half_width_hz",
            )
            theor = _optional_finite(
                item.get("theoretical_hz", item.get("theor_hz")), "theoretical_hz"
            )
            if center is None:
                center = theor
            if minimum is None or maximum is None:
                if center is None:
                    raise ConfigEditorError("peak_order 缺少可解析的搜索中心或区间")
                half = half if half is not None and half > 0 else 0.15
                minimum, maximum = center - half, center + half
            rows.append(
                SpectrumPeakOrderRow(
                    module_key,
                    scope,
                    point_id,
                    item.get("order", index),
                    str(item.get("label") or item.get("name") or f"峰{index}"),
                    theor,
                    minimum,
                    maximum,
                    str(item.get("theor_label") or item.get("theoretical_label") or ""),
                    True,
                    source,
                ).validated()
            )
        return rows
    freqs = _array(block.get("target_freqs"))
    tolerances = _array(block.get("tolerance")) or [0.15]
    theor = _array(block.get("theor_freqs"))
    theor_labels = _array(block.get("theor_labels"))
    peak_labels = _array(block.get("peak_labels"))
    for index, raw_freq in enumerate(freqs):
        frequency = _required_finite(raw_freq, "target_freqs")
        half = _required_finite(_index_or_last(tolerances, index, 0.15), "tolerance")
        theoretical = _optional_finite(_index_or_last(theor, index, None), "theor_freqs")
        rows.append(
            SpectrumPeakOrderRow(
                module_key,
                scope,
                point_id,
                index + 1,
                str(_index_or_last(peak_labels, index, f"峰{index + 1}")),
                theoretical,
                frequency - half,
                frequency + half,
                str(_index_or_last(theor_labels, index, "")),
                True,
                "兼容配置",
            ).validated()
        )
    return rows


def extract_spectrum_orders(
    payload: dict[str, Any], module_key: str
) -> list[SpectrumPeakOrderRow]:
    spec = SPECTRUM_MODULES[module_key]
    rows: list[SpectrumPeakOrderRow] = []
    params = payload.get(spec["params_key"], {}) or {}
    if not isinstance(params, dict):
        raise ConfigEditorError(f"{spec['params_key']} 必须是对象")
    rows.extend(_order_rows(module_key, "default", "", params, "params"))
    per_point = payload.get("per_point", {}) or {}
    name_map = payload.get("name_map_global", {}) or {}
    block = per_point.get(spec["per_point_key"], {}) if isinstance(per_point, dict) else {}
    if isinstance(block, dict):
        for point_key, point_config in block.items():
            if not isinstance(point_config, dict) or not FREQUENCY_FIELDS.intersection(point_config):
                continue
            point_id = str(name_map.get(point_key) or point_key) if isinstance(name_map, dict) else str(point_key)
            rows.extend(
                _order_rows(module_key, "point", point_id, point_config, "per_point")
            )
    return rows


def _order_identity(row: SpectrumPeakOrderRow) -> tuple[str, str, str]:
    key = f"order:{row.order:g}" if row.order is not None else f"label:{row.label.casefold()}"
    return row.scope, row.point_id, key


def _safe_point_key(payload: dict[str, Any], module_key: str, point_id: str) -> str:
    spec = SPECTRUM_MODULES[module_key]
    per_point = payload.get("per_point", {}) or {}
    block = per_point.get(spec["per_point_key"], {}) if isinstance(per_point, dict) else {}
    name_map = payload.get("name_map_global", {}) or {}
    candidates = [point_id, point_id.replace("-", "_")]
    if isinstance(name_map, dict):
        candidates.extend(key for key, value in name_map.items() if str(value) == point_id)
    if isinstance(block, dict):
        for candidate in candidates:
            if candidate in block:
                return candidate
    key = re.sub(r"[^0-9A-Za-z_]", "_", point_id.replace("-", "_"))
    if not key or key[0].isdigit():
        key = "x" + key
    return key


def _order_payload(row: SpectrumPeakOrderRow) -> dict[str, Any]:
    center = (row.search_min_hz + row.search_max_hz) / 2
    half = (row.search_max_hz - row.search_min_hz) / 2
    item: dict[str, Any] = {
        "label": row.label,
        "search_center_hz": center,
        "search_half_width_hz": half,
        "search_min_hz": row.search_min_hz,
        "search_max_hz": row.search_max_hz,
    }
    if row.order is not None:
        item["order"] = row.order
    if row.theoretical_hz is not None:
        item["theoretical_hz"] = row.theoretical_hz
    if row.theor_label:
        item["theor_label"] = row.theor_label
    return item


def apply_spectrum_config(
    payload: dict[str, Any], coverage: SpectrumCoverage, rows: Iterable[SpectrumPeakOrderRow]
) -> dict[str, Any]:
    coverage = coverage.validated()
    normalized = [row.validated() for row in rows]
    if any(row.module_key != coverage.module_key for row in normalized):
        raise ConfigEditorError("频谱阶次模块与测点覆盖模块不一致")
    active = [row for row in normalized if row.enabled]
    identities = [_order_identity(row) for row in active]
    if len(identities) != len(set(identities)):
        raise ConfigEditorError("同一 scope/point 存在重复频谱阶次")
    available = set(spectrum_available_points(payload, coverage.module_key)) | set(coverage.points)
    unknown = sorted({row.point_id for row in active if row.scope == "point" and row.point_id not in available})
    if unknown:
        raise ConfigEditorError("逐点频谱阶次引用未知测点：" + ", ".join(unknown))
    updated = copy.deepcopy(payload)
    points_root = updated.setdefault("points", {})
    if not isinstance(points_root, dict):
        raise ConfigEditorError("points 必须是对象")
    if coverage.explicit:
        points_root[coverage.module_key] = list(coverage.points)
    else:
        points_root.pop(coverage.module_key, None)
    spec = SPECTRUM_MODULES[coverage.module_key]
    params = updated.get(spec["params_key"], {}) or {}
    if not isinstance(params, dict):
        raise ConfigEditorError(f"{spec['params_key']} 必须是对象")
    for field in FREQUENCY_FIELDS:
        params.pop(field, None)
    defaults = [_order_payload(row) for row in active if row.scope == "default"]
    if defaults:
        params["peak_orders"] = defaults
    updated[spec["params_key"]] = params
    per_root = updated.setdefault("per_point", {})
    if not isinstance(per_root, dict):
        raise ConfigEditorError("per_point 必须是对象")
    per_block = per_root.setdefault(spec["per_point_key"], {})
    if not isinstance(per_block, dict):
        raise ConfigEditorError(f"per_point.{spec['per_point_key']} 必须是对象")
    for point_config in per_block.values():
        if isinstance(point_config, dict):
            for field in FREQUENCY_FIELDS:
                point_config.pop(field, None)
    names: dict[str, str] = {}
    point_rows: dict[str, list[dict[str, Any]]] = {}
    for row in active:
        if row.scope != "point":
            continue
        safe = _safe_point_key(payload, coverage.module_key, row.point_id)
        point_rows.setdefault(safe, []).append(_order_payload(row))
        names[safe] = row.point_id
    for safe, orders in point_rows.items():
        target = per_block.setdefault(safe, {})
        if not isinstance(target, dict):
            raise ConfigEditorError(f"per_point.{spec['per_point_key']}.{safe} 必须是对象")
        target["peak_orders"] = orders
    empty_keys = [key for key, value in per_block.items() if isinstance(value, dict) and not value]
    for key in empty_keys:
        per_block.pop(key, None)
    if names:
        name_map = updated.setdefault("name_map_global", {})
        if not isinstance(name_map, dict):
            raise ConfigEditorError("name_map_global 必须是对象")
        for safe, original in names.items():
            if safe != original:
                name_map[safe] = original
    return updated


class PlotCommonConfigSession(ConfigEditorSession):
    @property
    def rows(self) -> list[PlotCommonRow]:
        return extract_plot_common(self.payload)

    @property
    def gap_overrides(self) -> list[GapOverrideRow]:
        return extract_gap_overrides(self.payload)

    def build_payload(
        self,
        rows: Iterable[PlotCommonRow],
        gap_overrides: Iterable[GapOverrideRow] | None = None,
    ) -> dict[str, Any]:
        normalized = [row.validated() for row in rows]
        normalized_gap = (
            self.gap_overrides
            if gap_overrides is None
            else [row.validated() for row in gap_overrides]
        )
        if normalized == self.rows and normalized_gap == self.gap_overrides:
            return copy.deepcopy(self.payload)
        updated = apply_plot_common(self.payload, normalized)
        return apply_gap_overrides(updated, normalized_gap)

    def save(
        self,
        rows: Iterable[PlotCommonRow],
        gap_overrides: Iterable[GapOverrideRow] | None = None,
        *,
        target: Path | None = None,
    ) -> ConfigSaveResult:
        return self._save_updated(
            self.build_payload(rows, gap_overrides), target=target
        )


class SpectrumConfigSession(ConfigEditorSession):
    def coverage(self, module_key: str) -> SpectrumCoverage:
        return extract_spectrum_coverage(self.payload, module_key)

    def orders(self, module_key: str) -> list[SpectrumPeakOrderRow]:
        return extract_spectrum_orders(self.payload, module_key)

    def available_points(self, module_key: str) -> tuple[str, ...]:
        return spectrum_available_points(self.payload, module_key)

    def build_payload_all(
        self,
        coverages: dict[str, SpectrumCoverage],
        orders: dict[str, Iterable[SpectrumPeakOrderRow]],
    ) -> dict[str, Any]:
        normalized_coverages = {
            module: coverage.validated() for module, coverage in coverages.items()
        }
        normalized_orders = {
            module: [row.validated() for row in rows]
            for module, rows in orders.items()
        }
        unchanged = all(
            normalized_coverages.get(module) == self.coverage(module)
            and normalized_orders.get(module, []) == self.orders(module)
            for module in SPECTRUM_MODULES
        )
        if unchanged:
            return copy.deepcopy(self.payload)
        updated = copy.deepcopy(self.payload)
        for module in SPECTRUM_MODULES:
            updated = apply_spectrum_config(
                updated,
                normalized_coverages[module],
                normalized_orders.get(module, []),
            )
        return updated

    def save_all(
        self,
        coverages: dict[str, SpectrumCoverage],
        orders: dict[str, Iterable[SpectrumPeakOrderRow]],
        *,
        target: Path | None = None,
    ) -> ConfigSaveResult:
        return self._save_updated(
            self.build_payload_all(coverages, orders), target=target
        )
