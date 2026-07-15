from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable
from zipfile import BadZipFile, ZipFile

from build_guanbing_monthly_report import build_report as build_guanbing_monthly_report
from build_jlj_monthly_report import build_report as build_jlj_monthly_report
from build_monthly_report import build_report as build_hongtang_monthly_report
from build_period_report import build_period_report
from build_shuixianhua_monthly_report import build_report as build_shuixianhua_monthly_report
from build_zhishan_monthly_report import build_report as build_zhishan_monthly_report
from analysis_manifest import pinned_analysis_manifest_scope, pinned_derived_artifact_manifest_scope
from missing_summary import missing_summary_paths
from report_visual_qc import render_docx_visual_qc
from template_precheck import raise_for_template
from word_pdf_export import export_authoritative_word_pdf


REPORT_TYPE_NAMES = {
    "hongtang_monthly": "洪塘月报",
    "hongtang_period_wim": "洪塘周期报（含WIM）",
    "jlj_monthly": "九龙江月报",
    "guanbing_monthly": "管柄月报",
    "shuixianhua_monthly": "水仙花月报",
    "zhishan_monthly": "芝山月报",
}

# The period and Jiulongjiang builders already perform their own conditional
# prechecks because their required anchors depend on the generated section
# manifest.  These three legacy monthly builders did not, so the unified strict
# worker must fail before writing a report when their template contract is not
# satisfied.
STRICT_TEMPLATE_PRECHECK_KINDS = {
    "guanbing_monthly": "guanbing_monthly",
    "shuixianhua_monthly": "shuixianhua_monthly",
    "zhishan_monthly": "zhishan_monthly",
}
ProgressCallback = Callable[[str, float, str], None]


@dataclass(frozen=True)
class ReportJobRequest:
    report_type: str
    template: Path
    config_path: Path
    result_root: Path
    analysis_root: Path
    output_dir: Path
    period_label: str
    monitoring_range: str
    report_date: str
    start_date: str
    end_date: str
    wim_root: Path | None = None
    analysis_manifest_path: Path | None = None
    analysis_manifest_sha256: str = ""
    derived_artifact_manifest_path: Path | None = None
    derived_artifact_manifest_sha256: str = ""
    require_source_provenance: bool = False


@dataclass(frozen=True)
class ReportJobResult:
    manifest_path: Path | None
    report_path: Path
    pdf_path: Path | None
    missing: tuple[str, ...]
    summary_files: tuple[Path, ...]
    qc: dict[str, Any]


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _broken_reference_hits(text: str) -> list[str]:
    phrases = (
        "引用源未找到",
        "Error! Reference source not found",
        "Error: Reference source not found",
    )
    folded = str(text or "").casefold()
    return [phrase for phrase in phrases if phrase.casefold() in folded]


def _docx_qc(path: Path) -> dict[str, Any]:
    result: dict[str, Any] = {
        "path": str(path),
        "exists": path.is_file(),
        "size_bytes": path.stat().st_size if path.is_file() else 0,
        "sha256": _sha256(path) if path.is_file() else "",
        "zip_integrity": False,
        "document_xml": False,
        "media_count": 0,
    }
    if not path.is_file():
        return result
    try:
        with ZipFile(path) as archive:
            result["zip_integrity"] = archive.testzip() is None
            names = archive.namelist()
            result["document_xml"] = "word/document.xml" in names
            result["media_count"] = sum(
                name.startswith("word/media/") and not name.endswith("/") for name in names
            )
    except (BadZipFile, OSError):
        pass
    return result


def _pdf_qc(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {"path": "", "exists": False, "size_bytes": 0, "sha256": "", "page_count": 0}
    result: dict[str, Any] = {
        "path": str(path),
        "exists": path.is_file(),
        "size_bytes": path.stat().st_size if path.is_file() else 0,
        "sha256": _sha256(path) if path.is_file() else "",
        "page_count": 0,
    }
    if path.is_file():
        try:
            from pypdf import PdfReader

            reader = PdfReader(str(path))
            result["page_count"] = len(reader.pages)
            text = "\n".join(page.extract_text() or "" for page in reader.pages)
            result["broken_reference_hits"] = _broken_reference_hits(text)
            result["broken_reference"] = bool(result["broken_reference_hits"])
        except Exception as exc:  # noqa: BLE001
            result["error"] = str(exc)
    return result


def _manifest_qc(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return {"path": str(path or ""), "exists": False, "status": "missing", "missing_count": 0, "warning_count": 0}
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError("report build manifest must be an object")
    return {
        "path": str(path),
        "exists": True,
        "sha256": _sha256(path),
        "status": str(payload.get("status") or "unknown"),
        "missing_count": int(payload.get("missing_count") or len(payload.get("missing_items") or [])),
        "warning_count": len(payload.get("warnings") or []),
        "output_docx_image_count": int(payload.get("output_docx_image_count") or 0),
    }


def build_qc(
    report_path: Path,
    manifest_path: Path | None,
    pdf_path: Path | None,
    visual: dict[str, Any] | None = None,
    *,
    require_source_provenance: bool = False,
    require_authoritative_pdf: bool = False,
    pdf_export: dict[str, Any] | None = None,
) -> dict[str, Any]:
    docx = _docx_qc(report_path)
    manifest = _manifest_qc(manifest_path)
    pdf = _pdf_qc(pdf_path)
    export_record = dict(pdf_export or {})
    pdf_authoritative = bool(
        export_record.get("authoritative")
        if "authoritative" in export_record
        else pdf_path is not None
    )
    pdf["authoritative"] = pdf_authoritative
    pdf["export"] = export_record
    manifest_passed = bool(
        manifest.get("status") == "ok"
        and int(manifest.get("missing_count") or 0) == 0
        and (
            not require_source_provenance
            or int(manifest.get("warning_count") or 0) == 0
        )
    )
    if not require_source_provenance:
        manifest_passed = manifest.get("status") in {"ok", "warning"}
    authoritative_pdf_invalid = bool(
        pdf_authoritative
        and (
            not pdf.get("exists")
            or int(pdf.get("page_count") or 0) <= 0
            or bool(pdf.get("error"))
        )
    )
    structural_passed = bool(
        docx["exists"]
        and docx["size_bytes"] > 0
        and docx["zip_integrity"]
        and docx["document_xml"]
        and manifest_passed
        and not pdf.get("broken_reference", False)
        and not authoritative_pdf_invalid
    )
    visual = visual or {"status": "unavailable", "page_count": 0, "pages": []}
    if not structural_passed or visual.get("status") == "failed":
        status = "failed"
    elif require_authoritative_pdf and not pdf_authoritative:
        status = "warning"
    elif visual.get("status") in {"warning", "unavailable"}:
        status = "warning"
    else:
        status = "passed"
    return {"status": status, "docx": docx, "pdf": pdf, "manifest": manifest, "visual": visual}


def _ensure_report_manifest(
    output_dir: Path,
    report_path: Path,
    manifest_path: Path | None,
    report_type: str,
    *,
    require_source_provenance: bool = False,
) -> Path:
    if manifest_path is not None and manifest_path.is_file():
        return manifest_path
    if require_source_provenance:
        raise FileNotFoundError(
            "Strict source provenance requires a real report build manifest; "
            "a synthesized legacy warning manifest is not accepted."
        )
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = output_dir / f"embedded_report_build_manifest_{stamp}.json"
    payload = {
        "schema_version": 1,
        "manifest_type": "report_build",
        "report_type": report_type,
        "status": "warning",
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "output_docx": str(report_path),
        "missing_count": 0,
        "missing_items": [],
        "warnings": ["Legacy builder did not return a report manifest; embedded runner synthesized this QC record."],
    }
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return path


def _require_builder_output(
    path: Path | str,
    output_dir: Path,
    *,
    label: str,
    strict_containment: bool,
) -> Path:
    """Reject a missing or stale builder result before export/rendering.

    Strict workbench jobs must only consume artifacts published into their
    dedicated output directory.  This prevents a buggy builder from returning
    a still-valid report from an earlier month elsewhere on disk.
    """

    resolved = Path(path).expanduser().resolve()
    if not resolved.is_file():
        raise FileNotFoundError(f"{label} does not exist: {resolved}")
    if strict_containment:
        allowed = output_dir.expanduser().resolve()
        try:
            resolved.relative_to(allowed)
        except ValueError as exc:
            raise ValueError(f"{label} is outside output_dir: {resolved}") from exc
    return resolved


def _report_manifest_candidates(output_dir: Path) -> tuple[Path, ...]:
    """Return the manifest filenames used by the legacy monthly builders."""

    candidates = {
        path.resolve()
        for pattern in ("*report_build_manifest_*.json", "*_manifest_*.json")
        for path in output_dir.glob(pattern)
        if path.is_file()
    }
    return tuple(sorted(candidates, key=lambda path: str(path).casefold()))


def _report_manifest_snapshot(output_dir: Path) -> dict[Path, tuple[int, int, str]]:
    """Fingerprint manifests so a reused output directory cannot leak an old one."""

    snapshot: dict[Path, tuple[int, int, str]] = {}
    for path in _report_manifest_candidates(output_dir):
        stat = path.stat()
        snapshot[path] = (stat.st_mtime_ns, stat.st_size, _sha256(path))
    return snapshot


def _manifest_output_paths(value: Any, manifest_path: Path) -> tuple[Path, ...]:
    raw = str(value or "").strip()
    if not raw:
        raise ValueError(f"report build manifest has no output_docx: {manifest_path}")
    output = Path(raw).expanduser()
    if output.is_absolute():
        return (output.resolve(),)
    # Existing builders serialize ``str(output_docx)``.  With a relative
    # output_dir that value is relative to the worker cwd; a basename-only
    # legacy manifest is relative to the manifest directory.  Accept exactly
    # those two interpretations and still require one to equal report_path.
    return tuple(dict.fromkeys((output.resolve(), (manifest_path.parent / output).resolve())))


def _manifest_output_sha256(payload: dict[str, Any]) -> str:
    for key in ("output_docx_sha256", "output_sha256", "docx_sha256"):
        value = str(payload.get(key) or "").strip()
        if value:
            return value.upper()
    return ""


def _select_new_report_build_manifest(
    output_dir: Path,
    report_path: Path,
    before: dict[Path, tuple[int, int, str]],
) -> Path:
    """Bind a docx-only builder to the manifest written by this invocation.

    Jiulongjiang and Shuixianhua do not return their manifest path.  Selecting
    the newest file is unsafe when an output directory is reused, because an
    old manifest may have a later timestamp.  Only files created or modified
    after the pre-build snapshot are eligible, and their declared output must
    be the exact report returned by the builder.
    """

    expected_report = report_path.expanduser().resolve()
    actual_report_sha256 = ""
    matching: list[Path] = []
    changed: list[Path] = []
    mismatches: list[str] = []
    for candidate in _report_manifest_candidates(output_dir):
        stat = candidate.stat()
        fingerprint = (stat.st_mtime_ns, stat.st_size, _sha256(candidate))
        if before.get(candidate) == fingerprint:
            continue
        changed.append(candidate)
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8-sig"))
            if not isinstance(payload, dict):
                raise ValueError("manifest root is not an object")
            manifest_type = str(payload.get("manifest_type") or "").strip()
            if manifest_type and manifest_type != "report_build":
                raise ValueError(f"unexpected manifest_type={manifest_type!r}")
            declared_reports = _manifest_output_paths(payload.get("output_docx"), candidate)
            if expected_report not in declared_reports:
                declared_text = ", ".join(str(path) for path in declared_reports)
                mismatches.append(f"{candidate.name} -> {declared_text}")
                continue
            expected_sha256 = _manifest_output_sha256(payload)
            if expected_sha256:
                if not actual_report_sha256:
                    actual_report_sha256 = _sha256(expected_report)
                if expected_sha256 != actual_report_sha256:
                    raise ValueError(
                        "report build manifest output SHA-256 mismatch: "
                        f"{candidate}; expected {expected_sha256}, got {actual_report_sha256}"
                    )
            matching.append(candidate)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            mismatches.append(f"{candidate.name}: {exc}")

    if len(matching) == 1:
        return matching[0]
    if len(matching) > 1:
        names = ", ".join(path.name for path in matching)
        raise RuntimeError(
            "builder wrote multiple report manifests for the same DOCX; "
            f"cannot bind unambiguously: {names}"
        )
    detail = "; ".join(mismatches[:10]) or "no new or modified manifest was found"
    raise FileNotFoundError(
        "builder did not publish a new report manifest bound to its DOCX "
        f"({expected_report}); changed={len(changed)}; {detail}"
    )


def execute_report_job(request: ReportJobRequest, progress: ProgressCallback | None = None) -> ReportJobResult:
    with pinned_analysis_manifest_scope(
        request.analysis_manifest_path,
        request.analysis_manifest_sha256,
        require_source_provenance=request.require_source_provenance,
        result_root=request.result_root,
    ):
        with pinned_derived_artifact_manifest_scope(
            request.derived_artifact_manifest_path,
            request.derived_artifact_manifest_sha256,
            require_source_provenance=request.require_source_provenance,
        ):
            return _execute_report_job(request, progress)


def _execute_report_job(request: ReportJobRequest, progress: ProgressCallback | None = None) -> ReportJobResult:
    emit = progress or (lambda _stage, _fraction, _message: None)
    request.output_dir.mkdir(parents=True, exist_ok=True)
    emit("preflight", 0.05, "正在校验模板、配置和结果目录")
    for label, path in (("template", request.template), ("config", request.config_path)):
        if not path.is_file():
            raise FileNotFoundError(f"{label} does not exist: {path}")
    if not request.result_root.is_dir():
        raise FileNotFoundError(f"result root does not exist: {request.result_root}")
    report_type = request.report_type
    if report_type not in REPORT_TYPE_NAMES:
        raise ValueError(f"unsupported report type: {report_type or '<empty>'}")
    template_kind = STRICT_TEMPLATE_PRECHECK_KINDS.get(report_type)
    if request.require_source_provenance and template_kind:
        raise_for_template(template_kind, request.template)
    emit("building", 0.15, f"正在生成{REPORT_TYPE_NAMES[report_type]}")
    manifest_path: Path | None = None
    manifest_snapshot = (
        _report_manifest_snapshot(request.output_dir)
        if report_type in {"jlj_monthly", "shuixianhua_monthly"}
        else {}
    )
    pdf_path: Path | None = None
    missing: list[Any] = []
    if report_type == "hongtang_period_wim":
        manifest_path, report_path, missing = build_period_report(
            template=request.template,
            config_path=request.config_path,
            result_root=request.result_root,
            analysis_root=request.analysis_root,
            wim_root=request.wim_root,
            output_dir=request.output_dir,
            period_label=request.period_label,
            monitoring_range=request.monitoring_range,
            report_date=request.report_date,
            start_date=request.start_date,
            end_date=request.end_date,
        )
    elif report_type == "jlj_monthly":
        report_path = build_jlj_monthly_report(
            template=request.template, config_path=request.config_path,
            result_root=request.result_root, image_root=request.result_root,
            output_dir=request.output_dir, wim_root=request.wim_root,
            period_label=request.period_label, monitoring_range=request.monitoring_range,
            report_date=request.report_date, patrol_docx=None,
        )
        manifest_path = _select_new_report_build_manifest(
            request.output_dir,
            Path(report_path),
            manifest_snapshot,
        )
    elif report_type == "guanbing_monthly":
        report_path, manifest_path = build_guanbing_monthly_report(
            template=request.template, config_path=request.config_path,
            result_root=request.result_root, output_dir=request.output_dir,
            period_label=request.period_label, monitoring_range=request.monitoring_range,
            report_date=request.report_date, start_date=request.start_date, end_date=request.end_date,
        )
    elif report_type == "shuixianhua_monthly":
        report_path, pdf_path = build_shuixianhua_monthly_report(
            template=request.template, config_path=request.config_path,
            result_root=request.result_root, output_dir=request.output_dir,
            period_label=request.period_label, monitoring_range=request.monitoring_range,
            report_date=request.report_date, start_date=request.start_date,
            end_date=request.end_date,
        )
        manifest_path = _select_new_report_build_manifest(
            request.output_dir,
            Path(report_path),
            manifest_snapshot,
        )
    elif report_type == "zhishan_monthly":
        report_path, manifest_path = build_zhishan_monthly_report(
            template=request.template, config_path=request.config_path,
            result_root=request.result_root, output_dir=request.output_dir,
            period_label=request.period_label, monitoring_range=request.monitoring_range,
            report_date=request.report_date,
        )
    else:
        manifest_path, report_path, missing = build_hongtang_monthly_report(
            template=request.template, config_path=request.config_path,
            result_root=request.result_root, analysis_root=request.analysis_root,
            output_dir=request.output_dir, period_label=request.period_label,
            monitoring_range=request.monitoring_range, report_date=request.report_date,
        )
    report_path = _require_builder_output(
        report_path,
        request.output_dir,
        label="report DOCX",
        strict_containment=request.require_source_provenance,
    )
    manifest_path = (
        _require_builder_output(
            manifest_path,
            request.output_dir,
            label="report build manifest",
            strict_containment=request.require_source_provenance,
        )
        if manifest_path
        else None
    )
    pdf_path = (
        _require_builder_output(
            pdf_path,
            request.output_dir,
            label="report PDF",
            strict_containment=request.require_source_provenance,
        )
        if pdf_path
        else None
    )
    pdf_export: dict[str, Any] = {}
    if pdf_path is not None and pdf_path.is_file():
        pdf_export = {
            "status": "passed",
            "authoritative": True,
            "source": "builder_word_pdf",
            "path": str(pdf_path),
        }
    else:
        pdf_path = None
    if request.require_source_provenance and missing:
        raise RuntimeError(
            "Strict report build has missing or warning items: "
            + "; ".join(str(item) for item in missing[:20])
        )
    manifest_path = _ensure_report_manifest(
        request.output_dir,
        report_path,
        manifest_path,
        report_type,
        require_source_provenance=request.require_source_provenance,
    )
    emit("rendering", 0.82, "正在通过独立 Word 实例生成权威 PDF 并逐页检查")
    if pdf_path is None:
        word_export = export_authoritative_word_pdf(report_path)
        pdf_export = word_export.to_dict()
        if word_export.authoritative and word_export.path is not None:
            pdf_path = word_export.path.resolve()
    visual = render_docx_visual_qc(
        report_path,
        request.output_dir / "report_visual_qc",
        preferred_pdf_path=pdf_path,
    )
    if pdf_path is None:
        preview_pdf = str(visual.get("preview_pdf_path") or visual.get("pdf_path") or "")
        if preview_pdf:
            visual["preview_pdf_path"] = preview_pdf
        visual["pdf_authoritative"] = False
    emit("qc", 0.93, "正在执行 DOCX/PDF、页面渲染与报告内容清单质量检查")
    qc = build_qc(
        report_path,
        manifest_path,
        pdf_path,
        visual,
        require_source_provenance=request.require_source_provenance,
        require_authoritative_pdf=True,
        pdf_export=pdf_export,
    )
    if qc["status"] == "failed":
        raise RuntimeError(f"report QC failed: {qc}")
    summary_files = tuple(path for path in missing_summary_paths(report_path) if path.exists())
    emit("completed", 1.0, "报告生成与 QC 已完成")
    return ReportJobResult(
        manifest_path,
        report_path,
        pdf_path,
        tuple(str(item) for item in missing),
        summary_files,
        qc,
    )
