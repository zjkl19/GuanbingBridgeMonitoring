from __future__ import annotations

from copy import deepcopy
from typing import Any, Callable, Sequence

from docx.oxml.ns import qn
from lxml import etree


W_NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}


def xml_text(element) -> str:
    return "".join(node.text or "" for node in element.findall(".//w:t", W_NS))


def set_paragraph_text(paragraph, text: str) -> None:
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
    node = etree.SubElement(run, qn("w:t"))
    if text.startswith(" ") or text.endswith(" "):
        node.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    node.text = str(text)
    paragraph.append(run)


def set_cell_text(cell, text: Any) -> None:
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
    node = etree.SubElement(run, qn("w:t"))
    node.text = "" if text is None else str(text)


def rewrite_paragraphs_containing(root, contains: str, replacement: str, *, startswith: str | None = None) -> int:
    changed = 0
    for paragraph in root.findall(".//w:p", W_NS):
        current = xml_text(paragraph)
        if contains not in current:
            continue
        if startswith is not None and not current.startswith(startswith):
            continue
        set_paragraph_text(paragraph, replacement)
        changed += 1
    return changed


def fill_table(table, rows: Sequence[dict[str, Any]], value_builder: Callable[[int, dict[str, Any]], Sequence[Any]]) -> None:
    table_rows = table.findall(qn("w:tr"))
    for data_idx, tr in enumerate(table_rows[1:]):
        cells = tr.findall(qn("w:tc"))
        values = value_builder(data_idx + 1, rows[data_idx]) if data_idx < len(rows) else [""] * len(cells)
        for col_idx, cell in enumerate(cells):
            set_cell_text(cell, values[col_idx] if col_idx < len(values) else "")
