from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
from copy import deepcopy
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Callable, Iterable

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Mm, Pt
from docx.table import Table
from docx.text.paragraph import Paragraph
from openpyxl import load_workbook
from PIL import Image, ImageDraw, ImageFont, ImageOps


@dataclass
class ImageItem:
    label: str
    path: Path | None


@dataclass
class ParagraphTemplate:
    style_name: str | None
    alignment: WD_ALIGN_PARAGRAPH | None
    left_indent: object
    right_indent: object
    first_line_indent: object
    space_before: object
    space_after: object
    line_spacing: object
    line_spacing_rule: object
    keep_together: object
    keep_with_next: object
    page_break_before: object
    widow_control: object
    run_bold: bool | None
    run_italic: bool | None
    run_underline: object
    run_font_name: str | None
    run_font_size: object


@dataclass
class CaptionTemplates:
    figure_paragraph: Paragraph
    table_paragraph: Paragraph


@dataclass
class SectionContent:
    narrative: str
    summary_sentence: str
    table_title: str | None = None
    table_columns: list[tuple[str, str, float | None]] | None = None
    table_rows: list[dict] | None = None
    figure_title: str | None = None
    image_items: list[ImageItem] | None = None
    table_width_mm: float | None = None
    table_font_size_pt: int | None = None
    available: bool = True
    blocks: list["SectionBlock"] | None = None


@dataclass
class SectionBlock:
    narrative: str = ""
    table_title: str | None = None
    table_columns: list[tuple[str, str, float | None]] | None = None
    table_rows: list[dict] | None = None
    figure_title: str | None = None
    image_items: list[ImageItem] | None = None
    table_width_mm: float | None = None
    table_font_size_pt: int | None = None


JLG_REPORT_LIMITS = {
    "wind_10min_avg_mps": 25.0,
}

JLG_FIRST_MODE_FREQ_HZ = 1.26

JLG_HEALTH_STATUS_MODULES: list[tuple[str, list[str]]] = [
    ("温度监测", ["temperature", "temp_humidity"]),
    ("雨量监测", ["rainfall"]),
    ("主梁挠度监测", ["deflection"]),
    ("支座、梁段纵向位移监测", ["bearing_displacement"]),
    ("结构振动监测", ["acceleration"]),
    ("结构应变监测", ["strain"]),
    ("墩柱倾斜监测", ["tilt"]),
    ("裂缝监测", ["crack"]),
    ("吊杆索力监测", ["cable_force"]),
    ("风向风速监测", ["wind"]),
    ("地震动监测", ["eq"]),
    ("GNSS 位移监测", ["gnss"]),
]


JLG_MONTHLY_SECTIONS: list[tuple[str, str, str, str]] = [
    ("main_env", "主桥环境与作用监测", "温度监测", "4.1.1"),
    ("main_humidity", "主桥环境与作用监测", "湿度监测", "4.1.2"),
    ("main_rainfall", "主桥环境与作用监测", "雨量监测", "4.1.3"),
    ("main_wind", "主桥环境与作用监测", "风向风速监测", "4.1.4"),
    ("main_eq", "主桥环境与作用监测", "地震动监测", "4.1.5"),
    ("main_traffic", "主桥环境与作用监测", "车辆荷载监测", "4.1.6"),
    ("main_deflection", "主桥结构响应与结构变化监测", "主梁挠度监测", "4.2.1"),
    ("main_bearing", "主桥结构响应与结构变化监测", "支座、梁段纵向位移监测", "4.2.2"),
    ("main_gnss", "主桥结构响应与结构变化监测", "拱顶、拱脚位移监测（GNSS）", "4.2.3"),
    ("main_vibration", "主桥结构响应与结构变化监测", "结构振动监测", "4.2.4"),
    ("main_strain", "主桥结构响应与结构变化监测", "结构应变监测", "4.2.5"),
    ("main_crack", "主桥结构响应与结构变化监测", "裂缝监测", "4.2.6"),
    ("main_cable", "主桥结构响应与结构变化监测", "吊杆索力监测", "4.2.7"),
    ("north_strain", "北江滨匝道桥监测", "结构应变监测", "4.3.1"),
    ("north_bearing", "北江滨匝道桥监测", "支座位移监测", "4.3.2"),
    ("north_tilt", "北江滨匝道桥监测", "墩柱倾斜监测", "4.3.3"),
    ("south_strain", "南江滨匝道桥监测", "结构应变监测", "4.4.1"),
    ("south_bearing", "南江滨匝道桥监测", "支座位移监测", "4.4.2"),
    ("south_tilt", "南江滨匝道桥监测", "墩柱倾斜监测", "4.4.3"),
]


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    default_template = repo_root / "reports" / "九龙江大桥健康监测2026年3月份月报_修订5.docx"
    parser = argparse.ArgumentParser(description="Build Jiulongjiang monthly monitoring report.")
    parser.add_argument("--template", type=Path, default=default_template)
    parser.add_argument("--config", type=Path, default=repo_root / "config" / "jiulongjiang_config.json")
    parser.add_argument("--result-root", type=Path, default=None)
    parser.add_argument("--image-root", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--wim-root", type=Path, default=None)
    parser.add_argument("--period-label", default="2026年3月份")
    parser.add_argument("--monitoring-range", default="2026.03.23~2026.03.31")
    parser.add_argument("--report-date", default=datetime.now().strftime("%Y年%m月%d日"))
    return parser.parse_args()


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_sheet_rows(path: Path, sheet: str | None = None) -> list[dict]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb[sheet or wb.sheetnames[0]]
    rows = list(ws.iter_rows(values_only=True))
    wb.close()
    if not rows:
        return []
    header = [str(v) if v is not None else "" for v in rows[0]]
    out: list[dict] = []
    for row in rows[1:]:
        item = {}
        for key, value in zip(header, row):
            item[key] = value
        out.append(item)
    return out


def resolve_existing_file(primary_root: Path | None, fallback_root: Path | None, filename: str) -> Path:
    candidates: list[Path] = []
    if primary_root is not None:
        candidates.append(primary_root / filename)
        candidates.append(primary_root / "stats" / filename)
    if fallback_root is not None:
        candidates.append(fallback_root / filename)
        candidates.append(fallback_root / "stats" / filename)
    for candidate in candidates:
        if candidate.exists():
            return candidate
    checked = ", ".join(str(p) for p in candidates)
    raise FileNotFoundError(f"Required file not found: {filename}. Checked: {checked}")


def should_skip_search_dir(path: Path) -> bool:
    banned_parts = {".git", ".venv", "tests", "__pycache__"}
    return any(part in banned_parts for part in path.parts)


def resolve_output_dirs(root: Path, configured_dir: str) -> list[Path]:
    configured_path = Path(configured_dir)
    candidates: list[Path] = []
    direct = (root / configured_path).resolve()
    if direct.exists() and direct.is_dir():
        candidates.append(direct)

    target_name = configured_path.name
    if root.exists():
        for found in root.rglob(target_name):
            if not found.is_dir():
                continue
            resolved = found.resolve()
            if resolved in candidates or should_skip_search_dir(resolved):
                continue
            candidates.append(resolved)

    candidates.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return candidates


def filename_has_point_token(path: Path, point_id: str) -> bool:
    token = re.escape(point_id)
    return re.search(rf"(?<![A-Za-z0-9]){token}(?![A-Za-z0-9])", path.stem) is not None


def find_latest_point_image_patterns(root: Path, configured_dir: str, point_id: str, patterns: list[str]) -> Path | None:
    resolved_dirs = resolve_output_dirs(root, configured_dir)
    matched: list[Path] = []
    for folder in resolved_dirs:
        for pattern in patterns:
            for candidate in folder.glob(pattern):
                if filename_has_point_token(candidate, point_id):
                    matched.append(candidate.resolve())
    matched = sorted(set(matched), key=lambda p: p.stat().st_mtime, reverse=True)
    return matched[0] if matched else None


def find_latest_image_patterns(root: Path, configured_dir: str, patterns: list[str]) -> Path | None:
    resolved_dirs = resolve_output_dirs(root, configured_dir)
    matched: list[Path] = []
    for folder in resolved_dirs:
        for pattern in patterns:
            matched.extend(p.resolve() for p in folder.glob(pattern))
    matched = sorted(set(matched), key=lambda p: p.stat().st_mtime, reverse=True)
    return matched[0] if matched else None


def parse_float(value: object) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def safe_text(value: object, fallback: str = "") -> str:
    if value is None:
        return fallback
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return str(value)


def format_number(value: object, decimals: int = 3, unit: str = "") -> str:
    fv = parse_float(value)
    if fv is None:
        return ""
    text = f"{fv:.{decimals}f}".rstrip("0").rstrip(".")
    return f"{text}{unit}"


def format_number_fixed(value: object, decimals: int = 3, unit: str = "") -> str:
    fv = parse_float(value)
    if fv is None:
        return ""
    return f"{fv:.{decimals}f}{unit}"


def format_table_number(value: object, decimals: int = 3, keep_trailing: bool = False) -> str:
    fv = parse_float(value)
    if fv is None:
        return "/"
    if keep_trailing:
        return f"{fv:.{decimals}f}"
    return format_number(fv, decimals)


def format_table_datetime(value: object) -> str:
    text = safe_text(value)
    return text if text else "/"


def format_range(min_val: object, max_val: object, decimals: int = 3, unit: str = "") -> str:
    lo = parse_float(min_val)
    hi = parse_float(max_val)
    if lo is None or hi is None:
        return "--"
    return f"{format_number(lo, decimals, unit)}~{format_number(hi, decimals, unit)}"


def point_sort_key(point_id: str) -> tuple:
    idx = point_index(point_id)
    parts = re.split(r"(\d+)", point_id)
    normalized: list[object] = []
    for part in parts:
        if not part:
            continue
        if part.isdigit():
            normalized.append(int(part))
        else:
            normalized.append(part)
    return (idx is None, idx if idx is not None else 10**9, normalized)


def sorted_point_ids(point_ids: Iterable[str]) -> list[str]:
    clean = [safe_text(point_id) for point_id in point_ids if safe_text(point_id)]
    return sorted(dict.fromkeys(clean), key=point_sort_key)


def get_config_points(cfg: dict, key: str) -> list[str]:
    points = cfg.get("points", {}).get(key, [])
    if not isinstance(points, list):
        return []
    return sorted_point_ids(points)


def discover_csv_points(result_root: Path, prefixes: Iterable[str]) -> list[str]:
    prefix_tuple = tuple(prefixes)
    found: list[str] = []
    for daily_dir in sorted(result_root.glob("data_jlj_*")):
        csv_dir = daily_dir / "data" / "jlj" / "csv"
        if not csv_dir.exists():
            continue
        for path in csv_dir.glob("*.csv"):
            stem = path.stem
            if stem.startswith(prefix_tuple):
                found.append(stem)
    return sorted_point_ids(found)


def extract_dates_from_range(text: str) -> tuple[date, date] | None:
    pattern = re.compile(r"(\d{4})[年./-](\d{1,2})[月./-](\d{1,2})日?.*?(\d{4})[年./-](\d{1,2})[月./-](\d{1,2})日?")
    match = pattern.search(text)
    if not match:
        return None
    y1, m1, d1, y2, m2, d2 = map(int, match.groups())
    return date(y1, m1, d1), date(y2, m2, d2)


def iter_days(start_date: date, end_date: date) -> Iterable[date]:
    current = start_date
    while current <= end_date:
        yield current
        current += timedelta(days=1)


def format_day_range(start_day: date, end_day: date) -> str:
    if start_day == end_day:
        return start_day.strftime("%Y-%m-%d")
    return f"{start_day:%Y-%m-%d}~{end_day:%Y-%m-%d}"


def group_date_ranges(days: Iterable[date]) -> list[tuple[date, date]]:
    unique_days = sorted(set(days))
    if not unique_days:
        return []
    ranges: list[tuple[date, date]] = []
    start_day = unique_days[0]
    prev_day = unique_days[0]
    for current in unique_days[1:]:
        if current == prev_day + timedelta(days=1):
            prev_day = current
            continue
        ranges.append((start_day, prev_day))
        start_day = current
        prev_day = current
    ranges.append((start_day, prev_day))
    return ranges


def summarize_day_ranges(days: Iterable[date], max_ranges: int = 6) -> str:
    ranges = [format_day_range(start_day, end_day) for start_day, end_day in group_date_ranges(days)]
    if not ranges:
        return "/"
    if len(ranges) <= max_ranges:
        return "；".join(ranges)
    return "；".join(ranges[:max_ranges]) + "；等"


def resolve_jlj_monitoring_dates(monitoring_range: str, result_root: Path) -> tuple[date, date]:
    parsed = extract_dates_from_range(monitoring_range)
    if parsed is not None:
        return parsed
    days: list[date] = []
    for daily_dir in sorted(result_root.glob("data_jlj_*")):
        match = re.search(r"data_jlj_(\d{4})-(\d{2})-(\d{2})$", daily_dir.name)
        if match:
            y, m, d = map(int, match.groups())
            days.append(date(y, m, d))
    if not days:
        raise ValueError(f"Unable to resolve monitoring dates from range: {monitoring_range}")
    return min(days), max(days)


def normalize_jlj_raw_point_id(point_id: str) -> str:
    return re.sub(r"[-_][XYZ]$", "", point_id)


def locate_jlj_csv_dir(result_root: Path, current_day: date) -> Path | None:
    direct = result_root / f"data_jlj_{current_day:%Y-%m-%d}" / "data" / "jlj" / "csv"
    if direct.exists():
        return direct
    legacy = result_root / f"jljData{current_day:%Y%m%d}-{(current_day + timedelta(days=1)):%Y%m%d}" / "data" / "csv"
    if legacy.exists():
        return legacy
    return None


def find_jlj_csv_file(csv_dir: Path, point_id: str) -> Path | None:
    base = normalize_jlj_raw_point_id(point_id)
    candidate = csv_dir / f"{base}.csv"
    if candidate.exists():
        return candidate
    matches = sorted(csv_dir.glob(f"*{base}*.csv"))
    return matches[0] if matches else None


def csv_has_records(path: Path | None) -> bool:
    if path is None or not path.exists() or path.stat().st_size <= 0:
        return False
    with path.open("r", encoding="utf-8", errors="ignore") as fh:
        first_line = True
        for line in fh:
            if first_line:
                first_line = False
                continue
            if line.strip():
                return True
    return False


def collect_jlj_health_status_rows(cfg: dict, result_root: Path, start_date: date, end_date: date) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    points_cfg = cfg.get("points", {})

    for module_label, point_keys in JLG_HEALTH_STATUS_MODULES:
        module_points: list[str] = []
        for point_key in point_keys:
            module_points.extend(get_config_points(cfg, point_key))
        module_points = sorted_point_ids(module_points)
        if not module_points:
            continue

        all_missing_days: list[date] = []
        point_reason_days: dict[tuple[str, str], list[date]] = {}
        for current_day in iter_days(start_date, end_date):
            csv_dir = locate_jlj_csv_dir(result_root, current_day)
            if csv_dir is None:
                all_missing_days.append(current_day)
                continue
            for point_id in module_points:
                csv_path = find_jlj_csv_file(csv_dir, point_id)
                if csv_path is None:
                    point_reason_days.setdefault((point_id, "原始文件缺失"), []).append(current_day)
                    continue
                if not csv_has_records(csv_path):
                    point_reason_days.setdefault((point_id, "无原始记录"), []).append(current_day)

        if all_missing_days:
            rows.append(
                {
                    "module": module_label,
                    "points": "全测点",
                    "range": summarize_day_ranges(all_missing_days),
                    "reason": "原始文件缺失",
                }
            )

        grouped: dict[tuple[tuple[date, ...], str], set[str]] = {}
        for (point_id, reason), days in point_reason_days.items():
            grouped.setdefault((tuple(sorted(set(days))), reason), set()).add(point_id)

        for (days_key, reason), points in sorted(grouped.items(), key=lambda item: (item[0][0][0] if item[0][0] else start_date, point_sort_key(sorted_point_ids(item[1])[0]))):
            rows.append(
                {
                    "module": module_label,
                    "points": "、".join(sorted_point_ids(points)),
                    "range": summarize_day_ranges(days_key),
                    "reason": reason,
                }
            )
    return rows


def apply_health_status_section(doc: Document, cfg: dict, result_root: Path, monitoring_range: str) -> None:
    start_date, end_date = resolve_jlj_monitoring_dates(monitoring_range, result_root)
    section_idx, heading_para = find_heading(doc, "健康监测系统运行状况", 2)
    next_heading = next_heading_at_or_above(doc, section_idx, 2)
    end_para = next_heading[1] if next_heading is not None else None

    content_template_para = None
    for para in doc.paragraphs[section_idx + 1 : next_heading[0] if next_heading is not None else len(doc.paragraphs)]:
        if para.text.strip():
            content_template_para = para
            break
    text_template = capture_paragraph_template(content_template_para or heading_para)

    clear_section_between(heading_para, end_para)
    anchor = end_para if end_para is not None else doc.add_paragraph()
    rows = collect_jlj_health_status_rows(cfg, result_root, start_date, end_date)

    intro = "监测周期内原始数据缺失、无文件或无记录情况见下表。" if rows else "监测周期内未发现原始数据缺失、无文件或无记录情况。"
    add_text_paragraph_before(anchor, intro, text_template)
    add_text_paragraph_before(
        anchor,
        "说明：本节仅统计原始数据缺失、无文件或无记录情况，不包含阈值筛除、异常值剔除及后处理清洗结果。",
        text_template,
    )

    if not rows:
        return

    table = insert_table_before(anchor, rows=len(rows) + 1, cols=4)
    headers = ["监测项目", "异常测点/测点组", "时间段", "异常类型"]
    for idx, header in enumerate(headers):
        set_cell_text_preserve(table.cell(0, idx), header)
    for ridx, row in enumerate(rows, start=1):
        values = [row["module"], row["points"], row["range"], row["reason"]]
        for cidx, value in enumerate(values):
            set_cell_text_preserve(table.cell(ridx, cidx), value)
    style_table(table, left=True)
    set_header_bold(table)
    set_table_outer_border(table, size_eighth_pt=12)
    set_table_auto_width(table)
    set_table_column_widths(table, [28, 98, 34, 24])
    set_table_font_size(table, 9)


def summarize_first_mode_frequency(stats_root: Path, fallback_root: Path | None = None) -> tuple[str, str, list[str]]:
    try:
        workbook_path = resolve_existing_file(stats_root, fallback_root, "accel_spec_stats.xlsx")
    except FileNotFoundError:
        return "", "", []

    wb = load_workbook(workbook_path, read_only=True, data_only=True)
    point_means: list[float] = []
    all_values: list[float] = []
    point_ids: list[str] = []
    try:
        for ws in wb.worksheets:
            rows = list(ws.iter_rows(values_only=True))
            if len(rows) < 2:
                continue
            header = [safe_text(item) for item in rows[0]]
            first_freq_idx = next((idx for idx, name in enumerate(header) if name.startswith("Freq_")), None)
            if first_freq_idx is None:
                continue
            values = [parse_float(row[first_freq_idx]) for row in rows[1:] if len(row) > first_freq_idx]
            values = [value for value in values if value is not None]
            if not values:
                continue
            point_means.append(sum(values) / len(values))
            all_values.extend(values)
            point_ids.append(ws.title)
    finally:
        wb.close()

    if not all_values:
        return "", "", []

    min_freq = min(all_values)
    max_freq = max(all_values)
    mean_freq = sum(point_means) / len(point_means)
    detail = (
        f"已识别到有效一阶频率的{len(point_means)}个测点中，一阶频率范围约为"
        f"{format_number_fixed(min_freq, 3, 'Hz')}~{format_number_fixed(max_freq, 3, 'Hz')}，"
        f"平均约为{format_number_fixed(mean_freq, 3, 'Hz')}，与一阶自振频率"
        f"{format_number_fixed(JLG_FIRST_MODE_FREQ_HZ, 3, 'Hz')}总体接近。"
    )
    summary = (
        f"已识别测点一阶频率约为{format_number_fixed(min_freq, 3, 'Hz')}~"
        f"{format_number_fixed(max_freq, 3, 'Hz')}，与一阶自振频率"
        f"{format_number_fixed(JLG_FIRST_MODE_FREQ_HZ, 3, 'Hz')}总体接近。"
    )
    return detail, summary, sorted_point_ids(point_ids)


def select_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/msyhbd.ttc",
        "C:/Windows/Fonts/simhei.ttf",
        "C:/Windows/Fonts/simsun.ttc",
    ]
    for candidate in candidates:
        path = Path(candidate)
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def build_tile(label: str, image_path: Path | None, tile_size: tuple[int, int]) -> Image.Image:
    canvas = Image.new("RGB", tile_size, "white")
    draw = ImageDraw.Draw(canvas)
    font_label = select_font(28)
    font_hint = select_font(22)
    margin = 16
    if image_path is not None and image_path.exists():
        with Image.open(image_path) as src:
            src = ImageOps.exif_transpose(src.convert("RGB"))
            bbox = (margin, margin, tile_size[0] - margin, tile_size[1] - 56)
            fitted = ImageOps.contain(src, (bbox[2] - bbox[0], bbox[3] - bbox[1]))
            x = bbox[0] + (bbox[2] - bbox[0] - fitted.width) // 2
            y = bbox[1] + (bbox[3] - bbox[1] - fitted.height) // 2
            canvas.paste(fitted, (x, y))
    else:
        draw.rectangle((margin, margin, tile_size[0] - margin, tile_size[1] - 56), outline="#B0B0B0", width=2)
        draw.text((tile_size[0] / 2, tile_size[1] / 2 - 12), "图片缺失", anchor="mm", fill="#808080", font=font_hint)

    draw.text((tile_size[0] / 2, tile_size[1] - 24), label, anchor="mm", fill="black", font=font_label)
    return canvas


def compose_grid(items: list[ImageItem], out_path: Path, cols: int = 2, tile_size: tuple[int, int] = (920, 560)) -> Path:
    rows = math.ceil(len(items) / cols)
    canvas = Image.new("RGB", (tile_size[0] * cols, tile_size[1] * rows), "white")
    for idx, item in enumerate(items):
        row = idx // cols
        col = idx % cols
        tile = build_tile(item.label, item.path, tile_size)
        canvas.paste(tile, (col * tile_size[0], row * tile_size[1]))
    ensure_dir(out_path.parent)
    canvas.save(out_path, quality=92)
    return out_path


def insert_paragraph_before(paragraph: Paragraph) -> Paragraph:
    new_p = OxmlElement("w:p")
    paragraph._p.addprevious(new_p)
    return Paragraph(new_p, paragraph._parent)


def insert_template_table_before(paragraph: Paragraph, template_tbl) -> Table:
    table_xml = deepcopy(template_tbl)
    paragraph._p.addprevious(table_xml)
    return Table(table_xml, paragraph._parent)


def insert_table_before(paragraph: Paragraph, rows: int, cols: int) -> Table:
    body = paragraph._parent
    table = body.add_table(rows=rows, cols=cols, width=Mm(160))
    paragraph._p.addprevious(table._tbl)
    return table


def clear_section_between(start_paragraph: Paragraph, end_paragraph: Paragraph | None) -> None:
    parent = start_paragraph._p.getparent()
    current = start_paragraph._p.getnext()
    end = end_paragraph._p if end_paragraph is not None else None
    while current is not None and current is not end:
        nxt = current.getnext()
        parent.remove(current)
        current = nxt


def capture_paragraph_template(paragraph: Paragraph) -> ParagraphTemplate:
    pf = paragraph.paragraph_format
    run0 = paragraph.runs[0] if paragraph.runs else None
    return ParagraphTemplate(
        style_name=paragraph.style.name if paragraph.style is not None else None,
        alignment=paragraph.alignment,
        left_indent=pf.left_indent,
        right_indent=pf.right_indent,
        first_line_indent=pf.first_line_indent,
        space_before=pf.space_before,
        space_after=pf.space_after,
        line_spacing=pf.line_spacing,
        line_spacing_rule=pf.line_spacing_rule,
        keep_together=pf.keep_together,
        keep_with_next=pf.keep_with_next,
        page_break_before=pf.page_break_before,
        widow_control=pf.widow_control,
        run_bold=run0.bold if run0 else None,
        run_italic=run0.italic if run0 else None,
        run_underline=run0.underline if run0 else None,
        run_font_name=run0.font.name if run0 else None,
        run_font_size=run0.font.size if run0 else None,
    )


def apply_paragraph_template(paragraph: Paragraph, template: ParagraphTemplate) -> None:
    if template.style_name:
        paragraph.style = template.style_name
    paragraph.alignment = template.alignment
    pf = paragraph.paragraph_format
    pf.left_indent = template.left_indent
    pf.right_indent = template.right_indent
    pf.first_line_indent = template.first_line_indent
    pf.space_before = template.space_before
    pf.space_after = template.space_after
    pf.line_spacing = template.line_spacing
    pf.line_spacing_rule = template.line_spacing_rule
    pf.keep_together = template.keep_together
    pf.keep_with_next = template.keep_with_next
    pf.page_break_before = template.page_break_before
    pf.widow_control = template.widow_control
    for run in paragraph.runs:
        if template.run_bold is not None:
            run.bold = template.run_bold
        if template.run_italic is not None:
            run.italic = template.run_italic
        if template.run_underline is not None:
            run.underline = template.run_underline
        if template.run_font_name:
            run.font.name = template.run_font_name
        if template.run_font_size:
            run.font.size = template.run_font_size


def add_text_paragraph_before(anchor: Paragraph, text: str, template: ParagraphTemplate) -> Paragraph:
    para = insert_paragraph_before(anchor)
    para.add_run(text)
    apply_paragraph_template(para, template)
    return para


def set_cell_text_preserve(cell, text: str) -> None:
    paragraphs = cell.paragraphs
    if not paragraphs:
        cell.text = text
        return
    first = paragraphs[0]
    if first.runs:
        for run in first.runs:
            run.text = ""
        first.runs[0].text = text
    else:
        first.add_run(text)
    for para in paragraphs[1:]:
        for run in para.runs:
            run.text = ""


def set_cell_paragraphs(cell, lines: list[str], bold_indices: set[int] | None = None) -> None:
    bold_indices = bold_indices or set()
    if not cell.paragraphs:
        cell.text = ""
    base_para = cell.paragraphs[0]
    base_style = base_para.style
    base_alignment = base_para.alignment
    for para in cell.paragraphs[1:]:
        para._element.getparent().remove(para._element)
    if base_para.runs:
        for run in base_para.runs:
            run.text = ""
    else:
        base_para.add_run("")
    paragraphs = [base_para]
    for _ in range(max(0, len(lines) - 1)):
        para = cell.add_paragraph()
        para.style = base_style
        para.alignment = base_alignment
        paragraphs.append(para)
    for idx, (para, text) in enumerate(zip(paragraphs, lines)):
        if not para.runs:
            para.add_run("")
        for run in para.runs:
            run.text = ""
        para.runs[0].text = text
        para.runs[0].bold = idx in bold_indices


def style_table(table: Table, left: bool = False) -> None:
    table.style = "Table Grid"
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    table.autofit = True
    for row in table.rows:
        for cell in row.cells:
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            for para in cell.paragraphs:
                para.alignment = WD_ALIGN_PARAGRAPH.LEFT if left else WD_ALIGN_PARAGRAPH.CENTER


def set_table_autofit(table: Table, enabled: bool = True) -> None:
    table.autofit = enabled
    tbl_pr = table._tbl.tblPr
    tbl_layout = tbl_pr.first_child_found_in("w:tblLayout")
    if tbl_layout is None:
        tbl_layout = OxmlElement("w:tblLayout")
        tbl_pr.append(tbl_layout)
    tbl_layout.set(qn("w:type"), "autofit" if enabled else "fixed")


def set_table_width(table: Table, width_mm: float) -> None:
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.first_child_found_in("w:tblW")
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:type"), "dxa")
    tbl_w.set(qn("w:w"), str(round(width_mm * 56.6929)))


def set_table_auto_width(table: Table) -> None:
    tbl_pr = table._tbl.tblPr
    tbl_w = tbl_pr.first_child_found_in("w:tblW")
    if tbl_w is None:
        tbl_w = OxmlElement("w:tblW")
        tbl_pr.append(tbl_w)
    tbl_w.set(qn("w:type"), "auto")
    tbl_w.set(qn("w:w"), "0")


def set_table_column_widths(table: Table, widths_mm: list[float]) -> None:
    for row in table.rows:
        for idx, width in enumerate(widths_mm):
            if idx < len(row.cells):
                row.cells[idx].width = Mm(width)


def set_header_bold(table: Table, header_rows: int = 1) -> None:
    for row in table.rows[:header_rows]:
        for cell in row.cells:
            for para in cell.paragraphs:
                for run in para.runs:
                    run.bold = True


def set_table_outer_border(table: Table, size_eighth_pt: int = 12) -> None:
    tbl_pr = table._tbl.tblPr
    borders = tbl_pr.first_child_found_in("w:tblBorders")
    if borders is None:
        borders = OxmlElement("w:tblBorders")
        tbl_pr.append(borders)
    for edge in ("top", "left", "bottom", "right"):
        el = borders.find(qn(f"w:{edge}"))
        if el is None:
            el = OxmlElement(f"w:{edge}")
            borders.append(el)
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), str(size_eighth_pt))
        el.set(qn("w:space"), "0")
        el.set(qn("w:color"), "000000")


def set_table_font_size(table: Table, size_pt: int) -> None:
    for row in table.rows:
        for cell in row.cells:
            for para in cell.paragraphs:
                for run in para.runs:
                    run.font.size = Pt(size_pt)


def remove_bookmarks(paragraph_element) -> None:
    for child in list(paragraph_element):
        if child.tag in {qn("w:bookmarkStart"), qn("w:bookmarkEnd")}:
            paragraph_element.remove(child)


def append_text_run(paragraph_element, text: str) -> None:
    run = OxmlElement("w:r")
    t = OxmlElement("w:t")
    if text.startswith(" ") or text.endswith(" "):
        t.set(qn("xml:space"), "preserve")
    t.text = text
    run.append(t)
    paragraph_element.append(run)


def build_caption_paragraph(template_paragraph: Paragraph, title: str) -> Paragraph:
    para_xml = deepcopy(template_paragraph._p)
    remove_bookmarks(para_xml)
    end_count = 0
    last_end = None
    for child in para_xml:
        if child.tag != qn("w:r"):
            continue
        fld = child.find(qn("w:fldChar"))
        if fld is not None and fld.get(qn("w:fldCharType")) == "end":
            end_count += 1
            if end_count == 2:
                last_end = child
                break
    if last_end is None:
        raise ValueError("Caption template does not contain expected field sequence.")
    current = last_end.getnext()
    while current is not None:
        nxt = current.getnext()
        para_xml.remove(current)
        current = nxt
    append_text_run(para_xml, f" {title}")
    return Paragraph(para_xml, template_paragraph._parent)


def insert_auto_caption_before(anchor: Paragraph, template_paragraph: Paragraph, title: str) -> Paragraph:
    para = build_caption_paragraph(template_paragraph, title)
    anchor._p.addprevious(para._p)
    return para


def update_fields_with_word(docx_path: Path) -> None:
    try:
        import pythoncom
        import win32com.client  # type: ignore
    except ImportError:
        venv_python = Path(__file__).resolve().parent / ".venv" / "Scripts" / "python.exe"
        if not venv_python.exists():
            return
        script = f"""
import pythoncom
import win32com.client
p = r'''{str(docx_path)}'''
pythoncom.CoInitialize()
word = None
doc = None
try:
    word = win32com.client.DispatchEx("Word.Application")
    word.Visible = False
    word.DisplayAlerts = 0
    doc = word.Documents.Open(p)
    for story in doc.StoryRanges:
        try:
            story.Fields.Update()
        except Exception:
            pass
    try:
        doc.TablesOfContents(1).Update()
    except Exception:
        pass
    doc.Fields.Update()
    doc.Save()
finally:
    if doc is not None:
        doc.Close(SaveChanges=True)
    if word is not None:
        word.Quit()
    pythoncom.CoUninitialize()
"""
        subprocess.run([str(venv_python), "-c", script], check=False, timeout=180)
        return

    pythoncom.CoInitialize()
    word = None
    doc = None
    try:
        word = win32com.client.DispatchEx("Word.Application")
        word.Visible = False
        word.DisplayAlerts = 0
        doc = word.Documents.Open(str(docx_path))
        for story in doc.StoryRanges:
            try:
                story.Fields.Update()
            except Exception:
                pass
        try:
            doc.TablesOfContents(1).Update()
        except Exception:
            pass
        doc.Fields.Update()
        doc.Save()
    finally:
        if doc is not None:
            doc.Close(SaveChanges=True)
        if word is not None:
            word.Quit()
        pythoncom.CoUninitialize()


def heading_level(paragraph: Paragraph) -> int | None:
    style_name = paragraph.style.name if paragraph.style else ""
    match = re.match(r"Heading (\d+)", style_name)
    if match:
        return int(match.group(1))
    return None


def find_heading(doc: Document, text: str, level: int, start_idx: int = 0, end_idx: int | None = None) -> tuple[int, Paragraph]:
    paragraphs = doc.paragraphs
    stop = len(paragraphs) if end_idx is None else end_idx
    for idx in range(start_idx, stop):
        para = paragraphs[idx]
        if heading_level(para) == level and para.text.strip() == text:
            return idx, para
    raise ValueError(f"Heading not found: level={level}, text={text}")


def next_heading_at_or_above(doc: Document, index: int, level: int) -> tuple[int, Paragraph] | None:
    paragraphs = doc.paragraphs
    for idx in range(index + 1, len(paragraphs)):
        para = paragraphs[idx]
        para_level = heading_level(para)
        if para_level is not None and para_level <= level:
            return idx, para
    return None


def find_section_anchor(doc: Document, parent_heading: str, child_heading: str) -> tuple[Paragraph, Paragraph | None]:
    parent_idx, _ = find_heading(doc, parent_heading, 2)
    next_parent = next_heading_at_or_above(doc, parent_idx, 2)
    child_end = next_parent[0] if next_parent is not None else len(doc.paragraphs)
    child_idx, child_para = find_heading(doc, child_heading, 3, start_idx=parent_idx + 1, end_idx=child_end)
    next_heading = next_heading_at_or_above(doc, child_idx, 3)
    return child_para, next_heading[1] if next_heading is not None else None


def pick_evenly(items: list[dict], limit: int) -> list[dict]:
    if len(items) <= limit:
        return items
    if limit <= 1:
        return [items[0]]
    seen: set[int] = set()
    selected: list[dict] = []
    for i in range(limit):
        idx = round(i * (len(items) - 1) / (limit - 1))
        if idx in seen:
            continue
        seen.add(idx)
        selected.append(items[idx])
    return selected


def point_index(point_id: str) -> int | None:
    match = re.match(r"^[A-Z]+(?:[A-Z]+)?-(\d+)-", point_id)
    if not match:
        return None
    return int(match.group(1))


def is_main_strain(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 1 <= idx <= 26


def is_south_strain(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 27 <= idx <= 42


def is_north_strain(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 43 <= idx <= 50


def is_main_bearing(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 1 <= idx <= 8


def is_south_bearing(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 9 <= idx <= 18


def is_north_bearing(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 19 <= idx <= 24


def is_south_tilt(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 1 <= idx <= 2


def is_north_tilt(point_id: str) -> bool:
    idx = point_index(point_id)
    return idx is not None and 3 <= idx <= 6


def numeric_min(rows: Iterable[dict], key: str) -> float | None:
    values = [parse_float(row.get(key)) for row in rows]
    values = [v for v in values if v is not None]
    return min(values) if values else None


def numeric_max(rows: Iterable[dict], key: str) -> float | None:
    values = [parse_float(row.get(key)) for row in rows]
    values = [v for v in values if v is not None]
    return max(values) if values else None


def numeric_mean(rows: Iterable[dict], key: str) -> float | None:
    values = [parse_float(row.get(key)) for row in rows]
    values = [v for v in values if v is not None]
    return sum(values) / len(values) if values else None


def first_nonempty(rows: Iterable[dict], key: str) -> object:
    for row in rows:
        value = row.get(key)
        if value not in (None, ""):
            return value
    return None


def sort_rows_by_point(rows: list[dict]) -> list[dict]:
    return sorted(rows, key=lambda row: safe_text(row.get("PointID")))


def read_stats_rows(stats_root: Path, filename: str, fallback_root: Path | None = None) -> list[dict]:
    path = resolve_existing_file(stats_root, fallback_root, filename)
    return load_sheet_rows(path)


def load_section_rows(
    stats_root: Path,
    fallback_root: Path | None,
    filename: str,
    predicate: Callable[[dict], bool] | None = None,
) -> list[dict]:
    rows = read_stats_rows(stats_root, filename, fallback_root)
    if predicate is not None:
        rows = [row for row in rows if predicate(row)]
    return sort_rows_by_point(rows)


def choose_representative_points(rows: list[dict], limit: int = 6) -> list[dict]:
    compact = [row for row in rows if safe_text(row.get("PointID"))]
    return pick_evenly(compact, limit)


def resolve_expected_points(
    cfg: dict,
    result_root: Path,
    key: str,
    prefixes: Iterable[str],
    predicate: Callable[[str], bool] | None = None,
    fallback_rows: Iterable[dict] | None = None,
) -> list[str]:
    expected = get_config_points(cfg, key)
    expected.extend(discover_csv_points(result_root, prefixes))
    if fallback_rows is not None:
        expected.extend([safe_text(row.get("PointID")) for row in fallback_rows if safe_text(row.get("PointID"))])
    expected = sorted_point_ids(expected)
    if predicate is not None:
        expected = [point_id for point_id in expected if predicate(point_id)]
    return sorted_point_ids(expected)


def build_full_point_table_rows(
    expected_points: list[str],
    actual_rows: list[dict],
    columns: list[tuple[str, str, float | None]],
    formatters: dict[str, Callable[[object], str]] | None = None,
) -> list[dict]:
    formatters = formatters or {}
    row_map = {safe_text(row.get("PointID")): row for row in actual_rows if safe_text(row.get("PointID"))}
    output: list[dict] = []
    for point_id in expected_points:
        src = row_map.get(point_id, {})
        item: dict[str, object] = {}
        for key, _, _ in columns:
            if key == "PointID":
                item[key] = point_id
                continue
            value = src.get(key) if isinstance(src, dict) else None
            if key in formatters:
                item[key] = formatters[key](value)
            else:
                item[key] = "/" if value in (None, "") else value
        output.append(item)
    return output


def build_full_composite_table_rows(
    expected_keys: list[tuple[str, ...]],
    actual_rows: list[dict],
    key_fields: tuple[str, ...],
    columns: list[tuple[str, str, float | None]],
    formatters: dict[str, Callable[[object], str]] | None = None,
) -> list[dict]:
    formatters = formatters or {}
    row_map = {
        tuple(safe_text(row.get(field)) for field in key_fields): row
        for row in actual_rows
        if all(safe_text(row.get(field)) for field in key_fields)
    }
    output: list[dict] = []
    for key_values in expected_keys:
        src = row_map.get(tuple(key_values), {})
        item: dict[str, object] = {}
        for field, value in zip(key_fields, key_values):
            item[field] = value
        for column_key, _, _ in columns:
            if column_key in key_fields:
                continue
            value = src.get(column_key) if isinstance(src, dict) else None
            if column_key in formatters:
                item[column_key] = formatters[column_key](value)
            else:
                item[column_key] = "/" if value in (None, "") else value
        output.append(item)
    return output


def build_generic_table_rows(rows: list[dict], columns: list[tuple[str, str, float | None]], limit: int = 6) -> list[dict]:
    sampled = choose_representative_points(rows, limit)
    output: list[dict] = []
    for row in sampled:
        item = {}
        for key, _, _ in columns:
            item[key] = row.get(key)
        output.append(item)
    return output


def main_temp_rows(rows: list[dict]) -> tuple[list[dict], list[dict]]:
    env = [row for row in rows if safe_text(row.get("PointID")).startswith("JGWD-")]
    structure = [row for row in rows if safe_text(row.get("PointID")).startswith("WDCGQ-")]
    return env, structure


def classify_temperature_point(point_id: str) -> str:
    if point_id.startswith("JGWD-"):
        return "桥面温度"
    if point_id.startswith("WSDJ-"):
        if "-QM-" in point_id:
            return "桥址区环境温度"
        return "主梁内温度"
    if point_id.startswith("WDCGQ-") and "A20" in point_id:
        return "拱肋温度"
    return "主梁箱室温度"


def classify_humidity_point(point_id: str) -> str:
    if "-QM-" in point_id:
        return "桥址区环境相对湿度"
    return "主梁箱室相对湿度"


def numeric_table_formatters(keys: Iterable[str], decimals: int, keep_trailing: bool = False) -> dict[str, Callable[[object], str]]:
    return {key: (lambda value, d=decimals, keep=keep_trailing: format_table_number(value, d, keep)) for key in keys}


def build_missing_section(text: str) -> SectionContent:
    return SectionContent(
        narrative=text,
        summary_sentence=text,
        available=False,
        image_items=[],
        table_rows=[],
        table_columns=[],
    )


def build_numeric_summary_section(
    rows: list[dict],
    narrative_intro: str,
    summary_subject: str,
    min_key: str,
    max_key: str,
    mean_key: str,
    decimals: int,
    unit: str,
    table_title: str,
    table_columns: list[tuple[str, str, float | None]],
    figure_title: str,
    image_items: list[ImageItem],
    table_rows_override: list[dict] | None = None,
) -> SectionContent:
    if not rows:
        return build_missing_section(f"本月未获取到{summary_subject}有效数据。")
    lo = numeric_min(rows, min_key)
    hi = numeric_max(rows, max_key)
    mean_v = numeric_mean(rows, mean_key)
    narrative = (
        f"{narrative_intro}共统计{len(rows)}个测点，监测值范围为"
        f"{format_range(lo, hi, decimals, unit)}，平均值约为{format_number(mean_v, decimals, unit)}。"
    )
    summary = f"{summary_subject}监测值范围为{format_range(lo, hi, decimals, unit)}，总体未见明显突变。"
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title=table_title,
        table_columns=table_columns,
        table_rows=table_rows_override if table_rows_override is not None else build_generic_table_rows(rows, table_columns),
        figure_title=figure_title,
        image_items=image_items,
    )


def image_for_point(image_root: Path, directory: str, point_id: str, patterns: list[str]) -> Path | None:
    return find_latest_point_image_patterns(image_root, directory, point_id, patterns)


def images_for_point(image_root: Path, directory: str, point_id: str, patterns: list[str]) -> list[Path]:
    resolved_dirs = resolve_output_dirs(image_root, directory)
    matched: list[Path] = []
    for folder in resolved_dirs:
        for pattern in patterns:
            for candidate in folder.glob(pattern):
                if filename_has_point_token(candidate, point_id):
                    matched.append(candidate.resolve())
    return sorted(set(matched), key=lambda p: p.stat().st_mtime, reverse=True)


def find_latest_two_deflection_images(image_root: Path, point_id: str) -> tuple[Path | None, Path | None]:
    matched = images_for_point(image_root, "时程曲线_挠度", point_id, [f"Defl_{point_id}_*.jpg"])
    if not matched:
        return None, None
    filt = matched[0]
    orig = matched[1] if len(matched) > 1 else None
    return orig, filt


def make_image_items(image_root: Path, directory: str, rows: list[dict], patterns_fn: Callable[[str], list[str]], label_fn: Callable[[dict], str], limit: int = 4) -> list[ImageItem]:
    items: list[ImageItem] = []
    for row in choose_representative_points(rows, limit):
        point_id = safe_text(row.get("PointID"))
        if not point_id:
            continue
        items.append(ImageItem(label_fn(row), image_for_point(image_root, directory, point_id, patterns_fn(point_id))))
    return items


def date_value_to_text(value: object) -> str:
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    return safe_text(value)


def build_temperature_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "temp_stats.xlsx")
    if not rows:
        return build_missing_section("本月未获取到主桥温度监测有效数据。")
    deck_rows = [row for row in rows if classify_temperature_point(safe_text(row.get("PointID"))) == "桥面温度"]
    arch_rows = [row for row in rows if classify_temperature_point(safe_text(row.get("PointID"))) == "拱肋温度"]
    box_rows = [row for row in rows if classify_temperature_point(safe_text(row.get("PointID"))) == "主梁箱室温度"]
    inner_rows = [row for row in rows if classify_temperature_point(safe_text(row.get("PointID"))) == "主梁内温度"]
    env_rows = [row for row in rows if classify_temperature_point(safe_text(row.get("PointID"))) == "桥址区环境温度"]
    deck_range = format_range(numeric_min(deck_rows, "Min"), numeric_max(deck_rows, "Max"), 1, "℃") if deck_rows else "--"
    arch_range = format_range(numeric_min(arch_rows, "Min"), numeric_max(arch_rows, "Max"), 1, "℃") if arch_rows else "--"
    box_range = format_range(numeric_min(box_rows, "Min"), numeric_max(box_rows, "Max"), 1, "℃") if box_rows else "--"
    inner_range = format_range(numeric_min(inner_rows, "Min"), numeric_max(inner_rows, "Max"), 1, "℃") if inner_rows else "--"
    env_range = format_range(numeric_min(env_rows, "Min"), numeric_max(env_rows, "Max"), 1, "℃") if env_rows else "--"
    narrative = (
        f"选取典型监测数据进行分析。桥面温度监测范围为{deck_range}，"
        f"拱肋温度监测范围为{arch_range}，主梁箱室温度监测范围为{box_range}，"
        f"主梁内温度监测范围为{inner_range}，桥址区环境温度监测范围为{env_range}。"
    )
    summary = f"桥面、拱肋、主梁箱室、主梁内及桥址区环境温度监测范围分别为{deck_range}、{arch_range}、{box_range}、{inner_range}和{env_range}。"
    columns = [
        ("PointID", "测点编号", None),
        ("Category", "监测类型", None),
        ("Min", "最小值(℃)", None),
        ("Max", "最大值(℃)", None),
        ("Mean", "平均值(℃)", None),
    ]
    expected_points = resolve_expected_points(cfg, result_root, "temperature", ("JGWD-", "WDCGQ-", "WSDJ-"), fallback_rows=rows)
    table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        columns,
        formatters={
            "Category": lambda value: value if value else "/",
            "Min": lambda value: format_table_number(value, 1, True),
            "Max": lambda value: format_table_number(value, 1, True),
            "Mean": lambda value: format_table_number(value, 1, True),
        },
    )
    for row in table_rows:
        row["Category"] = classify_temperature_point(safe_text(row.get("PointID")))
    image_items = make_image_items(
        image_root,
        "时程曲线_温度",
        rows,
        lambda pid: [f"{pid}_*.jpg"],
        lambda row: safe_text(row.get("PointID")),
        limit=4,
    )
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="主桥温度监测统计表",
        table_columns=columns,
        table_rows=table_rows,
        figure_title="主桥温度监测典型时程曲线图",
        image_items=image_items,
    )


def build_humidity_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "humidity_stats.xlsx")
    columns = [
        ("PointID", "测点编号", None),
        ("Category", "监测类型", None),
        ("Min", "最小值(%)", None),
        ("Max", "最大值(%)", None),
        ("Mean", "平均值(%)", None),
    ]
    if not rows:
        return build_missing_section("本月未获取到主桥湿度监测有效数据。")
    env_rows = [row for row in rows if classify_humidity_point(safe_text(row.get("PointID"))) == "桥址区环境相对湿度"]
    box_rows = [row for row in rows if classify_humidity_point(safe_text(row.get("PointID"))) == "主梁箱室相对湿度"]
    env_range = format_range(numeric_min(env_rows, "Min"), numeric_max(env_rows, "Max"), 1, "%") if env_rows else "--"
    box_range = format_range(numeric_min(box_rows, "Min"), numeric_max(box_rows, "Max"), 1, "%") if box_rows else "--"
    image_items = make_image_items(
        image_root,
        "时程曲线_湿度",
        rows,
        lambda pid: [f"{pid}_*.jpg"],
        lambda row: safe_text(row.get("PointID")),
        limit=4,
    )
    expected_points = resolve_expected_points(cfg, result_root, "humidity", ("WSDJ-",), fallback_rows=rows)
    table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        columns,
        formatters={
            "Category": lambda value: value if value else "/",
            "Min": lambda value: format_table_number(value, 1, True),
            "Max": lambda value: format_table_number(value, 1, True),
            "Mean": lambda value: format_table_number(value, 1, True),
        },
    )
    for row in table_rows:
        row["Category"] = classify_humidity_point(safe_text(row.get("PointID")))
    return SectionContent(
        narrative=f"选取典型监测数据进行分析。主梁箱室相对湿度监测范围为{box_range}，桥址区环境相对湿度监测范围为{env_range}。",
        summary_sentence=f"主梁箱室及桥址区环境相对湿度监测范围分别为{box_range}和{env_range}。",
        table_title="主桥湿度监测统计表",
        table_columns=columns,
        table_rows=table_rows,
        figure_title="主桥湿度监测典型时程曲线图",
        image_items=image_items,
    )


def build_rainfall_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "rainfall_stats.xlsx")
    if not rows:
        return build_missing_section("本月未获取到主桥雨量监测有效数据。")
    row = rows[0]
    total_mm = parse_float(row.get("Total_mm"))
    max_mm_h = parse_float(row.get("Max_mm_h"))
    narrative = (
        f"本月主桥雨量累计约为{format_number(total_mm, 2, 'mm')}，"
        f"最大降雨强度约为{format_number(max_mm_h, 3, 'mm/h')}。"
    )
    summary = f"主桥本月累计降雨量约{format_number(total_mm, 2, 'mm')}，最大降雨强度约{format_number(max_mm_h, 3, 'mm/h')}。"
    columns = [
        ("PointID", "测点编号", None),
        ("StartTime", "起始时间", None),
        ("EndTime", "结束时间", None),
        ("Max_mm_h", "最大降雨强度(mm/h)", None),
        ("Total_mm", "累计降雨量(mm)", None),
    ]
    expected_points = resolve_expected_points(cfg, result_root, "rainfall", ("YLJ-",), fallback_rows=rows)
    table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        columns,
        formatters={
            "StartTime": format_table_datetime,
            "EndTime": format_table_datetime,
            "Max_mm_h": lambda value: format_table_number(value, 3, False),
            "Total_mm": lambda value: format_table_number(value, 2, False),
        },
    )
    path = find_latest_image_patterns(image_root, "时程曲线_雨量", ["Rainfall_*.jpg"])
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="主桥雨量监测统计表",
        table_columns=columns,
        table_rows=table_rows,
        figure_title="主桥降雨强度典型时程曲线图",
        image_items=[ImageItem("(a) 降雨强度时程", path)] if path else [],
    )


def build_wind_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "wind_stats.xlsx")
    if not rows:
        return build_missing_section("本月未获取到主桥风向风速监测有效数据。")
    summaries: list[dict[str, object]] = []
    for row in rows:
        pid = safe_text(row.get("PointID"))
        txt = image_root / "风速风向结果" / "风玫瑰"
        summary_files = sorted(txt.glob(f"{pid}_windrose_*_summary.txt"))
        summary = {"PointID": pid}
        if summary_files:
            text = summary_files[-1].read_text(encoding="utf-8")
            for line in text.splitlines():
                line = line.strip()
                if "平均风速" in line and "m/s" in line:
                    m = re.search(r"([0-9.]+)\s*m/s", line)
                    if m:
                        summary["MeanSpeed"] = float(m.group(1))
                elif "最大风速" in line and "m/s" in line:
                    m = re.search(r"([0-9.]+)\s*m/s", line)
                    if m:
                        summary["MaxSpeed"] = float(m.group(1))
                elif "主导风向" in line:
                    summary["DominantDir"] = line.split(":", 1)[-1].strip()
                elif "主要风速等级" in line:
                    summary["MainGrade"] = line.split(":", 1)[-1].strip()
        summary["Mean10minMax"] = parse_float(row.get("Mean10minMax"))
        summary["Mean10minTime"] = row.get("Mean10minTime")
        summaries.append(summary)

    deck_point_id = "CSFSY-02-K16-QM-G20"
    deck_summary = next((item for item in summaries if safe_text(item.get("PointID")) == deck_point_id), None)
    source_rows = [deck_summary] if deck_summary is not None else summaries
    max_speed = numeric_max(source_rows, "MaxSpeed")
    mean_speed = numeric_mean(source_rows, "MeanSpeed")
    max_10m = numeric_max(source_rows, "Mean10minMax")
    wind_limit = JLG_REPORT_LIMITS["wind_10min_avg_mps"]
    if max_10m is not None and max_10m <= wind_limit:
        limit_text = f"未超过{format_number_fixed(wind_limit, 0, 'm/s')}，处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"
    elif max_10m is not None:
        limit_text = f"已超过{format_number_fixed(wind_limit, 0, 'm/s')}预警阈值，需重点复核。"
    else:
        limit_text = "暂不具备预警判定条件。"
    narrative = (
        f"选取典型监测数据进行分析。主桥桥面平均风速约为{format_number(mean_speed, 2, 'm/s')}，"
        f"瞬时最大风速为{format_number(max_speed, 2, 'm/s')}，"
        f"桥面10min平均风速最大值为{format_number(max_10m, 2, 'm/s')}，{limit_text}"
    )
    summary = f"主桥桥面风速监测中，桥面10min平均风速最大值为{format_number(max_10m, 2, 'm/s')}，{limit_text}"
    columns = [
        ("PointID", "测点编号", 22.0),
        ("DominantDir", "主导风向", 24.0),
        ("MainGrade", "主要风速等级", 22.0),
        ("MeanSpeed", "平均风速(m/s)", 18.0),
        ("MaxSpeed", "最大风速(m/s)", 18.0),
        ("Mean10minMax", "10min平均风速最大值(m/s)", 24.0),
        ("Mean10minTime", "对应时间", 26.0),
    ]
    expected_points = resolve_expected_points(cfg, result_root, "wind_speed", ("CSFSY-",), fallback_rows=summaries)
    table_rows = build_full_point_table_rows(
        expected_points,
        summaries,
        columns,
        formatters={
            "DominantDir": lambda value: safe_text(value, "/") or "/",
            "MainGrade": lambda value: safe_text(value, "/") or "/",
            "MeanSpeed": lambda value: format_table_number(value, 2, False),
            "MaxSpeed": lambda value: format_table_number(value, 2, False),
            "Mean10minMax": lambda value: format_table_number(value, 2, False),
            "Mean10minTime": format_table_datetime,
        },
    )
    image_items: list[ImageItem] = []
    for row in choose_representative_points(summaries, 2):
        pid = safe_text(row.get("PointID"))
        rose = image_for_point(image_root, "风速风向结果/风玫瑰", pid, [f"{pid}_windrose_*.jpg"])
        speed10 = image_for_point(image_root, "风速风向结果/风速10min", pid, [f"{pid}_speed10min_*.jpg"])
        image_items.extend(
            [
                ImageItem(f"{pid} 风玫瑰图", rose),
                ImageItem(f"{pid} 10min平均风速时程", speed10),
            ]
        )
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="主桥风向风速监测统计表",
        table_columns=columns,
        table_rows=table_rows,
        figure_title="主桥风向风速监测典型图",
        image_items=image_items,
        table_width_mm=154.0,
        table_font_size_pt=9,
    )


def iter_daily_eq_files(result_root: Path) -> list[Path]:
    return sorted(result_root.glob("data_jlj_*/*/jlj/csv/DZY-*.csv"))


def collect_eq_peak_rows(result_root: Path) -> list[dict]:
    import csv

    peaks: dict[tuple[str, str], tuple[float, str]] = {}
    files = iter_daily_eq_files(result_root)
    component_keys = [("X", "value_x"), ("Y", "value_y"), ("Z", "value_z")]
    for path in files:
        point_id = path.stem
        with path.open("r", encoding="utf-8-sig", newline="") as fh:
            reader = csv.DictReader(fh)
            for row in reader:
                ts = row.get("ts", "")
                for comp, key in component_keys:
                    value = parse_float(row.get(key))
                    if value is None:
                        continue
                    abs_value = abs(value)
                    prev = peaks.get((point_id, comp))
                    if prev is None or abs_value > prev[0]:
                        peaks[(point_id, comp)] = (abs_value, ts)
    output: list[dict] = []
    for (point_id, comp), (peak, ts) in sorted(peaks.items()):
        output.append({"PointID": point_id, "Component": comp, "Peak": peak, "PeakTime": ts})
    return output


def build_eq_section(result_root: Path, image_root: Path) -> SectionContent:
    rows = collect_eq_peak_rows(result_root)
    if not rows:
        return build_missing_section("本月未获取到主桥地震动监测有效数据。")
    horizontal = [row for row in rows if row["Component"] in {"X", "Y"}]
    vertical = [row for row in rows if row["Component"] == "Z"]
    h_peak = numeric_max(horizontal, "Peak")
    v_peak = numeric_max(vertical, "Peak")
    narrative = (
        f"水平向地震动加速度峰值为{format_number_fixed(h_peak, 3, 'm/s²')}，"
        f"竖向地震动加速度峰值为{format_number_fixed(v_peak, 3, 'm/s²')}，典型时程见下图。"
    )
    summary = f"主桥地震动监测中，水平向峰值为{format_number_fixed(h_peak, 3, 'm/s²')}，竖向峰值为{format_number_fixed(v_peak, 3, 'm/s²')}。"
    columns = [
        ("PointID", "测点编号", None),
        ("Component", "分量", None),
        ("Peak", "峰值(m/s²)", None),
        ("PeakTime", "对应时间", None),
    ]
    expected_points = discover_csv_points(result_root, ("DZY-",))
    expected_keys = [(point_id, component) for point_id in expected_points for component in ("X", "Y", "Z")]
    table_rows = build_full_composite_table_rows(
        expected_keys,
        rows,
        ("PointID", "Component"),
        columns,
        formatters={
            "Peak": lambda value: format_table_number(value, 3, True),
            "PeakTime": format_table_datetime,
        },
    )
    image_items = [
        ImageItem("(a) X向地震动时程", find_latest_image_patterns(image_root, "地震动结果/地震动时程", ["EQ_X_*.jpg"])),
        ImageItem("(b) Y向地震动时程", find_latest_image_patterns(image_root, "地震动结果/地震动时程", ["EQ_Y_*.jpg"])),
        ImageItem("(c) Z向地震动时程", find_latest_image_patterns(image_root, "地震动结果/地震动时程", ["EQ_Z_*.jpg"])),
    ]
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="主桥地震动监测统计表",
        table_columns=columns,
        table_rows=table_rows,
        figure_title="主桥地震动监测典型时程曲线图",
        image_items=image_items,
        table_width_mm=None,
    )


def build_traffic_section(wim_root: Path | None) -> SectionContent:
    if wim_root is None or not wim_root.exists():
        return build_missing_section("本月未获取到车辆荷载监测结果。")
    narrative = "本月已检测到车辆荷载监测结果目录，后续将接入九龙江月报的车辆荷载统计与图表。"
    return SectionContent(
        narrative=narrative,
        summary_sentence="车辆荷载监测结果目录已就绪，待接入九龙江月报专用统计逻辑。",
        available=False,
    )


def build_deflection_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "deflection_stats.xlsx")
    if not rows:
        return build_missing_section("本月未获取到主桥挠度监测有效数据。")
    expected_points = resolve_expected_points(cfg, result_root, "deflection", ("NDY-",), fallback_rows=rows)
    orig_columns = [
        ("PointID", "测点编号", None),
        ("OrigMin_mm", "最小值(mm)", None),
        ("OrigMax_mm", "最大值(mm)", None),
        ("OrigMean_mm", "平均值(mm)", None),
    ]
    filt_columns = [
        ("PointID", "测点编号", None),
        ("FiltMin_mm", "最小值(mm)", None),
        ("FiltMax_mm", "最大值(mm)", None),
        ("FiltMean_mm", "平均值(mm)", None),
    ]
    orig_table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        orig_columns,
        formatters=numeric_table_formatters(("OrigMin_mm", "OrigMax_mm", "OrigMean_mm"), 1),
    )
    filt_table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        filt_columns,
        formatters=numeric_table_formatters(("FiltMin_mm", "FiltMax_mm", "FiltMean_mm"), 1),
    )
    orig_lo = numeric_min(rows, "OrigMin_mm")
    orig_hi = numeric_max(rows, "OrigMax_mm")
    orig_mean = numeric_mean(rows, "OrigMean_mm")
    filt_lo = numeric_min(rows, "FiltMin_mm")
    filt_hi = numeric_max(rows, "FiltMax_mm")
    filt_mean = numeric_mean(rows, "FiltMean_mm")
    orig_images: list[ImageItem] = []
    filt_images: list[ImageItem] = []
    for row in choose_representative_points(rows, 4):
        pid = safe_text(row.get("PointID"))
        orig_path, filt_path = find_latest_two_deflection_images(image_root, pid)
        orig_images.append(ImageItem(pid, orig_path))
        filt_images.append(ImageItem(pid, filt_path))
    narrative = (
        f"选取典型监测数据进行分析。主桥挠度原始数据监测值范围为{format_range(orig_lo, orig_hi, 1, 'mm')}，"
        f"平均值约为{format_number(orig_mean, 1, 'mm')}；"
        f"滤波后监测值范围为{format_range(filt_lo, filt_hi, 1, 'mm')}，"
        f"平均值约为{format_number(filt_mean, 1, 'mm')}。"
    )
    summary = (
        f"主桥挠度原始数据监测值范围为{format_range(orig_lo, orig_hi, 1, 'mm')}；"
        f"滤波后监测值范围为{format_range(filt_lo, filt_hi, 1, 'mm')}。"
    )
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        blocks=[
            SectionBlock(
                narrative="原始数据分析结果如下。",
                table_title="主桥挠度原始数据统计表",
                table_columns=orig_columns,
                table_rows=orig_table_rows,
                figure_title="主桥挠度原始数据典型时程曲线图",
                image_items=orig_images,
            ),
            SectionBlock(
                narrative="滤波后数据分析结果如下。",
                table_title="主桥挠度滤波后数据统计表",
                table_columns=filt_columns,
                table_rows=filt_table_rows,
                figure_title="主桥挠度滤波后数据典型时程曲线图",
                image_items=filt_images,
            ),
        ],
    )


def build_main_bearing_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "bearing_displacement_stats.xlsx", lambda row: is_main_bearing(safe_text(row.get("PointID"))))
    columns = [
        ("PointID", "测点编号", None),
        ("FiltMin_mm", "最小值(mm)", None),
        ("FiltMax_mm", "最大值(mm)", None),
        ("FiltMean_mm", "平均值(mm)", None),
    ]
    image_items = make_image_items(
        image_root,
        "时程曲线_支座位移",
        rows,
        lambda pid: [f"BearingDisp_{pid}_*Filt*.jpg", f"BearingDisp_{pid}_*.jpg"],
        lambda row: safe_text(row.get("PointID")),
        limit=4,
    )
    expected_points = resolve_expected_points(cfg, result_root, "bearing_displacement", ("WYJ-",), predicate=is_main_bearing, fallback_rows=rows)
    table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        columns,
        formatters=numeric_table_formatters(("FiltMin_mm", "FiltMax_mm", "FiltMean_mm"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。主桥支座及梁段纵向位移",
        "主桥支座及梁段纵向位移",
        "FiltMin_mm",
        "FiltMax_mm",
        "FiltMean_mm",
        3,
        "mm",
        "主桥支座、梁段纵向位移监测统计表",
        columns,
        "主桥支座、梁段纵向位移典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_gnss_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "gnss_stats.xlsx")
    if not rows:
        return build_missing_section("本月未获取到主桥 GNSS 监测有效数据。")
    columns = [
        ("PointID", "测点编号", None),
        ("ComponentLabel", "分量", None),
        ("Min_mm", "最小值(mm)", None),
        ("Max_mm", "最大值(mm)", None),
        ("PeakToPeak_mm", "峰峰值(mm)", None),
    ]
    pp = numeric_max(rows, "PeakToPeak_mm")
    narrative = f"选取典型监测数据进行分析。主桥拱顶、拱脚 GNSS 位移峰峰值最大约为{format_number(pp, 3, 'mm')}。"
    summary = f"主桥拱顶、拱脚 GNSS 位移峰峰值最大约为{format_number(pp, 3, 'mm')}。"
    image_items = make_image_items(
        image_root,
        "时程曲线_GNSS",
        [row for row in rows if safe_text(row.get('Component')) == 'X'],
        lambda pid: [f"GNSS_{pid}_*.jpg"],
        lambda row: safe_text(row.get("PointID")),
        limit=4,
    )
    expected_points = resolve_expected_points(cfg, result_root, "gnss", ("GNSS-",), fallback_rows=rows)
    expected_keys = [(point_id, component) for point_id in expected_points for component in ("X", "Y")]
    label_map = {"X": "X向位移", "Y": "Y向位移"}
    table_rows = build_full_composite_table_rows(
        expected_keys,
        rows,
        ("PointID", "Component"),
        [("PointID", "测点编号", None), ("Component", "分量代码", None), ("Min_mm", "最小值(mm)", None), ("Max_mm", "最大值(mm)", None), ("PeakToPeak_mm", "峰峰值(mm)", None)],
        formatters={
            "Min_mm": lambda value: format_table_number(value, 3, False),
            "Max_mm": lambda value: format_table_number(value, 3, False),
            "PeakToPeak_mm": lambda value: format_table_number(value, 3, False),
        },
    )
    normalized_rows = []
    for row in table_rows:
        normalized_rows.append(
            {
                "PointID": row["PointID"],
                "ComponentLabel": label_map.get(safe_text(row.get("Component")), safe_text(row.get("Component"), "/")),
                "Min_mm": row["Min_mm"],
                "Max_mm": row["Max_mm"],
                "PeakToPeak_mm": row["PeakToPeak_mm"],
            }
        )
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="主桥 GNSS 位移监测统计表",
        table_columns=columns,
        table_rows=normalized_rows,
        figure_title="主桥 GNSS 位移监测典型时程曲线图",
        image_items=image_items,
    )


def build_vibration_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    try:
        rows = load_section_rows(stats_root, fallback_root, "accel_stats.xlsx", lambda row: safe_text(row.get("PointID")) not in {"", "None"})
    except FileNotFoundError:
        rows = []
    first_mode_detail, first_mode_summary, first_mode_points = summarize_first_mode_frequency(stats_root, fallback_root)
    if not rows and not first_mode_detail:
        return build_missing_section("本月未获取到主桥结构振动监测有效数据。")

    narrative_parts: list[str] = []
    summary_parts: list[str] = []
    if rows:
        abs_peak = max(abs(parse_float(row.get("Min")) or 0.0) if abs(parse_float(row.get("Min")) or 0.0) > abs(parse_float(row.get("Max")) or 0.0) else abs(parse_float(row.get("Max")) or 0.0) for row in rows)
        rms_peak = numeric_max(rows, "RMS10minMax")
        narrative_parts.append(
            f"主桥振动加速度绝对峰值最大约为{format_number(abs_peak, 3, 'm/s²')}，"
            f"10min 均方根最大值约为{format_number(rms_peak, 3, 'm/s²')}。"
        )
        summary_parts.append(
            f"主桥振动加速度绝对峰值最大约为{format_number(abs_peak, 3, 'm/s²')}，"
            f"10min 均方根最大值约为{format_number(rms_peak, 3, 'm/s²')}。"
        )
    if first_mode_detail:
        narrative_parts.append(first_mode_detail)
    if first_mode_summary:
        summary_parts.append(first_mode_summary)
    narrative = "选取典型监测数据进行分析。" + "".join(narrative_parts)
    summary = "".join(summary_parts)
    columns = [
        ("PointID", "测点编号", None),
        ("Min", "最小值(m/s²)", None),
        ("Max", "最大值(m/s²)", None),
        ("RMS10minMax", "10min RMS最大值(m/s²)", None),
    ]
    expected_points = resolve_expected_points(cfg, result_root, "acceleration", ("ZDCQG-",), fallback_rows=rows or [{"PointID": point_id} for point_id in first_mode_points])
    table_rows = (
        build_full_point_table_rows(
            expected_points,
            rows,
            columns,
            formatters=numeric_table_formatters(("Min", "Max", "RMS10minMax"), 3),
        )
        if rows
        else None
    )
    image_items: list[ImageItem] = []
    representative_rows = choose_representative_points(rows, 2) if rows else [{"PointID": point_id} for point_id in pick_evenly([{"PointID": point_id} for point_id in first_mode_points], 2)]
    for row in representative_rows:
        pid = safe_text(row.get("PointID"))
        image_items.append(ImageItem(f"{pid} 振动时程", image_for_point(image_root, "时程曲线_加速度", pid, [f"{pid}_*.jpg"])))
        image_items.append(ImageItem(f"{pid} PSD", image_for_point(image_root, f"PSD_备查/{pid}", pid, [f"PSD_{pid}_*.jpg"])))
        image_items.append(ImageItem(f"{pid} 频谱峰值曲线", image_for_point(image_root, "频谱峰值曲线_加速度", pid, [f"SpecFreq_{pid}_*.jpg"])))
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="主桥结构振动监测统计表" if table_rows else None,
        table_columns=columns if table_rows else None,
        table_rows=table_rows,
        figure_title="主桥结构振动监测典型图（含 PSD）",
        image_items=image_items,
    )


def build_main_strain_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "strain_stats.xlsx", lambda row: is_main_strain(safe_text(row.get("PointID"))))
    columns = [("PointID", "测点编号", None), ("Min", "最小值(με)", None), ("Max", "最大值(με)", None), ("Mean", "平均值(με)", None)]
    image_items = make_image_items(
        image_root,
        "时程曲线_应变",
        rows,
        lambda pid: [f"Strain_{pid}_*.jpg"],
        lambda row: safe_text(row.get("PointID")),
        limit=4,
    )
    expected_points = resolve_expected_points(cfg, result_root, "strain", ("DYBCGQ-", "DYBCQG-"), predicate=is_main_strain, fallback_rows=rows)
    table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        columns,
        formatters=numeric_table_formatters(("Min", "Max", "Mean"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。主桥关键截面应变",
        "主桥应变",
        "Min",
        "Max",
        "Mean",
        3,
        "με",
        "主桥结构应变监测统计表",
        columns,
        "主桥结构应变监测典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_crack_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "crack_stats.xlsx")
    columns = [("PointID", "测点编号", None), ("CrkMin", "最小值(mm)", None), ("CrkMax", "最大值(mm)", None), ("CrkMean", "平均值(mm)", None)]
    image_items = make_image_items(
        image_root,
        "时程曲线_裂缝宽度",
        rows,
        lambda pid: [f"裂缝宽度_{pid}_*.jpg"],
        lambda row: safe_text(row.get("PointID")),
        limit=4,
    )
    if not rows:
        return build_missing_section("本月未获取到主桥裂缝监测有效数据。")
    lo = numeric_min(rows, "CrkMin")
    hi = numeric_max(rows, "CrkMax")
    mean_v = numeric_mean(rows, "CrkMean")
    narrative = (
        f"选取典型监测数据进行分析。主桥裂缝宽度变化范围为{format_range(lo, hi, 3, 'mm')}，"
        f"平均值约为{format_number(mean_v, 3, 'mm')}。"
    )
    summary = f"主桥裂缝宽度变化范围为{format_range(lo, hi, 3, 'mm')}。"
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="主桥裂缝监测统计表",
        table_columns=columns,
        table_rows=build_full_point_table_rows(
            resolve_expected_points(cfg, result_root, "crack", ("LFJ-",), fallback_rows=rows),
            rows,
            columns,
            formatters=numeric_table_formatters(("CrkMin", "CrkMax", "CrkMean"), 3),
        ),
        figure_title="主桥裂缝监测典型时程曲线图",
        image_items=image_items,
    )


def build_cable_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "cable_accel_stats.xlsx")
    if not rows:
        return build_missing_section("本月未获取到吊杆振动监测有效数据。")
    abs_peak = max(abs(parse_float(row.get("Min")) or 0.0) if abs(parse_float(row.get("Min")) or 0.0) > abs(parse_float(row.get("Max")) or 0.0) else abs(parse_float(row.get("Max")) or 0.0) for row in rows)
    rms_peak = numeric_max(rows, "RMS10minMax")
    narrative = (
        f"选取典型监测数据进行分析。吊杆振动加速度绝对峰值最大约为{format_number(abs_peak, 3, 'm/s²')}，"
        f"10min 均方根最大值约为{format_number(rms_peak, 3, 'm/s²')}。"
        "当前吊杆参数配置尚未完整校核，索力换算结果暂仅用于时程展示。"
    )
    summary = f"吊杆振动加速度绝对峰值最大约为{format_number(abs_peak, 3, 'm/s²')}，10min 均方根最大值约为{format_number(rms_peak, 3, 'm/s²')}。"
    columns = [
        ("PointID", "测点编号", None),
        ("Min", "最小值(m/s²)", None),
        ("Max", "最大值(m/s²)", None),
        ("RMS10minMax", "10min RMS最大值(m/s²)", None),
    ]
    expected_points = resolve_expected_points(cfg, result_root, "cable_accel", ("SLCGQ-",), fallback_rows=rows)
    table_rows = build_full_point_table_rows(
        expected_points,
        rows,
        columns,
        formatters=numeric_table_formatters(("Min", "Max", "RMS10minMax"), 3),
    )
    image_items: list[ImageItem] = []
    for row in choose_representative_points(rows, 2):
        pid = safe_text(row.get("PointID"))
        image_items.append(ImageItem(f"{pid} 吊杆加速度时程", image_for_point(image_root, "时程曲线_索力加速度", pid, [f"{pid}_*.jpg"])))
        image_items.append(ImageItem(f"{pid} 索力时程图", image_for_point(image_root, "索力时程图", pid, [f"CableForce_{pid}_*.jpg"])))
    return SectionContent(
        narrative=narrative,
        summary_sentence=summary,
        table_title="吊杆振动监测统计表",
        table_columns=columns,
        table_rows=table_rows,
        figure_title="吊杆振动与索力换算典型图",
        image_items=image_items,
    )


def build_north_strain_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "strain_stats.xlsx", lambda row: is_north_strain(safe_text(row.get("PointID"))))
    columns = [("PointID", "测点编号", None), ("Min", "最小值(με)", None), ("Max", "最大值(με)", None), ("Mean", "平均值(με)", None)]
    image_items = make_image_items(image_root, "时程曲线_应变", rows, lambda pid: [f"Strain_{pid}_*.jpg"], lambda row: safe_text(row.get("PointID")), limit=4)
    table_rows = build_full_point_table_rows(
        resolve_expected_points(cfg, result_root, "strain", ("DYBCGQ-", "DYBCQG-"), predicate=is_north_strain, fallback_rows=rows),
        rows,
        columns,
        formatters=numeric_table_formatters(("Min", "Max", "Mean"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。北江滨匝道桥结构应变",
        "北江滨匝道桥结构应变",
        "Min",
        "Max",
        "Mean",
        3,
        "με",
        "北江滨匝道桥结构应变监测统计表",
        columns,
        "北江滨匝道桥结构应变典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_south_strain_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "strain_stats.xlsx", lambda row: is_south_strain(safe_text(row.get("PointID"))))
    columns = [("PointID", "测点编号", None), ("Min", "最小值(με)", None), ("Max", "最大值(με)", None), ("Mean", "平均值(με)", None)]
    image_items = make_image_items(image_root, "时程曲线_应变", rows, lambda pid: [f"Strain_{pid}_*.jpg"], lambda row: safe_text(row.get("PointID")), limit=4)
    table_rows = build_full_point_table_rows(
        resolve_expected_points(cfg, result_root, "strain", ("DYBCGQ-", "DYBCQG-"), predicate=is_south_strain, fallback_rows=rows),
        rows,
        columns,
        formatters=numeric_table_formatters(("Min", "Max", "Mean"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。南江滨匝道桥结构应变",
        "南江滨匝道桥结构应变",
        "Min",
        "Max",
        "Mean",
        3,
        "με",
        "南江滨匝道桥结构应变监测统计表",
        columns,
        "南江滨匝道桥结构应变典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_north_bearing_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "bearing_displacement_stats.xlsx", lambda row: is_north_bearing(safe_text(row.get("PointID"))))
    columns = [("PointID", "测点编号", None), ("FiltMin_mm", "最小值(mm)", None), ("FiltMax_mm", "最大值(mm)", None), ("FiltMean_mm", "平均值(mm)", None)]
    image_items = make_image_items(image_root, "时程曲线_支座位移", rows, lambda pid: [f"BearingDisp_{pid}_*Filt*.jpg", f"BearingDisp_{pid}_*.jpg"], lambda row: safe_text(row.get("PointID")), limit=4)
    table_rows = build_full_point_table_rows(
        resolve_expected_points(cfg, result_root, "bearing_displacement", ("WYJ-",), predicate=is_north_bearing, fallback_rows=rows),
        rows,
        columns,
        formatters=numeric_table_formatters(("FiltMin_mm", "FiltMax_mm", "FiltMean_mm"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。北江滨匝道桥支座位移",
        "北江滨匝道桥支座位移",
        "FiltMin_mm",
        "FiltMax_mm",
        "FiltMean_mm",
        3,
        "mm",
        "北江滨匝道桥支座位移监测统计表",
        columns,
        "北江滨匝道桥支座位移典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_south_bearing_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "bearing_displacement_stats.xlsx", lambda row: is_south_bearing(safe_text(row.get("PointID"))))
    columns = [("PointID", "测点编号", None), ("FiltMin_mm", "最小值(mm)", None), ("FiltMax_mm", "最大值(mm)", None), ("FiltMean_mm", "平均值(mm)", None)]
    image_items = make_image_items(image_root, "时程曲线_支座位移", rows, lambda pid: [f"BearingDisp_{pid}_*Filt*.jpg", f"BearingDisp_{pid}_*.jpg"], lambda row: safe_text(row.get("PointID")), limit=4)
    table_rows = build_full_point_table_rows(
        resolve_expected_points(cfg, result_root, "bearing_displacement", ("WYJ-",), predicate=is_south_bearing, fallback_rows=rows),
        rows,
        columns,
        formatters=numeric_table_formatters(("FiltMin_mm", "FiltMax_mm", "FiltMean_mm"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。南江滨匝道桥支座位移",
        "南江滨匝道桥支座位移",
        "FiltMin_mm",
        "FiltMax_mm",
        "FiltMean_mm",
        3,
        "mm",
        "南江滨匝道桥支座位移监测统计表",
        columns,
        "南江滨匝道桥支座位移典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_north_tilt_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "tilt_stats.xlsx", lambda row: is_north_tilt(safe_text(row.get("PointID"))))
    columns = [("PointID", "测点编号", None), ("Min", "最小值(°)", None), ("Max", "最大值(°)", None), ("Mean", "平均值(°)", None)]
    image_items = make_image_items(image_root, "时程曲线_倾角", rows, lambda pid: [f"Tilt_{pid}_*.jpg"], lambda row: safe_text(row.get("PointID")), limit=4)
    table_rows = build_full_point_table_rows(
        resolve_expected_points(cfg, result_root, "tilt", (), predicate=is_north_tilt, fallback_rows=rows),
        rows,
        columns,
        formatters=numeric_table_formatters(("Min", "Max", "Mean"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。北江滨匝道桥墩柱倾斜",
        "北江滨匝道桥墩柱倾斜",
        "Min",
        "Max",
        "Mean",
        3,
        "°",
        "北江滨匝道桥墩柱倾斜监测统计表",
        columns,
        "北江滨匝道桥墩柱倾斜典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_south_tilt_section(cfg: dict, result_root: Path, stats_root: Path, fallback_root: Path | None, image_root: Path) -> SectionContent:
    rows = load_section_rows(stats_root, fallback_root, "tilt_stats.xlsx", lambda row: is_south_tilt(safe_text(row.get("PointID"))))
    columns = [("PointID", "测点编号", None), ("Min", "最小值(°)", None), ("Max", "最大值(°)", None), ("Mean", "平均值(°)", None)]
    image_items = make_image_items(image_root, "时程曲线_倾角", rows, lambda pid: [f"Tilt_{pid}_*.jpg"], lambda row: safe_text(row.get("PointID")), limit=4)
    table_rows = build_full_point_table_rows(
        resolve_expected_points(cfg, result_root, "tilt", (), predicate=is_south_tilt, fallback_rows=rows),
        rows,
        columns,
        formatters=numeric_table_formatters(("Min", "Max", "Mean"), 3),
    )
    return build_numeric_summary_section(
        rows,
        "选取典型监测数据进行分析。南江滨匝道桥墩柱倾斜",
        "南江滨匝道桥墩柱倾斜",
        "Min",
        "Max",
        "Mean",
        3,
        "°",
        "南江滨匝道桥墩柱倾斜监测统计表",
        columns,
        "南江滨匝道桥墩柱倾斜典型时程曲线图",
        image_items,
        table_rows_override=table_rows,
    )


def build_section_map(cfg: dict, stats_root: Path, fallback_root: Path | None, result_root: Path, image_root: Path, wim_root: Path | None) -> dict[str, SectionContent]:
    return {
        "main_env": build_temperature_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_humidity": build_humidity_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_rainfall": build_rainfall_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_wind": build_wind_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_eq": build_eq_section(result_root, image_root),
        "main_traffic": build_traffic_section(wim_root),
        "main_deflection": build_deflection_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_bearing": build_main_bearing_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_gnss": build_gnss_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_vibration": build_vibration_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_strain": build_main_strain_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_crack": build_crack_section(cfg, result_root, stats_root, fallback_root, image_root),
        "main_cable": build_cable_section(cfg, result_root, stats_root, fallback_root, image_root),
        "north_strain": build_north_strain_section(cfg, result_root, stats_root, fallback_root, image_root),
        "north_bearing": build_north_bearing_section(cfg, result_root, stats_root, fallback_root, image_root),
        "north_tilt": build_north_tilt_section(cfg, result_root, stats_root, fallback_root, image_root),
        "south_strain": build_south_strain_section(cfg, result_root, stats_root, fallback_root, image_root),
        "south_bearing": build_south_bearing_section(cfg, result_root, stats_root, fallback_root, image_root),
        "south_tilt": build_south_tilt_section(cfg, result_root, stats_root, fallback_root, image_root),
    }


def find_caption_templates(doc: Document) -> CaptionTemplates:
    figure_para = None
    table_para = None
    for para in doc.paragraphs:
        text = para.text.strip()
        if figure_para is None and text.startswith("图 1-1"):
            figure_para = para
        if table_para is None and text.startswith("表 1-1"):
            table_para = para
        if figure_para is not None and table_para is not None:
            break
    if figure_para is None or table_para is None:
        raise ValueError("Unable to locate chapter 1 auto-caption templates.")
    return CaptionTemplates(figure_paragraph=figure_para, table_paragraph=table_para)


def update_cover_metadata(doc: Document, monitoring_range: str, report_date: str) -> None:
    if len(doc.tables) > 1 and len(doc.tables[1].rows) > 1:
        if len(doc.tables[1].rows[1].cells) > 4:
            set_cell_text_preserve(doc.tables[1].rows[1].cells[4], monitoring_range)


def table_cell_text(value: object) -> str:
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, float):
        return f"{value:.6f}".rstrip("0").rstrip(".")
    if value is None:
        return ""
    return str(value)


def render_section_block(anchor: Paragraph, content: SectionBlock, body_template: ParagraphTemplate, caption_templates: CaptionTemplates) -> None:
    if content.narrative:
        add_text_paragraph_before(anchor, content.narrative, body_template)

    if content.table_title and content.table_columns and content.table_rows:
        insert_auto_caption_before(anchor, caption_templates.table_paragraph, content.table_title)
        table = insert_table_before(anchor, rows=len(content.table_rows) + 1, cols=len(content.table_columns))
        style_table(table)
        for col_idx, (_, label, _) in enumerate(content.table_columns):
            set_cell_text_preserve(table.cell(0, col_idx), label)
        for row_idx, row in enumerate(content.table_rows, start=1):
            for col_idx, (key, _, _) in enumerate(content.table_columns):
                set_cell_text_preserve(table.cell(row_idx, col_idx), table_cell_text(row.get(key)))
        set_header_bold(table)
        set_table_outer_border(table, size_eighth_pt=12)
        set_table_autofit(table, True)
        if content.table_width_mm is not None:
            set_table_width(table, content.table_width_mm)
        else:
            set_table_auto_width(table)
        if content.table_width_mm is not None and any(width is not None for _, _, width in content.table_columns):
            set_table_column_widths(table, [width or 26.0 for _, _, width in content.table_columns])
        if content.table_font_size_pt is not None:
            set_table_font_size(table, content.table_font_size_pt)

    valid_images = [item for item in (content.image_items or []) if item.path is not None and item.path.exists()]
    if content.figure_title and valid_images:
        for item in valid_images:
            pic_para = insert_paragraph_before(anchor)
            pic_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
            pic_para.add_run().add_picture(str(item.path), width=Mm(165))
        insert_auto_caption_before(anchor, caption_templates.figure_paragraph, content.figure_title)


def add_section_content(
    doc: Document,
    parent_heading: str,
    child_heading: str,
    content: SectionContent,
    body_template: ParagraphTemplate,
    caption_templates: CaptionTemplates,
    assets_dir: Path,
) -> None:
    heading_para, next_heading = find_section_anchor(doc, parent_heading, child_heading)
    clear_section_between(heading_para, next_heading)
    anchor = next_heading if next_heading is not None else doc.add_paragraph()

    if content.narrative:
        add_text_paragraph_before(anchor, content.narrative, body_template)

    if content.blocks:
        for block in content.blocks:
            render_section_block(anchor, block, body_template, caption_templates)
        return

    render_section_block(
        anchor,
        SectionBlock(
            table_title=content.table_title,
            table_columns=content.table_columns,
            table_rows=content.table_rows,
            figure_title=content.figure_title,
            image_items=content.image_items,
            table_width_mm=content.table_width_mm,
            table_font_size_pt=content.table_font_size_pt,
        ),
        body_template,
        caption_templates,
    )


def update_summary_table(doc: Document, section_map: dict[str, SectionContent]) -> None:
    if len(doc.tables) <= 2:
        return
    summary_table = doc.tables[2]
    result_lines = [
        "1、主桥环境与作用监测",
        "1.1 温度监测",
        section_map["main_env"].summary_sentence,
        "1.2 湿度监测",
        section_map["main_humidity"].summary_sentence,
        "1.3 雨量监测",
        section_map["main_rainfall"].summary_sentence,
        "1.4 风向风速监测",
        section_map["main_wind"].summary_sentence,
        "1.5 地震动监测",
        section_map["main_eq"].summary_sentence,
        "1.6 车辆荷载监测",
        section_map["main_traffic"].summary_sentence,
        "2、主桥结构响应与结构变化监测",
        "2.1 主梁挠度监测",
        section_map["main_deflection"].summary_sentence,
        "2.2 支座、梁段纵向位移监测",
        section_map["main_bearing"].summary_sentence,
        "2.3 拱顶、拱脚位移监测（GNSS）",
        section_map["main_gnss"].summary_sentence,
        "2.4 结构振动监测",
        section_map["main_vibration"].summary_sentence,
        "2.5 结构应变监测",
        section_map["main_strain"].summary_sentence,
        "2.6 裂缝监测",
        section_map["main_crack"].summary_sentence,
        "2.7 吊杆索力监测",
        section_map["main_cable"].summary_sentence,
        "3、北江滨匝道桥监测",
        "3.1 结构应变监测",
        section_map["north_strain"].summary_sentence,
        "3.2 支座位移监测",
        section_map["north_bearing"].summary_sentence,
        "3.3 墩柱倾斜监测",
        section_map["north_tilt"].summary_sentence,
        "4、南江滨匝道桥监测",
        "4.1 结构应变监测",
        section_map["south_strain"].summary_sentence,
        "4.2 支座位移监测",
        section_map["south_bearing"].summary_sentence,
        "4.3 墩柱倾斜监测",
        section_map["south_tilt"].summary_sentence,
    ]
    bold_indices = {0, 1, 3, 5, 7, 9, 11, 12, 13, 15, 17, 19, 21, 23, 25, 26, 27, 29, 31, 33, 34, 35, 37, 39}
    set_cell_paragraphs(summary_table.cell(0, 1), result_lines, bold_indices=bold_indices)
    if len(summary_table.rows) > 1:
        for row in summary_table.rows[1:]:
            for cell in row.cells:
                set_cell_text_preserve(cell, "")


def build_report(
    template: Path,
    config_path: Path,
    result_root: Path,
    image_root: Path | None = None,
    output_dir: Path | None = None,
    wim_root: Path | None = None,
    period_label: str = "2026年3月份",
    monitoring_range: str = "2026.03.23~2026.03.31",
    report_date: str | None = None,
) -> Path:
    if report_date is None:
        report_date = datetime.now().strftime("%Y年%m月%d日")

    cfg = load_json(config_path)
    image_root = image_root or result_root
    output_dir = output_dir or (result_root / "自动报告")
    output_dir = ensure_dir(output_dir)
    assets_dir = ensure_dir(output_dir / "generated_assets_jlj")

    doc = Document(str(template))
    caption_templates = find_caption_templates(doc)
    placeholder_para = next(para for para in doc.paragraphs if "本节用于填充主桥温度监测结果" in para.text)
    body_template = capture_paragraph_template(placeholder_para)

    update_cover_metadata(doc, monitoring_range, report_date)
    apply_health_status_section(doc, cfg, result_root, monitoring_range)
    section_map = build_section_map(cfg, result_root, None, result_root, image_root, wim_root)
    for key, parent_heading, child_heading, _ in JLG_MONTHLY_SECTIONS:
        add_section_content(doc, parent_heading, child_heading, section_map[key], body_template, caption_templates, assets_dir)
    update_summary_table(doc, section_map)
    ending_para = doc.add_paragraph()
    ending_para.add_run("（以下无正文）")
    apply_paragraph_template(ending_para, body_template)
    ending_para.alignment = WD_ALIGN_PARAGRAPH.CENTER

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_docx = output_dir / f"{template.stem}_{period_label}_自动生成_{timestamp}.docx"
    doc.save(str(output_docx))
    update_fields_with_word(output_docx)
    return output_docx


def main() -> None:
    args = parse_args()
    if args.template is None or not args.template.exists():
        raise SystemExit("Template docx not found.")
    if not args.config.exists():
        raise SystemExit("Config file not found.")
    if args.result_root is None:
        raise SystemExit("--result-root is required for Jiulongjiang monthly report.")
    output = build_report(
        template=args.template,
        config_path=args.config,
        result_root=args.result_root,
        image_root=args.image_root,
        output_dir=args.output_dir,
        wim_root=args.wim_root,
        period_label=args.period_label,
        monitoring_range=args.monitoring_range,
        report_date=args.report_date,
    )
    print(f"Jiulongjiang monthly report generated: {output}")


if __name__ == "__main__":
    main()
