from __future__ import annotations

import argparse
import json
from dataclasses import asdict, is_dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable

from docx import Document
from openpyxl import load_workbook

from build_monthly_report import (
    apply_manifest_to_doc,
    build_manifest,
    ensure_dir,
    load_json,
    replace_paragraph_text,
    summarize_missing_images,
)
from build_quarterly_wim_sample import (
    T_NEXT,
    T_WIM,
    add_month_block,
    add_quarter_overview,
    add_text_paragraph_before,
    capture_paragraph_template,
    clear_section_between,
    find_last_paragraph,
    make_quarter_summary,
    parse_month_summary,
    set_summary_table,
)


LOWFREQ_MODULES = {
    "strain": "结构应变监测",
    "tilt": "主塔倾斜监测",
    "bearing_displacement": "支座变位监测",
}

HIGHFREQ_MODULES = {
    "cable_accel": "吊索索力监测",
    "acceleration": "主梁、主塔振动监测",
    "wind": "风向风速监测",
    "eq": "地震动监测",
}


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    default_template = repo_root / "reports" / "洪塘大桥健康监测周期报模板0318.docx"
    parser = argparse.ArgumentParser(description="Build full period monitoring report, including WIM.")
    parser.add_argument("--template", type=Path, default=default_template)
    parser.add_argument("--config", type=Path, default=repo_root / "config" / "hongtang_config.json")
    parser.add_argument("--result-root", type=Path, required=True)
    parser.add_argument("--analysis-root", type=Path, default=repo_root)
    parser.add_argument("--image-root", type=Path, default=None)
    parser.add_argument("--wim-root", type=Path, default=None, help="Processed monthly WIM result root, e.g. <result-root>/WIM/results/hongtang")
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
    import re

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


def _next_nonempty_paragraph_after(doc: Document, heading_text: str) -> object:
    paragraphs = doc.paragraphs
    for idx, para in enumerate(paragraphs):
        if para.text.strip() == heading_text:
            for nxt in paragraphs[idx + 1 :]:
                if nxt.text.strip():
                    return nxt
            break
    raise ValueError(f'Paragraph after "{heading_text}" not found')


def _normalize_missing_value(value: object) -> bool:
    if value is None:
        return True
    if isinstance(value, str):
        stripped = value.strip()
        return stripped == "" or stripped == "--"
    return False


def _iter_days(start_date: date, end_date: date) -> Iterable[date]:
    current = start_date
    while current <= end_date:
        yield current
        current += timedelta(days=1)


def _group_datetime_ranges(timestamps: list[datetime], missing_flags: list[bool]) -> list[tuple[datetime, datetime]]:
    ranges: list[tuple[datetime, datetime]] = []
    start_ts: datetime | None = None
    prev_ts: datetime | None = None
    for ts, missing in zip(timestamps, missing_flags):
        if missing:
            if start_ts is None:
                start_ts = ts
            prev_ts = ts
            continue
        if start_ts is not None and prev_ts is not None:
            ranges.append((start_ts, prev_ts))
            start_ts = None
            prev_ts = None
    if start_ts is not None and prev_ts is not None:
        ranges.append((start_ts, prev_ts))
    return ranges


def _group_date_ranges(days: list[date]) -> list[tuple[date, date]]:
    if not days:
        return []
    sorted_days = sorted(set(days))
    ranges: list[tuple[date, date]] = []
    start_day = sorted_days[0]
    prev_day = sorted_days[0]
    for current in sorted_days[1:]:
        if current == prev_day + timedelta(days=1):
            prev_day = current
            continue
        ranges.append((start_day, prev_day))
        start_day = current
        prev_day = current
    ranges.append((start_day, prev_day))
    return ranges


def _format_dt_range(start_dt: datetime, end_dt: datetime) -> str:
    if start_dt == end_dt:
        return start_dt.strftime("%Y-%m-%d %H:%M:%S")
    return f"{start_dt:%Y-%m-%d %H:%M:%S}~{end_dt:%Y-%m-%d %H:%M:%S}"


def _format_day_range(start_day: date, end_day: date) -> str:
    if start_day == end_day:
        return start_day.strftime("%Y-%m-%d")
    return f"{start_day:%Y-%m-%d}~{end_day:%Y-%m-%d}"


def _pattern_for_point(cfg: dict, module: str, point_id: str, file_id: str | None = None) -> str:
    patterns = cfg.get("file_patterns", {}).get(module, {})
    per_point = patterns.get("per_point", {})
    pattern = per_point.get(point_id)
    if pattern is None:
        default_patterns = patterns.get("default") or []
        if not default_patterns:
            raise KeyError(f"No file pattern configured for module={module}, point={point_id}")
        pattern = default_patterns[0]
    return pattern.format(point=point_id, file_id=file_id or "")


def _csv_has_records(path: Path) -> bool:
    if not path.exists() or path.stat().st_size <= 0:
        return False
    with path.open("r", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            if line.strip():
                return True
    return False


def collect_lowfreq_missing_events(cfg: dict, result_root: Path, start_date: date, end_date: date) -> list[dict]:
    workbook = result_root / "lowfreq" / "data.xlsx"
    points_by_module = {key: cfg.get("points", {}).get(key, []) for key in LOWFREQ_MODULES}
    start_dt = datetime.combine(start_date, datetime.min.time())
    end_dt = datetime.combine(end_date, datetime.max.time())
    events: list[dict] = []
    if not workbook.exists():
        for module, label in LOWFREQ_MODULES.items():
            if points_by_module.get(module):
                events.append(
                    {
                        "module": label,
                        "points": ["全测点"],
                        "range": _format_dt_range(start_dt, end_dt),
                        "reason": "lowfreq/data.xlsx 缺失",
                    }
                )
        return events

    wb = load_workbook(workbook, read_only=True, data_only=True)
    ws = wb.active
    rows = ws.iter_rows(values_only=True)
    headers = list(next(rows))
    header_index = {str(name).strip(): idx for idx, name in enumerate(headers) if name is not None}
    timestamps: list[datetime] = []
    missing_days_by_point: dict[str, set[date]] = {}
    for module_points in points_by_module.values():
        for point in module_points:
            missing_days_by_point[point] = set()

    for row in rows:
        ts = row[0]
        if ts is None:
            continue
        if isinstance(ts, datetime):
            dt = ts
        else:
            try:
                dt = datetime.fromisoformat(str(ts))
            except ValueError:
                continue
        if dt < start_dt or dt > end_dt:
            continue
        timestamps.append(dt)
        for point in missing_days_by_point:
            col_idx = header_index.get(point)
            is_missing = col_idx is None or col_idx >= len(row) or _normalize_missing_value(row[col_idx])
            if is_missing:
                missing_days_by_point[point].add(dt.date())
    wb.close()

    if not timestamps:
        for module, label in LOWFREQ_MODULES.items():
            if points_by_module.get(module):
                events.append(
                    {
                        "module": label,
                        "points": ["全测点"],
                        "range": _format_dt_range(start_dt, end_dt),
                        "reason": "lowfreq 数据期内无原始记录",
                    }
                )
        return events

    for module, label in LOWFREQ_MODULES.items():
        for point in points_by_module.get(module, []):
            ranges = _group_date_ranges(sorted(missing_days_by_point.get(point, set())))
            for start_day, end_day in ranges:
                events.append(
                    {
                        "module": label,
                        "points": [point],
                        "range": _format_day_range(start_day, end_day),
                        "reason": "原始记录缺失",
                    }
                )
    return events


def collect_highfreq_missing_events(cfg: dict, result_root: Path, start_date: date, end_date: date) -> list[dict]:
    events: list[dict] = []
    subfolders = cfg.get("subfolders", {})
    points_cfg = cfg.get("points", {})
    file_patterns = cfg.get("file_patterns", {})

    def add_events(module_label: str, point_label: str, days: list[date], reason: str) -> None:
        for start_day, end_day in _group_date_ranges(days):
            events.append(
                {
                    "module": module_label,
                    "points": [point_label],
                    "range": _format_day_range(start_day, end_day),
                    "reason": reason,
                }
            )

    # acceleration and cable acceleration
    for module in ("acceleration", "cable_accel"):
        module_label = HIGHFREQ_MODULES[module]
        day_missing: dict[tuple[str, str], list[date]] = {}
        folder_name = subfolders.get(module)
        if not folder_name:
            continue
        for current_day in _iter_days(start_date, end_date):
            raw_dir = result_root / current_day.strftime("%Y-%m-%d") / folder_name
            for point in points_cfg.get(module, []):
                key = (point, "原始文件缺失")
                if not raw_dir.exists():
                    day_missing.setdefault(key, []).append(current_day)
                    continue
                pattern = _pattern_for_point(cfg, module, point)
                matches = list(raw_dir.glob(pattern))
                if not matches:
                    day_missing.setdefault(key, []).append(current_day)
                    continue
                if not any(_csv_has_records(path) for path in matches):
                    day_missing.setdefault((point, "无原始记录"), []).append(current_day)
        for (point, reason), days in day_missing.items():
            add_events(module_label, point, days, reason)

    # wind speed / direction
    wind_folder = subfolders.get("wind_raw") or subfolders.get("wind")
    if wind_folder:
        day_missing: dict[tuple[str, str], list[date]] = {}
        for current_day in _iter_days(start_date, end_date):
            raw_dir = result_root / current_day.strftime("%Y-%m-%d") / wind_folder
            for point, point_cfg in cfg.get("per_point", {}).get("wind", {}).items():
                for suffix, field, module_key in (("风速", "speed_point_id", "wind_speed"), ("风向", "dir_point_id", "wind_direction")):
                    label = f"{point}-{suffix}"
                    file_id = point_cfg.get(field)
                    if not file_id:
                        continue
                    key = (label, "原始文件缺失")
                    if not raw_dir.exists():
                        day_missing.setdefault(key, []).append(current_day)
                        continue
                    pattern = _pattern_for_point(cfg, module_key, point, file_id=file_id)
                    matches = list(raw_dir.glob(pattern))
                    if not matches:
                        day_missing.setdefault(key, []).append(current_day)
                        continue
                    if not any(_csv_has_records(path) for path in matches):
                        day_missing.setdefault((label, "无原始记录"), []).append(current_day)
        for (point, reason), days in day_missing.items():
            add_events(HIGHFREQ_MODULES["wind"], point, days, reason)

    # earthquake
    eq_folder = subfolders.get("eq_raw") or subfolders.get("eq")
    if eq_folder:
        day_missing: dict[tuple[str, str], list[date]] = {}
        for current_day in _iter_days(start_date, end_date):
            raw_dir = result_root / current_day.strftime("%Y-%m-%d") / eq_folder
            for point, point_cfg in cfg.get("per_point", {}).get("eq", {}).items():
                file_id = point_cfg.get("file_id")
                if not file_id:
                    continue
                key = (point, "原始文件缺失")
                if not raw_dir.exists():
                    day_missing.setdefault(key, []).append(current_day)
                    continue
                module_key = point.lower().replace("-", "_")
                pattern = _pattern_for_point(cfg, module_key, point, file_id=file_id)
                matches = list(raw_dir.glob(pattern))
                if not matches:
                    day_missing.setdefault(key, []).append(current_day)
                    continue
                if not any(_csv_has_records(path) for path in matches):
                    day_missing.setdefault((point, "无原始记录"), []).append(current_day)
        for (point, reason), days in day_missing.items():
            add_events(HIGHFREQ_MODULES["eq"], point, days, reason)

    return events


def build_health_status_summary(cfg: dict, result_root: Path, start_date: date, end_date: date) -> str:
    events = collect_lowfreq_missing_events(cfg, result_root, start_date, end_date)
    events.extend(collect_highfreq_missing_events(cfg, result_root, start_date, end_date))
    if not events:
        return "监测周期内未发现原始数据缺失、无文件或无记录情况。"

    grouped: dict[str, dict[tuple[str, str], set[str]]] = {}
    for event in events:
        module = event["module"]
        grouped.setdefault(module, {})
        key = (event["range"], event["reason"])
        grouped[module].setdefault(key, set()).update(event["points"])

    parts: list[str] = []
    for module in list(LOWFREQ_MODULES.values()) + list(HIGHFREQ_MODULES.values()):
        bucket = grouped.get(module)
        if not bucket:
            continue
        item_texts = []
        for (range_text, reason), points in sorted(bucket.items(), key=lambda x: x[0][0]):
            points_text = "、".join(sorted(points))
            item_texts.append(f"{points_text}（{range_text}，{reason}）")
        parts.append(f"{module}：{'；'.join(item_texts)}")
    return "监测周期内原始数据缺失/无文件/无记录情况如下：" + "；".join(parts) + "。"


def apply_health_status_to_doc(doc: Document, summary_text: str) -> None:
    paragraph = _next_nonempty_paragraph_after(doc, "健康监测系统运行状况")
    replace_paragraph_text(paragraph, summary_text)


def find_last_paragraph_contains(doc: Document, fragment: str):
    matches = [para for para in doc.paragraphs if fragment in para.text.strip()]
    if not matches:
        raise ValueError(f"Paragraph containing '{fragment}' not found")
    return matches[-1]


def apply_wim_period_to_doc(doc: Document, section: dict) -> None:
    if not section.get("enabled"):
        return

    summaries = section["month_summaries"]
    summary_text = section["summary"]

    set_summary_table(doc, summary_text)

    wim_heading = find_last_paragraph(doc, T_WIM)
    next_heading = find_last_paragraph(doc, T_NEXT)
    heading_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "2026年3月交通状况监测"))
    body_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "桥梁共通过车辆"))
    caption_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "季度交通状况分月统计表"))
    subcap_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "续表 4-3"))
    fig_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "桥梁交通流参数分析"))

    clear_section_between(wim_heading, next_heading)
    add_text_paragraph_before(next_heading, summary_text, body_tpl)
    add_quarter_overview(next_heading, summaries, caption_tpl)
    for idx, item in enumerate(summaries, start=1):
        add_month_block(
            next_heading,
            item,
            heading_tpl,
            body_tpl,
            caption_tpl,
            fig_tpl,
            subcap_tpl,
            section_index=idx,
            base_table_no=2 + (idx - 1) * 3,
            figure_no=idx,
        )


def summarize_missing_wim_images(section: dict) -> list[str]:
    missing: list[str] = []
    if not section.get("enabled"):
        return missing
    expected_labels = {
        "(a) 不同车道车辆数",
        "(b) 不同车速车辆数",
        "(c) 不同重量车辆数",
        "(d) 不同时间段车辆总数",
        "(e) 不同时间段平均车速",
        "(f) 大于50t车辆时间分布",
    }
    for item in section.get("month_summaries", []):
        found_labels = {label for label, _ in item.plot_paths}
        for label in sorted(expected_labels - found_labels):
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
    manifest["health_status_summary"] = build_health_status_summary(cfg, result_root, start_dt, end_dt)
    wim_months = months_between(start_dt, end_dt)
    manifest["wim"] = build_wim_period_section(resolve_wim_root(result_root, analysis_root, wim_root), wim_months)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    manifest_path = output_dir / f"period_report_manifest_{timestamp}.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")

    doc = Document(str(template))
    apply_manifest_to_doc(doc, manifest)
    apply_health_status_to_doc(doc, manifest["health_status_summary"])
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
