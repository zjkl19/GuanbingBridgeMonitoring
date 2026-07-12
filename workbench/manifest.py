from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any


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

    @property
    def failed_modules(self) -> tuple[ModuleResult, ...]:
        return tuple(item for item in self.modules if item.status.lower() not in {"ok", "success", "completed"})

    def missing_selected_modules(self, selected_modules: list[str] | tuple[str, ...]) -> tuple[str, ...]:
        recorded = {item.key for item in self.modules if item.key}
        return tuple(key for key in selected_modules if key not in recorded)


def find_latest_manifest(data_root: Path) -> Path | None:
    candidates = list((data_root / "run_logs").glob("analysis_manifest_*.json")) if (data_root / "run_logs").is_dir() else []
    return max(candidates, key=lambda path: path.stat().st_mtime) if candidates else None


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
    )


def manifest_context_issues(summary: ManifestSummary, *, bridge_id: str, data_root: Path, start_date: str, end_date: str) -> list[str]:
    issues: list[str] = []
    if summary.bridge_id and summary.bridge_id != bridge_id:
        issues.append(f"bridge mismatch: manifest={summary.bridge_id}, job={bridge_id}")
    if summary.data_root:
        try:
            manifest_root = Path(summary.data_root).resolve()
            job_root = data_root.resolve()
            if os.path.normcase(str(manifest_root)) != os.path.normcase(str(job_root)):
                issues.append(f"data root mismatch: manifest={manifest_root}, job={job_root}")
        except OSError:
            issues.append(f"manifest data root is invalid: {summary.data_root}")
    if summary.start_date and summary.start_date != start_date:
        issues.append(f"start date mismatch: manifest={summary.start_date}, job={start_date}")
    if summary.end_date and summary.end_date != end_date:
        issues.append(f"end date mismatch: manifest={summary.end_date}, job={end_date}")
    return issues
