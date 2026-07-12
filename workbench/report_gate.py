from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .manifest import ManifestSummary, load_manifest_summary, manifest_context_issues
from .models import JobContext, file_sha256
from .provenance import PlotProvenanceSummary, inspect_manifest_plot_provenance


SUCCESS_STATES = {"ok", "success", "completed"}


@dataclass(frozen=True)
class ReportGateAudit:
    manifest: ManifestSummary | None
    provenance: PlotProvenanceSummary | None
    issues: tuple[str, ...]

    @property
    def passed(self) -> bool:
        return not self.issues


def _pinned_file_issues(label: str, raw_path: str, expected_sha256: str) -> tuple[Path | None, list[str]]:
    issues: list[str] = []
    if not raw_path:
        return None, [f"{label} path is not pinned"]
    path = Path(raw_path).expanduser().resolve()
    if not path.is_file():
        return path, [f"{label} does not exist: {path}"]
    if not expected_sha256:
        issues.append(f"{label} SHA256 is not pinned")
    elif file_sha256(path) != expected_sha256.upper():
        issues.append(f"{label} changed after workbench approval: {path}")
    return path, issues


def inspect_report_gate(context: JobContext) -> ReportGateAudit:
    """Re-evaluate every report approval condition at the process boundary."""

    issues: list[str] = []
    manifest: ManifestSummary | None = None
    provenance: PlotProvenanceSummary | None = None
    if context.analysis.state.lower() != "completed":
        issues.append("analysis is not completed")
    if not context.report.plots_approved:
        issues.append("plot review gate is not approved")
    if not context.selected_modules:
        issues.append("no analysis modules are bound to the report task")

    _, config_issues = _pinned_file_issues("config", context.config_path, context.config_sha256)
    _, template_issues = _pinned_file_issues(
        "report template", context.report.template_path, context.report.template_sha256
    )
    manifest_path, manifest_file_issues = _pinned_file_issues(
        "analysis manifest", context.analysis.manifest_path, context.analysis.manifest_sha256
    )
    issues.extend(config_issues)
    issues.extend(template_issues)
    issues.extend(manifest_file_issues)

    if manifest_path is not None and manifest_path.is_file() and not manifest_file_issues:
        try:
            manifest = load_manifest_summary(manifest_path)
            issues.extend(
                manifest_context_issues(
                    manifest,
                    bridge_id=context.bridge_id,
                    data_root=Path(context.data_root),
                    start_date=context.start_date,
                    end_date=context.end_date,
                )
            )
            if manifest.status.lower() not in SUCCESS_STATES:
                issues.append(f"analysis manifest status is not successful: {manifest.status}")
            if manifest.failed_modules:
                failed = ", ".join(item.key or item.label for item in manifest.failed_modules)
                issues.append(f"analysis manifest contains failed modules: {failed}")
            missing = manifest.missing_selected_modules(context.selected_modules)
            if missing:
                issues.append(f"analysis manifest does not cover selected modules: {', '.join(missing)}")
        except Exception as exc:  # noqa: BLE001
            issues.append(f"analysis manifest cannot be parsed: {exc}")

        try:
            provenance = inspect_manifest_plot_provenance(manifest_path)
            if not provenance.rows:
                issues.append("analysis manifest contains no formal plot provenance")
            elif provenance.failed_count:
                failures = "; ".join(
                    f"{row.path}: {row.message or row.status}" for row in provenance.rows if not row.closed
                )
                issues.append(f"formal plot provenance does not close: {failures}")
        except Exception as exc:  # noqa: BLE001
            issues.append(f"formal plot provenance cannot be verified: {exc}")

    return ReportGateAudit(manifest, provenance, tuple(dict.fromkeys(issues)))


def require_report_gate(context: JobContext) -> ReportGateAudit:
    audit = inspect_report_gate(context)
    if audit.issues:
        raise RuntimeError("report gate validation failed: " + "; ".join(audit.issues))
    return audit
