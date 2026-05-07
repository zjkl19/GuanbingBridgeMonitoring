from __future__ import annotations

import math
from datetime import datetime
from typing import Iterable


def parse_float(value: object) -> float | None:
    if value is None or value == "":
        return None
    try:
        fv = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(fv):
        return None
    return fv


def safe_text(value: object, fallback: str = "") -> str:
    if value is None:
        return fallback
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return str(value)


def format_number(value: object, decimals: int = 3, unit: str = "", *, trim: bool = True, missing: str = "") -> str:
    fv = parse_float(value)
    if fv is None:
        return missing
    if decimals >= 0 and abs(fv) < 0.5 * (10 ** -decimals):
        fv = 0.0
    text = f"{fv:.{decimals}f}"
    if trim:
        text = text.rstrip("0").rstrip(".")
    return f"{text}{unit}"


def format_number_fixed(value: object, decimals: int = 3, unit: str = "") -> str:
    return format_number(value, decimals, unit, trim=False, missing="")


def format_table_number(value: object, decimals: int = 3, keep_trailing: bool = False) -> str:
    return format_number(value, decimals, trim=not keep_trailing, missing="/")


def format_table_datetime(value: object) -> str:
    text = safe_text(value)
    return text if text else "/"


def format_range(min_val: object, max_val: object, decimals: int = 3, unit: str = "", *, trim: bool = True, missing: str = "--") -> str:
    lo = parse_float(min_val)
    hi = parse_float(max_val)
    if lo is None or hi is None:
        return missing
    return f"{format_number(lo, decimals, unit, trim=trim)}~{format_number(hi, decimals, unit, trim=trim)}"


def format_range_fixed(min_val: object, max_val: object, decimals: int = 1, unit: str = "") -> str:
    return format_range(min_val, max_val, decimals, unit, trim=False, missing="--")


def numeric_values(rows: Iterable[dict], key: str) -> list[float]:
    values = [parse_float(row.get(key)) for row in rows]
    return [value for value in values if value is not None]


def numeric_min(rows: Iterable[dict], key: str) -> float | None:
    values = numeric_values(rows, key)
    return min(values) if values else None


def numeric_max(rows: Iterable[dict], key: str) -> float | None:
    values = numeric_values(rows, key)
    return max(values) if values else None


def numeric_mean(rows: Iterable[dict], key: str) -> float | None:
    values = numeric_values(rows, key)
    return sum(values) / len(values) if values else None


def table_cell_text(value: object) -> str:
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, float):
        return f"{value:.6f}".rstrip("0").rstrip(".")
    if value is None:
        return ""
    return str(value)


def format_percent(count: int, total: int, decimals: int = 5) -> str:
    if total <= 0:
        return f"{0:.{decimals}f}"
    return f"{count / total * 100:.{decimals}f}"
