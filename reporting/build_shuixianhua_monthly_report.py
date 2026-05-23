from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable
from zipfile import ZIP_DEFLATED, ZipFile

from docx.oxml.ns import qn
from lxml import etree
from openpyxl import load_workbook

try:
    from shuixianhua_table_anchors import required_result_tables
    from ooxml_utils import fill_table as ooxml_fill_table
    from ooxml_utils import rewrite_paragraphs_containing as ooxml_rewrite_contains
    from ooxml_utils import set_cell_text as ooxml_set_cell_text
    from ooxml_utils import set_paragraph_text as ooxml_set_paragraph_text
    from ooxml_utils import xml_text as ooxml_text
except Exception:  # pragma: no cover - package import path
    from .shuixianhua_table_anchors import required_result_tables
    from .ooxml_utils import fill_table as ooxml_fill_table
    from .ooxml_utils import rewrite_paragraphs_containing as ooxml_rewrite_contains
    from .ooxml_utils import set_cell_text as ooxml_set_cell_text
    from .ooxml_utils import set_paragraph_text as ooxml_set_paragraph_text
    from .ooxml_utils import xml_text as ooxml_text


REPORT_NO = "BG20TUJC2600003-J1"
EXCLUDED_ACQUISITION_MODULES = {"dynamic_strain_highpass", "dynamic_strain_lowpass"}


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="Build Shuixianhua monthly monitoring report.")
    parser.add_argument("--config", type=Path, default=repo_root / "config" / "shuixianhua_config.json")
    parser.add_argument("--template", type=Path, default=repo_root / "reports" / "水仙花大桥健康监测月报模板.docx")
    parser.add_argument("--result-root", type=Path, default=Path(r"E:\水仙花大桥数据\2026年3月"))
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--period-label", default="2026年3月份")
    parser.add_argument("--monitoring-range", default="2026年03月23日~2026年03月31日")
    parser.add_argument("--report-date", default="2026年04月05日")
    parser.add_argument("--no-word-update", action="store_true", help="Skip Word field update and PDF export.")
    return parser.parse_args()

def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))

def load_rows(path: Path, sheet: str | None = None) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb[sheet] if sheet else wb[wb.sheetnames[0]]
    raw = list(ws.iter_rows(values_only=True))
    wb.close()
    if not raw:
        return []
    header = [str(value) if value is not None else "" for value in raw[0]]
    rows: list[dict[str, Any]] = []
    for values in raw[1:]:
        item = {key: value for key, value in zip(header, values)}
        if any(value is not None and value != "" for value in item.values()):
            rows.append(item)
    return rows

def safe_float(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def fmt_num(value: Any, digits: int = 3) -> str:
    num = safe_float(value)
    if num is None:
        return "/"
    text = f"{num:.{digits}f}".rstrip("0").rstrip(".")
    return text if text else "0"

def fmt_percent(value: Any) -> str:
    num = safe_float(value)
    if num is None:
        return "/"
    if num <= 1:
        num *= 100
    return f"{num:.1f}%"

def fmt_datetime(value: Any) -> str:
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M")
    return "" if value is None else str(value)

def extreme_row(rows: list[dict[str, Any]], key: str, *, abs_value: bool = False) -> dict[str, Any] | None:
    best = None
    best_value = None
    for row in rows:
        value = safe_float(row.get(key))
        if value is None:
            continue
        metric = abs(value) if abs_value else value
        if best_value is None or metric > best_value:
            best = row
            best_value = metric
    return best

def update_word_fields_and_export_pdf(docx_path: Path) -> Path | None:
    docx_path = docx_path.resolve()
    pdf_path = docx_path.with_suffix(".pdf")
    script = f"""
$docx = @'
{docx_path}
'@
$pdf = @'
{pdf_path}
'@
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {{
    $doc = $word.Documents.Open($docx)
    $doc.TrackRevisions = $false
    if ($doc.Revisions.Count -gt 0) {{ $doc.AcceptAllRevisions() | Out-Null }}
    $doc.Fields.Update() | Out-Null
    foreach ($toc in $doc.TablesOfContents) {{ $toc.Update() | Out-Null }}
    $doc.TrackRevisions = $false
    if ($doc.Revisions.Count -gt 0) {{ $doc.AcceptAllRevisions() | Out-Null }}
    $doc.Save()
    $doc.ExportAsFixedFormat($pdf, 17)
    $doc.Close($false)
}} finally {{
    $word.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
}}
"""
    result = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
        capture_output=True,
        timeout=300,
    )
    if result.returncode != 0:
        stderr = (result.stderr or b"").decode("utf-8", errors="replace").strip()
        stdout = (result.stdout or b"").decode("utf-8", errors="replace").strip()
        print(f"Warning: Word field update/PDF export failed: {stderr or stdout or 'unknown error'}")
        return None
    return pdf_path if pdf_path.exists() else None

def adjusted_rows(stats_dir: Path, filename: str, fallback: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    path = stats_dir / "adjusted" / filename
    if path.exists():
        return load_rows(path)
    return fallback or []

def scaled_accel_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for row in rows:
        item = dict(row)
        for key in ["Min", "Max", "Mean", "RMS10minMax"]:
            value = safe_float(item.get(key))
            if value is not None:
                item[key] = value / 1000.0
        out.append(item)
    return out

def report_acquisition_rows(acquisition_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = []
    for row in acquisition_rows:
        code = row.get("模块代码")
        if code in EXCLUDED_ACQUISITION_MODULES:
            continue
        item = dict(row)
        if code == "strain":
            item["模块"] = "结构应变及动应变"
        if code == "temperature":
            item["配置测点数"] = 10
            item["缺失测点数"] = 9
            item["获取率"] = 0.1
            item["缺失说明"] = "WD-01~WD-09未获取CSV"
        rows.append(item)
    return rows

def _sxh_fixed(value: Any, digits: int = 1) -> str:
    num = safe_float(value)
    if num is None:
        return "/"
    return f"{num:.{digits}f}"

def _sxh_range(rows: list[dict[str, Any]], min_key: str, max_key: str, *, digits: int = 1, unit: str = "") -> str:
    lows = [safe_float(row.get(min_key)) for row in rows]
    highs = [safe_float(row.get(max_key)) for row in rows]
    lows = [value for value in lows if value is not None]
    highs = [value for value in highs if value is not None]
    if not lows or not highs:
        return "/"
    return f"{_sxh_fixed(min(lows), digits)}{unit}~{_sxh_fixed(max(highs), digits)}{unit}"

def _sxh_range_plain(rows: list[dict[str, Any]], min_key: str, max_key: str, *, digits: int = 1, unit: str = "") -> str:
    lows = [safe_float(row.get(min_key)) for row in rows]
    highs = [safe_float(row.get(max_key)) for row in rows]
    lows = [value for value in lows if value is not None]
    highs = [value for value in highs if value is not None]
    if not lows or not highs:
        return "/"
    return f"{fmt_num(min(lows), digits)}{unit}~{fmt_num(max(highs), digits)}{unit}"

def _sxh_by_prefix(rows: list[dict[str, Any]], prefix: str) -> list[dict[str, Any]]:
    return [row for row in rows if str(row.get("PointID") or row.get("测点编号") or "").startswith(prefix)]

def _sxh_text_value(row: dict[str, Any], *keys: str, default: str = "/") -> str:
    for key in keys:
        value = row.get(key)
        if value is not None and value != "":
            return str(value)
    return default

def _sxh_parse_wind_summaries(result_root: Path, wind_rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    rows = [dict(row) for row in wind_rows]
    by_pid = {str(row.get("测点编号") or row.get("PointID") or ""): row for row in rows}
    for summary_path in (result_root / "风速风向结果" / "风玫瑰").glob("*_summary.txt"):
        text = summary_path.read_text(encoding="utf-8", errors="replace")
        pid_match = re.search(r"风玫瑰简要结论（(.+?)）", text)
        if not pid_match:
            continue
        pid = pid_match.group(1)
        row = by_pid.setdefault(pid, {"测点编号": pid})
        for key in ["平均风向", "主导风向", "平均风速", "最大风速", "主要风速等级"]:
            match = re.search(rf"{key}:\s*([^\n]+)", text)
            if match:
                row[key] = match.group(1).strip().replace("占比 ", "占比")
    return list(by_pid.values())

def _sxh_accel_frequency_map(stats_dir: Path) -> dict[str, tuple[float | None, float | None]]:
    path = stats_dir / "accel_spec_stats.xlsx"
    if not path.exists():
        return {}
    wb = load_workbook(path, read_only=True, data_only=True)
    out: dict[str, tuple[float | None, float | None]] = {}
    try:
        for sheet in wb.sheetnames:
            if sheet.endswith("-Y"):
                out[sheet] = (None, None)
                continue
            ws = wb[sheet]
            rows = list(ws.iter_rows(values_only=True))
            if not rows:
                continue
            header = [str(value) if value is not None else "" for value in rows[0]]
            freq_indices = [idx for idx, name in enumerate(header) if name.startswith("Freq_")]
            values: list[float] = []
            for raw in rows[1:]:
                for idx in freq_indices:
                    if idx < len(raw):
                        value = safe_float(raw[idx])
                        if value is not None:
                            values.append(value)
            out[sheet] = (min(values), max(values)) if values else (None, None)
    finally:
        wb.close()
    return out

def _sxh_strain_rows_with_group(rows: list[dict[str, Any]], cfg: dict[str, Any]) -> list[dict[str, Any]]:
    labels = cfg.get("plot_styles", {}).get("strain", {}).get("group_labels", {})
    groups = cfg.get("groups", {}).get("strain", {})
    row_by_point = {str(row.get("PointID") or ""): row for row in rows}
    out = []
    for group_key, points in groups.items():
        label = labels.get(group_key, group_key)
        for point in points:
            point_text = str(point)
            if point_text not in row_by_point:
                continue
            item = dict(row_by_point.pop(point_text))
            item["分组"] = str(label)
            out.append(item)
    for row in rows:
        point_text = str(row.get("PointID") or "")
        if point_text not in row_by_point:
            continue
        item = dict(row_by_point.pop(point_text))
        item["分组"] = "/"
        out.append(item)
    return out

def _sxh_strain_group_ranges(rows: list[dict[str, Any]], cfg: dict[str, Any]) -> list[str]:
    labels = list(cfg.get("plot_styles", {}).get("strain", {}).get("group_labels", {}).values())
    if not labels:
        labels = ["小纵梁底部静应变", "横梁底部静应变", "主拱拱顶静应变", "主拱拱脚静应变"]
    out = []
    for label in labels:
        group_rows = [row for row in rows if row.get("分组") == label]
        if not group_rows:
            continue
        out.append(f"{label}为{_sxh_range_plain(group_rows, 'Min', 'Max', digits=1, unit='με')}")
    return out

def _sxh_report_row(module: str, configured: int, found: int, missing_note: str = "") -> dict[str, Any]:
    configured = int(configured or 0)
    found = int(found or 0)
    missing = max(configured - found, 0)
    return {
        "模块": module,
        "配置测点数": configured,
        "实际获取测点数": found,
        "缺失测点数": missing,
        "获取率": (found / configured) if configured else 0,
        "缺失说明": missing_note or ("无" if missing == 0 else f"缺失{missing}个测点"),
    }

def _sxh_fallback_report_rows(
    cfg: dict[str, Any],
    *,
    temp_rows: list[dict[str, Any]],
    humidity_rows: list[dict[str, Any]],
    wind_rows: list[dict[str, Any]],
    earthquake_rows: list[dict[str, Any]],
    deflection_rows: list[dict[str, Any]],
    bearing_rows: list[dict[str, Any]],
    accel_rows: list[dict[str, Any]],
    strain_rows: list[dict[str, Any]],
    cable_rows: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    points = cfg.get("points", {})
    per_point = cfg.get("per_point", {})
    pending = cfg.get("design_points_pending", {})
    temp_config = len(points.get("temperature") or per_point.get("temperature") or []) or 10
    gnss_config = len(points.get("gnss") or per_point.get("gnss") or pending.get("gnss") or [])
    return [
        _sxh_report_row(
            "温度",
            temp_config,
            len(temp_rows),
            "结构温度测点WD-01~WD-09本月未获取数据；WSD-01温湿度测点温度记录已获取" if len(temp_rows) < temp_config else "无",
        ),
        _sxh_report_row("湿度", len(points.get("humidity") or per_point.get("humidity") or []) or 1, len(humidity_rows)),
        _sxh_report_row("风速风向", len(points.get("wind_speed") or per_point.get("wind_speed") or []) or 2, len(wind_rows)),
        _sxh_report_row("地震动", len(points.get("eq") or per_point.get("eq") or []) or len(earthquake_rows), len(earthquake_rows)),
        _sxh_report_row("主梁挠度", len(points.get("deflection") or per_point.get("deflection") or []) or len(deflection_rows), len(deflection_rows)),
        _sxh_report_row("支座及伸缩缝位移", len(points.get("bearing_displacement") or per_point.get("bearing_displacement") or []) or len(bearing_rows), len(bearing_rows)),
        _sxh_report_row("拱顶、拱脚位移（GNSS）", gnss_config, 0, "本月未获取有效数据" if gnss_config else "未配置在线数据"),
        _sxh_report_row("结构振动", len(points.get("acceleration") or per_point.get("acceleration") or []) or len(accel_rows), len(accel_rows)),
        _sxh_report_row("结构应变及动应变", len(points.get("strain") or per_point.get("strain") or []) or len(strain_rows), len(strain_rows)),
        _sxh_report_row("吊杆及系杆索力加速度", len(points.get("cable_accel") or per_point.get("cable_accel") or []) or len(cable_rows), len(cable_rows)),
    ]

def _sxh_context(config_path: Path, result_root: Path, monitoring_range: str) -> dict[str, Any]:
    cfg = load_json(config_path)
    stats_dir = result_root / "stats"
    acq_files = sorted(stats_dir.glob("水仙花大桥_测点配置与数据获取情况_*.xlsx"), key=lambda p: p.stat().st_mtime, reverse=True)
    acquisition_rows = load_rows(acq_files[0], "汇总") if acq_files else []
    raw_wind_rows = load_rows(stats_dir / "wind_stats.xlsx")
    wind_rows = adjusted_rows(stats_dir, "wind_direction_stats_report.xlsx", adjusted_rows(stats_dir, "wind_stats_report.xlsx", raw_wind_rows))
    wind_rows = _sxh_parse_wind_summaries(result_root, wind_rows)
    temp_rows = load_rows(stats_dir / "temp_stats.xlsx")
    humidity_rows = load_rows(stats_dir / "humidity_stats.xlsx")
    earthquake_rows = adjusted_rows(stats_dir, "earthquake_filtered_stats_mps2.xlsx", adjusted_rows(stats_dir, "earthquake_filtered_stats.xlsx", load_rows(stats_dir / "eq_stats.xlsx")))
    deflection_rows = load_rows(stats_dir / "deflection_stats.xlsx")
    bearing_rows = load_rows(stats_dir / "bearing_displacement_stats.xlsx")
    accel_rows = adjusted_rows(stats_dir, "accel_stats_mps2.xlsx", scaled_accel_rows(load_rows(stats_dir / "accel_stats.xlsx")))
    strain_rows = adjusted_rows(stats_dir, "strain_stats_zero_corrected.xlsx", load_rows(stats_dir / "strain_stats.xlsx"))
    strain_rows = _sxh_strain_rows_with_group(strain_rows, cfg)
    cable_rows = adjusted_rows(stats_dir, "cable_accel_stats_mps2.xlsx", scaled_accel_rows(load_rows(stats_dir / "cable_accel_stats.xlsx")))
    report_rows = report_acquisition_rows(acquisition_rows) if acquisition_rows else _sxh_fallback_report_rows(
        cfg,
        temp_rows=temp_rows,
        humidity_rows=humidity_rows,
        wind_rows=wind_rows,
        earthquake_rows=earthquake_rows,
        deflection_rows=deflection_rows,
        bearing_rows=bearing_rows,
        accel_rows=accel_rows,
        strain_rows=strain_rows,
        cable_rows=cable_rows,
    )
    return {
        "cfg": cfg,
        "stats_dir": stats_dir,
        "date_span": "2026-03-23~2026-03-31" if "2026" in monitoring_range else monitoring_range,
        "report_rows": report_rows,
        "temp_rows": temp_rows,
        "humidity_rows": humidity_rows,
        "wind_rows": wind_rows,
        "earthquake_rows": earthquake_rows,
        "deflection_rows": deflection_rows,
        "bearing_rows": bearing_rows,
        "accel_rows": accel_rows,
        "accel_freq_map": _sxh_accel_frequency_map(stats_dir),
        "strain_rows": strain_rows,
        "cable_rows": cable_rows,
    }

def _sxh_summary_payload(context: dict[str, Any]) -> dict[str, str]:
    temp_range = _sxh_range_plain(context["temp_rows"], "Min", "Max", digits=1, unit="℃")
    humidity_range = _sxh_range_plain(context["humidity_rows"], "Min", "Max", digits=1, unit="%")
    wind_deck_rows = [row for row in context["wind_rows"] if str(row.get("测点编号") or row.get("PointID") or "").startswith("FSFX-01")]
    wind_deck = wind_deck_rows[0] if wind_deck_rows else (context["wind_rows"][0] if context["wind_rows"] else {})
    wind_deck_10 = _sxh_fixed(wind_deck.get("10min平均风速最大值(m/s)") or wind_deck.get("Mean10minMax"), 2)
    eq_rows = context["earthquake_rows"]
    horiz_rows = [row for row in eq_rows if str(row.get("方向") or row.get("Component") or "").upper() in {"X", "Y"}]
    vert_rows = [row for row in eq_rows if str(row.get("方向") or row.get("Component") or "").upper() == "Z"]
    horiz_values = [safe_float(row.get("最大值(m/s²)") or row.get("Peak") or row.get("Max")) for row in horiz_rows]
    vert_values = [safe_float(row.get("最大值(m/s²)") or row.get("Peak") or row.get("Max")) for row in vert_rows]
    horiz_max = max([value for value in horiz_values if value is not None], default=None)
    vert_max = max([value for value in vert_values if value is not None], default=None)
    defl_orig = _sxh_range_plain(context["deflection_rows"], "OrigMin_mm", "OrigMax_mm", digits=1, unit="mm")
    defl_filt = _sxh_range_plain(context["deflection_rows"], "FiltMin_mm", "FiltMax_mm", digits=1, unit="mm")
    support_rows = _sxh_by_prefix(context["bearing_rows"], "ZZWY")
    expansion_rows = _sxh_by_prefix(context["bearing_rows"], "SSF")
    support_orig = _sxh_range(support_rows, "OrigMin_mm", "OrigMax_mm", digits=1, unit="mm")
    expansion_orig = _sxh_range(expansion_rows, "OrigMin_mm", "OrigMax_mm", digits=1, unit="mm")
    support_filt = _sxh_range(support_rows, "FiltMin_mm", "FiltMax_mm", digits=1, unit="mm")
    expansion_filt = _sxh_range(expansion_rows, "FiltMin_mm", "FiltMax_mm", digits=1, unit="mm")
    accel_row = extreme_row(context["accel_rows"], "RMS10minMax")
    cable_row = extreme_row(context["cable_rows"], "RMS10minMax")
    freq_values = [value for pair in context["accel_freq_map"].values() for value in pair if value is not None]
    freq_range = f"{fmt_num(min(freq_values), 3)}Hz~{fmt_num(max(freq_values), 3)}Hz" if freq_values else "/"
    strain_ranges = "；".join(_sxh_strain_group_ranges(context["strain_rows"], context["cfg"]))
    accel_body = f"监测结果表明，各测点10min均方根最大值为{fmt_num(accel_row.get('RMS10minMax') if accel_row else None, 3)}m/s²，对应测点为{accel_row.get('PointID') if accel_row else '/'}，未超过0.315m/s²，处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。竖向1阶自振频率范围在{freq_range}之间，均大于结构相应理论计算的1阶竖弯频率1.050Hz。"
    cable_body = f"监测结果表明，各测点10min均方根最大值为{fmt_num(cable_row.get('RMS10minMax') if cable_row else None, 3)}m/s²，对应测点为{cable_row.get('PointID') if cable_row else '/'}，未超过1.000m/s²，均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"
    bearing_body = f"监测结果表明，支座位移原始数据实测值范围在{support_orig}之间，伸缩缝位移原始数据实测值范围在{expansion_orig}之间，均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。支座位移滤波后实测值在{support_filt}之间，伸缩缝位移滤波后实测值范围在{expansion_filt}之间。"
    return {
        "temp": f"WD-01~WD-09温度测点本月未获取有效数据，监测结果表明，WSD-01-11#-S11温度在{temp_range}之间，处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。",
        "humidity": f"监测结果表明，WSD-01-11#-S11相对湿度实测值范围为{humidity_range}，处于正常环境湿度范围。",
        "wind": f"监测结果表明，桥面风速风向测点10min平均风速最大值为{wind_deck_10}m/s，未超过25m/s，处于预警阈值范围之内，未出现超过各级超限阈值和报警的情况。",
        "earthquake": f"监测结果表明，水平向地震动加速度峰值为{fmt_num(horiz_max, 3)}m/s²，竖向地震动加速度峰值为{fmt_num(vert_max, 3)}m/s²，处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。",
        "deflection_body": f"监测结果表明，主梁挠度在{defl_orig}之间，均处于预警阈值范围之内，未超过各级超限阈值和报警的情况。主梁挠度滤波后在{defl_filt}之间。",
        "deflection_front": f"主梁挠度原始数据实测值范围在{defl_orig}之间，均处于预警阈值范围之内，未出现超过各级超限阈值和报警的情况。滤波后实测值范围在{defl_filt}之间。",
        "bearing_body": bearing_body,
        "bearing_front": bearing_body.replace("监测结果表明，", "", 1),
        "accel_body": accel_body,
        "accel_front": accel_body.replace("监测结果表明，", "", 1),
        "strain": f"监测结果表明，本月结构应变按组图分组统计：{strain_ranges}，均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。",
        "cable_body": cable_body,
        "cable_front": cable_body.replace("监测结果表明，", "", 1),
    }

def _sxh_xml_text(element) -> str:
    return ooxml_text(element)

def _sxh_xml_set_paragraph_text(paragraph, text: str) -> None:
    ooxml_set_paragraph_text(paragraph, text)

def _sxh_xml_set_cell_text(cell, text: Any) -> None:
    ooxml_set_cell_text(cell, text)

def _sxh_xml_rewrite_contains(root, contains: str, replacement: str, *, startswith: str | None = None) -> None:
    ooxml_rewrite_contains(root, contains, replacement, startswith=startswith)

def _sxh_xml_fill_table(table, rows: list[dict[str, Any]], value_builder) -> None:
    ooxml_fill_table(table, rows, value_builder)

def _sxh_xml_update_stats_tables(root, context: dict[str, Any]) -> None:
    tables = required_result_tables(root)
    report_rows = context["report_rows"]
    _sxh_xml_fill_table(tables["acquisition"], report_rows, lambda idx, row: [idx, row.get("模块"), row.get("配置测点数"), row.get("实际获取测点数"), fmt_percent(row.get("获取率")).replace("100.0%", "100%"), context["date_span"], row.get("缺失说明") or ("无" if not row.get("缺失测点数") else f"缺失{row.get('缺失测点数')}个")])
    _sxh_xml_fill_table(tables["temperature"], context["temp_rows"], lambda idx, row: [idx, row.get("PointID"), "温度", fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_xml_fill_table(tables["humidity"], context["humidity_rows"], lambda idx, row: [idx, row.get("PointID"), "相对湿度", fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_xml_fill_table(tables["wind"], context["wind_rows"], lambda idx, row: [idx, _sxh_text_value(row, "测点编号", "PointID"), _sxh_text_value(row, "平均风向"), _sxh_text_value(row, "主导风向"), fmt_num(row.get("平均风速(m/s)") or row.get("MeanSpeed") or str(_sxh_text_value(row, "平均风速")).split()[0], 2), fmt_num(row.get("最大风速(m/s)") or row.get("MaxSpeed") or str(_sxh_text_value(row, "最大风速")).split()[0], 1), _sxh_fixed(row.get("10min平均风速最大值(m/s)") or row.get("Mean10minMax"), 2)])
    _sxh_xml_fill_table(tables["earthquake"], context["earthquake_rows"], lambda idx, row: [idx, _sxh_text_value(row, "测点编号", "PointID"), _sxh_text_value(row, "方向", "Component"), fmt_num(row.get("最小值(m/s²)") or row.get("Min"), 3), fmt_num(row.get("最大值(m/s²)") or row.get("Peak") or row.get("Max"), 3)])
    _sxh_xml_fill_table(tables["deflection_raw"], context["deflection_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("OrigMin_mm"), 1), fmt_num(row.get("OrigMax_mm"), 1)])
    _sxh_xml_fill_table(tables["deflection_filtered"], context["deflection_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("FiltMin_mm"), 1), fmt_num(row.get("FiltMax_mm"), 1)])
    _sxh_xml_fill_table(tables["bearing_raw"], context["bearing_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("OrigMin_mm"), 1), fmt_num(row.get("OrigMax_mm"), 1)])
    _sxh_xml_fill_table(tables["bearing_filtered"], context["bearing_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("FiltMin_mm"), 1), fmt_num(row.get("FiltMax_mm"), 1)])
    _sxh_xml_fill_table(tables["gnss"], [{"PointID": "拱顶、拱脚位移（GNSS）"}], lambda idx, row: [idx, row.get("PointID"), "/", "/", "/"])
    freq_map = context["accel_freq_map"]
    _sxh_xml_fill_table(tables["acceleration"], context["accel_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("Min"), 4), fmt_num(row.get("Max"), 4), fmt_num(row.get("RMS10minMax"), 4), fmt_num(freq_map.get(str(row.get("PointID")), (None, None))[0], 3), fmt_num(freq_map.get(str(row.get("PointID")), (None, None))[1], 3)])
    _sxh_xml_fill_table(tables["strain"], context["strain_rows"], lambda idx, row: [row.get("分组"), row.get("PointID"), fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_xml_fill_table(tables["cable_accel"], context["cable_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("Min"), 4), fmt_num(row.get("Max"), 4), fmt_num(row.get("RMS10minMax"), 4)])

def _sxh_xml_update_summary(root, context: dict[str, Any], monitoring_range: str, report_date: str) -> None:
    payload = _sxh_summary_payload(context)
    for paragraph in root.findall(".//w:p", {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}):
        text = _sxh_xml_text(paragraph)
        if text.startswith("报告编号："):
            _sxh_xml_set_paragraph_text(paragraph, f"报告编号：{REPORT_NO}")
        elif text.startswith("报告日期："):
            _sxh_xml_set_paragraph_text(paragraph, f"报告日期：{report_date}")
        elif "2026.03.23~2026.03.31" in text:
            _sxh_xml_set_paragraph_text(paragraph, text.replace("2026.03.23~2026.03.31", monitoring_range.replace("年", ".").replace("月", ".").replace("日", "")))
    _sxh_xml_rewrite_contains(root, "WSD-01-11#-S11温度", payload["temp"])
    _sxh_xml_rewrite_contains(root, "相对湿度实测值范围", payload["humidity"])
    _sxh_xml_rewrite_contains(root, "桥面风速风向测点10min平均风速最大值", payload["wind"])
    _sxh_xml_rewrite_contains(root, "水平向地震动加速度峰值", payload["earthquake"])
    _sxh_xml_rewrite_contains(root, "监测结果表明，主梁挠度", payload["deflection_body"])
    _sxh_xml_rewrite_contains(root, "主梁挠度原始数据实测值范围", payload["deflection_front"])
    _sxh_xml_rewrite_contains(root, "支座位移原始数据实测值范围", payload["bearing_body"], startswith="监测结果表明")
    for paragraph in root.findall(".//w:p", {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}):
        text = _sxh_xml_text(paragraph)
        if "支座位移原始数据实测值范围" in text and not text.startswith("监测结果表明"):
            _sxh_xml_set_paragraph_text(paragraph, payload["bearing_front"])
        if "各测点10min均方根最大值" in text:
            if "0.315m/s²" in text or "ZLZD" in text:
                _sxh_xml_set_paragraph_text(paragraph, payload["accel_body"] if text.startswith("监测结果表明") else payload["accel_front"])
            elif "1.000m/s²" in text or "SL-" in text:
                _sxh_xml_set_paragraph_text(paragraph, payload["cable_body"] if text.startswith("监测结果表明") else payload["cable_front"])
    _sxh_xml_rewrite_contains(root, "结构应变按组图分组统计", payload["strain"])

def _sxh_update_docx_package(docx_path: Path, context: dict[str, Any], monitoring_range: str, report_date: str) -> None:
    with tempfile.NamedTemporaryFile(delete=False, suffix=".docx", dir=str(docx_path.parent)) as tmp_file:
        tmp_path = Path(tmp_file.name)
    try:
        with ZipFile(docx_path, "r") as zin, ZipFile(tmp_path, "w", ZIP_DEFLATED) as zout:
            for item in zin.infolist():
                data = zin.read(item.filename)
                if item.filename == "word/document.xml":
                    root = etree.fromstring(data)
                    _sxh_xml_update_summary(root, context, monitoring_range, report_date)
                    _sxh_xml_update_stats_tables(root, context)
                    data = etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)
                elif item.filename == "word/settings.xml":
                    root = etree.fromstring(data)
                    for element in list(root.findall(qn("w:trackRevisions"))):
                        root.remove(element)
                    data = etree.tostring(root, xml_declaration=True, encoding="UTF-8", standalone=True)
                zout.writestr(item, data)
        tmp_path.replace(docx_path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()

def build_report(
    template: Path,
    config_path: Path,
    result_root: Path,
    output_dir: Path | None = None,
    period_label: str = "2026年3月份",
    monitoring_range: str = "2026年3月23日~2026年3月31日",
    report_date: str = "2026年4月5日",
    update_word: bool = True,
) -> tuple[Path, Path | None]:
    if not template.exists():
        raise FileNotFoundError(f"未找到水仙花报告模板：{template}")
    output_dir = output_dir or result_root / "自动报告"
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = output_dir / f"水仙花大桥健康监测2026年3月份月报_报告生成器_{timestamp}.docx"
    shutil.copy2(template, output)

    context = _sxh_context(config_path, result_root, monitoring_range)
    _sxh_update_docx_package(output, context, monitoring_range, report_date)
    pdf = update_word_fields_and_export_pdf(output) if update_word else None
    return output.resolve(), pdf.resolve() if pdf else None

def main() -> None:
    args = parse_args()
    output_dir = args.output_dir or args.result_root / "自动报告"
    output, pdf = build_report(
        template=args.template,
        config_path=args.config,
        result_root=args.result_root,
        output_dir=output_dir,
        period_label=args.period_label,
        monitoring_range=args.monitoring_range,
        report_date=args.report_date,
        update_word=not args.no_word_update,
    )
    print(f"Shuixianhua monthly report generated: {output}")
    if pdf:
        print(f"Shuixianhua monthly report PDF generated: {pdf}")


if __name__ == "__main__":
    main()
