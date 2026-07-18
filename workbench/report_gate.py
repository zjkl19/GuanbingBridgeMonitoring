from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from .manifest import ManifestSummary, load_manifest_summary, manifest_context_issues
from .models import JobContext, file_sha256
from .config_layers import config_dependency_sha256
from .provenance import PlotProvenanceSummary, inspect_manifest_plot_provenance
from .report_disclosures import (
    DISCLOSABLE_MODULE_STATUSES,
    DisclosureItem,
    analysis_disclosure_items,
    disclosure_supported_for_report,
    validate_confirmations,
)


SUCCESS_STATES = {"ok", "success", "completed"}


@dataclass(frozen=True)
class ReportGateAudit:
    manifest: ManifestSummary | None
    provenance: PlotProvenanceSummary | None
    hard_issues: tuple[str, ...]
    disclosure_items: tuple[DisclosureItem, ...] = ()
    missing_confirmation_ids: tuple[str, ...] = ()
    stale_confirmation_ids: tuple[str, ...] = ()

    @property
    def issues(self) -> tuple[str, ...]:
        issues = list(self.hard_issues)
        if self.missing_confirmation_ids:
            issues.append(
                f"黄色缺项尚未逐项确认：{len(self.missing_confirmation_ids)}项"
            )
        if self.stale_confirmation_ids:
            issues.append(
                f"黄色缺项确认已失效或不属于当前清单：{len(self.stale_confirmation_ids)}项"
            )
        return tuple(issues)

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

    config_path = Path(context.config_path).expanduser()
    config_issues: list[str] = []
    if not config_path.is_file():
        config_issues.append(f"配置文件不存在：{config_path}")
    elif config_dependency_sha256(config_path) != context.config_sha256.upper():
        config_issues.append(f"配置文件或其分层依赖在任务建立后发生变化：{config_path}")
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
                    config_path=Path(context.config_path),
                    config_sha256=context.config_sha256,
                )
            )
            if manifest.status.lower() not in SUCCESS_STATES:
                issues.append(f"分析结果状态不是成功：{manifest.status}")
            hard_failed_modules = tuple(
                item
                for item in manifest.failed_modules
                if str(item.status or "").strip().casefold()
                not in DISCLOSABLE_MODULE_STATUSES
                or not str(item.message or "").strip()
            )
            if hard_failed_modules:
                failed = ", ".join(item.key or item.label for item in hard_failed_modules)
                issues.append(f"分析结果包含失败项目：{failed}")
            missing = manifest.missing_selected_modules(context.selected_modules)
            if missing:
                issues.append(f"分析结果未覆盖所选项目：{', '.join(missing)}")
        except Exception as exc:  # noqa: BLE001
            issues.append(f"分析结果清单无法读取：{exc}")

        try:
            provenance = inspect_manifest_plot_provenance(manifest_path)
            disclosable_module_keys = {
                item.key
                for item in manifest.modules
                if str(item.status or "").strip().casefold()
                in DISCLOSABLE_MODULE_STATUSES
                and str(item.message or "").strip()
            } if manifest is not None else set()
            modules_requiring_provenance = {
                key for key in context.selected_modules if key not in disclosable_module_keys
            }
            if not provenance.rows and modules_requiring_provenance:
                issues.append("分析结果中没有正式图件的数据核验记录")
            elif provenance.failed_count:
                failures = "; ".join(
                    f"{row.path}: {row.message or row.status}" for row in provenance.rows if not row.closed
                )
                issues.append(f"正式图件数据检查未通过：{failures}")
        except Exception as exc:  # noqa: BLE001
            issues.append(f"正式图件数据无法核验：{exc}")

    disclosures: tuple[DisclosureItem, ...] = ()
    missing_confirmation_ids: tuple[str, ...] = ()
    stale_confirmation_ids: tuple[str, ...] = ()
    if manifest is not None and provenance is not None:
        discovered = analysis_disclosure_items(manifest, provenance)
        unsupported = tuple(
            item
            for item in discovered
            if not disclosure_supported_for_report(context.report.report_type, item)
        )
        if unsupported:
            issues.append(
                "当前报告类型尚未实现这些黄色缺项的安全正文处置："
                + ", ".join(item.label for item in unsupported)
            )
        report_build_items: list[DisclosureItem] = []
        for raw in context.report.report_build_disclosure_candidates:
            if not isinstance(raw, dict):
                issues.append("报告缺项候选记录损坏，必须重新执行报告预检查")
                continue
            try:
                item = DisclosureItem(**{
                    name: str(raw.get(name) or "")
                    for name in DisclosureItem.__dataclass_fields__
                })
            except TypeError:
                issues.append("报告缺项候选记录无法读取，必须重新执行报告预检查")
                continue
            if item.source_kind != "report_build" or not item.stable_id:
                issues.append("报告缺项候选记录来源无效，必须重新执行报告预检查")
                continue
            report_build_items.append(item)
        disclosures = (
            *(item for item in discovered if item not in unsupported),
            *report_build_items,
        )
        if disclosures:
            if (
                str(context.report.disclosure_manifest_sha256 or "").upper()
                != str(context.analysis.manifest_sha256 or "").upper()
            ):
                missing_confirmation_ids = tuple(item.stable_id for item in disclosures)
                stale_confirmation_ids = tuple(
                    str(raw.get("stable_id") or "")
                    for raw in context.report.disclosure_confirmations
                    if isinstance(raw, dict) and raw.get("stable_id")
                )
            else:
                missing_confirmation_ids, stale_confirmation_ids = validate_confirmations(
                    disclosures,
                    context.report.disclosure_confirmations,
                    analysis_manifest_sha256=context.analysis.manifest_sha256,
                    policy_version=context.report.disclosure_policy_version,
                )
        elif context.report.disclosure_confirmations:
            stale_confirmation_ids = tuple(
                str(raw.get("stable_id") or "")
                for raw in context.report.disclosure_confirmations
                if isinstance(raw, dict) and raw.get("stable_id")
            )
    return ReportGateAudit(
        manifest,
        provenance,
        tuple(dict.fromkeys(issues)),
        disclosures,
        missing_confirmation_ids,
        stale_confirmation_ids,
    )


def require_report_gate(context: JobContext) -> ReportGateAudit:
    audit = inspect_report_gate(context)
    if audit.issues:
        raise RuntimeError("报告生成条件检查未通过：" + "; ".join(audit.issues))
    return audit
