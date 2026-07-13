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
        return None, [f"{label}路径尚未固定"]
    path = Path(raw_path).expanduser().resolve()
    if not path.is_file():
        return path, [f"{label}不存在：{path}"]
    if not expected_sha256:
        issues.append(f"{label}版本尚未固定")
    elif file_sha256(path) != expected_sha256.upper():
        issues.append(f"{label}在审核后发生变化：{path}")
    return path, issues


def inspect_report_gate(context: JobContext) -> ReportGateAudit:
    """Re-evaluate every report approval condition at the process boundary."""

    issues: list[str] = []
    manifest: ManifestSummary | None = None
    provenance: PlotProvenanceSummary | None = None
    if context.analysis.state.lower() != "completed":
        issues.append("分析尚未完成")
    if not context.report.plots_approved:
        issues.append("当前图件尚未审核")
    if not context.selected_modules:
        issues.append("报告任务尚未绑定任何分析项目")

    _, config_issues = _pinned_file_issues("配置文件", context.config_path, context.config_sha256)
    _, template_issues = _pinned_file_issues(
        "报告模板", context.report.template_path, context.report.template_sha256
    )
    manifest_path, manifest_file_issues = _pinned_file_issues(
        "分析结果清单", context.analysis.manifest_path, context.analysis.manifest_sha256
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
                issues.append(f"分析结果状态不是成功：{manifest.status}")
            if manifest.failed_modules:
                failed = ", ".join(item.key or item.label for item in manifest.failed_modules)
                issues.append(f"分析结果包含失败项目：{failed}")
            missing = manifest.missing_selected_modules(context.selected_modules)
            if missing:
                issues.append(f"分析结果未覆盖所选项目：{', '.join(missing)}")
        except Exception as exc:  # noqa: BLE001
            issues.append(f"分析结果清单无法读取：{exc}")

        try:
            provenance = inspect_manifest_plot_provenance(manifest_path)
            if not provenance.rows:
                issues.append("分析结果中没有正式图件的数据核验记录")
            elif provenance.failed_count:
                failures = "; ".join(
                    f"{row.path}: {row.message or row.status}" for row in provenance.rows if not row.closed
                )
                issues.append(f"正式图件数据检查未通过：{failures}")
        except Exception as exc:  # noqa: BLE001
            issues.append(f"正式图件数据无法核验：{exc}")

    return ReportGateAudit(manifest, provenance, tuple(dict.fromkeys(issues)))


def require_report_gate(context: JobContext) -> ReportGateAudit:
    audit = inspect_report_gate(context)
    if audit.issues:
        raise RuntimeError("报告生成条件检查未通过：" + "; ".join(audit.issues))
    return audit
