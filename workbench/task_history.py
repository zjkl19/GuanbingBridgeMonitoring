from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from .models import JobContext
from .config_layers import config_dependency_sha256
from .operator_text import operator_stage_label, operator_state_label


@dataclass(frozen=True)
class TaskHistoryEntry:
    context_path: Path
    job_id: str
    bridge_id: str
    bridge_name: str
    period_text: str
    updated_at: str
    analysis_state: str
    analysis_detail: str
    report_state: str
    report_detail: str
    health: str
    issues: tuple[str, ...]
    can_restore: bool


def _read_object(path: Path) -> tuple[dict[str, Any] | None, str]:
    if not path.is_file():
        return None, ""
    try:
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        return None, f"状态文件不可读：{path.name}（{exc}）"
    if not isinstance(payload, dict):
        return None, f"状态文件根节点不是对象：{path.name}"
    return payload, ""


def _state(payload: dict[str, Any] | None, fallback: str, *keys: str) -> str:
    for key in keys:
        if payload is not None and payload.get(key):
            return str(payload[key]).strip().lower()
    return str(fallback or "unknown").strip().lower()


def _analysis_detail(payload: dict[str, Any] | None) -> str:
    if payload is None:
        return ""
    bits: list[str] = []
    current = str(payload.get("current_module_label") or payload.get("current_module_key") or "").strip()
    if current:
        bits.append(current)
    completed = payload.get("completed_modules")
    total = payload.get("module_total")
    if completed is not None and total is not None:
        bits.append(f"{completed}/{total}")
    try:
        fraction = float(payload.get("progress_fraction"))
    except (TypeError, ValueError):
        fraction = -1
    if 0 <= fraction <= 1:
        bits.append(f"{fraction:.0%}")
    return "；".join(bits)


def _report_detail(payload: dict[str, Any] | None, context: JobContext) -> str:
    stage = str((payload or {}).get("stage") or "").strip()
    qc_payload = (payload or {}).get("qc")
    qc = str(
        context.report.qc_state
        or (qc_payload.get("status") if isinstance(qc_payload, dict) else "")
        or ""
    ).strip()
    stage_label = operator_stage_label(stage) if stage else ""
    quality_label = f"质量检查：{operator_state_label(qc)}" if qc else ""
    if stage.casefold() == "qc" and quality_label:
        return quality_label
    return "；".join(bit for bit in (stage_label, quality_label) if bit)


def _sort_timestamp(entry: TaskHistoryEntry) -> float:
    value = entry.updated_at.strip()
    if value:
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
        except ValueError:
            pass
    try:
        return entry.context_path.stat().st_mtime
    except OSError:
        return 0.0


class TaskHistoryIndex:
    def __init__(self, known_bridge_ids: Iterable[str] = ()) -> None:
        self.known_bridge_ids = {str(value) for value in known_bridge_ids}

    @staticmethod
    def _candidate_paths(data_roots: Iterable[Path], extra_paths: Iterable[Path]) -> tuple[Path, ...]:
        candidates: set[Path] = set()
        for raw in extra_paths:
            path = raw.expanduser().resolve()
            if path.is_file() and path.name.casefold() == "job_context.json":
                candidates.add(path)
        for raw in data_roots:
            root = raw.expanduser()
            workbench_root = root if root.name.casefold() == "workbench" else root / "run_logs" / "workbench"
            if not workbench_root.is_dir() or workbench_root.is_symlink():
                continue
            try:
                children = tuple(workbench_root.iterdir())
            except OSError:
                continue
            for child in children:
                if child.is_dir() and not child.is_symlink():
                    path = child / "job_context.json"
                    if path.is_file() and not path.is_symlink():
                        candidates.add(path.resolve())
        return tuple(sorted(candidates, key=lambda path: str(path).casefold()))

    def discover(
        self,
        *,
        data_roots: Iterable[Path] = (),
        extra_paths: Iterable[Path] = (),
        limit: int = 500,
    ) -> tuple[TaskHistoryEntry, ...]:
        entries = [self.inspect(path) for path in self._candidate_paths(data_roots, extra_paths)]
        entries.sort(key=_sort_timestamp, reverse=True)
        return tuple(entries[: max(1, int(limit))])

    def inspect(self, path: Path) -> TaskHistoryEntry:
        path = path.expanduser().resolve()
        try:
            context = JobContext.read(path)
        except Exception as exc:  # noqa: BLE001
            try:
                updated_at = datetime.fromtimestamp(path.stat().st_mtime).astimezone().isoformat(timespec="seconds")
            except OSError:
                updated_at = ""
            return TaskHistoryEntry(
                path,
                path.parent.name,
                "",
                "不可读取",
                "",
                updated_at,
                "invalid",
                "",
                "invalid",
                "",
                "invalid",
                (f"任务上下文不可读：{exc}",),
                False,
            )

        issues: list[str] = []
        if self.known_bridge_ids and context.bridge_id not in self.known_bridge_ids:
            issues.append(f"未知桥梁标识：{context.bridge_id}")
        data_root = Path(context.data_root)
        if not data_root.is_dir():
            issues.append("数据根目录不存在")
        config_path = Path(context.config_path)
        if not config_path.is_file():
            issues.append("配置文件不存在")
        elif context.config_sha256:
            try:
                actual = config_dependency_sha256(config_path)
            except (OSError, ValueError) as exc:
                issues.append(f"配置文件无法读取：{exc}")
                actual = ""
            if actual and actual != context.config_sha256:
                issues.append("配置SHA256已变化")

        analysis_payload, analysis_issue = _read_object(Path(context.analysis.status_path))
        report_status_payload, report_issue = _read_object(Path(context.report.status_path))
        result_value = str(
            (report_status_payload or {}).get("result_path") or context.report.result_path or ""
        ).strip()
        report_result_payload, report_result_issue = (
            _read_object(Path(result_value)) if result_value else (None, "")
        )
        report_payload: dict[str, Any] | None = None
        if report_result_payload is not None or report_status_payload is not None:
            report_payload = dict(report_result_payload or {})
            report_payload.update(report_status_payload or {})
        if analysis_issue:
            issues.append(analysis_issue)
        if report_issue:
            issues.append(report_issue)
        if report_result_issue:
            issues.append(report_result_issue)
        analysis_state = _state(analysis_payload, context.analysis.state, "status", "state")
        report_state = _state(report_payload, context.report.state, "state", "status")

        if analysis_state == "completed":
            manifest_value = str(
                (analysis_payload or {}).get("manifest_path") or context.analysis.manifest_path or ""
            ).strip()
            manifest = Path(manifest_value) if manifest_value else None
            if manifest is None or not manifest.is_file():
                issues.append("分析已完成但结果清单不存在")
        if report_state == "completed":
            report_payload = report_payload or {}
            outputs = [
                Path(value)
                for value in (
                    report_payload.get("output_docx"),
                    report_payload.get("report_path"),
                    report_payload.get("output_pdf"),
                    report_payload.get("pdf_path"),
                    context.report.output_docx,
                    context.report.output_pdf,
                )
                if value
            ]
            if not outputs or not any(output.is_file() for output in outputs):
                issues.append("报告已完成但DOCX/PDF不存在")

        fatal = any(
            issue.startswith(("未知桥梁", "配置文件不存在", "任务上下文不可读"))
            for issue in issues
        )
        health = "invalid" if fatal else "warning" if issues else "ready"
        can_restore = not fatal
        return TaskHistoryEntry(
            path,
            context.job_id,
            context.bridge_id,
            context.bridge_name,
            f"{context.start_date} 至 {context.end_date}",
            context.updated_at,
            analysis_state,
            _analysis_detail(analysis_payload),
            report_state,
            _report_detail(report_payload, context),
            health,
            tuple(issues),
            can_restore,
        )
