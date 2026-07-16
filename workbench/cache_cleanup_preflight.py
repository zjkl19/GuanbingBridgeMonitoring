from __future__ import annotations

import json
import os
import zipfile
from datetime import date, timedelta
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from .cache_cleanup_settings import CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS


def cleanup_root_preflight_errors(
    data_root: Path,
    config_path: Path,
    start_date: str,
    end_date: str,
    data_layout: str,
) -> list[str]:
    """Read-only, bounded archive check before a destructive task is saved/run.

    This intentionally validates only facts available before MATLAB executes:
    the active source root, complete per-day archive set, a readable central
    directory, and safe/unique ZIP entry paths. The authoritative path/size/CRC
    match and standalone MAT-cache load still run in MATLAB immediately before
    any rename or deletion.
    """

    root = Path(data_root).expanduser()
    config = Path(config_path).expanduser()
    if data_layout not in CACHE_SOURCE_CLEANUP_SUPPORTED_LAYOUTS:
        return [f"当前数据目录格式不支持安全删除：{data_layout}"]
    if not root.is_dir() or not config.is_file():
        return []  # The ordinary input validator reports these first.
    try:
        cfg = json.loads(config.read_text(encoding="utf-8-sig"))
        first = date.fromisoformat(start_date)
        last = date.fromisoformat(end_date)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return [f"无法读取安全清理预检所需的配置或日期：{exc}"]
    if last < first:
        return []

    source_root = _archive_source_root(root, cfg)
    if not source_root.is_dir():
        return [f"安全清理所需的原 ZIP 根目录不存在：{source_root}"]

    errors: list[str] = []
    current = first
    while current <= last:
        day_text = current.isoformat()
        if data_layout == "jlj_daily_export":
            archives = _daily_export_archives(source_root, cfg, day_text)
            if len(archives) != 1:
                errors.append(
                    f"{day_text} 必须恰好有 1 个可恢复的逐日 ZIP，实际 {len(archives)} 个"
                )
            else:
                errors.extend(_zip_errors(archives[0], day_text))
        else:
            for kind in ("波形", "特征值"):
                kind_root = source_root / day_text / kind
                archives = sorted(
                    (item for item in kind_root.rglob("*.zip") if item.is_file()),
                    key=lambda item: os.path.normcase(str(item)),
                ) if kind_root.is_dir() else []
                if not archives:
                    errors.append(
                        f"{day_text}/{kind} 至少需要 1 个可恢复 ZIP，实际 0 个"
                    )
                else:
                    for archive in archives:
                        errors.extend(
                            _zip_errors(archive, f"{day_text}/{kind}/{archive.name}")
                        )
        current += timedelta(days=1)
    return errors


def _archive_source_root(data_root: Path, cfg: dict[str, Any]) -> Path:
    section: dict[str, Any] = {}
    for outer in ("preprocess", "preprocessing"):
        candidate = cfg.get(outer)
        if isinstance(candidate, dict) and isinstance(candidate.get("unzip"), dict):
            section.update(candidate["unzip"])
    raw = str(section.get("source_root") or "").strip()
    if not raw:
        return data_root.resolve()
    candidate = Path(raw).expanduser()
    if candidate.is_absolute():
        return candidate.resolve()
    return (data_root / candidate).resolve()


def _daily_export_archives(
    source_root: Path, cfg: dict[str, Any], day_text: str
) -> list[Path]:
    adapter = cfg.get("data_adapter")
    zip_cfg = adapter.get("zip") if isinstance(adapter, dict) else None
    raw_glob: object = zip_cfg.get("glob") if isinstance(zip_cfg, dict) else None
    if isinstance(raw_glob, str):
        globs: Iterable[str] = (raw_glob,)
    elif isinstance(raw_glob, list):
        globs = (str(item) for item in raw_glob)
    else:
        vendor = str(cfg.get("vendor") or "").lower()
        prefix = "sxh" if vendor in {"shuixianhua", "sxh"} else "jlj"
        globs = (f"data_{prefix}_*.zip",)
    compact = day_text.replace("-", "")
    rows: dict[str, Path] = {}
    for pattern in globs:
        for item in source_root.glob(pattern):
            name = item.name
            if item.is_file() and (day_text in name or compact in name):
                rows[os.path.normcase(str(item.resolve()))] = item.resolve()
    return [rows[key] for key in sorted(rows)]


def _zip_errors(path: Path, label: str) -> list[str]:
    reserved_windows_names = {
        "con",
        "prn",
        "aux",
        "nul",
        *(f"com{index}" for index in range(1, 10)),
        *(f"lpt{index}" for index in range(1, 10)),
    }
    try:
        with zipfile.ZipFile(path, "r") as archive:
            entries = [item for item in archive.infolist() if not item.is_dir()]
            if not entries:
                return [f"{label} 的 ZIP 不含文件：{path}"]
            seen: set[str] = set()
            for item in entries:
                normalized = item.filename.replace("\\", "/")
                pure = PurePosixPath(normalized)
                raw_parts = normalized.split("/")
                unsafe_windows_part = any(
                    not part
                    or part in {".", ".."}
                    or part.endswith((" ", "."))
                    or Path(part).stem.casefold() in reserved_windows_names
                    for part in raw_parts
                )
                if (
                    not normalized
                    or normalized.startswith("/")
                    or pure.is_absolute()
                    or ":" in normalized
                    or any(ord(character) < 32 for character in normalized)
                    or unsafe_windows_part
                    or ".." in pure.parts
                    or item.file_size < 0
                    or item.CRC < 0
                ):
                    return [f"{label} 的 ZIP 含不安全或无效条目：{item.filename}"]
                key = normalized.casefold()
                if key in seen:
                    return [f"{label} 的 ZIP 含 Windows 下重名条目：{item.filename}"]
                seen.add(key)
    except (OSError, zipfile.BadZipFile, RuntimeError) as exc:
        return [f"{label} 的 ZIP 无法读取：{path}（{exc}）"]
    return []
