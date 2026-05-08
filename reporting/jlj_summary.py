from __future__ import annotations

import re
from copy import deepcopy
from typing import Any, Mapping

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.oxml.ns import qn
from docx.table import Table
from docx.text.paragraph import Paragraph

from docx_table_utils import find_first_row_index_by_first_cell, find_summary_table, table_has_first_cell
from docx_utils import set_cell_paragraphs, set_cell_text_preserve


def is_summary_table(table: Table) -> bool:
    return table_has_first_cell(table, "监测结果")


def clear_repeat_table_headers(table: Table) -> None:
    for row in table.rows:
        tr_pr = row._tr.get_or_add_trPr()
        for child in list(tr_pr):
            if child.tag == qn("w:tblHeader"):
                tr_pr.remove(child)


def allow_table_rows_to_expand_and_split(table: Table) -> None:
    for row in table.rows:
        tr_pr = row._tr.get_or_add_trPr()
        for child in list(tr_pr):
            if child.tag in {qn("w:trHeight"), qn("w:cantSplit")}:
                tr_pr.remove(child)


def append_table_row_from_template(table: Table, template_tr) -> object:
    new_tr = deepcopy(template_tr)
    table._tbl.append(new_tr)
    return table.rows[-1]


def clear_table_rows(table: Table) -> None:
    for tr in list(table._tbl.tr_lst):
        table._tbl.remove(tr)


def summary_line_is_heading(line: str) -> bool:
    text = str(line or "").strip()
    return bool(
        re.match(r"^[一二三四五六七八九十]+、", text)
        or re.match(r"^\d+、", text)
        or re.match(r"^\d+(?:\.\d+)+\s*", text)
        or re.match(r"^（\d+）", text)
    )


def build_summary_result_rows(result_lines: list[str]) -> list[tuple[list[str], set[int]]]:
    lines = [str(line or "") for line in result_lines]
    return [(lines, {idx for idx, item in enumerate(lines) if summary_line_is_heading(item)})] if lines else []


def clear_paragraph_numbering(paragraph: Paragraph) -> None:
    p_pr = paragraph._p.get_or_add_pPr()
    num_pr = p_pr.find(qn("w:numPr"))
    if num_pr is not None:
        p_pr.remove(num_pr)


def clear_cell_numbering(cell) -> None:
    for paragraph in cell.paragraphs:
        clear_paragraph_numbering(paragraph)


def rebuild_summary_table_rows(
    table: Table,
    result_lines: list[str],
    advice_left: str,
    advice_lines: list[str],
) -> None:
    if not table.rows:
        return
    advice_template_idx = find_first_row_index_by_first_cell(table, "建议")
    result_template_tr = deepcopy(table.rows[0]._tr)
    advice_template_tr = deepcopy(table.rows[advice_template_idx]._tr if advice_template_idx is not None else table.rows[-1]._tr)
    clear_table_rows(table)

    result_rows = build_summary_result_rows(result_lines)
    for idx, (lines, bold_indices) in enumerate(result_rows):
        row = append_table_row_from_template(table, result_template_tr)
        row.cells[0].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        row.cells[1].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        set_cell_text_preserve(row.cells[0], "监测结果" if idx == 0 else "")
        set_cell_paragraphs(row.cells[1], lines, bold_indices=bold_indices)
        clear_cell_numbering(row.cells[0])
        clear_cell_numbering(row.cells[1])

    row = append_table_row_from_template(table, advice_template_tr)
    row.cells[0].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    row.cells[1].vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    set_cell_text_preserve(row.cells[0], advice_left or "建  议")
    set_cell_paragraphs(row.cells[1], advice_lines or ["建议结合监测数据变化情况进行持续跟踪。"])
    clear_cell_numbering(row.cells[0])
    clear_cell_numbering(row.cells[1])
    allow_table_rows_to_expand_and_split(table)
    clear_repeat_table_headers(table)


def _summary_text(section_map: Mapping[str, Any], key: str) -> str:
    content = section_map[key]
    return str(getattr(content, "summary_sentence", "") or "")


def build_summary_result_lines(section_map: Mapping[str, Any], data_acquisition_summary: str | None = None) -> list[str]:
    return [
        "一、监测系统运行情况",
        "",
        "二、本月监测数据情况",
        data_acquisition_summary or "本月监测数据获取情况详见正文。",
        "三、监测数据分析结果",
        "1、主桥环境与作用监测",
        "1.1 温度监测",
        _summary_text(section_map, "main_env"),
        "1.2 湿度监测",
        _summary_text(section_map, "main_humidity"),
        "1.3 雨量监测",
        _summary_text(section_map, "main_rainfall"),
        "1.4 风向风速监测",
        _summary_text(section_map, "main_wind"),
        "1.5 地震动监测",
        _summary_text(section_map, "main_eq"),
        "1.6 车辆荷载监测",
        _summary_text(section_map, "main_traffic"),
        "2、主桥结构响应与结构变化监测",
        "2.1 主梁挠度监测",
        _summary_text(section_map, "main_deflection"),
        "2.2 支座、梁段纵向位移监测",
        _summary_text(section_map, "main_bearing"),
        "2.3 拱顶、拱脚位移监测（GNSS）",
        _summary_text(section_map, "main_gnss"),
        "2.4 结构振动监测",
        _summary_text(section_map, "main_vibration"),
        "2.5 结构应变监测",
        _summary_text(section_map, "main_strain"),
        "2.6 裂缝监测",
        _summary_text(section_map, "main_crack"),
        "2.7 吊杆索力监测",
        _summary_text(section_map, "main_cable"),
        "3、北江滨匝道桥监测",
        "3.1 结构应变监测",
        _summary_text(section_map, "north_strain"),
        "3.2 支座位移监测",
        _summary_text(section_map, "north_bearing"),
        "3.3 墩柱倾斜监测",
        _summary_text(section_map, "north_tilt"),
        "4、南江滨匝道桥监测",
        "4.1 结构应变监测",
        _summary_text(section_map, "south_strain"),
        "4.2 支座位移监测",
        _summary_text(section_map, "south_bearing"),
        "4.3 墩柱倾斜监测",
        _summary_text(section_map, "south_tilt"),
    ]


def update_summary_table(doc: Document, section_map: Mapping[str, Any], data_acquisition_summary: str | None = None) -> None:
    summary_table = find_summary_table(doc)
    if summary_table is None:
        raise ValueError("Jiulongjiang summary table not found: expected left-column labels '监测结果' and '建  议'.")
    advice_row_idx = find_first_row_index_by_first_cell(summary_table, "建议")
    advice_left = summary_table.cell(advice_row_idx, 0).text.strip() if advice_row_idx is not None else "建  议"
    advice_lines = []
    if advice_row_idx is not None:
        advice_lines = [
            para.text.strip()
            for para in summary_table.cell(advice_row_idx, 1).paragraphs
            if para.text.strip()
        ]
    rebuild_summary_table_rows(
        summary_table,
        build_summary_result_lines(section_map, data_acquisition_summary),
        advice_left,
        advice_lines,
    )
