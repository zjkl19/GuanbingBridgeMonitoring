from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Any

from image_block_utils import count_docx_images
from report_context import ReportBuildContext
from reporting_contract import contract_precheck_warnings


SCHEMA_VERSION = 1


def normalize_missing(items: list[Any] | None) -> list[dict[str, str]]:
    normalized: list[dict[str, str]] = []
    for item in items or []:
        if isinstance(item, dict):
            category = str(item.get("category") or item.get("severity") or "missing")
            label = str(item.get("item") or item.get("label") or item.get("module") or item.get("path") or "")
            detail = str(item.get("detail") or item.get("message") or item.get("source") or "")
        else:
            text = str(item)
            category = "warning" if text.startswith("warning:") else "missing"
            label = text.removeprefix("warning:")
            detail = ""
        normalized.append({"category": category, "label": label, "detail": detail})
    return normalized


def build_report_manifest(
    *,
    context: ReportBuildContext,
    report_type: str,
    output_docx: Path,
    timestamp: str,
    legacy_manifest: dict[str, Any] | None = None,
    missing: list[Any] | None = None,
    warnings: list[str] | None = None,
    extra: dict[str, Any] | None = None,
) -> dict[str, Any]:
    missing_items = normalize_missing(missing)
    warnings = warnings or []
    analysis_context = context.analysis_context()
    reporting_contract = context.reporting_contract_context(analysis_context)
    warnings = [*warnings, *contract_precheck_warnings(reporting_contract)]
    status = "warning" if missing_items or warnings else "ok"
    payload: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "manifest_type": "report_build",
        "report_type": report_type,
        "status": status,
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "timestamp": timestamp,
        "paths": context.to_manifest_paths(),
        "output_docx": str(output_docx),
        "output_docx_image_count": count_docx_images(output_docx),
        "analysis_run_manifest": analysis_context,
        "analysis_reporting_contract": reporting_contract,
        "missing_items": missing_items,
        "missing_count": len(missing_items),
        "warnings": warnings,
    }
    if legacy_manifest is not None:
        payload["legacy_manifest"] = legacy_manifest
    if extra:
        payload.update(extra)
    return payload


def write_report_build_manifest(
    *,
    context: ReportBuildContext,
    report_type: str,
    output_docx: Path,
    timestamp: str,
    legacy_manifest: dict[str, Any] | None = None,
    missing: list[Any] | None = None,
    warnings: list[str] | None = None,
    extra: dict[str, Any] | None = None,
    filename_prefix: str = "report_build_manifest",
) -> Path:
    payload = build_report_manifest(
        context=context,
        report_type=report_type,
        output_docx=output_docx,
        timestamp=timestamp,
        legacy_manifest=legacy_manifest,
        missing=missing,
        warnings=warnings,
        extra=extra,
    )
    path = context.output_dir / f"{filename_prefix}_{timestamp}.json"
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")
    return path


def find_latest_report_build_manifest(output_dir: Path | str | None) -> Path | None:
    if output_dir is None:
        return None
    root = Path(output_dir)
    if not root.exists():
        return None
    candidates = list(root.glob("*report_build_manifest_*.json")) + list(root.glob("*_manifest_*.json"))
    candidates = [path for path in candidates if path.is_file()]
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)
