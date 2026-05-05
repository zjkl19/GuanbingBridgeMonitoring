from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def find_latest_analysis_manifest(result_root: Path | str | None) -> Path | None:
    """Return the newest MATLAB analysis manifest under result_root/run_logs."""
    if result_root is None:
        return None
    root = Path(result_root)
    candidates: list[Path] = []
    search_roots = [root / "run_logs", root]
    for folder in search_roots:
        if not folder.exists() or not folder.is_dir():
            continue
        candidates.extend(folder.glob("analysis_manifest_*.json"))
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def load_analysis_manifest(path: Path | str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    p = Path(path)
    if not p.exists():
        return None
    return json.loads(p.read_text(encoding="utf-8"))


def load_latest_analysis_manifest(result_root: Path | str | None) -> tuple[Path | None, dict[str, Any] | None]:
    path = find_latest_analysis_manifest(result_root)
    return path, load_analysis_manifest(path)


def _module_label(item: dict[str, Any]) -> str:
    return str(item.get("label") or item.get("key") or item.get("module") or "unknown")


def manifest_missing_modules(manifest: dict[str, Any] | None) -> list[dict[str, str]]:
    """Normalize missing/failed module information from the MATLAB run manifest."""
    if not isinstance(manifest, dict):
        return []

    missing: list[dict[str, str]] = []
    seen: set[tuple[str, str]] = set()

    for item in manifest.get("module_preflight", []) or []:
        if not isinstance(item, dict):
            continue
        status = str(item.get("status") or "").lower()
        exists = item.get("exists")
        if status == "missing" or exists is False:
            key = str(item.get("key") or _module_label(item))
            rec = {
                "key": key,
                "label": _module_label(item),
                "status": "missing",
                "message": str(item.get("message") or "stats file missing"),
                "stats_path": str(item.get("stats_path") or ""),
            }
            marker = (rec["key"], rec["status"])
            if marker not in seen:
                seen.add(marker)
                missing.append(rec)

    module_records = manifest.get("module_results") or manifest.get("module_logs") or []
    for item in module_records:
        if not isinstance(item, dict):
            continue
        status = str(item.get("status") or "").lower()
        if status in {"fail", "failed", "skip", "missing"}:
            key = str(item.get("key") or _module_label(item))
            rec = {
                "key": key,
                "label": _module_label(item),
                "status": status,
                "message": str(item.get("message") or ""),
                "error_type": str(item.get("error_type") or ""),
                "stats_path": str(item.get("stats_path") or ""),
            }
            marker = (rec["key"], rec["status"])
            if marker not in seen:
                seen.add(marker)
                missing.append(rec)

    return missing


def analysis_manifest_context(result_root: Path | str | None) -> dict[str, Any]:
    path, manifest = load_latest_analysis_manifest(result_root)
    return {
        "path": str(path) if path is not None else "",
        "available": manifest is not None,
        "schema_version": manifest.get("schema_version") if isinstance(manifest, dict) else None,
        "status": manifest.get("status") if isinstance(manifest, dict) else "",
        "bridge_profile": manifest.get("bridge_profile", {}) if isinstance(manifest, dict) else {},
        "data_layout": manifest.get("data_layout", {}) if isinstance(manifest, dict) else {},
        "missing_modules": manifest_missing_modules(manifest),
        "manifest": manifest,
    }


def missing_module_summary_items(context: dict[str, Any] | None) -> list[str]:
    if not isinstance(context, dict):
        return []
    items: list[str] = []
    for item in context.get("missing_modules", []) or []:
        if not isinstance(item, dict):
            continue
        label = item.get("label") or item.get("key") or "unknown"
        status = item.get("status") or "missing"
        message = item.get("message") or item.get("error_type") or ""
        if message:
            items.append(f"analysis:{label}:{status}:{message}")
        else:
            items.append(f"analysis:{label}:{status}")
    return items
