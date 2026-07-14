from __future__ import annotations

import argparse
import json
import sys
import time
import traceback
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "reporting"))

from report_job import ReportJobRequest, execute_report_job
from report_job_cli import request_from_context
from workbench.manifest import load_manifest_summary
from workbench.models import JobContext, file_sha256
from workbench.profiles import WorkbenchProfile, load_profiles, profile_by_id
from workbench.report_gate import inspect_report_gate


COPIED_MANIFESTS = {
    "hongtang": ROOT / "output" / "doc" / "zhishan_april_hongtang_q2_v1727_20260711" / "hongtang_analysis_manifest.json",
    "zhishan": ROOT / "output" / "doc" / "zhishan_april_hongtang_q2_v1727_20260711" / "zhishan_analysis_manifest.json",
}


def _load_json(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return payload


def _manifest_candidates(profile: WorkbenchProfile, data_root: Path) -> list[Path]:
    candidates = list((data_root / "run_logs").glob("analysis_manifest_*.json"))
    copied = COPIED_MANIFESTS.get(profile.bridge_id)
    if copied and copied.is_file():
        candidates.append(copied)
    unique = {str(path.resolve()).casefold(): path.resolve() for path in candidates if path.is_file()}
    return sorted(unique.values(), key=lambda path: path.stat().st_mtime, reverse=True)


def _audit_candidate(
    profile: WorkbenchProfile,
    data_root: Path,
    output_dir: Path,
    manifest_path: Path,
) -> tuple[JobContext | None, dict[str, Any]]:
    try:
        summary = load_manifest_summary(manifest_path)
        selected = [item.key for item in summary.modules if item.key and item.key != "offset_correction_report"]
        context = JobContext.create(
            project_root=ROOT,
            bridge_id=profile.bridge_id,
            bridge_name=profile.bridge_name,
            data_root=data_root,
            start_date=profile.default_start_date,
            end_date=profile.default_end_date,
            config_path=profile.config_path(ROOT),
            selected_modules=selected,
            options={},
            report_type=profile.report_gui_type,
            template_path=profile.template_path(ROOT),
            output_dir=output_dir,
            period_label=profile.default_period_label,
            monitoring_range=profile.default_monitoring_range,
            report_date=profile.default_report_date,
        )
        context.analysis.state = "completed"
        context.analysis.manifest_path = str(manifest_path)
        context.analysis.manifest_sha256 = file_sha256(manifest_path)
        context.report.plots_approved = True
        audit = inspect_report_gate(context)
        return context, {
            "path": str(manifest_path),
            "status": summary.status,
            "module_count": len(summary.modules),
            "selected_modules": selected,
            "provenance_count": len(audit.provenance.rows) if audit.provenance else 0,
            "provenance_failed_count": audit.provenance.failed_count if audit.provenance else 0,
            "eligible": audit.passed,
            "issues": list(audit.issues),
        }
    except Exception as exc:  # noqa: BLE001
        return None, {"path": str(manifest_path), "eligible": False, "issues": [str(exc)]}


def _historical_by_bridge(matrix_path: Path) -> dict[str, dict[str, Any]]:
    if not matrix_path.is_file():
        return {}
    return {
        str(record.get("bridge_id")): record
        for record in _load_json(matrix_path).get("records", [])
        if isinstance(record, dict)
    }


def _fresh_record(result: Any) -> dict[str, Any]:
    qc = result.qc
    return {
        "report_path": str(result.report_path),
        "manifest_path": str(result.manifest_path or ""),
        "qc_status": qc.get("status"),
        "docx_bytes": qc.get("docx", {}).get("size_bytes", 0),
        "docx_sha256": qc.get("docx", {}).get("sha256", ""),
        "media_count": qc.get("docx", {}).get("media_count", 0),
        "page_count": qc.get("visual", {}).get("page_count", 0),
        "blank_pages": qc.get("visual", {}).get("blank_pages", []),
        "edge_touch_pages": qc.get("visual", {}).get("edge_touch_pages", []),
        "contact_sheet": qc.get("visual", {}).get("contact_sheet", ""),
        "report_manifest_status": qc.get("manifest", {}).get("status", ""),
        "report_manifest_missing_count": qc.get("manifest", {}).get("missing_count", 0),
        "report_manifest_warning_count": qc.get("manifest", {}).get("warning_count", 0),
    }


def _comparison(fresh: dict[str, Any], historical: dict[str, Any] | None) -> dict[str, Any]:
    if not historical:
        return {"historical_available": False}
    visual = historical.get("visual") if isinstance(historical.get("visual"), dict) else {}
    package = historical.get("package") if isinstance(historical.get("package"), dict) else {}
    historical_pages = int(visual.get("page_count") or 0)
    historical_media = int(package.get("media_count") or 0)
    return {
        "historical_available": True,
        "historical_report_path": historical.get("docx_path", ""),
        "historical_status": historical.get("status", ""),
        "historical_page_count": historical_pages,
        "historical_media_count": historical_media,
        "page_count_delta": int(fresh.get("page_count") or 0) - historical_pages,
        "media_count_delta": int(fresh.get("media_count") or 0) - historical_media,
        "historical_contact_sheet": visual.get("contact_sheet", ""),
    }


def _build_request(profile: WorkbenchProfile, data_root: Path, output_dir: Path) -> ReportJobRequest:
    return ReportJobRequest(
        report_type=profile.report_gui_type,
        template=profile.template_path(ROOT),
        config_path=profile.config_path(ROOT),
        result_root=data_root,
        analysis_root=ROOT,
        output_dir=output_dir,
        period_label=profile.default_period_label,
        monitoring_range=profile.default_monitoring_range,
        report_date=profile.default_report_date,
        start_date=profile.default_start_date,
        end_date=profile.default_end_date,
        wim_root=(data_root / "WIM" / "results" / "hongtang" if profile.bridge_id == "hongtang" else None),
    )


def _console_progress(bridge_id: str, stage: str, fraction: float) -> None:
    try:
        print(f"{bridge_id}: {stage} {fraction:.0%}", flush=True)
    except OSError:
        # The integration build must not be reclassified as failed merely because
        # a CI/desktop monitor detached from its stdout pipe during a long render.
        pass


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Audit embedded-report eligibility and optionally run isolated generator-only comparisons."
    )
    parser.add_argument("--profile", action="append", dest="profiles")
    parser.add_argument("--generate-fallback", action="store_true")
    parser.add_argument(
        "--output-root", type=Path,
        default=ROOT / "tmp" / "docs" / "fresh_report_profile_validation",
    )
    parser.add_argument(
        "--historical-matrix", type=Path,
        default=ROOT / "tmp" / "docs" / "workbench_report_visual_samples" / "sample_matrix.json",
    )
    args = parser.parse_args(argv)
    profiles = [profile for profile in load_profiles(ROOT) if profile.report_gui_type]
    requested = set(args.profiles or [profile.bridge_id for profile in profiles])
    unknown = requested - {profile.bridge_id for profile in profiles}
    if unknown:
        parser.error("unknown report profile(s): " + ", ".join(sorted(unknown)))
    output_root = args.output_root.expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    historical = _historical_by_bridge(args.historical_matrix.expanduser().resolve())
    records: list[dict[str, Any]] = []
    for profile in profiles:
        if profile.bridge_id not in requested:
            continue
        started = time.perf_counter()
        data_root = Path(profile.default_data_root).expanduser().resolve()
        output_dir = output_root / profile.bridge_id
        output_dir.mkdir(parents=True, exist_ok=True)
        candidate_records: list[dict[str, Any]] = []
        approved_context: JobContext | None = None
        if data_root.is_dir():
            for candidate in _manifest_candidates(profile, data_root):
                context, audit = _audit_candidate(profile, data_root, output_dir, candidate)
                candidate_records.append(audit)
                if approved_context is None and audit.get("eligible"):
                    approved_context = context
        record: dict[str, Any] = {
            "bridge_id": profile.bridge_id,
            "data_root": str(data_root),
            "data_root_exists": data_root.is_dir(),
            "template_path": str(profile.template_path(ROOT)),
            "template_exists": profile.template_path(ROOT).is_file(),
            "manifest_candidates": candidate_records,
            "embedded_eligible": approved_context is not None,
            "generation_mode": "not_run",
        }
        if args.generate_fallback and data_root.is_dir():
            try:
                if approved_context is not None:
                    context_path = approved_context.write(output_dir / "job_context.json")
                    request = request_from_context(context_path)
                    record["generation_mode"] = "embedded_gate_source"
                else:
                    # This mode deliberately exercises only the shared generator/QC. It never
                    # claims embedded eligibility when formal provenance is unavailable.
                    request = _build_request(profile, data_root, output_dir)
                    record["generation_mode"] = "generator_only_fallback"
                result = execute_report_job(
                    request,
                    lambda stage, fraction, _message: _console_progress(
                        profile.bridge_id, stage, fraction
                    ),
                )
                fresh = _fresh_record(result)
                record["fresh"] = fresh
                record["comparison"] = _comparison(fresh, historical.get(profile.bridge_id))
            except Exception as exc:  # noqa: BLE001
                record["generation_error"] = str(exc)
                record["generation_traceback"] = traceback.format_exc()
        records.append(record)
        record["elapsed_sec"] = round(time.perf_counter() - started, 3)
        (output_root / "fresh_report_profile_matrix.json").write_text(
            json.dumps({"schema_version": 1, "records": records}, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    payload = {
        "schema_version": 1,
        "profile_count": len(records),
        "embedded_eligible_count": sum(bool(record.get("embedded_eligible")) for record in records),
        "generated_count": sum("fresh" in record for record in records),
        "failed_generation_count": sum("generation_error" in record for record in records),
        "records": records,
    }
    result_path = output_root / "fresh_report_profile_matrix.json"
    result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(result_path)
    return 1 if payload["failed_generation_count"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
