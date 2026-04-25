from __future__ import annotations

import argparse
import json
from dataclasses import asdict, is_dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Iterable

from docx import Document
from docx.shared import Mm
from openpyxl import load_workbook

from build_monthly_report import (
    SECTION_TITLES,
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
    capture_wim_table_templates,
    clear_section_between,
    find_last_paragraph,
    insert_table_before,
    make_quarter_summary,
    parse_month_summary,
    resolve_wim_thresholds,
    set_summary_table,
    set_header_bold,
    set_table_column_widths,
    style_table,
)
from template_precheck import raise_for_template
from missing_summary import write_missing_summary


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


def default_period_template(repo_root: Path) -> Path:
    reports_dir = repo_root / "reports"
    candidates = [
        reports_dir / "洪塘大桥健康监测2026年第一季季报-改4.docx",
        reports_dir / "洪塘大桥健康监测周期报模板-自动报告.docx",
        reports_dir / "洪塘大桥健康监测周期报模板0318.docx",
        reports_dir / "洪塘大桥健康监测周期报模板.docx",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    default_template = default_period_template(repo_root)
    parser = argparse.ArgumentParser(description="Build full period monitoring report, including WIM.")
    parser.add_argument("--template", type=Path, default=default_template)
    parser.add_argument("--config", type=Path, default=repo_root / "config" / "hongtang_config.json")
    parser.add_argument("--result-root", type=Path, required=True)
    parser.add_argument("--analysis-root", type=Path, default=repo_root)
    parser.add_argument("--image-root", type=Path, default=None)
    parser.add_argument("--wim-root", type=Path, default=None, help="Processed monthly WIM result root, e.g. <result-root>/WIM/results/hongtang")
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--period-label", default="2026年1-3月")
    parser.add_argument("--monitoring-range", default="2026年01月01日~2026年03月31日")
    parser.add_argument("--report-date", default=datetime.now().strftime("%Y年%m月%d日"))
    parser.add_argument("--start-date", default="2026-01-01")
    parser.add_argument("--end-date", default="2026-03-31")
    parser.add_argument(
        "--debug-section",
        default=None,
        help="Print a generated manifest section for debugging, e.g. cable_force, vibration, wim, health_status.",
    )
    parser.add_argument("--skip-template-precheck", action="store_true", help="Skip DOCX template anchor precheck.")
    return parser.parse_args()


def parse_date_str(text: str) -> date:
    return datetime.strptime(text, "%Y-%m-%d").date()


def extract_dates_from_range(text: str) -> tuple[date, date] | None:
    import re

    pattern = re.compile(r"(\d{4})[年.-](\d{1,2})[月.-](\d{1,2})日?.*?(\d{4})[年.-](\d{1,2})[月.-](\d{1,2})日?")
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


def build_wim_period_section(wim_root: Path, months: list[str], cfg: dict | None = None) -> dict:
    thresholds = resolve_wim_thresholds(cfg)
    summaries = []
    warnings: list[str] = []
    for yyyymm in months:
        month_dir = wim_root / yyyymm
        if not month_dir.exists():
            warnings.append(f"Missing WIM month directory: {month_dir}")
            continue
        summaries.append(parse_month_summary(wim_root, yyyymm, thresholds))
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


def insert_table_after(paragraph, rows: int, cols: int):
    body = paragraph._parent
    table = body.add_table(rows=rows, cols=cols, width=Mm(160))
    paragraph._p.addnext(table._tbl)
    return table


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


def _parse_range_bounds(range_text: str) -> tuple[date, date]:
    parts = range_text.split("~", 1)
    start_part = parts[0][:10]
    end_part = (parts[1][:10] if len(parts) == 2 else parts[0][:10])
    return (
        datetime.strptime(start_part, "%Y-%m-%d").date(),
        datetime.strptime(end_part, "%Y-%m-%d").date(),
    )


def _format_range_short(range_text: str) -> str:
    start_day, end_day = _parse_range_bounds(range_text)
    if start_day == end_day:
        return start_day.strftime("%Y-%m-%d")
    if start_day.year == end_day.year and start_day.month == end_day.month:
        return f"{start_day:%Y-%m-%d}~{end_day:%m-%d}"
    return f"{start_day:%Y-%m-%d}~{end_day:%Y-%m-%d}"


def _point_sort_key(point: str) -> tuple[int, str]:
    import re

    tokens = re.split(r"(\d+)", point)
    key: list[object] = []
    for token in tokens:
        if not token:
            continue
        key.append(int(token) if token.isdigit() else token)
    return (0, str(key))


def _join_points(points: Iterable[str], max_names: int = 4) -> str:
    ordered = sorted(dict.fromkeys(points), key=_point_sort_key)
    if len(ordered) <= max_names:
        return "、".join(ordered)
    return f"{'、'.join(ordered[:max_names])}等{len(ordered)}个测点"


def _join_module_names(names: Iterable[str]) -> str:
    ordered = []
    for module in list(LOWFREQ_MODULES.values()) + list(HIGHFREQ_MODULES.values()):
        if module in names and module not in ordered:
            ordered.append(module)
    return "、".join(ordered)


def _summarize_ranges(range_texts: Iterable[str], max_ranges: int = 3) -> str:
    ordered = sorted(dict.fromkeys(range_texts), key=_parse_range_bounds)
    formatted = [_format_range_short(item) for item in ordered]
    if not formatted:
        return ""
    if len(formatted) <= max_ranges:
        return "、".join(formatted)
    return f"{'、'.join(formatted[:max_ranges])}等{len(formatted)}段时段"


def _full_period_text(start_date: date, end_date: date) -> str:
    return _format_dt_range(datetime.combine(start_date, datetime.min.time()), datetime.combine(end_date, datetime.max.time()))


def _summarize_lowfreq_module(module: str, module_events: list[dict], start_date: date, end_date: date) -> str:
    full_period = _full_period_text(start_date, end_date)
    reason_priority = {"原始记录缺失": 0, "lowfreq/data.xlsx 缺失": 1, "lowfreq 数据期内无原始记录": 2}
    grouped_by_range: dict[tuple[str, str], set[str]] = {}
    for event in module_events:
        grouped_by_range.setdefault((event["range"], event["reason"]), set()).update(event["points"])

    grouped: dict[tuple[tuple[str, ...], str], list[str]] = {}
    for (range_text, reason), points in grouped_by_range.items():
        point_key = tuple(sorted(points, key=_point_sort_key))
        grouped.setdefault((point_key, reason), []).append(range_text)

    persistent_parts: list[str] = []
    intermittent_parts: list[str] = []
    for (points, reason), ranges in sorted(
        grouped.items(),
        key=lambda item: (reason_priority.get(item[0][1], 99), -len(item[0][0]), item[0][0]),
    ):
        unique_ranges = sorted(dict.fromkeys(ranges), key=_parse_range_bounds)
        point_text = _join_points(points)
        if len(unique_ranges) == 1 and unique_ranges[0] == full_period:
            if points == ("全测点",):
                persistent_parts.append(reason)
            else:
                persistent_parts.append(f"{point_text}全周期{reason}")
            continue
        range_text = _summarize_ranges(unique_ranges)
        if points == ("全测点",):
            intermittent_parts.append(f"{range_text}{reason}")
        else:
            intermittent_parts.append(f"{point_text}在{range_text}{reason}")

    parts: list[str] = []
    if persistent_parts:
        parts.append("；".join(persistent_parts))
    if intermittent_parts:
        parts.append("；".join(intermittent_parts))
    if not parts:
        return ""
    return f"{module}中，" + "；".join(parts)


def _summarize_highfreq_events(module_events: list[dict]) -> str:
    if not module_events:
        return ""

    range_reason_modules: dict[tuple[str, str], dict[str, set[str]]] = {}
    for event in module_events:
        key = (event["range"], event["reason"])
        bucket = range_reason_modules.setdefault(key, {})
        bucket.setdefault(event["module"], set()).update(event["points"])

    common_parts: list[str] = []
    common_keys: set[tuple[str, str]] = set()
    for (range_text, reason), modules in sorted(range_reason_modules.items(), key=lambda item: _parse_range_bounds(item[0][0])):
        if len(modules) < 2:
            continue
        common_keys.add((range_text, reason))
        common_parts.append(f"{_format_range_short(range_text)}出现{reason}，影响{_join_module_names(modules.keys())}")

    residual_by_module: dict[str, list[tuple[str, str, set[str]]]] = {}
    for (range_text, reason), modules in range_reason_modules.items():
        if (range_text, reason) in common_keys:
            continue
        for module, points in modules.items():
            residual_by_module.setdefault(module, []).append((range_text, reason, points))

    residual_parts: list[str] = []
    for module in HIGHFREQ_MODULES.values():
        entries = residual_by_module.get(module, [])
        if not entries:
            continue
        grouped: dict[tuple[tuple[str, ...], str], list[str]] = {}
        for range_text, reason, points in entries:
            grouped.setdefault((tuple(sorted(points, key=_point_sort_key)), reason), []).append(range_text)
        module_parts = []
        for (points, reason), ranges in sorted(grouped.items(), key=lambda item: _parse_range_bounds(item[1][0])):
            point_text = _join_points(points)
            range_text = _summarize_ranges(ranges)
            module_parts.append(f"{point_text}在{range_text}{reason}")
        residual_parts.append(f"{module}中，" + "；".join(module_parts))

    parts: list[str] = []
    if common_parts:
        parts.append("高频监测系统在" + "；".join(common_parts))
    if residual_parts:
        parts.append("此外，" + "；".join(residual_parts))
    return "。".join(parts)


def _build_lowfreq_health_rows(module: str, module_events: list[dict], start_date: date, end_date: date) -> list[dict[str, str]]:
    full_period = _full_period_text(start_date, end_date)
    grouped_by_range: dict[tuple[str, str], set[str]] = {}
    for event in module_events:
        grouped_by_range.setdefault((event["range"], event["reason"]), set()).update(event["points"])

    grouped: dict[tuple[tuple[str, ...], str], list[str]] = {}
    for (range_text, reason), points in grouped_by_range.items():
        grouped.setdefault((tuple(sorted(points, key=_point_sort_key)), reason), []).append(range_text)

    rows: list[dict[str, str]] = []
    for (points, reason), ranges in sorted(grouped.items(), key=lambda item: (_parse_range_bounds(item[1][0])[0], item[0][0])):
        unique_ranges = sorted(dict.fromkeys(ranges), key=_parse_range_bounds)
        rows.append(
            {
                "module": module,
                "points": "全测点" if points == ("全测点",) else _join_points(points, max_names=6),
                "range": "全周期" if len(unique_ranges) == 1 and unique_ranges[0] == full_period else _summarize_ranges(unique_ranges, max_ranges=4),
                "reason": reason,
            }
        )
    return rows


def _build_highfreq_health_rows(module_events: list[dict]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    range_reason_modules: dict[tuple[str, str], dict[str, set[str]]] = {}
    for event in module_events:
        key = (event["range"], event["reason"])
        range_reason_modules.setdefault(key, {}).setdefault(event["module"], set()).update(event["points"])

    common_keys: set[tuple[str, str]] = set()
    for (range_text, reason), modules in sorted(range_reason_modules.items(), key=lambda item: _parse_range_bounds(item[0][0])):
        if len(modules) < 2:
            continue
        common_keys.add((range_text, reason))
        rows.append(
            {
                "module": _join_module_names(modules.keys()),
                "points": "相关测点",
                "range": _format_range_short(range_text),
                "reason": reason,
            }
        )

    residual_by_module: dict[str, list[tuple[str, str, set[str]]]] = {}
    for (range_text, reason), modules in range_reason_modules.items():
        if (range_text, reason) in common_keys:
            continue
        for module, points in modules.items():
            residual_by_module.setdefault(module, []).append((range_text, reason, points))

    for module in HIGHFREQ_MODULES.values():
        entries = residual_by_module.get(module, [])
        if not entries:
            continue
        grouped: dict[tuple[tuple[str, ...], str], list[str]] = {}
        for range_text, reason, points in entries:
            grouped.setdefault((tuple(sorted(points, key=_point_sort_key)), reason), []).append(range_text)
        for (points, reason), ranges in sorted(grouped.items(), key=lambda item: _parse_range_bounds(item[1][0])):
            rows.append(
                {
                    "module": module,
                    "points": _join_points(points, max_names=6),
                    "range": _summarize_ranges(ranges, max_ranges=4),
                    "reason": reason,
                }
            )
    return rows


def build_health_status_rows(cfg: dict, result_root: Path, start_date: date, end_date: date) -> list[dict[str, str]]:
    lowfreq_events = collect_lowfreq_missing_events(cfg, result_root, start_date, end_date)
    highfreq_events = collect_highfreq_missing_events(cfg, result_root, start_date, end_date)

    rows: list[dict[str, str]] = []
    for module in LOWFREQ_MODULES.values():
        module_events = [event for event in lowfreq_events if event["module"] == module]
        rows.extend(_build_lowfreq_health_rows(module, module_events, start_date, end_date))
    rows.extend(_build_highfreq_health_rows(highfreq_events))
    return rows


def build_report_missing_rows(manifest: dict, wim_section: dict) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for key, title in SECTION_TITLES.items():
        section = manifest.get("sections", {}).get(key, {})
        if not section.get("enabled", True):
            continue
        if section.get("available", True):
            continue
        rows.append(
            {
                "module": title,
                "points": "-",
                "range": "本周期",
                "reason": "本周期未获取到有效数据",
            }
        )

    if not wim_section.get("enabled"):
        rows.append(
            {
                "module": "交通状况监测",
                "points": "-",
                "range": "本周期",
                "reason": "本周期未获取到有效数据",
            }
        )
        return rows

    available_months = {item.yyyymm for item in wim_section.get("month_summaries", [])}
    missing_months = [month for month in wim_section.get("months", []) if month not in available_months]
    if missing_months:
        rows.append(
            {
                "module": "交通状况监测",
                "points": "-",
                "range": "、".join(missing_months),
                "reason": "部分月份WIM结果缺失",
            }
        )
    return rows


def merge_health_status_summary(summary_text: str, missing_rows: list[dict[str, str]]) -> str:
    if not missing_rows:
        return summary_text
    extra = "此外，部分监测内容缺失，详见下表。"
    if not summary_text or "未发现原始数据缺失" in summary_text:
        return extra
    return summary_text.rstrip("。") + "。" + extra


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
    lowfreq_events = collect_lowfreq_missing_events(cfg, result_root, start_date, end_date)
    highfreq_events = collect_highfreq_missing_events(cfg, result_root, start_date, end_date)
    if not lowfreq_events and not highfreq_events:
        return "监测周期内未发现原始数据缺失、无文件或无记录情况。"

    parts: list[str] = []
    if lowfreq_events:
        lowfreq_parts = []
        for module in LOWFREQ_MODULES.values():
            module_events = [event for event in lowfreq_events if event["module"] == module]
            text = _summarize_lowfreq_module(module, module_events, start_date, end_date)
            if text:
                lowfreq_parts.append(text)
        if lowfreq_parts:
            parts.append("低频监测系统存在持续性和阶段性原始记录缺失。" + "；".join(lowfreq_parts) + "。")

    highfreq_text = _summarize_highfreq_events(highfreq_events)
    if highfreq_text:
        parts.append(highfreq_text + "。")

    return "监测周期内原始数据缺失、无文件或无记录情况见下表。"


def apply_health_status_to_doc(doc: Document, summary_text: str, rows: list[dict[str, str]]) -> None:
    paragraph = _next_nonempty_paragraph_after(doc, "健康监测系统运行状况")
    if not rows:
        return
    table = insert_table_after(paragraph, rows=len(rows) + 1, cols=4)
    headers = ["监测项目", "异常测点/测点组", "时间段", "异常类型"]
    for idx, header in enumerate(headers):
        table.cell(0, idx).text = header
    for ridx, row in enumerate(rows, start=1):
        values = [row["module"], row["points"], row["range"], row["reason"]]
        for cidx, value in enumerate(values):
            table.cell(ridx, cidx).text = value
    style_table(table, left=True)
    set_header_bold(table)
    set_table_column_widths(table, [28, 66, 42, 24])


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
    table_templates = capture_wim_table_templates(wim_heading, next_heading)
    heading_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "2026年3月交通状况监测"))
    body_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "桥梁共通过车辆"))
    caption_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "季度交通状况分月统计表"))
    subcap_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "续表 4-3"))
    fig_tpl = capture_paragraph_template(find_last_paragraph_contains(doc, "桥梁交通流参数分析"))

    clear_section_between(wim_heading, next_heading)
    add_text_paragraph_before(next_heading, summary_text, body_tpl)
    add_quarter_overview(next_heading, summaries, caption_tpl, table_templates)
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
            table_templates=table_templates,
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
    monitoring_range: str = "2026年01月01日~2026年03月31日",
    report_date: str | None = None,
    start_date: str | None = None,
    end_date: str | None = None,
    precheck_template: bool = True,
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
    try:
        resolved_wim_root = resolve_wim_root(result_root, analysis_root, wim_root)
        manifest["wim"] = build_wim_period_section(resolved_wim_root, wim_months, cfg)
    except FileNotFoundError as exc:
        fallback_wim_root = wim_root if wim_root is not None else (result_root / "WIM" / "results" / "hongtang")
        manifest["wim"] = {
            "enabled": False,
            "wim_root": str(fallback_wim_root),
            "months": wim_months,
            "warnings": [str(exc)],
            "summary": "",
            "month_summaries": [],
        }
    raw_health_summary = build_health_status_summary(cfg, result_root, start_dt, end_dt)
    raw_health_rows = build_health_status_rows(cfg, result_root, start_dt, end_dt)
    missing_rows = build_report_missing_rows(manifest, manifest["wim"])
    manifest["health_status_summary"] = merge_health_status_summary(raw_health_summary, missing_rows)
    manifest["health_status_rows"] = raw_health_rows + missing_rows

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    manifest_path = output_dir / f"period_report_manifest_{timestamp}.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2, default=_json_default) + "\n", encoding="utf-8")

    if precheck_template:
        raise_for_template("hongtang_period", template, manifest)

    doc = Document(str(template))
    apply_manifest_to_doc(doc, manifest)
    apply_health_status_to_doc(doc, manifest["health_status_summary"], manifest["health_status_rows"])
    apply_wim_period_to_doc(doc, manifest["wim"])

    output_docx = output_dir / f"{template.stem}_周期报_{timestamp}.docx"
    doc.save(str(output_docx))

    missing = summarize_missing_images(manifest) + summarize_missing_wim_images(manifest["wim"])
    warnings = manifest["wim"].get("warnings", [])
    missing.extend(f"warning:{msg}" for msg in warnings)
    write_missing_summary(
        "洪塘周期报",
        output_docx,
        missing,
        context={"manifest": str(manifest_path), "result_root": str(result_root), "wim_root": str(wim_root or "")},
    )
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
        precheck_template=not args.skip_template_precheck,
    )
    print(f"Manifest written to: {manifest_path}")
    print(f"Report written to:   {report_path}")
    if args.debug_section:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        key = args.debug_section
        if key == "wim":
            payload = manifest.get("wim", {})
        elif key == "health_status":
            payload = {
                "summary": manifest.get("health_status_summary", ""),
                "rows": manifest.get("health_status_rows", []),
            }
        else:
            payload = manifest.get("sections", {}).get(key, {})
        print(f"Debug section [{key}]:")
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    if missing:
        print("Warnings / missing assets:")
        for item in missing:
            print(f"  - {item}")


if __name__ == "__main__":
    main()
