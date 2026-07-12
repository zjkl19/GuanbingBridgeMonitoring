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
class ConfigSaveResult:
    path: Path
    sha256: str
    changed: bool
    backup_path: Path | None = None


def _level_sort_key(level: str) -> tuple[int, str]:
    match = LEVEL_PATTERN.fullmatch(level)
    return (int(match.group(1)), level) if match else (2**31 - 1, level)


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
        target_path = (target or self.path).expanduser().resolve()
        overwriting_source = target_path == self.path
        if overwriting_source and file_sha256(self.path) != self.loaded_sha256:
            raise ConfigChangedError("配置文件已被其它程序修改，请重新加载后再保存")
        updated = self.build_payload(rows)
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
