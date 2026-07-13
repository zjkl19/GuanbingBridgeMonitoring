from __future__ import annotations

import re
import zipfile
from dataclasses import dataclass
from pathlib import Path
from xml.etree import ElementTree as ET

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Pt, Twips


HONGTANG_HEADER_WIDTHS_TWIPS = (3150, 3900, 2203)


@dataclass(frozen=True)
class HeaderPaginationAudit:
    valid: bool
    header_parts: int
    page_fields: int
    numpages_fields: int
    duplicate_page_phrases: int
    details: tuple[str, ...]


def _clear_paragraph(paragraph) -> None:
    for child in list(paragraph._p):
        if child.tag != qn("w:pPr"):
            paragraph._p.remove(child)


def _style_run(run) -> None:
    run.font.size = Pt(9)
    run.font.name = "宋体"
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), "宋体")


def _append_field(paragraph, instruction: str, result: str = "1") -> None:
    begin_run = OxmlElement("w:r")
    begin = OxmlElement("w:fldChar")
    begin.set(qn("w:fldCharType"), "begin")
    begin.set(qn("w:dirty"), "true")
    begin_run.append(begin)
    paragraph._p.append(begin_run)

    instruction_run = OxmlElement("w:r")
    instruction_text = OxmlElement("w:instrText")
    instruction_text.set(qn("xml:space"), "preserve")
    instruction_text.text = f" {instruction} "
    instruction_run.append(instruction_text)
    paragraph._p.append(instruction_run)

    separator_run = OxmlElement("w:r")
    separator = OxmlElement("w:fldChar")
    separator.set(qn("w:fldCharType"), "separate")
    separator_run.append(separator)
    paragraph._p.append(separator_run)

    result_run = paragraph.add_run(result)
    _style_run(result_run)

    end_run = OxmlElement("w:r")
    end = OxmlElement("w:fldChar")
    end.set(qn("w:fldCharType"), "end")
    end_run.append(end)
    paragraph._p.append(end_run)


def _replace_cell_pagination(cell) -> None:
    paragraph = cell.paragraphs[0]
    for extra in list(cell.paragraphs[1:]):
        cell._tc.remove(extra._p)
    _clear_paragraph(paragraph)
    paragraph.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    run = paragraph.add_run("第 ")
    _style_run(run)
    _append_field(paragraph, "PAGE")
    run = paragraph.add_run(" 页 共 ")
    _style_run(run)
    _append_field(paragraph, "NUMPAGES")
    run = paragraph.add_run(" 页")
    _style_run(run)


def _normalize_header_row_widths(table, row) -> None:
    """Keep the report number on one line while preserving the page cell width."""

    if len(row.cells) != len(HONGTANG_HEADER_WIDTHS_TWIPS):
        return
    for column_index, width_twips in enumerate(HONGTANG_HEADER_WIDTHS_TWIPS):
        width = Twips(width_twips)
        table.columns[column_index].width = width
        row.cells[column_index].width = width
        tc_width = row.cells[column_index]._tc.get_or_add_tcPr().get_or_add_tcW()
        tc_width.type = "dxa"
        tc_width.w = width_twips


def ensure_header_pagination_fields(document: Document) -> int:
    """Replace Hongtang's duplicated floating page text with PAGE/NUMPAGES fields."""

    changed = 0
    seen_parts: set[str] = set()
    for section in document.sections:
        header = section.header
        part_name = str(header.part.partname)
        if part_name in seen_parts:
            continue
        seen_parts.add(part_name)
        for table in header.tables:
            for row in table.rows:
                texts = [cell.text.strip() for cell in row.cells]
                if len(row.cells) < 3 or not any("报告编号" in text for text in texts):
                    continue
                _normalize_header_row_widths(table, row)
                _replace_cell_pagination(row.cells[-1])
                changed += 1
    return changed


def audit_header_pagination_fields(docx_path: Path) -> HeaderPaginationAudit:
    page_fields = 0
    numpages_fields = 0
    duplicate_phrases = 0
    details: list[str] = []
    header_parts = 0
    with zipfile.ZipFile(docx_path) as archive:
        for name in archive.namelist():
            if not re.fullmatch(r"word/header\d+\.xml", name):
                continue
            xml = archive.read(name).decode("utf-8")
            if "报告编号" not in xml:
                continue
            header_parts += 1
            root = ET.fromstring(xml)
            namespace = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
            fields = []
            fields.extend(
                re.sub(r"\s+", " ", node.text or "").strip().upper()
                for node in root.findall(".//w:instrText", namespace)
            )
            fields.extend(
                re.sub(r"\s+", " ", node.get(qn("w:instr"), "")).strip().upper()
                for node in root.findall(".//w:fldSimple", namespace)
            )
            page_count = sum(value == "PAGE" for value in fields)
            numpages_count = sum(value == "NUMPAGES" for value in fields)
            page_fields += page_count
            numpages_fields += numpages_count
            plain_text = "".join(node.text or "" for node in root.findall(".//w:t", namespace))
            phrase_count = plain_text.count("第 ")
            duplicate_phrases += max(0, phrase_count - 1)
            details.append(
                f"{name}: PAGE={page_count}, NUMPAGES={numpages_count}, page_phrases={phrase_count}"
            )
    valid = (
        header_parts == 1
        and page_fields == 1
        and numpages_fields == 1
        and duplicate_phrases == 0
    )
    return HeaderPaginationAudit(
        valid=valid,
        header_parts=header_parts,
        page_fields=page_fields,
        numpages_fields=numpages_fields,
        duplicate_page_phrases=duplicate_phrases,
        details=tuple(details),
    )
