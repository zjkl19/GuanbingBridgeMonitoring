from __future__ import annotations

import argparse
import json
import re
from dataclasses import asdict, is_dataclass
from datetime import date, datetime
from pathlib import Path

from docx import Document

from build_monthly_report import (
    apply_manifest_to_doc,
    build_manifest,
    ensure_dir,
    load_json,
    summarize_missing_images,
)
from build_quarterly_wim_sample import (
    T_NEXT,
    T_WIM,
    add_month_block,
    add_quarter_overview,
    capture_paragraph_template,
    clear_section_between,
    find_last_paragraph,
    make_quarter_summary,
    parse_month_summary,
    set_summary_table,
)


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    templates = sorted((repo_root / "reports").glob("*.docx"))
    default_template = templates[0] if templates else None
    parser = argparse.ArgumentParser(description="Build full period monitoring report, including WIM.")
    parser.add_argument("--template", type=Path, default=default_template)
    parser.add_argument("--config", type=Path, default=repo_root / "config" / "hongtang_config.json")
    parser.add_argument("--result-root", type=Path, required=True)
    parser.add_argument("--analysis-root", type=Path, default=repo_root)
    parser.add_argument("--image-root", type=Path, default=None)
    parser.add_argument("--wim-root", type=Path, default=None, help="Processed monthly WIM result root, e.g. outputs/wim_quarter_sql/hongtang")
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--period-label", default="2026年1-3月")
    parser.add_argument("--monitoring-range", default="2026.01.01~2026.03.16")
    parser.add_argument("--report-date", default=datetime.now().strftime("%Y年%m月%d日"))
    parser.add_argument("--start-date", default="2026-01-01")
    parser.add_argument("--end-date", default="2026-03-16")
    return parser.parse_args()


def parse_date_str(text: str) -> date:
    return datetime.strptime(text, "%Y-%m-%d").date()


def extract_dates_from_range(text: str) -> tuple[date, date] | None:
    pattern = re.compile(r"(\d{4})[.-](\d{1,2})[.-](\d{1,2}).*?(\d{4})[.-](\d{1,2})[.-](\d{1,2})")
    match = pattern.search(text)
    if not match:
        return None
    y1, m1, d1, y2, m2, d2 = map(int, match.groups())
    return date(y1, m1, d1), date(y2, m2, d2)


def months_between(start_date: date, end_date: date) -> list[str]:
    if end_date < start_date:
        raise ValueError("end-date must not be earlier than start-date")
    months: list[str] = []
    year = start_date.year
    month = start_date.month
    while (year, month) <= (end_date.year, end_date.month):
        months.append(f"{year:04d}{month:02d}")
        if month == 12:
            year += 1
            month = 1
        else:
            month += 1
    return months


def resolve_wim_root(result_root: Path, analysis_root: Path, explicit_root: Path | None) -> Path:
    candidates: list[Path] = []
    if explicit_root is not None:
        candidates.append(explicit_root)
    candidates.extend(
        [
            result_root / "WIM" / "results" / "hongtang",
            result_root / "WIM" / "results",
            result_root / "WIM_results",
            result_root / "wim_results",
            analysis_root / "outputs" / "wim_quarter_sql" / "hongtang",
        ]
    )
    for candidate in candidates:
        if candidate.exists() and candidate.is_dir():
            return candidate
    checked = ", ".join(str(p) for p in candidates)
    raise FileNotFoundError(f"Processed WIM result root not found. Checked: {checked}")


def build_wim_period_section(wim_root: Path, months: list[str]) -> dict:
    summaries = []
    warnings: list[str] = []
    for yyyymm in months:
        month_dir = wim_root / yyyymm
        if not month_dir.exists():
            warnings.append(f"Missing WIM month directory: {month_dir}")
            continue
        summaries.append(parse_month_summary(wim_root, yyyymm))

    return {
        "enabled": bool(summaries),
        "wim_root": str(wim_root),
        "months": months,
        "warnings": warnings,
        "summary": make_quarter_summary(summaries) if summaries else "",
        "month_summaries": summaries,
    }


def apply_wim_period_to_doc(doc: Document, section: dict) -> None:
    if not section.get("enabled"):
        return

    summaries = section["month_summaries"]
    summary_text = section["summary"]

    set_summary_table(doc, summary_text)

    wim_heading = find_last_paragraph(doc, T_WIM)
    next_heading = find_last_paragraph(doc, T_NEXT)

    heading_tpl = capture_paragraph_template(wim_heading)
    summary_cell_paras = doc.tables[1].rows[3].cells[2].paragraphs
    body_tpl = capture_paragraph_template(summary_cell_paras[8] if len(summary_cell_paras) > 8 else summary_cell_paras[-1])
    fig_anchor = find_last_paragraph(doc, "图 4-3 桥梁交通流参数分析")
    table_anchor = find_last_paragraph(doc, "表 4-4 车流量统计表")
    cont_anchor = find_last_paragraph(doc, "续表 4-5")
    caption_tpl = capture_paragraph_template(table_anchor)
    subcap_tpl = capture_paragraph_template(cont_anchor)
    fig_tpl = capture_paragraph_template(fig_anchor)

    clear_section_between(wim_heading, next_heading)
    from build_quarterly_wim_sample import add_text_paragraph_before  # local import to avoid widening top-level surface

    add_text_paragraph_before(next_heading, summary_text, body_tpl)
    add_quarter_overview(next_heading, summaries, caption_tpl)
    for item in summaries:
        add_month_block(next_heading, item, heading_tpl, body_tpl, caption_tpl, fig_tpl, subcap_tpl)


def summarize_missing_wim_images(section: dict) -> list[str]:
    missing: list[str] = []
    if not section.get("enabled"):
        return missing
    for item in section.get("month_summaries", []):
        expected = 6
        actual = len(item.plot_paths)
        if actual >= expected:
            continue
        found_labels = {label for label, _ in item.plot_paths}
        for label, _pattern in [
            ("(a) 不同车道车辆数", None),
            ("(b) 不同车速车辆数", None),
            ("(c) 不同重量车辆数", None),
            ("(d) 不同时间段车辆总数", None),
            ("(e) 不同时间段平均车速", None),
            ("(f) 大于50t车辆时间分布", None),
        ]:
            if label not in found_labels:
                missing.append(f"wim:{item.yyyymm}:{label}")
    return missing


def build_period_report(
    template: Path,
    config_path: Path,
    result_root: Path,
    analysis_root: Path | None = None,
    image_root: Path | None = None,
    wim_root: Path | None = None,
    output_dir: Path | None = None,
    period_label: str = "2026年1-3月",
    monitoring_range: str = "2026.01.01~2026.03.16",
    report_date: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
) -> tuple[Path, Path, list[str]]:
    if analysis_root is None:
        analysis_root = Path(__file__).resolve().parents[1]
    if report_date is None:
        report_date = datetime.now().strftime("%Y年%m月%d日")

    if start_date and end_date:
        start_dt = parse_date_str(start_date)
        end_dt = parse_date_str(end_date)
    else:
        extracted = extract_dates_from_range(monitoring_range)
        if extracted is None:
            raise ValueError("Unable to derive start/end dates. Provide --start-date and --end-date.")
        start_dt, end_dt = extracted

    stats_root = result_root
    fallback_stats_root = analysis_root if result_root != analysis_root else None
    image_root = image_root if image_root is not None else result_root
    output_dir = output_dir if output_dir is not None else (result_root / "自动报告")
    output_dir = ensure_dir(output_dir)
    assets_dir = ensure_dir(output_dir / "generated_assets")

    cfg = load_json(config_path)
    manifest = build_manifest(cfg, stats_root, fallback_stats_root, image_root, template, assets_dir, period_label, monitoring_range, report_date)
    wim_months = months_between(start_dt, end_dt)
    manifest["wim"] = build_wim_period_section(resolve_wim_root(result_root, analysis_root, wim_root), wim_months)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    manifest_path = output_dir / f"period_report_manifest_{timestamp}.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")

    doc = Document(str(template))
    apply_manifest_to_doc(doc, manifest)
    apply_wim_period_to_doc(doc, manifest["wim"])

    output_docx = output_dir / f"{template.stem}_周期报_{timestamp}.docx"
    doc.save(str(output_docx))

    missing = summarize_missing_images(manifest) + summarize_missing_wim_images(manifest["wim"])
    warnings = manifest["wim"].get("warnings", [])
    missing.extend(f"warning:{msg}" for msg in warnings)
    return manifest_path, output_docx, missing


def _json_default(value):
    if is_dataclass(value):
        return asdict(value)
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    raise TypeError(f"Object of type {value.__class__.__name__} is not JSON serializable")


def main() -> None:
    args = parse_args()
    if args.template is None or not args.template.exists():
        raise SystemExit("Template docx not found.")
    if not args.config.exists():
        raise SystemExit("Config file not found.")
    if not args.result_root.exists():
        raise SystemExit("Result root not found.")

    manifest_path, report_path, missing = build_period_report(
        template=args.template,
        config_path=args.config,
        result_root=args.result_root,
        analysis_root=args.analysis_root,
        image_root=args.image_root,
        wim_root=args.wim_root,
        output_dir=args.output_dir,
        period_label=args.period_label,
        monitoring_range=args.monitoring_range,
        report_date=args.report_date,
        start_date=args.start_date,
        end_date=args.end_date,
    )
    print(f"Manifest written to: {manifest_path}")
    print(f"Report written to:   {report_path}")
    if missing:
        print("Warnings / missing assets:")
        for item in missing:
            print(f"  - {item}")


if __name__ == "__main__":
    main()
