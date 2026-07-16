from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .auto_threshold import AutoThresholdError, load_preview_artifact
from .manual_threshold import select_preview_series


@dataclass(frozen=True)
class ThresholdPreviewQuery:
    bridge_id: str
    data_root: Path
    start_date: str
    end_date: str
    config_sha256: str
    module_key: str
    point_ids: tuple[str, ...]


@dataclass(frozen=True)
class ThresholdPreviewMatch:
    path: Path | None
    message: str
    checked_count: int = 0


def find_matching_threshold_preview(query: ThresholdPreviewQuery) -> ThresholdPreviewMatch:
    """Find the newest preview that is pinned to the current task and point."""

    root = query.data_root.expanduser().resolve(strict=False)
    logs = root / "run_logs"
    if not root.is_dir():
        return ThresholdPreviewMatch(None, f"当前数据目录不存在：{root}")
    if not logs.is_dir():
        return ThresholdPreviewMatch(
            None,
            "当前数据目录还没有任务记录。请先到“自动清洗建议”页为当前日期范围生成建议。",
        )
    candidates = list(logs.rglob("auto_threshold_preview*.json"))
    candidates.sort(
        key=lambda path: path.stat().st_mtime_ns if path.is_file() else 0,
        reverse=True,
    )
    checked = 0
    for path in candidates:
        checked += 1
        try:
            previews = load_preview_artifact(
                path,
                expected_config_sha256=query.config_sha256,
                expected_bridge_id=query.bridge_id,
                expected_data_root=root,
                expected_start_date=query.start_date,
                expected_end_date=query.end_date,
            )
            select_preview_series(
                previews,
                module_key=query.module_key,
                point_ids=query.point_ids,
            )
        except (AutoThresholdError, ValueError):
            continue
        return ThresholdPreviewMatch(
            path.resolve(),
            f"已自动匹配当前任务和测点的曲线预览：{path.resolve()}",
            checked,
        )
    if candidates:
        detail = (
            f"检查了 {checked} 个历史预览，但桥梁、数据目录、日期、配置版本或测点均未完全匹配。"
        )
    else:
        detail = "当前数据目录尚未生成曲线预览。"
    return ThresholdPreviewMatch(
        None,
        detail + " 请到“自动清洗建议”页按当前任务生成建议，完成后重新打开本工具。",
        checked,
    )


def preview_query(
    *,
    bridge_id: str,
    data_root: str | Path,
    start_date: str,
    end_date: str,
    config_sha256: str,
    module_key: str,
    point_ids: Iterable[str],
) -> ThresholdPreviewQuery:
    return ThresholdPreviewQuery(
        str(bridge_id or "").strip(),
        Path(data_root).expanduser().resolve(strict=False),
        str(start_date or "").strip(),
        str(end_date or "").strip(),
        str(config_sha256 or "").strip(),
        str(module_key or "").strip(),
        tuple(dict.fromkeys(str(value or "").strip() for value in point_ids if str(value or "").strip())),
    )
