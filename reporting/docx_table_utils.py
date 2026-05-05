from __future__ import annotations

from typing import Any

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.table import Table

from docx_utils import set_cell_text_preserve


def center_cell(cell) -> None:
    cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
    for paragraph in cell.paragraphs:
        paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER


def find_table_by_header(doc: Document, header_text: str) -> Table | None:
    """Find the first table containing a header/cell fragment."""
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                if header_text in cell.text:
                    return table
    return None


def set_table_cell(table: Table, row_idx: int, col_idx: int, text: Any, *, preserve: bool = True, center: bool = True) -> None:
    cell = table.cell(row_idx, col_idx)
    value = "" if text is None else str(text)
    if preserve:
        set_cell_text_preserve(cell, value)
    else:
        cell.text = value
    if center:
        center_cell(cell)
