from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from .manual_threshold import select_preview_series
from .threshold_curve import (
    ThresholdCurveError,
    load_threshold_curve_preview,
    load_threshold_curve_record,
)


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
    source_kind: str = ""


def find_matching_threshold_preview(query: ThresholdPreviewQuery) -> ThresholdPreviewMatch:
    """Find the newest preview that is pinned to the current task and point."""

    root = query.data_root.expanduser().resolve(strict=False)
    logs = root / "run_logs"
    if not root.is_dir():
        return ThresholdPreviewMatch(None, f"当前数据目录不存在：{root}")
    if not logs.is_dir():
        return ThresholdPreviewMatch(
            None,
            "当前数据目录还没有曲线记录。请生成当前测点曲线后重试。",
        )
    checked = 0
    rejected_reasons: list[str] = []

    # A completed threshold_curve_record is the canonical new history entry.
    record_candidates = list(logs.rglob("threshold_curve_record*.json"))
    record_candidates.sort(
        key=lambda path: path.stat().st_mtime_ns if path.is_file() else 0,
        reverse=True,
    )
    referenced_previews: set[Path] = set()
    record_task_dirs = {path.parent.resolve() for path in record_candidates}
    for path in record_candidates:
        checked += 1
        try:
            record = load_threshold_curve_record(path)
            referenced_previews.add(record.preview_path.resolve())
            previews = load_threshold_curve_preview(
                record.preview_path,
                expected_config_sha256=query.config_sha256,
                expected_bridge_id=query.bridge_id,
                expected_data_root=root,
                expected_start_date=query.start_date,
                expected_end_date=query.end_date,
                expected_module_key=query.module_key,
                expected_point_ids=query.point_ids,
            )
            select_preview_series(
                previews,
                module_key=query.module_key,
                point_ids=query.point_ids,
            )
        except (ThresholdCurveError, ValueError) as exc:
            rejected_reasons.append(str(exc))
            continue
        return ThresholdPreviewMatch(
            record.preview_path.resolve(),
            f"已自动匹配当前任务和测点的独立曲线记录：{record.preview_path.resolve()}",
            checked,
            "threshold_curve_record",
        )

    # Accept a fully written preview before its small history record appears.
    preview_candidates = [
        path
        for path in logs.rglob("threshold_curve_preview*.json")
        if path.resolve() not in referenced_previews
        and path.parent.resolve() not in record_task_dirs
    ]
    preview_candidates.sort(
        key=lambda path: path.stat().st_mtime_ns if path.is_file() else 0,
        reverse=True,
    )
    for path in preview_candidates:
        checked += 1
        try:
            previews = load_threshold_curve_preview(
                path,
                expected_config_sha256=query.config_sha256,
                expected_bridge_id=query.bridge_id,
                expected_data_root=root,
                expected_start_date=query.start_date,
                expected_end_date=query.end_date,
                expected_module_key=query.module_key,
                expected_point_ids=query.point_ids,
            )
            select_preview_series(
                previews,
                module_key=query.module_key,
                point_ids=query.point_ids,
            )
        except (ThresholdCurveError, ValueError) as exc:
            rejected_reasons.append(str(exc))
            continue
        return ThresholdPreviewMatch(
            path.resolve(),
            f"已自动匹配当前任务和测点的独立曲线预览：{path.resolve()}",
            checked,
            "threshold_curve_preview",
        )

    candidate_count = len(record_candidates) + len(preview_candidates)
    if candidate_count:
        unique_reasons = tuple(dict.fromkeys(rejected_reasons))
        reason_text = "；".join(unique_reasons[:3])
        detail = f"检查了 {checked} 个新版独立曲线记录，但没有匹配当前任务。"
        if reason_text:
            detail += f" 不匹配原因：{reason_text}。"
    else:
        detail = "当前数据目录尚未生成曲线预览。"
    return ThresholdPreviewMatch(
        None,
        detail + " 请生成当前模块和测点的新版独立曲线，完成后重新打开本工具。",
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
