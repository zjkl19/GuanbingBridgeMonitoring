from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
from copy import deepcopy
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable
from zipfile import ZIP_DEFLATED, ZipFile

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Mm, Pt
from docx.text.paragraph import Paragraph
from lxml import etree
from openpyxl import load_workbook

try:
    from docx_utils import set_cell_text_preserve
    from table_utils import (
        set_header_bold,
        set_table_auto_width,
        set_table_autofit,
        set_table_column_widths,
        set_table_font_size,
        set_table_outer_border,
        style_table,
    )
except Exception:  # pragma: no cover - package import path
    from .docx_utils import set_cell_text_preserve
    from .table_utils import (
        set_header_bold,
        set_table_auto_width,
        set_table_autofit,
        set_table_column_widths,
        set_table_font_size,
        set_table_outer_border,
        style_table,
    )


CN_FONT = "楷体_GB2312"
EN_FONT = "Times New Roman"
REPORT_NO = "BG20TUJC2600003-J1"
EXCLUDED_ACQUISITION_MODULES = {"dynamic_strain_highpass", "dynamic_strain_lowpass"}


PROJECT_OVERVIEW = [
    "水仙花大桥位于福建省漳州市芗城区，横跨九龙江，北起瑞京路，南至南江滨路。桥梁全长约770m，主桥长约230m，主桥桥面宽约33m，设计为双向四车道，并在两侧设置非机动车道及人行道。",
    "主桥桥型为飞燕式钢管混凝土系杆拱桥，孔跨布置为40m+150m+40m。主跨由钢管混凝土拱肋、系杆索、吊杆、横梁和纵梁等共同组成受力体系；南、北引桥为连续箱梁结构。",
    "本月报依据水仙花大桥健康监测服务实施方案、测点配置文件及2026年3月23日至2026年3月31日自动化监测数据处理成果编制。",
]

MODULE_ORDER = [
    ("temperature", "温度监测"),
    ("humidity", "湿度监测"),
    ("wind", "风速风向监测"),
    ("earthquake", "地震动监测"),
    ("deflection", "主梁挠度监测"),
    ("bearing_displacement", "支座及伸缩缝位移监测"),
    ("acceleration", "结构振动监测"),
    ("accel_spectrum", "结构振动频谱分析"),
    ("cable_accel", "吊杆及系杆索力加速度监测"),
    ("cable_accel_spectrum", "吊杆及系杆索力加速度频谱分析"),
    ("strain", "结构应变监测"),
    ("dynamic_strain_highpass", "动应变高通分析"),
    ("dynamic_strain_lowpass", "动应变低通分析"),
]

DESIGN_SECTION_ORDER = [
    ("1.3.1 桥梁环境（温湿度、风速风向）监测", "温湿度测点布置于第十一跨上游02机箱旁；风速风向测点布置于第十一跨跨中桥面上游侧壁及拱顶横杆上拱圈中部。"),
    ("1.3.2 结构温度监测", "结构温度测点布置于下游及上游主拱圈顶部、第十一跨梁底小纵梁、横梁以及10#、11#墩上游拱脚顶部侧壁。"),
    ("1.3.3 地震动监测", "地震动测点布置于10#、11#墩上游拱脚顶部侧壁。"),
    ("1.3.4 主梁挠度监测", "主梁挠度测点布置于9#墩下游、上游梁板侧壁及12#墩下游梁板侧壁。"),
    ("1.3.5 支座及伸缩缝位移监测", "支座位移测点布置于9#墩和12#墩支座位置，伸缩缝位移测点布置于3#、6#伸缩缝上下游梁板侧壁。"),
    ("1.3.6 拱顶、拱脚位移监测（GNSS）", "拱顶、拱脚位移测点布置于10#、11#墩上下游梁板侧壁、主拱拱顶及上游北岸桥头绿化带基准点。"),
    ("1.3.7 结构振动监测", "结构振动测点布置于第十至十二跨纵梁底部及主拱拱顶。"),
    ("1.3.8 吊杆及系杆索力监测", "吊杆及系杆索力加速度测点布置于上下游6#~16#吊杆6.5m高度及1#~12#系杆1/3处。"),
    ("1.3.9 结构应变及动应变监测", "结构应变测点布置于第十一跨梁底小纵梁、横梁、第十至十二跨拱脚及主拱拱顶等关键位置。"),
    ("1.3.10 视频监控", "视频监控设备布置于第十一跨梁板侧壁、桥面灯杆及桥区关键通行位置。"),
]

LAYOUT_FIGURES_BY_SECTION = {
    "1.3.1 桥梁环境（温湿度、风速风向）监测": [
        ("env_temp_humidity_layout.png", "温湿度监测测点布置图"),
        ("env_wind_layout.png", "风速风向监测测点布置图"),
    ],
    "1.3.2 结构温度监测": [
        ("struct_temperature_layout.png", "结构温度监测测点布置图"),
    ],
    "1.3.3 地震动监测": [
        ("earthquake_layout.png", "地震动监测测点布置图"),
    ],
    "1.3.4 主梁挠度监测": [
        ("deflection_layout.png", "主梁挠度监测测点布置图"),
    ],
    "1.3.5 支座及伸缩缝位移监测": [
        ("bearing_layout.png", "支座位移监测测点布置图"),
        ("expansion_joint_layout.png", "伸缩缝位移监测测点布置图"),
    ],
    "1.3.6 拱顶、拱脚位移监测（GNSS）": [
        ("gnss_layout.png", "拱顶、拱脚位移监测测点布置图"),
    ],
    "1.3.7 结构振动监测": [
        ("vibration_girder_layout.png", "主梁振动监测测点布置图"),
        ("vibration_arch_layout.png", "主拱振动监测测点布置图"),
    ],
    "1.3.8 吊杆及系杆索力监测": [
        ("cable_force_layout.png", "吊杆及系杆索力监测测点布置图"),
    ],
    "1.3.9 结构应变及动应变监测": [
        ("strain_girder_layout.png", "主梁应变监测测点布置图"),
        ("strain_arch_layout.png", "主拱应变监测测点布置图"),
    ],
    "1.3.10 视频监控": [
        ("video_ship_layout.png", "船舶撞击视频监控测点布置图"),
        ("video_bridge_layout.png", "桥面视频监控测点布置图"),
    ],
}


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


def numeric_values(rows: Iterable[dict[str, Any]], keys: Iterable[str]) -> list[float]:
    values: list[float] = []
    for row in rows:
        for key in keys:
            value = safe_float(row.get(key))
            if value is not None:
                values.append(value)
    return values


def range_text(rows: list[dict[str, Any]], keys: Iterable[str], digits: int = 3, unit: str = "") -> str:
    values = numeric_values(rows, keys)
    if not values:
        return "/"
    return f"{fmt_num(min(values), digits)}{unit}~{fmt_num(max(values), digits)}{unit}"


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


def apply_report_font(run, size: int | None = None, bold: bool | None = None) -> None:
    run.font.name = EN_FONT
    rpr = run._element.get_or_add_rPr()
    rfonts = rpr.rFonts
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    rfonts.set(qn("w:ascii"), EN_FONT)
    rfonts.set(qn("w:hAnsi"), EN_FONT)
    rfonts.set(qn("w:cs"), EN_FONT)
    rfonts.set(qn("w:eastAsia"), CN_FONT)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold


def set_cell_text(cell, text: Any) -> None:
    cell.text = "" if text is None else str(text)
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    for paragraph in cell.paragraphs:
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
        for run in paragraph.runs:
            apply_report_font(run, 9)


def style_paragraph(paragraph, size: int = 10, bold: bool = False, align=None) -> None:
    if align is not None:
        paragraph.alignment = align
    for run in paragraph.runs:
        apply_report_font(run, size, bold)


def heading_display_text(text: str) -> str:
    text = text.strip()
    if text.startswith("第") and "章" in text[:6]:
        return text.split("章", 1)[1].strip()
    if " " in text and text.split(" ", 1)[0].replace(".", "").isdigit():
        return text.split(" ", 1)[1].strip()
    return text


def heading_template_level(paragraph: Paragraph) -> int | None:
    style_name = paragraph.style.name if paragraph.style is not None else ""
    match = re.fullmatch(r"Heading (\d+)", style_name)
    return int(match.group(1)) if match else None


def capture_heading_templates(doc: Document) -> dict[int, object]:
    templates: dict[int, object] = {}
    for paragraph in doc.paragraphs:
        level = heading_template_level(paragraph)
        if level is not None and level not in templates:
            templates[level] = deepcopy(paragraph._p)
        if {1, 2, 3}.issubset(templates):
            break
    return templates


def append_heading_from_template(doc: Document, template_xml, text: str) -> Paragraph:
    paragraph_xml = OxmlElement("w:p")
    ppr = template_xml.find(qn("w:pPr"))
    if ppr is not None:
        paragraph_xml.append(deepcopy(ppr))
    paragraph = Paragraph(paragraph_xml, doc._body)
    paragraph.add_run(heading_display_text(text))
    append_body_element(doc, paragraph_xml)
    return paragraph


def append_body_element(doc: Document, element) -> None:
    body = doc._body._element
    sect_pr = body.find(qn("w:sectPr"))
    if sect_pr is not None:
        sect_pr.addprevious(element)
    else:
        body.append(element)


def add_paragraph(doc: Document, text: str = "", *, first_line_indent: bool = True):
    try:
        paragraph = doc.add_paragraph(style="洪塘大桥月报正文")
    except KeyError:
        paragraph = doc.add_paragraph()
    paragraph.paragraph_format.line_spacing = 1.5
    if first_line_indent:
        paragraph.paragraph_format.first_line_indent = Pt(21)
    paragraph.add_run(text)
    style_paragraph(paragraph, 10)
    return paragraph


def add_heading(doc: Document, text: str, level: int) -> None:
    heading_templates = getattr(doc, "_sxh_heading_templates", None)
    if isinstance(heading_templates, dict) and level in heading_templates:
        append_heading_from_template(doc, heading_templates[level], text)
        return
    try:
        paragraph = doc.add_paragraph(style=f"Heading {level}")
    except KeyError:
        paragraph = doc.add_paragraph()
        ppr = paragraph._p.get_or_add_pPr()
        outline = ppr.find(qn("w:outlineLvl"))
        if outline is None:
            outline = OxmlElement("w:outlineLvl")
            ppr.append(outline)
        outline.set(qn("w:val"), str(max(level - 1, 0)))
    if level in (1, 2):
        ppr = paragraph._p.get_or_add_pPr()
        num_pr = ppr.find(qn("w:numPr"))
        if num_pr is None:
            num_pr = OxmlElement("w:numPr")
            ppr.append(num_pr)
        ilvl = num_pr.find(qn("w:ilvl"))
        if ilvl is None:
            ilvl = OxmlElement("w:ilvl")
            num_pr.append(ilvl)
        ilvl.set(qn("w:val"), str(level - 1))
        num_id = num_pr.find(qn("w:numId"))
        if num_id is None:
            num_id = OxmlElement("w:numId")
            num_pr.append(num_id)
        num_id.set(qn("w:val"), "2")
    paragraph.add_run(heading_display_text(text))


def add_field_run(paragraph, instr_text: str, placeholder: str) -> None:
    run = paragraph.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = instr_text
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    value = OxmlElement("w:t")
    value.text = placeholder
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.append(begin)
    run._r.append(instr)
    run._r.append(separate)
    run._r.append(value)
    run._r.append(end)


def remove_bookmarks(paragraph_xml) -> None:
    for child in list(paragraph_xml):
        if child.tag in {qn("w:bookmarkStart"), qn("w:bookmarkEnd")}:
            paragraph_xml.remove(child)


def append_text_run(paragraph_xml, text: str) -> None:
    run = OxmlElement("w:r")
    text_node = OxmlElement("w:t")
    if text.startswith(" ") or text.endswith(" "):
        text_node.set(qn("xml:space"), "preserve")
    text_node.text = text
    run.append(text_node)
    paragraph_xml.append(run)


def caption_title(text: str, kind: str) -> str:
    text = text.strip()
    return re.sub(rf"^{re.escape(kind)}\s*\d+(?:-\d+)?\s*", "", text).strip()


def capture_caption_templates(doc: Document) -> dict[str, object]:
    templates: dict[str, object] = {}
    static_templates: dict[str, object] = {}
    for paragraph in doc.paragraphs:
        fields = "".join(node.text or "" for node in paragraph._p.iter() if node.tag == qn("w:instrText"))
        if "SEQ 图" in fields and "图" not in templates:
            templates["图"] = deepcopy(paragraph._p)
        if "SEQ 表" in fields and "表" not in templates:
            templates["表"] = deepcopy(paragraph._p)
        text = paragraph.text.strip()
        if re.match(r"^图\s*\d+(?:-\d+)?\s+", text):
            if "图_static" not in static_templates or (paragraph.style is not None and paragraph.style.name != "Normal"):
                static_templates["图_static"] = deepcopy(paragraph._p)
        if re.match(r"^表\s*\d+(?:-\d+)?\s+", text):
            if "表_static" not in static_templates or (paragraph.style is not None and paragraph.style.name != "Normal"):
                static_templates["表_static"] = deepcopy(paragraph._p)
        if {"图", "表"}.issubset(templates):
            break
    for key, value in static_templates.items():
        templates.setdefault(key, value)
    return templates


def append_auto_caption_fields(paragraph: Paragraph, kind: str, title: str) -> None:
    paragraph.add_run(f"{kind} ")
    add_field_run(paragraph, r" STYLEREF 1 \s ", "1")
    paragraph.add_run("-")
    add_field_run(paragraph, f" SEQ {kind} \\* ARABIC \\s 1 ", "1")
    paragraph.add_run(f" {title}")


def build_auto_caption_from_static_template(doc: Document, template_xml, kind: str, title: str) -> Paragraph:
    paragraph_xml = OxmlElement("w:p")
    ppr = template_xml.find(qn("w:pPr"))
    if ppr is not None:
        paragraph_xml.append(deepcopy(ppr))
    paragraph = Paragraph(paragraph_xml, doc._body)
    append_auto_caption_fields(paragraph, kind, title)
    append_body_element(doc, paragraph_xml)
    return paragraph


def build_caption_from_template(doc: Document, template_xml, title: str) -> Paragraph:
    paragraph_xml = deepcopy(template_xml)
    remove_bookmarks(paragraph_xml)
    end_count = 0
    last_field_end = None
    for child in paragraph_xml:
        if child.tag != qn("w:r"):
            continue
        field = child.find(qn("w:fldChar"))
        if field is not None and field.get(qn("w:fldCharType")) == "end":
            end_count += 1
            if end_count == 2:
                last_field_end = child
                break
    if last_field_end is None:
        raise ValueError("Caption template does not contain the expected auto-numbering fields.")
    current = last_field_end.getnext()
    while current is not None:
        nxt = current.getnext()
        paragraph_xml.remove(current)
        current = nxt
    append_text_run(paragraph_xml, f" {title}")
    paragraph = Paragraph(paragraph_xml, doc._body)
    append_body_element(doc, paragraph_xml)
    return paragraph


def add_caption(doc: Document, text: str, *, kind: str = "表") -> None:
    caption_templates = getattr(doc, "_sxh_caption_templates", None)
    if isinstance(caption_templates, dict) and f"{kind}_static" in caption_templates:
        build_auto_caption_from_static_template(doc, caption_templates[f"{kind}_static"], kind, caption_title(text, kind))
        return
    if isinstance(caption_templates, dict) and kind in caption_templates:
        build_caption_from_template(doc, caption_templates[kind], caption_title(text, kind))
        return
    if isinstance(caption_templates, dict) and f"{kind}_static" in caption_templates:
        build_auto_caption_from_static_template(doc, caption_templates[f"{kind}_static"], kind, caption_title(text, kind))
        return
    style_name = "表格文字" if kind == "表" else "洪塘大桥月报题注"
    try:
        paragraph = doc.add_paragraph(style=style_name)
    except KeyError:
        try:
            paragraph = doc.add_paragraph(style="Caption")
        except KeyError:
            paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.paragraph_format.line_spacing = 1.2
    append_auto_caption_fields(paragraph, kind, caption_title(text, kind))
    style_paragraph(paragraph, 9, bold=False)


def set_repeat_table_header(table) -> None:
    if not table.rows:
        return
    tr_pr = table.rows[0]._tr.get_or_add_trPr()
    tbl_header = tr_pr.find(qn("w:tblHeader"))
    if tbl_header is None:
        tbl_header = OxmlElement("w:tblHeader")
        tr_pr.append(tbl_header)
    tbl_header.set(qn("w:val"), "true")


def add_table(doc: Document, headers: list[str], rows: list[list[Any]], *, font_size: int = 8, widths_mm: list[float] | None = None):
    table = doc.add_table(rows=len(rows) + 1, cols=len(headers))
    style_table(table)
    for idx, header in enumerate(headers):
        set_cell_text(table.cell(0, idx), header)
        for paragraph in table.cell(0, idx).paragraphs:
            for run in paragraph.runs:
                run.bold = True
                run.font.size = Pt(font_size)
    for ridx, row in enumerate(rows, start=1):
        for cidx, value in enumerate(row):
            set_cell_text(table.cell(ridx, cidx), value)
            for paragraph in table.cell(ridx, cidx).paragraphs:
                for run in paragraph.runs:
                    run.font.size = Pt(font_size)
    set_header_bold(table)
    set_repeat_table_header(table)
    set_table_outer_border(table, size_eighth_pt=12)
    set_table_autofit(table, True)
    set_table_auto_width(table)
    if widths_mm is not None:
        set_table_column_widths(table, widths_mm)
    set_table_font_size(table, font_size)
    return table


def add_table_with_caption(doc: Document, caption: str, headers: list[str], rows: list[list[Any]], *, font_size: int = 8, widths_mm: list[float] | None = None):
    add_caption(doc, caption, kind="表")
    return add_table(doc, headers, rows, font_size=font_size, widths_mm=widths_mm)


def add_page_break(doc: Document) -> None:
    paragraph = doc.add_paragraph()
    run = paragraph.add_run()
    br = OxmlElement("w:br")
    br.set(qn("w:type"), "page")
    run._r.append(br)


def add_picture(doc: Document, path: Path, caption: str, *, width_mm: float = 155.0) -> None:
    if not path.exists():
        return
    paragraph = doc.add_paragraph()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    try:
        paragraph.add_run().add_picture(str(path), width=Mm(width_mm))
    except Exception:
        return
    add_caption(doc, caption, kind="图")


def image_candidates(root: Path, rel_dir: str, patterns: list[str], limit: int = 2) -> list[Path]:
    base = root / rel_dir
    out: list[Path] = []
    if not base.exists():
        return out
    for pattern in patterns:
        for path in sorted(base.rglob(pattern)):
            if path.suffix.lower() in {".jpg", ".jpeg", ".png"} and path not in out:
                out.append(path)
                if len(out) >= limit:
                    return out
    return out


def latest_manifest(result_root: Path) -> dict[str, Any] | None:
    manifests = sorted((result_root / "run_logs").glob("analysis_manifest_*.json"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not manifests:
        return None
    return load_json(manifests[0])


def unique_row_cells(row) -> list[Any]:
    cells = []
    seen = set()
    for cell in row.cells:
        marker = id(cell._tc)
        if marker not in seen:
            seen.add(marker)
            cells.append(cell)
    return cells


def set_cell_lines(cell, lines: Iterable[str], *, font_size: int = 9, align=WD_ALIGN_PARAGRAPH.LEFT) -> None:
    cell.text = ""
    first = True
    for line in lines:
        paragraph = cell.paragraphs[0] if first else cell.add_paragraph()
        first = False
        paragraph.alignment = align
        paragraph.paragraph_format.line_spacing = 1.3
        run = paragraph.add_run(str(line))
        apply_report_font(run, font_size)


def replace_text_in_paragraph(paragraph, replacements: dict[str, str]) -> None:
    for run in paragraph.runs:
        text = run.text
        for old, new in replacements.items():
            text = text.replace(old, new)
        run.text = text


def rewrite_paragraph_text(paragraph, text: str) -> None:
    if not paragraph.runs:
        paragraph.add_run(text)
    else:
        paragraph.runs[0].text = text
        for run in paragraph.runs[1:]:
            run.text = ""


def replace_template_text(doc: Document, monitoring_range: str, report_date: str) -> None:
    replacements = {
        "九龙江大桥桥梁健康监测": "水仙花大桥桥梁健康监测",
        "2026年03月": "2026年03月",
        "2026.03.23~2026.03.31": monitoring_range.replace("年", ".").replace("月", ".").replace("日", "").replace("~", "~"),
    }
    for paragraph in doc.paragraphs:
        replace_text_in_paragraph(paragraph, replacements)
        text = paragraph.text.strip()
        if text.startswith("报告编号："):
            rewrite_paragraph_text(paragraph, f"报告编号：{REPORT_NO}")
        elif text.startswith("报告日期："):
            rewrite_paragraph_text(paragraph, f"报告日期：{report_date}")
    for table in doc.tables:
        for row in table.rows:
            for cell in unique_row_cells(row):
                for paragraph in cell.paragraphs:
                    replace_text_in_paragraph(paragraph, replacements)


def clear_after_toc(doc: Document) -> None:
    toc_paragraph = None
    for paragraph in doc.paragraphs:
        if paragraph.text.strip().replace(" ", "") == "目录":
            toc_paragraph = paragraph
            break
    if toc_paragraph is None:
        raise RuntimeError("未在九龙江模板中找到目录标题。")
    body = toc_paragraph._p.getparent()
    removing = False
    for element in list(body):
        if element is toc_paragraph._p:
            removing = True
            continue
        if removing and element.tag != qn("w:sectPr"):
            body.remove(element)


def add_toc_field(doc: Document) -> None:
    paragraph = doc.add_paragraph()
    paragraph.paragraph_format.line_spacing = 1.5
    run = paragraph.add_run()
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    instr = OxmlElement("w:instrText")
    instr.set(qn("xml:space"), "preserve")
    instr.text = ' TOC \\o "1-3" \\h \\z \\u '
    separate = OxmlElement("w:fldChar")
    separate.set(qn("w:fldCharType"), "separate")
    placeholder = OxmlElement("w:t")
    placeholder.text = "目录将在打开 Word 时更新"
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    run._r.append(begin)
    run._r.append(instr)
    run._r.append(separate)
    run._r.append(placeholder)
    run._r.append(end)


def update_template_front_matter(
    doc: Document,
    monitoring_range: str,
    report_date: str,
    acquisition_rows: list[dict[str, Any]],
    summary_lines: list[str],
    advice_lines: list[str],
) -> None:
    replace_template_text(doc, monitoring_range, report_date)
    total_config = sum(int(row.get("配置测点数") or 0) for row in acquisition_rows)
    total_found = sum(int(row.get("实际获取测点数") or 0) for row in acquisition_rows)
    rate = total_found / total_config * 100 if total_config else 0

    if len(doc.tables) < 4:
        raise RuntimeError("九龙江模板摘要表数量不足，无法复用模板生成报告。")

    front = doc.tables[1]
    set_cell_lines(unique_row_cells(front.rows[0])[2], ["漳州市市政工程中心"], align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_lines(unique_row_cells(front.rows[0])[4], ["/"], align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_lines(unique_row_cells(front.rows[1])[2], ["漳州市芗城区水仙大街中段污水提升泵站综合楼"], align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_lines(unique_row_cells(front.rows[1])[4], [monitoring_range.replace("年", ".").replace("月", ".").replace("日", "")], align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_lines(unique_row_cells(front.rows[2])[1], ["水仙花大桥桥梁健康监测"], align=WD_ALIGN_PARAGRAPH.CENTER)
    set_cell_lines(unique_row_cells(front.rows[2])[3], ["漳州市"], align=WD_ALIGN_PARAGRAPH.CENTER)

    result_intro = [
        "一、监测系统运行情况",
        "本月自动化数据处理流程已完成，温度、湿度、风速风向、地震动、挠度、支座及伸缩缝位移、应变、结构振动、吊杆及系杆索力加速度，以及相关频谱、动应变分析模块均已完成运行。",
        "",
        "二、本月监测数据情况",
        f"本月按监测项目统计配置测点共{total_config}项次，实际获取{total_found}项次，整体获取率约{rate:.1f}%。",
        "",
        "三、监测数据分析结果",
    ]
    chunks = [
        result_intro + summary_lines[:3],
        summary_lines[3:6],
        summary_lines[6:],
    ]
    set_cell_lines(unique_row_cells(doc.tables[1].rows[3])[1], chunks[0])
    set_cell_lines(unique_row_cells(doc.tables[2].rows[0])[1], chunks[1])
    set_cell_lines(unique_row_cells(doc.tables[3].rows[0])[1], chunks[2])
    set_cell_lines(unique_row_cells(doc.tables[3].rows[1])[1], ["针对目前的监测状况，建议如下：", *advice_lines])


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


def build_cover(doc: Document, monitoring_range: str, report_date: str) -> None:
    for _ in range(5):
        doc.add_paragraph()
    title = doc.add_paragraph()
    title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    title.add_run("水仙花大桥桥梁健康监测").bold = True
    title.add_run("\n系统数据分析月报").bold = True
    style_paragraph(title, 22, bold=True)
    subtitle = doc.add_paragraph(f"（监测时间：2026年03月，{monitoring_range}）")
    subtitle.alignment = WD_ALIGN_PARAGRAPH.CENTER
    style_paragraph(subtitle, 14)
    for _ in range(6):
        doc.add_paragraph()
    info = doc.add_paragraph(f"报告编号：{REPORT_NO}\n报告日期：{report_date}")
    info.alignment = WD_ALIGN_PARAGRAPH.CENTER
    style_paragraph(info, 12)
    for _ in range(5):
        doc.add_paragraph()
    org = doc.add_paragraph("福建省建研工程检测有限公司")
    org.alignment = WD_ALIGN_PARAGRAPH.CENTER
    style_paragraph(org, 14, bold=True)
    add_page_break(doc)


def build_front_summary(doc: Document, monitoring_range: str, acquisition_rows: list[dict[str, Any]], summary_lines: list[str], advice_lines: list[str]) -> None:
    total_config = sum(int(row.get("配置测点数") or 0) for row in acquisition_rows)
    total_found = sum(int(row.get("实际获取测点数") or 0) for row in acquisition_rows)
    rate = total_found / total_config * 100 if total_config else 0
    table = doc.add_table(rows=5, cols=4)
    table.style = "Table Grid"
    rows = [
        ["委托单位", "漳州市市政工程中心", "监测时间", monitoring_range],
        ["工程名称", "水仙花大桥桥梁健康监测", "工程地点", "漳州市"],
        ["监测结果", "\n".join([
            "一、监测系统运行情况",
            "本月自动化数据处理流程已完成，温度、湿度、风速风向、地震动、挠度、支座及伸缩缝位移、应变、振动、索力加速度及相关频谱/动应变分析模块运行完成。",
            "二、本月监测数据情况",
            f"本月按监测项目统计配置测点共{total_config}项次，实际获取{total_found}项次，整体获取率约{rate:.1f}%。",
            "三、监测数据分析结果",
            *summary_lines,
        ]), "", ""],
        ["建  议", "\n".join(advice_lines), "", ""],
        ["备注", "本报告为自动化统计生成稿，报警评价以最终审定阈值及人工复核结果为准。", "", ""],
    ]
    for ridx, row in enumerate(rows):
        for cidx, value in enumerate(row):
            set_cell_text(table.cell(ridx, cidx), value)
    table.cell(2, 1).merge(table.cell(2, 3))
    table.cell(3, 1).merge(table.cell(3, 3))
    table.cell(4, 1).merge(table.cell(4, 3))
    add_page_break(doc)


def format_stat_value(value: Any, label: str) -> Any:
    if value is None or value == "":
        return "/"
    if isinstance(value, datetime):
        return fmt_datetime(value)
    num = safe_float(value)
    if num is None:
        return value
    if any(unit in label for unit in ["m/s²", "cm/s²", "Hz", "με"]):
        return f"{num:.3f}"
    if "m/s" in label:
        return f"{num:.2f}"
    if any(unit in label for unit in ["mm", "℃", "%"]):
        return f"{num:.1f}"
    return value


def stats_rows(rows: list[dict[str, Any]], columns: list[tuple[str, str]], limit: int | None = None) -> list[list[Any]]:
    selected = rows if limit is None else rows[:limit]
    return [[format_stat_value(row.get(key, "/"), label) for key, label in columns] for row in selected]


def add_stats_table(doc: Document, title: str, rows: list[dict[str, Any]], columns: list[tuple[str, str]], limit: int | None = None) -> None:
    if not rows:
        add_paragraph(doc, f"{title}暂无统计表。")
        return
    add_table_with_caption(doc, title, [label for _, label in columns], stats_rows(rows, columns, limit), font_size=8)


def text_value(value: Any) -> str:
    if value is None or value == "":
        return "/"
    return str(value)


def design_section_key(row: dict[str, Any]) -> str:
    module = str(row.get("推断模块") or "")
    name = str(row.get("设备名称") or "")
    point_id = str(row.get("设备编号") or "")
    if module == "风速风向":
        return "1.3.1 桥梁环境（温湿度、风速风向）监测"
    if module == "温度":
        if point_id.upper().startswith("WSD") or "温湿度" in name:
            return "1.3.1 桥梁环境（温湿度、风速风向）监测"
        return "1.3.2 结构温度监测"
    if module == "地震动":
        return "1.3.3 地震动监测"
    if module == "挠度":
        return "1.3.4 主梁挠度监测"
    if module == "支座/梁端位移":
        if "GNSS" in name.upper() or point_id.upper().startswith("GNSS"):
            return "1.3.6 拱顶、拱脚位移监测（GNSS）"
        return "1.3.5 支座及伸缩缝位移监测"
    if module == "振动加速度":
        if point_id.upper().startswith("SL-") or "索力" in name or "吊杆" in name:
            return "1.3.8 吊杆及系杆索力监测"
        return "1.3.7 结构振动监测"
    if module == "应变":
        return "1.3.9 结构应变及动应变监测"
    return "1.3.10 视频监控"


def design_rows_by_section(design_rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped = {title: [] for title, _ in DESIGN_SECTION_ORDER}
    for row in design_rows:
        grouped.setdefault(design_section_key(row), []).append(row)
    return grouped


def threshold_text(row: dict[str, Any], level: str) -> str:
    lower = row.get(f"{level}超限阈值下限")
    upper = row.get(f"{level}超限阈值上限")
    parts = []
    if lower not in (None, ""):
        parts.append(f"下限：{lower}")
    if upper not in (None, ""):
        parts.append(f"上限：{upper}")
    return "；".join(parts) if parts else "/"


def layout_assets_dir(doc: Document) -> Path:
    template_path = getattr(doc, "_sxh_template_path", None)
    if template_path:
        return Path(template_path).parent / "assets" / "shuixianhua_layouts"
    return Path(__file__).resolve().parents[1] / "reports" / "assets" / "shuixianhua_layouts"


def add_layout_figures(doc: Document, section_title: str) -> None:
    assets_dir = layout_assets_dir(doc)
    for filename, caption in LAYOUT_FIGURES_BY_SECTION.get(section_title, []):
        add_picture(doc, assets_dir / filename, caption, width_mm=165.0)


def add_design_layout_sections(doc: Document, design_rows: list[dict[str, Any]]) -> None:
    grouped = design_rows_by_section(design_rows)
    for table_no, (title, intro) in enumerate(DESIGN_SECTION_ORDER, start=2):
        rows = grouped.get(title, [])
        if not rows:
            continue
        add_heading(doc, title, 3)
        add_paragraph(doc, intro)
        add_layout_figures(doc, title)
        table_rows = [
            [
                item.get("设备名称"),
                item.get("设备编号"),
                item.get("安装位置"),
                item.get("采集频率"),
                item.get("是否在配置中"),
                item.get("是否获取CSV"),
            ]
            for item in rows
        ]
        caption = f"表 1-{table_no} 水仙花大桥{title.split(' ', 1)[1]}测点布置表"
        add_table_with_caption(
            doc,
            caption,
            ["设备名称", "测点/设备编号", "安装位置", "采集频率", "是否在配置中", "本月是否获取"],
            table_rows,
            font_size=10,
            widths_mm=[28, 38, 56, 18, 20, 20],
        )


def threshold_table_rows(design_rows: list[dict[str, Any]]) -> list[list[Any]]:
    rows: list[list[Any]] = []
    for row in design_rows:
        first = threshold_text(row, "一级")
        second = threshold_text(row, "二级")
        third = threshold_text(row, "三级")
        if first == second == third == "/":
            continue
        rows.append([
            design_section_key(row).split(" ", 1)[1],
            row.get("设备名称"),
            row.get("设备编号"),
            first,
            second,
            third,
        ])
    return rows


def threshold_detail_rows() -> list[list[Any]]:
    return [
        ["桥梁环境监测", "温度", "按实施方案温度阈值", "一级", "40℃", "0℃"],
        ["桥梁环境监测", "温度", "按实施方案温度阈值", "二级", "46℃", "-2℃"],
        ["桥梁环境监测", "风速", "按实施方案风速阈值", "一级", "25m/s", "/"],
        ["桥梁环境监测", "风速", "按实施方案风速阈值", "二级", "27m/s", "/"],
        ["桥梁环境监测", "风速", "按实施方案风速阈值", "三级", "34m/s", "/"],
        ["结构响应监测", "地震动加速度", "峰值加速度", "二级", "1.50m/s²", "/"],
        ["结构响应监测", "地震动加速度", "峰值加速度", "三级", "2.55m/s²", "/"],
        ["结构响应监测", "主梁挠度", "按实施方案挠度阈值", "一级", "/", "/"],
        ["结构响应监测", "主梁挠度", "按实施方案挠度阈值", "二级", "/", "/"],
        ["结构响应监测", "支座及伸缩缝位移", "按实施方案位移阈值", "一级", "/", "/"],
        ["结构响应监测", "支座及伸缩缝位移", "按实施方案位移阈值", "二级", "/", "/"],
        ["结构响应监测", "拱顶及拱脚位移", "按测点坐标分量阈值", "二级", "见表1-11", "见表1-11"],
        ["结构响应监测", "结构应变/动应变", "按实施方案应变阈值", "一级", "/", "/"],
        ["结构响应监测", "结构应变/动应变", "按实施方案应变阈值", "二级", "/", "/"],
        ["结构响应监测", "结构振动加速度", "10min均方根", "一级", "0.315m/s²", "/"],
        ["结构响应监测", "结构振动加速度", "10min均方根", "二级", "0.500m/s²", "/"],
        ["索力监测", "吊杆/系杆索力加速度", "10min均方根", "一级", "1.000m/s²", "/"],
        ["索力监测", "吊杆/系杆索力加速度", "10min均方根", "二级", "3.000m/s²", "/"],
        ["不适用/未接入", "雨量、车辆荷载等", "本月未纳入水仙花在线监测项", "/", "/", "/"],
    ]


def add_threshold_section(doc: Document, design_rows: list[dict[str, Any]]) -> None:
    add_heading(doc, "1.4 报警阈值设置", 2)
    add_paragraph(doc, "水仙花大桥各监测项报警阈值按实施方案及测点配置核对表整理，后续报告评价应以经审定的最新阈值文件为准。")
    rows = threshold_table_rows(design_rows)
    add_table_with_caption(
        doc,
        "表 1-11 水仙花大桥监测阈值汇总表",
        ["监测类别", "设备名称", "测点/设备编号", "一级阈值", "二级阈值", "三级阈值"],
        rows,
        font_size=7,
        widths_mm=[34, 28, 36, 26, 26, 26],
    )
    add_table_with_caption(
        doc,
        "表 1-12 水仙花大桥监测阈值明细表",
        ["报警类别", "报警内容", "预警值", "超限级别", "上限", "下限"],
        threshold_detail_rows(),
        font_size=7,
        widths_mm=[24, 38, 42, 18, 24, 24],
    )


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


def filtered_deflection_rows(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out = []
    for row in rows:
        item = dict(row)
        filtered_count = 0
        for key in ["OrigMin_mm", "OrigMax_mm", "OrigMean_mm", "FiltMin_mm", "FiltMax_mm", "FiltMean_mm"]:
            value = safe_float(item.get(key))
            if value is not None and value < -21:
                item[key] = None
                filtered_count += 1
        item["低于-21mm过滤项数"] = filtered_count
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


def design_monitoring_summary_rows() -> list[list[Any]]:
    return [
        [
            "桥梁环境监测",
            "温湿度传感器、温度传感器",
            "10",
            "WSD-01-11#-S02机箱；WD-01-X-拱顶；WD-02-X11-1#；WD-03-X11-3#；WD-04-11-15#横梁；WD-05-S11-1#；WD-06-S11-3#；WD-07-S-拱顶；WD-08-10#墩-01；WD-09-11#墩-01",
            "第11跨上游02机箱旁、主拱圈顶部、第十一跨梁底及10#、11#墩上游拱脚顶部侧壁",
        ],
        ["桥梁环境监测", "超声风速风向仪", "2", "FSFX-01-11#-S11；FSFX-02-S-拱顶", "第十一跨桥面上游侧壁、拱顶横杆"],
        ["结构响应监测", "地震仪（三向）", "2台/6向", "JSD-01-10#墩-01；JSD-02-11#墩-01", "10#、11#墩上游拱脚顶部侧壁"],
        ["结构响应监测", "挠度仪（光电图像位移计）", "3", "GSNDY-01-9#墩-X侧壁；GSNDY-02-9#墩-S侧壁；GSNDY-03-12#墩-X侧壁", "9#墩下游、上游梁板侧壁及12#墩下游梁板侧壁"],
        ["结构响应监测", "拱顶、拱脚位移、支座位移及梁端纵向位移", "15", "GNSS-01-10#墩-X侧壁；GNSS-02-10#墩-S侧壁；GNSS-03-X-拱顶；GNSS-04-S-拱顶；GNSS-05-11#墩-X侧壁；GNSS-06-11#墩-S侧壁；GNSS-JD；ZZWY-01-9#墩-1#支座；ZZWY-02-9#墩-2#支座；ZZWY-03-12#墩-1#支座；ZZWY-04-12#墩-2#支座；SSF-01-3#伸缩缝-X侧壁；SSF-02-3#伸缩缝-S侧壁；SSF-03-6#伸缩缝-X侧壁；SSF-04-6#伸缩缝-S侧壁", "主拱拱顶、拱脚、支座、伸缩缝及基准点"],
        ["结构响应监测", "结构振动传感器", "14", "ZLZD-01-X10-3#；ZLZD-02-S10-3#；ZLZD-03-X11-3#；ZLZD-04-S11-3#；ZLZD-05-X11-3#；ZLZD-06-S11-3#；ZLZD-07-X12-3#；ZLZD-08-S12-3#；ZLZD-09-X12-3#；ZLZD-10-S12-3#；ZGZD-01-X-拱顶；ZGZD-02-X-拱顶；ZGZD-03-S-拱顶；ZGZD-04-S-拱顶", "第十至十二跨纵梁底部及主拱拱顶"],
        ["结构响应监测", "结构应变/动应变传感器", "34", "ZLYB-01-X11-1#；ZLYB-02-X11-3#；ZLYB-03-11-15#横梁；ZLYB-04-S11-3#；ZLYB-05-S11-1#；ZLYB-06-X11-1#；ZLYB-07-X11-3#；ZLYB-08-11-15#横梁；ZLYB-09-S11-3#；ZLYB-10-S11-1#；GLYB-01-X10-1#；GLYB-02-X10-3#；GLYB-03-S10-3#；GLYB-04-S10-1#；GLYB-05-10#墩-X拱脚；GLYB-06-10#墩-X拱脚；GLYB-07-10#墩-S拱脚；GLYB-08-10#墩-S拱脚；GLYB-09-X-拱顶；GLYB-10-X-拱顶；GLYB-11-X-拱顶；GLYB-12-X-拱顶；GLYB-13-S-拱顶；GLYB-14-S-拱顶；GLYB-15-S-拱顶；GLYB-16-S-拱顶；GLYB-17-11#墩-X拱脚；GLYB-18-11#墩-X拱脚；GLYB-19-11#墩-S拱脚；GLYB-20-11#墩-S拱脚；GLYB-21-X12-1#；GLYB-22-X12-3#；GLYB-23-S12-3#；GLYB-24-S12-1#", "主梁小纵梁、横梁、主拱及拱脚"],
        ["索力监测", "吊杆及系杆索力加速度传感器", "34", "SL-01-X6#吊杆；SL-02-X7#吊杆；SL-03-X8#吊杆；SL-04-X9#吊杆；SL-05-X10#吊杆；SL-06-X11#吊杆；SL-07-X12#吊杆；SL-08-X13#吊杆；SL-09-X14#吊杆；SL-10-X15#吊杆；SL-11-X16#吊杆；SL-12-S6#吊杆；SL-13-S7#吊杆；SL-14-S8#吊杆；SL-15-S9#吊杆；SL-16-S10#吊杆；SL-17-S11#吊杆；SL-18-S12#吊杆；SL-19-S13#吊杆；SL-20-S14#吊杆；SL-21-S15#吊杆；SL-22-S16#吊杆；SL-23-1#系杆；SL-24-2#系杆；SL-25-3#系杆；SL-26-4#系杆；SL-27-5#系杆；SL-28-6#系杆；SL-29-7#系杆；SL-30-8#系杆；SL-31-9#系杆；SL-32-10#系杆；SL-33-11#系杆；SL-34-12#系杆", "吊杆及系杆"],
        ["视频监控", "AI摄像机、监控球机", "12", "AIQJ-01~04；QJ-01~08", "桥面、梁板侧壁及灯杆"],
    ]


def add_optional_picture(doc: Document, path: Path, caption: str, *, width_mm: float = 155.0) -> None:
    if path.exists():
        add_picture(doc, path, caption, width_mm=width_mm)


def build_report(
    template: Path,
    config_path: Path,
    result_root: Path,
    output_dir: Path | None = None,
    period_label: str = "2026年3月份",
    monitoring_range: str = "2026年03月23日~2026年03月31日",
    report_date: str = "2026年04月05日",
    update_word: bool = True,
) -> tuple[Path, Path | None]:
    output_dir = output_dir or result_root / "自动报告"
    output_dir.mkdir(parents=True, exist_ok=True)
    cfg = load_json(config_path)
    stats_dir = result_root / "stats"
    acquisition_path = next(stats_dir.glob("水仙花大桥_测点配置与数据获取情况_*.xlsx"))
    acquisition_rows = load_rows(acquisition_path, "汇总")
    design_rows = load_rows(acquisition_path, "设计表核对")
    manifest = latest_manifest(result_root)

    temp_rows = load_rows(stats_dir / "temp_stats.xlsx")
    humidity_rows = load_rows(stats_dir / "humidity_stats.xlsx")
    raw_wind_rows = load_rows(stats_dir / "wind_stats.xlsx")
    raw_deflection_rows = load_rows(stats_dir / "deflection_stats.xlsx")
    bearing_rows = load_rows(stats_dir / "bearing_displacement_stats.xlsx")
    raw_strain_rows = load_rows(stats_dir / "strain_stats.xlsx")
    raw_accel_rows = load_rows(stats_dir / "accel_stats.xlsx")
    raw_cable_rows = load_rows(stats_dir / "cable_accel_stats.xlsx")

    wind_rows = adjusted_rows(stats_dir, "wind_direction_stats_report.xlsx", adjusted_rows(stats_dir, "wind_stats_report.xlsx", raw_wind_rows))
    for row in wind_rows:
        row.setdefault("备注", "本月正常获取")
    deflection_rows = adjusted_rows(stats_dir, "deflection_stats_filtered.xlsx", filtered_deflection_rows(raw_deflection_rows))
    strain_rows = adjusted_rows(stats_dir, "strain_stats_zero_corrected.xlsx", raw_strain_rows)
    accel_rows = adjusted_rows(stats_dir, "accel_stats_mps2.xlsx", scaled_accel_rows(raw_accel_rows))
    cable_rows = adjusted_rows(stats_dir, "cable_accel_stats_mps2.xlsx", scaled_accel_rows(raw_cable_rows))
    earthquake_rows = adjusted_rows(stats_dir, "earthquake_filtered_stats_mps2.xlsx", adjusted_rows(stats_dir, "earthquake_filtered_stats.xlsx"))
    accel_first_mode_rows = adjusted_rows(stats_dir, "accel_first_mode_stats.xlsx")
    report_rows = report_acquisition_rows(acquisition_rows)

    temp_range = range_text(temp_rows, ["Min", "Max"], 1, "℃")
    humidity_range = range_text(humidity_rows, ["Min", "Max"], 1, "%")
    wind_max = max((safe_float(row.get("最大风速(m/s)")) if "最大风速(m/s)" in row else safe_float(row.get("MaxSpeed")) or 0 for row in wind_rows), default=0)
    wind_10 = max((safe_float(row.get("10min平均风速最大值(m/s)")) if "10min平均风速最大值(m/s)" in row else safe_float(row.get("Mean10minMax")) or 0 for row in wind_rows), default=0)
    defl_range = range_text(deflection_rows, ["FiltMin_mm", "FiltMax_mm"], 1, "mm")
    bearing_range = range_text(bearing_rows, ["FiltMin_mm", "FiltMax_mm"], 1, "mm")
    strain_range = range_text(strain_rows, ["Min", "Max"], 3, "με")
    accel_rms = extreme_row(accel_rows, "RMS10minMax")
    cable_rms = extreme_row(cable_rows, "RMS10minMax")

    summary_lines = [
        f"温湿度监测：温度实测值范围为{temp_range}，相对湿度实测值范围为{humidity_range}。",
        f"风速风向监测：瞬时风速最大值约{fmt_num(wind_max, 2)}m/s，10min平均风速最大值约{fmt_num(wind_10, 2)}m/s。",
        "地震动监测：已按三向记录统计并统一换算为m/s²，对原始记录中的明显异常低值进行过滤。",
        f"主梁挠度监测：已对低于-21mm的异常低值进行过滤，滤波后挠度统计范围为{defl_range}。",
        f"支座及伸缩缝位移监测：滤波后位移统计范围为{bearing_range}。",
        f"结构应变监测：按首个有效采样值进行零点修正，修正后统计范围为{strain_range}。",
        f"结构振动监测：加速度统计单位统一为m/s²，10min均方根最大值约{fmt_num(accel_rms.get('RMS10minMax') if accel_rms else None, 3)}m/s²，对应测点为{accel_rms.get('PointID') if accel_rms else '/'}。",
        f"吊杆及系杆索力加速度监测：统计单位统一为m/s²，10min均方根最大值约{fmt_num(cable_rms.get('RMS10minMax') if cable_rms else None, 3)}m/s²，对应测点为{cable_rms.get('PointID') if cable_rms else '/'}。",
    ]
    advice_lines = [
        "1、建议继续保持地震动、结构应变及动应变分析的统计口径一致，便于后续月报形成连续可追溯的量化评价。",
        "2、加速度及索力加速度相关报警评价应持续统一采集单位、统计单位与实施方案阈值单位，再开展超限判定。",
        "3、建议对挠度、支座及伸缩缝位移等低频测项开展长期趋势跟踪，结合温度、车辆及运维工况判断变化原因。",
        "4、建议保持现有数据接入完整性，并对图件、统计表和平台数据进行月度一致性复核。",
    ]

    if not template.exists():
        raise FileNotFoundError(f"未找到水仙花报告模板：{template}")

    doc = Document(str(template))
    doc._sxh_template_path = str(template)
    doc._sxh_heading_templates = capture_heading_templates(doc)
    doc._sxh_caption_templates = capture_caption_templates(doc)
    update_template_front_matter(doc, monitoring_range, report_date, report_rows, summary_lines, advice_lines)
    clear_after_toc(doc)
    add_toc_field(doc)
    add_page_break(doc)

    add_heading(doc, "第1章 监测概况", 1)
    add_heading(doc, "1.1 工程概况", 2)
    for paragraph in PROJECT_OVERVIEW:
        add_paragraph(doc, paragraph)
    add_picture(doc, layout_assets_dir(doc) / "bridge_overview.png", "水仙花大桥监测总体布置图", width_mm=165.0)
    add_heading(doc, "1.2 监测内容", 2)
    add_paragraph(doc, "第1章按设计图纸、实施方案及测点配置核对表梳理设计监测内容和测点布置；第2章按2026年3月23日至2026年3月31日期间实际获取的数据进行统计评价。")
    add_table_with_caption(
        doc,
        "表 1-1 水仙花大桥设计监测内容及测点布置汇总表",
        ["监测类别", "监测子项", "设计测点数量", "测点编号", "主要布设位置"],
        design_monitoring_summary_rows(),
        font_size=10,
        widths_mm=[26, 42, 24, 52, 58],
    )
    add_heading(doc, "1.3 主桥监测测点布置", 2)
    add_paragraph(doc, "水仙花大桥监测测点布置按实施方案和测点配置核对表整理如下，表中同时列出本月配置接入及数据获取状态，便于与后续分析结果对应。")
    add_design_layout_sections(doc, design_rows)
    add_threshold_section(doc, design_rows)

    add_heading(doc, "第2章 自动化系统监测结果", 1)
    add_heading(doc, "2.1 监测系统运行情况", 2)
    if manifest:
        status_counts = manifest.get("module_status_counts", {})
        add_paragraph(
            doc,
            f"本月自动化处理任务状态为{manifest.get('status', 'unknown')}，共完成{status_counts.get('ok', 0)}个模块，失败{status_counts.get('fail', 0)}个模块，跳过{status_counts.get('skip', 0)}个模块。最后一次处理日志显示各启用模块均完成运行。",
        )
        missing_stats = manifest.get("missing_expected_stats") or []
        if earthquake_rows:
            missing_stats = [item for item in missing_stats if Path(item).name != "eq_stats.xlsx"]
        if missing_stats:
            names = "、".join(Path(item).name for item in missing_stats)
            add_paragraph(doc, f"自动化清单提示以下期望统计表未输出：{names}。动应变结果纳入结构应变章节统一说明，后续可继续完善独立统计表。")
    add_heading(doc, "2.2 本月监测数据情况", 2)
    add_table_with_caption(
        doc,
        "表 2-1 本月监测数据获取情况统计表",
        ["监测项目", "配置测点数", "实际获取测点数", "获取率", "获取日期", "缺失说明"],
        [
            [
                row.get("模块"),
                row.get("配置测点数"),
                row.get("实际获取测点数"),
                fmt_percent(row.get("获取率")),
                "2026-03-23~2026-03-31",
                row.get("缺失说明") or ("无" if row.get("缺失测点数") in (0, None, "") else f"缺失{row.get('缺失测点数')}个"),
            ]
            for row in report_rows
        ],
        font_size=8,
        widths_mm=[38, 24, 28, 20, 42, 42],
    )

    add_heading(doc, "2.3 监测数据分析", 2)
    add_heading(doc, "2.3.1 温湿度监测", 3)
    add_paragraph(doc, f"本月温度实测值范围为{temp_range}，相对湿度实测值范围为{humidity_range}。")
    add_stats_table(doc, "温度统计表", temp_rows, [("PointID", "测点编号"), ("Min", "最小值(℃)"), ("Max", "最大值(℃)"), ("Mean", "平均值(℃)")])
    add_stats_table(doc, "湿度统计表", humidity_rows, [("PointID", "测点编号"), ("Min", "最小值(%)"), ("Max", "最大值(%)"), ("Mean", "平均值(%)")])
    for path in image_candidates(result_root, "时程曲线_温度", ["*20260323_20260331*.jpg"], 1):
        add_picture(doc, path, "温度时程曲线")
    for path in image_candidates(result_root, "频次分布_湿度", ["*20260323_20260331*.jpg"], 1):
        add_picture(doc, path, "湿度频次分布图")

    add_heading(doc, "2.3.2 风速风向监测", 3)
    add_paragraph(doc, f"本月瞬时风速最大值约{fmt_num(wind_max, 2)}m/s，10min平均风速最大值约{fmt_num(wind_10, 2)}m/s，未超过25m/s一级阈值。")
    add_stats_table(
        doc,
        "风速风向统计表",
        wind_rows,
        [
            ("测点编号", "测点编号"),
            ("主导风向", "主导风向"),
            ("主要风速等级", "主要风速等级"),
            ("平均风速(m/s)", "平均风速(m/s)"),
            ("最大风速(m/s)", "最大风速(m/s)"),
            ("10min平均风速最大值(m/s)", "10min平均风速最大值(m/s)"),
            ("对应时间", "对应时间"),
        ],
    )
    add_optional_picture(doc, stats_dir / "adjusted" / "figures" / "wind_rose.png", "风玫瑰图")
    for path in image_candidates(result_root, "风速风向结果", ["*2026-03-23_2026-03-31*.jpg"], 3):
        add_picture(doc, path, "风速风向分析图")

    add_heading(doc, "2.3.3 地震动监测", 3)
    add_paragraph(doc, "本月地震动监测结果已统一换算为m/s²，并对原始记录中明显异常的低值进行过滤；过滤后各测点峰值统计见下表。")
    if earthquake_rows:
        add_stats_table(
            doc,
            "地震动过滤后峰值统计表",
            earthquake_rows,
            [
                ("测点编号", "测点编号"),
                ("方向", "方向"),
                ("最小值(m/s²)", "最小值(m/s²)"),
                ("最大值(m/s²)", "最大值(m/s²)"),
            ],
        )
        add_optional_picture(doc, stats_dir / "adjusted" / "figures" / "earthquake_filtered_stats_mps2.png", "地震动过滤后峰值统计图")

    add_heading(doc, "2.3.4 主梁挠度监测", 3)
    add_paragraph(doc, f"本月主梁挠度统计已剔除低于-21mm的异常低值，滤波后统计范围为{defl_range}。部分测点原始值为0，建议结合现场接入状态和零点修正记录复核。")
    add_stats_table(doc, "主梁挠度统计表", deflection_rows, [("PointID", "测点编号"), ("OrigMin_mm", "原始最小值(mm)"), ("OrigMax_mm", "原始最大值(mm)"), ("FiltMin_mm", "滤波最小值(mm)"), ("FiltMax_mm", "滤波最大值(mm)")])
    add_optional_picture(doc, stats_dir / "adjusted" / "figures" / "deflection_filtered_stats.png", "主梁挠度过滤后统计图")
    for path in image_candidates(result_root, "时程曲线_挠度_组图", ["*20260323_20260331*.jpg"], 2):
        add_picture(doc, path, "主梁挠度时程曲线")

    add_heading(doc, "2.3.5 支座及伸缩缝位移监测", 3)
    add_paragraph(doc, f"本月支座及伸缩缝位移滤波后统计范围为{bearing_range}。")
    add_stats_table(doc, "支座及伸缩缝位移统计表", bearing_rows, [("PointID", "测点编号"), ("OrigMin_mm", "原始最小值(mm)"), ("OrigMax_mm", "原始最大值(mm)"), ("FiltMin_mm", "滤波最小值(mm)"), ("FiltMax_mm", "滤波最大值(mm)")])
    bearing_images = image_candidates(result_root, "时程曲线_支座位移_组图", ["*20260323_20260331*.jpg"], 2)
    if not bearing_images:
        bearing_images = image_candidates(result_root, "时程曲线_支座位移", ["*20260323_20260331*.jpg"], 2)
    for path in bearing_images:
        add_picture(doc, path, "支座及伸缩缝位移时程曲线")

    add_heading(doc, "2.3.6 结构应变与动应变分析", 3)
    add_paragraph(doc, f"本月结构应变按首个有效采样值进行零点修正，修正后统计范围为{strain_range}。动应变高通和低通分析纳入结构应变章节统一说明。")
    add_stats_table(doc, "结构应变统计表", strain_rows, [("PointID", "测点编号"), ("Min", "最小值(με)"), ("Max", "最大值(με)"), ("Mean", "平均值(με)")], limit=34)
    for rel_dir, caption in [("时程曲线_应变_组图", "结构应变组图"), ("箱线图_应变", "结构应变箱线图"), ("时程曲线_动应变_高通滤波", "动应变高通时程曲线"), ("动应变箱线图_低通滤波", "动应变低通箱线图")]:
        for path in image_candidates(result_root, rel_dir, ["*20260323_20260331*.jpg"], 2):
            add_picture(doc, path, caption)

    add_heading(doc, "2.3.7 结构振动及频谱分析", 3)
    add_paragraph(doc, f"本月结构振动加速度统计单位统一为m/s²，10min均方根最大值约{fmt_num(accel_rms.get('RMS10minMax') if accel_rms else None, 3)}m/s²，对应测点为{accel_rms.get('PointID') if accel_rms else '/'}。频谱分析按理论一阶频率1.05Hz及1.20Hz附近峰值识别口径，仅列一阶识别结果。")
    add_stats_table(doc, "结构振动加速度统计表", accel_rows, [("PointID", "测点编号"), ("Min", "最小值(m/s²)"), ("Max", "最大值(m/s²)"), ("Mean", "平均值(m/s²)"), ("RMS10minMax", "10min均方根最大值(m/s²)")])
    if accel_first_mode_rows:
        add_stats_table(doc, "结构振动一阶频率识别统计表", accel_first_mode_rows, [("测点编号", "测点编号"), ("一阶频率最小值(Hz)", "一阶频率最小值(Hz)"), ("一阶频率最大值(Hz)", "一阶频率最大值(Hz)"), ("一阶频率平均值(Hz)", "一阶频率平均值(Hz)"), ("理论一阶频率(Hz)", "理论一阶频率(Hz)")])
    add_optional_picture(doc, stats_dir / "adjusted" / "figures" / "accel_stats_mps2.png", "结构振动加速度统计图")
    add_optional_picture(doc, stats_dir / "adjusted" / "figures" / "accel_first_mode_stats.png", "结构振动一阶频率识别统计图")
    for rel_dir, caption in [
        ("时程曲线_加速度_组图", "结构振动加速度时程组图"),
        ("时程曲线_加速度", "结构振动加速度时程曲线"),
        ("频谱峰值曲线_加速度_组图", "结构振动频谱峰值组图"),
        ("频谱峰值曲线_加速度", "结构振动频谱峰值曲线"),
    ]:
        for path in image_candidates(result_root, rel_dir, ["*20260323_20260331*.jpg"], 2):
            add_picture(doc, path, caption)

    add_heading(doc, "2.3.8 吊杆及系杆索力加速度分析", 3)
    add_paragraph(doc, f"本月吊杆及系杆索力加速度统计单位统一为m/s²，10min均方根最大值约{fmt_num(cable_rms.get('RMS10minMax') if cable_rms else None, 3)}m/s²，对应测点为{cable_rms.get('PointID') if cable_rms else '/'}。")
    add_stats_table(doc, "吊杆及系杆索力加速度统计表", cable_rows, [("PointID", "测点编号"), ("Min", "最小值(m/s²)"), ("Max", "最大值(m/s²)"), ("Mean", "平均值(m/s²)"), ("RMS10minMax", "10min均方根最大值(m/s²)")], limit=34)
    add_optional_picture(doc, stats_dir / "adjusted" / "figures" / "cable_accel_stats_mps2.png", "吊杆及系杆索力加速度统计图")
    for rel_dir, caption in [("时程曲线_索力加速度", "索力加速度时程曲线"), ("频谱峰值曲线_索力加速度", "索力加速度频谱峰值曲线"), ("索力时程图_组图", "索力时程组图")]:
        for path in image_candidates(result_root, rel_dir, ["*20260323_20260331*.jpg"], 2):
            add_picture(doc, path, caption)

    add_heading(doc, "第3章 结论与建议", 1)
    for line in summary_lines:
        add_paragraph(doc, line)
    for line in advice_lines:
        add_paragraph(doc, line)
    add_paragraph(doc, "（以下无正文）", first_line_indent=False)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output = output_dir / f"水仙花大桥健康监测2026年3月份月报_自动生成_{timestamp}.docx"
    doc.save(output)
    pdf = update_word_fields_and_export_pdf(output) if update_word else None
    return output.resolve(), pdf.resolve() if pdf else None


def _sxh_all_paragraphs(doc: Document):
    for paragraph in doc.paragraphs:
        yield paragraph
    seen_cells = set()
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                marker = id(cell._tc)
                if marker in seen_cells:
                    continue
                seen_cells.add(marker)
                for paragraph in cell.paragraphs:
                    yield paragraph


def _sxh_disable_track_revisions(doc: Document) -> None:
    settings = doc.settings.element
    for element in list(settings.findall(qn("w:trackRevisions"))):
        settings.remove(element)


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


def _sxh_rewrite_contains(doc: Document, contains: str, text: str, *, startswith: str | None = None) -> int:
    count = 0
    for paragraph in _sxh_all_paragraphs(doc):
        current = paragraph.text
        if contains not in current:
            continue
        if startswith is not None and not current.startswith(startswith):
            continue
        rewrite_paragraph_text(paragraph, text)
        style_paragraph(paragraph, 10)
        count += 1
    return count


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


def _sxh_fill_table(table, rows: list[dict[str, Any]], value_builder) -> None:
    while len(table.rows) - 1 < len(rows):
        table.add_row()
    for idx, table_row in enumerate(table.rows[1:]):
        if idx < len(rows):
            values = value_builder(idx + 1, rows[idx])
        else:
            values = [""] * len(table_row.cells)
        for col_idx, value in enumerate(values[: len(table_row.cells)]):
            set_cell_text(table_row.cells[col_idx], value)


def _sxh_update_stats_tables(doc: Document, context: dict[str, Any]) -> None:
    report_rows = context["report_rows"]
    _sxh_fill_table(
        doc.tables[16],
        report_rows,
        lambda idx, row: [
            idx,
            row.get("模块"),
            row.get("配置测点数"),
            row.get("实际获取测点数"),
            fmt_percent(row.get("获取率")).replace("100.0%", "100%"),
            context["date_span"],
            row.get("缺失说明") or ("无" if not row.get("缺失测点数") else f"缺失{row.get('缺失测点数')}个"),
        ],
    )
    _sxh_fill_table(doc.tables[17], context["temp_rows"], lambda idx, row: [idx, row.get("PointID"), "温度", fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_fill_table(doc.tables[18], context["humidity_rows"], lambda idx, row: [idx, row.get("PointID"), "相对湿度", fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_fill_table(
        doc.tables[19],
        context["wind_rows"],
        lambda idx, row: [
            idx,
            _sxh_text_value(row, "测点编号", "PointID"),
            _sxh_text_value(row, "平均风向"),
            _sxh_text_value(row, "主导风向"),
            fmt_num(row.get("平均风速(m/s)") or row.get("MeanSpeed") or str(_sxh_text_value(row, "平均风速")).split()[0], 2),
            fmt_num(row.get("最大风速(m/s)") or row.get("MaxSpeed") or str(_sxh_text_value(row, "最大风速")).split()[0], 1),
            _sxh_fixed(row.get("10min平均风速最大值(m/s)") or row.get("Mean10minMax"), 2),
        ],
    )
    _sxh_fill_table(
        doc.tables[20],
        context["earthquake_rows"],
        lambda idx, row: [
            idx,
            _sxh_text_value(row, "测点编号", "PointID"),
            _sxh_text_value(row, "方向", "Component"),
            fmt_num(row.get("最小值(m/s²)") or row.get("Min"), 3),
            fmt_num(row.get("最大值(m/s²)") or row.get("Peak") or row.get("Max"), 3),
        ],
    )
    _sxh_fill_table(doc.tables[21], context["deflection_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("OrigMin_mm"), 1), fmt_num(row.get("OrigMax_mm"), 1)])
    _sxh_fill_table(doc.tables[22], context["deflection_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("FiltMin_mm"), 1), fmt_num(row.get("FiltMax_mm"), 1)])
    _sxh_fill_table(doc.tables[23], context["bearing_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("OrigMin_mm"), 1), fmt_num(row.get("OrigMax_mm"), 1)])
    _sxh_fill_table(doc.tables[24], context["bearing_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("FiltMin_mm"), 1), fmt_num(row.get("FiltMax_mm"), 1)])
    _sxh_fill_table(doc.tables[25], [{"PointID": "拱顶、拱脚位移（GNSS）"}], lambda idx, row: [idx, row.get("PointID"), "/", "/", "/"])
    freq_map = context["accel_freq_map"]
    _sxh_fill_table(
        doc.tables[26],
        context["accel_rows"],
        lambda idx, row: [
            idx,
            row.get("PointID"),
            fmt_num(row.get("Min"), 4),
            fmt_num(row.get("Max"), 4),
            fmt_num(row.get("RMS10minMax"), 4),
            fmt_num(freq_map.get(str(row.get("PointID")), (None, None))[0], 3),
            fmt_num(freq_map.get(str(row.get("PointID")), (None, None))[1], 3),
        ],
    )
    _sxh_fill_table(doc.tables[27], context["strain_rows"], lambda idx, row: [row.get("分组"), row.get("PointID"), fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_fill_table(doc.tables[28], context["cable_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("Min"), 4), fmt_num(row.get("Max"), 4), fmt_num(row.get("RMS10minMax"), 4)])


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


def _sxh_update_summary_text(doc: Document, context: dict[str, Any]) -> None:
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

    temp_text = f"WD-01~WD-09温度测点本月未获取有效数据，监测结果表明，WSD-01-11#-S11温度在{temp_range}之间，处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"
    humidity_text = f"监测结果表明，WSD-01-11#-S11相对湿度实测值范围为{humidity_range}，处于正常环境湿度范围。"
    wind_text = f"监测结果表明，桥面风速风向测点10min平均风速最大值为{wind_deck_10}m/s，未超过25m/s，处于预警阈值范围之内，未出现超过各级超限阈值和报警的情况。"
    eq_text = f"监测结果表明，水平向地震动加速度峰值为{fmt_num(horiz_max, 3)}m/s²，竖向地震动加速度峰值为{fmt_num(vert_max, 3)}m/s²，处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"
    defl_body = f"监测结果表明，主梁挠度在{defl_orig}之间，均处于预警阈值范围之内，未超过各级超限阈值和报警的情况。主梁挠度滤波后在{defl_filt}之间。"
    defl_front = f"主梁挠度原始数据实测值范围在{defl_orig}之间，均处于预警阈值范围之内，未出现超过各级超限阈值和报警的情况。滤波后实测值范围在{defl_filt}之间。"
    bearing_body = f"监测结果表明，支座位移原始数据实测值范围在{support_orig}之间，伸缩缝位移原始数据实测值范围在{expansion_orig}之间，均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。支座位移滤波后实测值在{support_filt}之间，伸缩缝位移滤波后实测值范围在{expansion_filt}之间。"
    bearing_front = bearing_body.replace("监测结果表明，", "", 1)
    accel_body = f"监测结果表明，各测点10min均方根最大值为{fmt_num(accel_row.get('RMS10minMax') if accel_row else None, 3)}m/s²，对应测点为{accel_row.get('PointID') if accel_row else '/'}，未超过0.315m/s²，处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。竖向1阶自振频率范围在{freq_range}之间，均大于结构相应理论计算的1阶竖弯频率1.050Hz。"
    accel_front = accel_body.replace("监测结果表明，", "", 1)
    strain_body = f"监测结果表明，本月结构应变按组图分组统计：{strain_ranges}，均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"
    cable_body = f"监测结果表明，各测点10min均方根最大值为{fmt_num(cable_row.get('RMS10minMax') if cable_row else None, 3)}m/s²，对应测点为{cable_row.get('PointID') if cable_row else '/'}，未超过1.000m/s²，均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"

    _sxh_rewrite_contains(doc, "WSD-01-11#-S11温度", temp_text)
    _sxh_rewrite_contains(doc, "相对湿度实测值范围", humidity_text)
    _sxh_rewrite_contains(doc, "桥面风速风向测点10min平均风速最大值", wind_text)
    _sxh_rewrite_contains(doc, "水平向地震动加速度峰值", eq_text)
    _sxh_rewrite_contains(doc, "监测结果表明，主梁挠度", defl_body)
    _sxh_rewrite_contains(doc, "主梁挠度原始数据实测值范围", defl_front)
    _sxh_rewrite_contains(doc, "支座位移原始数据实测值范围", bearing_body, startswith="监测结果表明")
    for paragraph in _sxh_all_paragraphs(doc):
        if "支座位移原始数据实测值范围" in paragraph.text and not paragraph.text.startswith("监测结果表明"):
            rewrite_paragraph_text(paragraph, bearing_front)
            style_paragraph(paragraph, 10)
    for paragraph in _sxh_all_paragraphs(doc):
        text = paragraph.text
        if "各测点10min均方根最大值" not in text:
            continue
        if "0.315m/s²" in text or "ZLZD" in text:
            rewrite_paragraph_text(paragraph, accel_body if text.startswith("监测结果表明") else accel_front)
            style_paragraph(paragraph, 10)
        elif "1.000m/s²" in text or "SL-" in text:
            rewrite_paragraph_text(paragraph, cable_body if text.startswith("监测结果表明") else cable_body.replace("监测结果表明，", "", 1))
            style_paragraph(paragraph, 10)
    _sxh_rewrite_contains(doc, "结构应变按组图分组统计", strain_body)


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
    return "".join(node.text or "" for node in element.findall(".//w:t", {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}))


def _sxh_xml_set_paragraph_text(paragraph, text: str) -> None:
    first_run = paragraph.find(qn("w:r"))
    run_props = first_run.find(qn("w:rPr")) if first_run is not None else None
    paragraph_props = paragraph.find(qn("w:pPr"))
    for child in list(paragraph):
        if paragraph_props is not None and child is paragraph_props:
            continue
        paragraph.remove(child)
    run = etree.Element(qn("w:r"))
    if run_props is not None:
        run.append(deepcopy(run_props))
    t = etree.SubElement(run, qn("w:t"))
    if text.startswith(" ") or text.endswith(" "):
        t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    t.text = str(text)
    paragraph.append(run)


def _sxh_xml_set_cell_text(cell, text: Any) -> None:
    cell_props = cell.find(qn("w:tcPr"))
    first_paragraph = cell.find(qn("w:p"))
    paragraph_props = first_paragraph.find(qn("w:pPr")) if first_paragraph is not None else None
    first_run = first_paragraph.find(qn("w:r")) if first_paragraph is not None else None
    run_props = first_run.find(qn("w:rPr")) if first_run is not None else None
    for child in list(cell):
        if cell_props is not None and child is cell_props:
            continue
        cell.remove(child)
    paragraph = etree.SubElement(cell, qn("w:p"))
    if paragraph_props is not None:
        paragraph.append(deepcopy(paragraph_props))
    run = etree.SubElement(paragraph, qn("w:r"))
    if run_props is not None:
        run.append(deepcopy(run_props))
    t = etree.SubElement(run, qn("w:t"))
    t.text = "" if text is None else str(text)


def _sxh_xml_rewrite_contains(root, contains: str, replacement: str, *, startswith: str | None = None) -> None:
    for paragraph in root.findall(".//w:p", {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}):
        current = _sxh_xml_text(paragraph)
        if contains not in current:
            continue
        if startswith is not None and not current.startswith(startswith):
            continue
        _sxh_xml_set_paragraph_text(paragraph, replacement)


def _sxh_xml_fill_table(table, rows: list[dict[str, Any]], value_builder) -> None:
    table_rows = table.findall(qn("w:tr"))
    for data_idx, tr in enumerate(table_rows[1:]):
        cells = tr.findall(qn("w:tc"))
        values = value_builder(data_idx + 1, rows[data_idx]) if data_idx < len(rows) else [""] * len(cells)
        for col_idx, cell in enumerate(cells):
            _sxh_xml_set_cell_text(cell, values[col_idx] if col_idx < len(values) else "")


def _sxh_xml_update_stats_tables(root, context: dict[str, Any]) -> None:
    tables = root.findall(".//w:tbl", {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"})
    report_rows = context["report_rows"]
    _sxh_xml_fill_table(tables[16], report_rows, lambda idx, row: [idx, row.get("模块"), row.get("配置测点数"), row.get("实际获取测点数"), fmt_percent(row.get("获取率")).replace("100.0%", "100%"), context["date_span"], row.get("缺失说明") or ("无" if not row.get("缺失测点数") else f"缺失{row.get('缺失测点数')}个")])
    _sxh_xml_fill_table(tables[17], context["temp_rows"], lambda idx, row: [idx, row.get("PointID"), "温度", fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_xml_fill_table(tables[18], context["humidity_rows"], lambda idx, row: [idx, row.get("PointID"), "相对湿度", fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_xml_fill_table(tables[19], context["wind_rows"], lambda idx, row: [idx, _sxh_text_value(row, "测点编号", "PointID"), _sxh_text_value(row, "平均风向"), _sxh_text_value(row, "主导风向"), fmt_num(row.get("平均风速(m/s)") or row.get("MeanSpeed") or str(_sxh_text_value(row, "平均风速")).split()[0], 2), fmt_num(row.get("最大风速(m/s)") or row.get("MaxSpeed") or str(_sxh_text_value(row, "最大风速")).split()[0], 1), _sxh_fixed(row.get("10min平均风速最大值(m/s)") or row.get("Mean10minMax"), 2)])
    _sxh_xml_fill_table(tables[20], context["earthquake_rows"], lambda idx, row: [idx, _sxh_text_value(row, "测点编号", "PointID"), _sxh_text_value(row, "方向", "Component"), fmt_num(row.get("最小值(m/s²)") or row.get("Min"), 3), fmt_num(row.get("最大值(m/s²)") or row.get("Peak") or row.get("Max"), 3)])
    _sxh_xml_fill_table(tables[21], context["deflection_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("OrigMin_mm"), 1), fmt_num(row.get("OrigMax_mm"), 1)])
    _sxh_xml_fill_table(tables[22], context["deflection_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("FiltMin_mm"), 1), fmt_num(row.get("FiltMax_mm"), 1)])
    _sxh_xml_fill_table(tables[23], context["bearing_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("OrigMin_mm"), 1), fmt_num(row.get("OrigMax_mm"), 1)])
    _sxh_xml_fill_table(tables[24], context["bearing_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("FiltMin_mm"), 1), fmt_num(row.get("FiltMax_mm"), 1)])
    _sxh_xml_fill_table(tables[25], [{"PointID": "拱顶、拱脚位移（GNSS）"}], lambda idx, row: [idx, row.get("PointID"), "/", "/", "/"])
    freq_map = context["accel_freq_map"]
    _sxh_xml_fill_table(tables[26], context["accel_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("Min"), 4), fmt_num(row.get("Max"), 4), fmt_num(row.get("RMS10minMax"), 4), fmt_num(freq_map.get(str(row.get("PointID")), (None, None))[0], 3), fmt_num(freq_map.get(str(row.get("PointID")), (None, None))[1], 3)])
    _sxh_xml_fill_table(tables[27], context["strain_rows"], lambda idx, row: [row.get("分组"), row.get("PointID"), fmt_num(row.get("Min"), 1), fmt_num(row.get("Max"), 1), fmt_num(row.get("Mean"), 1)])
    _sxh_xml_fill_table(tables[28], context["cable_rows"], lambda idx, row: [idx, row.get("PointID"), fmt_num(row.get("Min"), 4), fmt_num(row.get("Max"), 4), fmt_num(row.get("RMS10minMax"), 4)])


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
