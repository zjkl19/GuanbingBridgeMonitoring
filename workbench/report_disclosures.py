from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

from .manifest import ManifestSummary
from .provenance import PlotProvenanceSummary


DISCLOSURE_POLICY_VERSION = 1
DISCLOSABLE_MODULE_STATUSES = {
    "skip": "not_applicable",
    "skipped": "not_applicable",
    "not_applicable": "not_applicable",
    "no_data": "no_valid_data",
    "no_valid_data": "no_valid_data",
}
MODULE_DISCLOSURE_REPORT_TYPES = {"jlj_monthly", "shuixianhua_monthly"}
SAFE_REPORT_MISSING_CATEGORIES = {
    "jlj_monthly": {"章节内容缺失", "图表/资源缺失", "巡查资料缺失"},
    "shuixianhua_monthly": {"report_image"},
}


@dataclass(frozen=True)
class DisclosureItem:
    stable_id: str
    source_kind: str
    reason_code: str
    module_key: str
    label: str
    reason_zh: str
    action_zh: str
    source_path: str = ""

    def to_dict(self) -> dict[str, str]:
        return asdict(self)


def _stable_id(source_kind: str, payload: Mapping[str, Any]) -> str:
    encoded = json.dumps(
        {"source_kind": source_kind, **dict(payload)},
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")
    return f"{source_kind}:{hashlib.sha256(encoded).hexdigest()[:24]}"


def _module_disclosure_item(module: Any) -> DisclosureItem | None:
    status = str(getattr(module, "status", "") or "").strip().casefold()
    reason_code = DISCLOSABLE_MODULE_STATUSES.get(status)
    if reason_code is None:
        return None
    message = str(getattr(module, "message", "") or "").strip()
    if not message:
        # A skip without a recorded reason is not auditable and must stay red.
        return None
    module_key = str(getattr(module, "key", "") or "").strip()
    label = str(getattr(module, "label", "") or module_key or "未命名模块").strip()
    if reason_code == "not_applicable":
        reason_zh = f"{label}已在分析清单中明确标记为不适用：{message}"
        action_zh = "清除模板中该模块的旧期次媒体，并在正文写明本期不适用。"
    else:
        reason_zh = f"{label}在本报告期没有有效数据：{message}"
        action_zh = "清除模板中该模块的旧期次媒体，并在正文写明本期无有效数据。"
    identity = {
        "module_key": module_key,
        "status": status,
        "reason_code": reason_code,
        "message": message,
    }
    return DisclosureItem(
        stable_id=_stable_id("analysis_module", identity),
        source_kind="analysis_module",
        reason_code=reason_code,
        module_key=module_key,
        label=label,
        reason_zh=reason_zh,
        action_zh=action_zh,
        source_path=str(getattr(module, "stats_path", "") or ""),
    )


def analysis_disclosure_items(
    manifest: ManifestSummary,
    provenance: PlotProvenanceSummary,
) -> tuple[DisclosureItem, ...]:
    """Return only evidence-backed yellow findings from an analysis run.

    Unknown module statuses and all failed provenance contracts are deliberately
    excluded here; the report gate classifies those as hard blockers.
    """

    items: list[DisclosureItem] = []
    for module in manifest.modules:
        item = _module_disclosure_item(module)
        if item is not None:
            items.append(item)
    for row in provenance.rows:
        if row.status != "closed_incomplete_source":
            continue
        days = tuple(str(day) for day in row.incomplete_days if str(day).strip())
        identity = {
            "module_key": row.module_key,
            "path": str(row.path.resolve(strict=False)),
            "incomplete_days": days,
        }
        label = row.path.stem.removesuffix(".plot")
        reason = (
            f"{label}的来源记录已闭合，但存在{len(days)}个不完整日期："
            f"{', '.join(days)}"
        )
        items.append(
            DisclosureItem(
                stable_id=_stable_id("analysis_provenance", identity),
                source_kind="analysis_provenance",
                reason_code="incomplete_source_coverage",
                module_key=row.module_key,
                label=label,
                reason_zh=reason,
                action_zh="正文披露不完整日期；统计仅使用实际有效数据，不插补缺失时段。",
                source_path=str(row.path),
            )
        )
    return tuple(items)


def disclosure_supported_for_report(
    report_type: str,
    item: DisclosureItem,
) -> bool:
    if item.source_kind == "analysis_module":
        return str(report_type) in MODULE_DISCLOSURE_REPORT_TYPES
    return item.source_kind == "analysis_provenance"


def report_build_disclosure_item(
    report_type: str,
    raw: Mapping[str, Any],
) -> DisclosureItem | None:
    category = str(raw.get("category") or "").strip()
    if category not in SAFE_REPORT_MISSING_CATEGORIES.get(str(report_type), set()):
        return None
    label = str(
        raw.get("label")
        or raw.get("item")
        or raw.get("section")
        or "报告缺项"
    ).strip()
    detail = str(
        raw.get("detail")
        or raw.get("reason_zh")
        or raw.get("reason")
        or raw.get("message")
        or "本报告期没有可用于该位置的有效数据。"
    ).strip()
    module_key = str(raw.get("module_key") or raw.get("module") or "").strip()
    reason_code = (
        "no_valid_data"
        if category in {"章节内容缺失", "图表/资源缺失", "report_image"}
        else "report_type_omission_allowed"
    )
    action = (
        "生成器已清除该位置的模板旧媒体，并在正文写入本期无有效数据或等效说明。"
        if reason_code == "no_valid_data"
        else "该报告类型允许省略此项；生成器已清除模板旧内容并写入缺项说明。"
    )
    identity = {
        "report_type": str(report_type),
        "category": category,
        "label": label,
        "detail": detail,
        "module_key": module_key,
    }
    return DisclosureItem(
        stable_id=_stable_id("report_build", identity),
        source_kind="report_build",
        reason_code=reason_code,
        module_key=module_key,
        label=label,
        reason_zh=f"{label}：{detail}",
        action_zh=action,
        source_path=str(raw.get("source") or raw.get("path") or ""),
    )


def confirmation_record(
    item: DisclosureItem,
    *,
    analysis_manifest_sha256: str,
    confirmed_at: str | None = None,
) -> dict[str, Any]:
    return {
        **item.to_dict(),
        "policy_version": DISCLOSURE_POLICY_VERSION,
        "analysis_manifest_sha256": str(analysis_manifest_sha256).upper(),
        "confirmed_at": confirmed_at
        or datetime.now().astimezone().isoformat(timespec="seconds"),
    }


def validate_confirmations(
    items: Sequence[DisclosureItem],
    confirmations: Iterable[Mapping[str, Any]],
    *,
    analysis_manifest_sha256: str,
    policy_version: int,
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    """Return missing and stale confirmation IDs for an exact disclosure set."""

    expected = {item.stable_id: item for item in items}
    valid: set[str] = set()
    stale: set[str] = set()
    expected_sha = str(analysis_manifest_sha256).upper()
    if int(policy_version or 0) != DISCLOSURE_POLICY_VERSION:
        return tuple(expected), tuple(
            str(raw.get("stable_id") or "") for raw in confirmations if raw
        )
    for raw in confirmations:
        stable_id = str(raw.get("stable_id") or "")
        item = expected.get(stable_id)
        if item is None:
            if stable_id:
                stale.add(stable_id)
            continue
        if str(raw.get("analysis_manifest_sha256") or "").upper() != expected_sha:
            stale.add(stable_id)
            continue
        if int(raw.get("policy_version") or 0) != DISCLOSURE_POLICY_VERSION:
            stale.add(stable_id)
            continue
        immutable_fields = (
            "source_kind",
            "reason_code",
            "module_key",
            "label",
            "reason_zh",
            "action_zh",
            "source_path",
        )
        if any(str(raw.get(name) or "") != str(getattr(item, name)) for name in immutable_fields):
            stale.add(stable_id)
            continue
        if not str(raw.get("confirmed_at") or "").strip():
            stale.add(stable_id)
            continue
        valid.add(stable_id)
    return tuple(sorted(set(expected) - valid)), tuple(sorted(stale))


def invalidate_disclosure_approval(report_state: Any) -> None:
    report_state.disclosure_manifest_sha256 = ""
    report_state.disclosure_policy_version = DISCLOSURE_POLICY_VERSION
    report_state.disclosure_confirmations = []
    report_state.report_build_disclosure_candidates = []


def confirmed_disclosure_dicts(
    items: Sequence[DisclosureItem],
    confirmations: Iterable[Mapping[str, Any]],
) -> list[dict[str, Any]]:
    by_id = {
        str(raw.get("stable_id") or ""): dict(raw)
        for raw in confirmations
        if isinstance(raw, Mapping)
    }
    return [by_id[item.stable_id] for item in items if item.stable_id in by_id]
