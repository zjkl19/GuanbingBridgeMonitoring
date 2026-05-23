from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def find_latest_reporting_contract(result_root: Path | str | None) -> Path | None:
    if result_root is None:
        return None
    root = Path(result_root)
    candidates: list[Path] = []
    for folder in (root / "run_logs", root):
        if folder.exists():
            candidates.extend(folder.glob("analysis_reporting_contract_*.json"))
    candidates = [path for path in candidates if path.is_file()]
    if not candidates:
        return None
    return max(candidates, key=lambda path: path.stat().st_mtime)


def load_reporting_contract(path: Path | str | None) -> dict[str, Any] | None:
    if path is None:
        return None
    p = Path(path)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def contract_from_analysis_manifest(manifest: dict[str, Any] | None) -> dict[str, Any] | None:
    if not isinstance(manifest, dict):
        return None
    run_preflight = manifest.get("run_preflight")
    if isinstance(run_preflight, dict) and isinstance(run_preflight.get("reporting_contract"), dict):
        return run_preflight["reporting_contract"]
    if isinstance(manifest.get("reporting_contract"), dict):
        return manifest["reporting_contract"]
    return None


def reporting_contract_context(result_root: Path | str | None, analysis_context: dict[str, Any] | None = None) -> dict[str, Any]:
    analysis_context = analysis_context or {}
    contract = contract_from_analysis_manifest(analysis_context.get("manifest") if isinstance(analysis_context, dict) else None)
    source = "analysis_manifest" if contract is not None else ""
    path = ""
    if contract is None:
        contract_path = find_latest_reporting_contract(result_root)
        contract = load_reporting_contract(contract_path)
        if contract is not None and contract_path is not None:
            source = "contract_file"
            path = str(contract_path)

    summary = contract.get("summary", {}) if isinstance(contract, dict) else {}
    modules = contract.get("modules", []) if isinstance(contract, dict) else []
    return {
        "available": isinstance(contract, dict),
        "path": path,
        "source": source,
        "schema_version": contract.get("schema_version") if isinstance(contract, dict) else None,
        "summary": summary if isinstance(summary, dict) else {},
        "module_count": len(modules) if isinstance(modules, list) else 0,
        "contract": contract if isinstance(contract, dict) else None,
    }


def module_contracts(context: dict[str, Any]) -> list[dict[str, Any]]:
    contract = context.get("contract") if isinstance(context, dict) else None
    modules = contract.get("modules") if isinstance(contract, dict) else None
    return [item for item in modules if isinstance(item, dict)] if isinstance(modules, list) else []


def output_dir_records_by_module(context: dict[str, Any], module_key: str) -> list[dict[str, Any]]:
    module_key = str(module_key)
    for module in module_contracts(context):
        if str(module.get("key")) != module_key:
            continue
        records = module.get("output_dir_records")
        if isinstance(records, list):
            return [record for record in records if isinstance(record, dict)]
        dirs = module.get("output_dirs")
        if isinstance(dirs, list):
            return [{"field": "", "dir": str(path), "role": ""} for path in dirs if path]
        return []
    return []


def output_dirs_by_module(context: dict[str, Any], module_key: str, *, role: str | None = None) -> list[str]:
    records = output_dir_records_by_module(context, module_key)
    out: list[str] = []
    for record in records:
        if role is not None and record.get("role") != role:
            continue
        value = record.get("dir")
        if value:
            out.append(str(value))
    return list(dict.fromkeys(out))


def contract_precheck_warnings(context: dict[str, Any]) -> list[str]:
    if not context.get("available"):
        return ["analysis reporting contract not found; report generator will use legacy config/stats/image lookup"]
    warnings: list[str] = []
    summary = context.get("summary") or {}
    module_count = int(summary.get("module_count") or context.get("module_count") or 0)
    if module_count <= 0:
        warnings.append("analysis reporting contract contains no reportable modules")
    return warnings
