from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True)
class ModuleResult:
    key: str
    label: str
    status: str
    elapsed_sec: str
    stats_path: str
    message: str


@dataclass(frozen=True)
class ManifestSummary:
    path: Path
    status: str
    artifact_count: int
    modules: tuple[ModuleResult, ...]
    bridge_id: str = ""
    data_root: str = ""
    start_date: str = ""
    end_date: str = ""
    config_path: str = ""
    config_sha256: str = ""

    @property
    def failed_modules(self) -> tuple[ModuleResult, ...]:
        return tuple(item for item in self.modules if item.status.lower() not in {"ok", "success", "completed"})

    def missing_selected_modules(self, selected_modules: list[str] | tuple[str, ...]) -> tuple[str, ...]:
        recorded = {item.key for item in self.modules if item.key}
        return tuple(key for key in selected_modules if key not in recorded)


def find_latest_manifest(
    data_root: Path,
    *,
    bridge_id: str = "",
    start_date: str = "",
    end_date: str = "",
    config_path: Path | None = None,
    config_sha256: str = "",
    selected_modules: Iterable[str] = (),
    successful_only: bool = False,
) -> Path | None:
    """Return the newest manifest compatible with the current task.

    With no compatibility arguments this preserves the legacy behaviour and
    simply returns the newest file. GUI callers provide the current bridge,
    date range and selected modules so that a newer one-module repair run does
    not hide an older complete run for the same task.
    """

    logs_dir = data_root / "run_logs"
    candidates = list(logs_dir.glob("analysis_manifest_*.json")) if logs_dir.is_dir() else []
    candidates.sort(key=lambda path: path.stat().st_mtime, reverse=True)
    selected = tuple(dict.fromkeys(str(key).strip() for key in selected_modules if str(key).strip()))
    filtered = bool(
        bridge_id
        or start_date
        or end_date
        or config_path
        or config_sha256
        or selected
        or successful_only
    )
    if not filtered:
        return candidates[0] if candidates else None

    normalized_root = os.path.normcase(str(data_root.resolve()))
    for path in candidates:
        try:
            summary = load_manifest_summary(path)
        except (OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError):
            continue
        if bridge_id and summary.bridge_id != bridge_id:
            continue
        if not summary.data_root:
            continue
        try:
            if os.path.normcase(str(Path(summary.data_root).resolve())) != normalized_root:
                continue
        except OSError:
            continue
        if start_date and summary.start_date != start_date:
            continue
        if end_date and summary.end_date != end_date:
            continue
        if config_path is not None:
            if not summary.config_path:
                continue
            try:
                expected_config = os.path.normcase(str(config_path.expanduser().resolve()))
                manifest_config = os.path.normcase(
                    str(Path(summary.config_path).expanduser().resolve())
                )
            except OSError:
                continue
            if manifest_config != expected_config:
                continue
        if config_sha256 and summary.config_sha256.lower() != config_sha256.lower():
            continue
        if selected and summary.missing_selected_modules(selected):
            continue
        if successful_only and (
            summary.status.lower() not in {"ok", "success", "completed"}
            or summary.failed_modules
        ):
            continue
        return path
    return None


def load_manifest_summary(path: Path) -> ManifestSummary:
    payload: dict[str, Any] = json.loads(path.read_text(encoding="utf-8-sig"))
    records = payload.get("module_results") or payload.get("module_logs") or []
    modules: list[ModuleResult] = []
    for raw in records:
        if not isinstance(raw, dict):
            continue
        elapsed = raw.get("elapsed_sec", raw.get("elapsed", ""))
        modules.append(ModuleResult(
            key=str(raw.get("key") or raw.get("module") or ""),
            label=str(raw.get("label") or raw.get("key") or raw.get("module") or "unknown"),
            status=str(raw.get("status") or "unknown"),
            elapsed_sec=str(elapsed if elapsed is not None else ""),
            stats_path=str(raw.get("stats_path") or ""),
            message=str(raw.get("message") or raw.get("error_type") or ""),
        ))
    run_request = payload.get("run_request") if isinstance(payload.get("run_request"), dict) else {}
    bridge_profile = payload.get("bridge_profile") if isinstance(payload.get("bridge_profile"), dict) else {}
    request_profile = run_request.get("bridge_profile") if isinstance(run_request.get("bridge_profile"), dict) else {}
    return ManifestSummary(
        path=path.resolve(),
        status=str(payload.get("status") or "unknown"),
        artifact_count=int(payload.get("artifact_count") or 0),
        modules=tuple(modules),
        bridge_id=str(bridge_profile.get("bridge_id") or request_profile.get("bridge_id") or ""),
        data_root=str(run_request.get("data_root") or payload.get("root") or payload.get("data_root") or ""),
        start_date=str(run_request.get("start_date") or payload.get("start_date") or ""),
        end_date=str(run_request.get("end_date") or payload.get("end_date") or ""),
        config_path=str(run_request.get("config_path") or payload.get("config_path") or ""),
        config_sha256=str(
            run_request.get("config_sha256") or payload.get("config_sha256") or ""
        ),
    )


def manifest_context_issues(
    summary: ManifestSummary,
    *,
    bridge_id: str,
    data_root: Path,
    start_date: str,
    end_date: str,
    config_path: Path | None = None,
    config_sha256: str = "",
) -> list[str]:
    issues: list[str] = []
    if bridge_id and summary.bridge_id != bridge_id:
        issues.append(f"桥梁不一致：分析结果={summary.bridge_id or '缺失'}，当前任务={bridge_id}")
    if not summary.data_root:
        issues.append("分析结果缺少数据目录，无法证明与当前任务一致")
    else:
        try:
            manifest_root = Path(summary.data_root).resolve()
            job_root = data_root.resolve()
            if os.path.normcase(str(manifest_root)) != os.path.normcase(str(job_root)):
                issues.append(f"数据目录不一致：分析结果={manifest_root}，当前任务={job_root}")
        except OSError:
            issues.append(f"分析结果中的数据目录无效：{summary.data_root}")
    if start_date and summary.start_date != start_date:
        issues.append(f"开始日期不一致：分析结果={summary.start_date or '缺失'}，当前任务={start_date}")
    if end_date and summary.end_date != end_date:
        issues.append(f"结束日期不一致：分析结果={summary.end_date or '缺失'}，当前任务={end_date}")
    if config_path is not None:
        if not summary.config_path:
            issues.append("分析结果缺少配置文件路径，无法证明配置一致")
        else:
            try:
                manifest_config = Path(summary.config_path).expanduser().resolve()
                job_config = config_path.expanduser().resolve()
                if os.path.normcase(str(manifest_config)) != os.path.normcase(str(job_config)):
                    issues.append(
                        f"配置文件不一致：分析结果={manifest_config}，当前任务={job_config}"
                    )
            except OSError:
                issues.append(f"分析结果中的配置文件路径无效：{summary.config_path}")
    if config_sha256 and summary.config_sha256.lower() != config_sha256.lower():
        issues.append(
            "配置版本不一致：分析结果="
            f"{summary.config_sha256 or '缺失'}，当前任务={config_sha256}"
        )
    return issues
