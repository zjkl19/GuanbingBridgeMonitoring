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
        "run_request": manifest.get("run_request", {}) if isinstance(manifest, dict) else {},
        "run_preflight": manifest.get("run_preflight", {}) if isinstance(manifest, dict) else {},
        "missing_modules": manifest_missing_modules(manifest),
        "module_artifacts": manifest.get("module_artifacts", []) if isinstance(manifest, dict) else [],
        "artifact_count": manifest.get("artifact_count", 0) if isinstance(manifest, dict) else 0,
        "manifest": manifest,
    }


def manifest_module_records(manifest: dict[str, Any] | None) -> list[dict[str, Any]]:
    if not isinstance(manifest, dict):
        return []
    records = manifest.get("module_results") or manifest.get("module_logs") or []
    return [item for item in records if isinstance(item, dict)]


def manifest_stats_path(manifest: dict[str, Any] | None, key: str, filename: str | None = None) -> Path | None:
    """Return a stats path from manifest v1/v2 module records when available."""
    key = str(key)
    filename = str(filename) if filename else None
    for item in manifest_module_records(manifest):
        if str(item.get("key") or "") != key:
            continue
        stats_path = str(item.get("stats_path") or "")
        if stats_path:
            path = Path(stats_path)
            if path.exists() and (filename is None or path.name == filename):
                return path
        for artifact in item.get("artifacts") or []:
            if not isinstance(artifact, dict):
                continue
            if artifact.get("kind") != "stats":
                continue
            path = Path(str(artifact.get("path") or ""))
            if path.exists() and (filename is None or path.name == filename):
                return path
    return None


def manifest_artifact_paths(
    manifest: dict[str, Any] | None,
    key: str,
    *,
    kind: str | None = None,
    suffixes: tuple[str, ...] | None = None,
) -> list[Path]:
    """Return artifact paths for a module from manifest schema v2."""
    out: list[Path] = []
    key = str(key)
    suffixes_lc = tuple(s.lower() for s in suffixes) if suffixes else None
    for item in manifest_module_records(manifest):
        if str(item.get("key") or "") != key:
            continue
        for artifact in item.get("artifacts") or []:
            if not isinstance(artifact, dict):
                continue
            if kind and str(artifact.get("kind") or "") != kind:
                continue
            path = Path(str(artifact.get("path") or ""))
            if not path.exists():
                continue
            if suffixes_lc and path.suffix.lower() not in suffixes_lc:
                continue
            out.append(path)
    return out


def manifest_precheck_warnings(result_root: Path | str | None) -> list[str]:
    """Build concise report-generation warnings from the latest analysis manifest."""
    context = analysis_manifest_context(result_root)
    if not context["available"]:
        return ["analysis manifest not found; report generator will rely on stats/images only"]

    warnings: list[str] = []
    status = str(context.get("status") or "").lower()
    if status and status not in {"ok", "success", "completed"}:
        warnings.append(f"analysis manifest status is {status}")

    for item in context.get("missing_modules", []) or []:
        if not isinstance(item, dict):
            continue
        label = item.get("label") or item.get("key") or "unknown"
        msg = item.get("message") or item.get("error_type") or item.get("status") or ""
        warnings.append(f"module missing/failed: {label} {msg}".strip())

    manifest = context.get("manifest")
    if isinstance(manifest, dict):
        run_preflight = manifest.get("run_preflight")
        if isinstance(run_preflight, dict):
            for item in run_preflight.get("errors", []) or []:
                if item:
                    warnings.append(f"analysis preflight error: {item}")
            for item in run_preflight.get("warnings", []) or []:
                if item:
                    warnings.append(f"analysis preflight warning: {item}")
        for path in manifest.get("missing_expected_stats") or manifest.get("missing_stats_files") or []:
            if path:
                warnings.append(f"expected stats missing: {path}")
        for item in manifest.get("warnings", []) or []:
            if item:
                warnings.append(f"analysis warning: {item}")

    deduped: list[str] = []
    seen: set[str] = set()
    for item in warnings:
        if item not in seen:
            seen.add(item)
            deduped.append(item)
    return deduped


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
