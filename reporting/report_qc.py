from __future__ import annotations

import argparse
import json
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from docx import Document
from docx.table import Table

try:
    from docx_table_utils import find_first_row_index_by_first_cell, table_has_first_cell
    from image_block_utils import count_docx_images
except Exception:  # pragma: no cover - package import fallback
    from .docx_table_utils import find_first_row_index_by_first_cell, table_has_first_cell
    from .image_block_utils import count_docx_images


FORBIDDEN_REVIEW_PHRASES = (
    "需结合原始数据和现场运维记录复核",
    "建议结合原始数据和传感器状态进一步复核",
    "建议结合原始数据进一步复核",
    "当前吊杆参数配置尚未完整校核",
    "索力换算结果暂仅用于时程展示",
)


@dataclass(frozen=True)
class ReportQcIssue:
    code: str
    severity: str
    message: str
    detail: str = ""


@dataclass(frozen=True)
class ReportQcResult:
    kind: str
    docx_path: str
    checked_at: str
    status: str
    issue_count: int
    warning_count: int
    issues: list[ReportQcIssue]
    summary: dict[str, Any]


def _all_doc_text(doc) -> str:
    parts: list[str] = []
    parts.extend(para.text for para in doc.paragraphs if para.text)
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                if cell.text:
                    parts.append(cell.text)
    return "\n".join(parts)


def _find_front_cover_summary_table(doc) -> tuple[int | None, Table | None]:
    for idx, table in enumerate(doc.tables):
        if len(table.columns) < 2:
            continue
        if find_first_row_index_by_first_cell(table, "委托单位") == 0 and find_first_row_index_by_first_cell(table, "监测结果") is not None:
            return idx, table
    return None, None


def _front_summary_table_indices(doc, cover_idx: int | None) -> list[int]:
    if cover_idx is None:
        return []
    out = [cover_idx]
    for idx in range(cover_idx + 1, len(doc.tables)):
        table = doc.tables[idx]
        if table_has_first_cell(table, "监测结果"):
            out.append(idx)
            continue
        break
    return out


def _has_summary_table(table: Table) -> bool:
    return table_has_first_cell(table, "监测结果")


def check_jlj_report(docx_path: Path | str) -> ReportQcResult:
    path = Path(docx_path)
    issues: list[ReportQcIssue] = []
    summary: dict[str, Any] = {
        "exists": path.exists(),
        "table_count": 0,
        "image_count": 0,
        "summary_table_indices": [],
        "front_summary_table_indices": [],
        "transfer_marker_count": 0,
        "continue_marker_count": 0,
    }
    if not path.exists():
        issues.append(ReportQcIssue("missing-file", "error", f"报告文件不存在: {path}"))
        return _build_result("jlj_monthly", path, issues, summary)

    doc = Document(str(path))
    text = _all_doc_text(doc)
    summary["table_count"] = len(doc.tables)
    summary["image_count"] = count_docx_images(path)
    summary["transfer_marker_count"] = text.count("（转下页）")
    summary["continue_marker_count"] = text.count("（续上页）")

    for phrase in FORBIDDEN_REVIEW_PHRASES:
        count = text.count(phrase)
        if count:
            issues.append(
                ReportQcIssue(
                    "forbidden-review-phrase",
                    "warning",
                    f"报告仍包含需删除的复核/临时说明: {phrase}",
                    f"count={count}",
                )
            )

    cover_idx, _ = _find_front_cover_summary_table(doc)
    front_indices = _front_summary_table_indices(doc, cover_idx)
    summary_indices = [idx for idx, table in enumerate(doc.tables) if _has_summary_table(table)]
    summary["summary_table_indices"] = summary_indices
    summary["front_summary_table_indices"] = front_indices

    if cover_idx is None:
        issues.append(ReportQcIssue("missing-front-summary", "error", "未找到首页委托单位表格内的监测结果区域。"))
    else:
        stale_before = [idx for idx in summary_indices if idx < cover_idx]
        if stale_before:
            issues.append(
                ReportQcIssue(
                    "stale-summary-before-cover",
                    "warning",
                    "首页委托单位表格前存在独立监测结果表，可能是模板残留。",
                    ",".join(str(idx) for idx in stale_before),
                )
            )
        stale_later = [idx for idx in summary_indices if idx not in front_indices]
        if stale_later:
            issues.append(
                ReportQcIssue(
                    "summary-table-outside-front-block",
                    "warning",
                    "结论页监测结果表未连续贴在首页表格后，可能出现重复或错位。",
                    ",".join(str(idx) for idx in stale_later),
                )
            )

    if summary["transfer_marker_count"] != summary["continue_marker_count"]:
        issues.append(
            ReportQcIssue(
                "continuation-marker-mismatch",
                "info",
                "（转下页）与（续上页）数量不一致，仅作为分页提示复核信息。",
                f"transfer={summary['transfer_marker_count']}, continue={summary['continue_marker_count']}",
            )
        )

    if summary["image_count"] <= 0:
        issues.append(ReportQcIssue("no-images", "warning", "报告中未检测到图片。"))

    return _build_result("jlj_monthly", path, issues, summary)


def _build_result(kind: str, path: Path, issues: list[ReportQcIssue], summary: dict[str, Any]) -> ReportQcResult:
    warning_count = sum(1 for issue in issues if issue.severity == "warning")
    error_count = sum(1 for issue in issues if issue.severity == "error")
    status = "failed" if error_count else ("warning" if warning_count else "ok")
    return ReportQcResult(
        kind=kind,
        docx_path=str(path),
        checked_at=datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        status=status,
        issue_count=len(issues),
        warning_count=warning_count,
        issues=issues,
        summary=summary,
    )


def result_to_dict(result: ReportQcResult) -> dict[str, Any]:
    payload = asdict(result)
    payload["issues"] = [asdict(issue) for issue in result.issues]
    return payload


def write_report_qc_report(
    result: ReportQcResult,
    output_dir: Path | str,
    *,
    timestamp: str | None = None,
    prefix: str = "report_qc",
) -> tuple[Path, Path]:
    out_dir = Path(output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    ts = timestamp or datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = out_dir / f"{prefix}_{result.kind}_{ts}.json"
    txt_path = out_dir / f"{prefix}_{result.kind}_{ts}.txt"
    payload = result_to_dict(result)
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")

    lines = [
        f"检查时间: {result.checked_at}",
        f"报告类型: {result.kind}",
        f"报告文件: {result.docx_path}",
        f"状态: {result.status}",
        f"问题数量: {result.issue_count}",
        f"表格数量: {result.summary.get('table_count')}",
        f"图片数量: {result.summary.get('image_count')}",
        f"结论页表格索引: {result.summary.get('front_summary_table_indices')}",
    ]
    if result.issues:
        lines.append("")
        lines.append("问题清单:")
        for issue in result.issues:
            detail = f" ({issue.detail})" if issue.detail else ""
            lines.append(f"- [{issue.severity}/{issue.code}] {issue.message}{detail}")
    else:
        lines.append("")
        lines.append("检查通过：未发现已知格式或内容风险。")
    txt_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return txt_path, json_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Run report quality checks.")
    parser.add_argument("--docx", type=Path, required=True, help="Generated report DOCX path.")
    parser.add_argument("--kind", choices=["jlj_monthly"], default="jlj_monthly")
    parser.add_argument("--output-dir", type=Path, default=None, help="Directory for QC txt/json outputs.")
    parser.add_argument("--strict", action="store_true", help="Exit non-zero when QC status is warning/failed.")
    args = parser.parse_args()

    if args.kind != "jlj_monthly":
        raise SystemExit(f"Unsupported report kind: {args.kind}")
    result = check_jlj_report(args.docx)
    if args.output_dir:
        txt_path, json_path = write_report_qc_report(result, args.output_dir)
        print(f"QC report: {txt_path}")
        print(f"QC JSON:   {json_path}")
    print(f"QC {result.status}: {args.docx}")
    if result.issues:
        for issue in result.issues:
            print(f"- [{issue.severity}/{issue.code}] {issue.message}")
    if args.strict and result.status != "ok":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
