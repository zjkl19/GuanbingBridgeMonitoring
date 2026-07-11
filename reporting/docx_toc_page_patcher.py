from __future__ import annotations

import copy
import json
import re
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile

from pypdf import PdfReader


W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W_NS}
PREFIX_RE = re.compile(r"^\s*(?P<prefix>第\s*\d+\s*章|\d+(?:\.\d+)+)")


def qn(local: str) -> str:
    return f"{{{W_NS}}}{local}"


def normalize_prefix(value: str) -> str:
    return re.sub(r"\s+", "", value)


def toc_prefix(paragraph: ET.Element) -> str:
    text = "".join(node.text or "" for node in paragraph.iter(qn("t")))
    match = PREFIX_RE.match(text)
    return "" if not match else normalize_prefix(match.group("prefix"))


def logical_page_map(pdf_path: Path, prefixes: set[str]) -> dict[str, int]:
    reader = PdfReader(str(pdf_path))
    result: dict[str, int] = {}
    for page in reader.pages:
        text = page.extract_text() or ""
        header = re.search(r"第\s*(\d+)\s*页\s*共", text)
        if not header:
            continue
        logical_page = int(header.group(1))
        if logical_page < 7:
            continue
        compact = re.sub(r"\s+", "", text)
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        for prefix in prefixes - set(result):
            if prefix.startswith("第"):
                if prefix in compact:
                    result[prefix] = logical_page
            elif any(re.match(rf"^{re.escape(prefix)}(?:\s|$)", line) for line in lines):
                result[prefix] = logical_page
    missing = sorted(prefixes - set(result))
    if missing:
        raise RuntimeError(f"unable to resolve TOC headings in rendered PDF: {missing}")
    return result


def _field_type(run: ET.Element) -> str:
    field = run.find("w:fldChar", NS)
    return "" if field is None else str(field.attrib.get(qn("fldCharType")) or "")


def _patch_pageref_in_parent(parent: ET.Element, page_number: int) -> int:
    children = list(parent)
    stack: list[dict[str, object]] = []
    targets: list[tuple[int, int, int]] = []
    for index, child in enumerate(children):
        if child.tag != qn("r"):
            continue
        kind = _field_type(child)
        if kind == "begin":
            stack.append({"begin": index, "separate": None, "instructions": []})
            continue
        for frame in stack:
            frame["instructions"].extend(node.text or "" for node in child.findall("w:instrText", NS))
        if kind == "separate" and stack:
            stack[-1]["separate"] = index
        elif kind == "end" and stack:
            frame = stack.pop()
            instructions = "".join(frame.get("instructions") or [])
            separate = frame.get("separate")
            if separate is not None and re.match(r"^\s*PAGEREF\b", instructions, re.IGNORECASE):
                targets.append((int(frame["begin"]), int(separate), index))
    count = 0
    for begin, separate, end in sorted(targets, reverse=True):
        current = list(parent)
        result_nodes = current[separate + 1:end]
        replacement = ET.Element(qn("r"))
        if result_nodes:
            original_rpr = result_nodes[0].find("w:rPr", NS)
            if original_rpr is not None:
                replacement.append(copy.deepcopy(original_rpr))
        text_node = ET.SubElement(replacement, qn("t"))
        text_node.text = str(page_number)
        for node in result_nodes:
            parent.remove(node)
        parent.insert(separate + 1, replacement)
        count += 1
    return count


def patch_toc_and_total_pages(source: Path, rendered_pdf: Path, output: Path) -> dict:
    with ZipFile(source, "r") as archive:
        infos = archive.infolist()
        payloads = {info.filename: archive.read(info.filename) for info in infos}
    root = ET.fromstring(payloads["word/document.xml"])
    toc_paragraphs: list[tuple[ET.Element, str]] = []
    for paragraph in root.iter(qn("p")):
        style = paragraph.find("./w:pPr/w:pStyle", NS)
        style_name = "" if style is None else str(style.attrib.get(qn("val")) or "")
        if not style_name.upper().startswith("TOC"):
            continue
        prefix = toc_prefix(paragraph)
        if prefix:
            toc_paragraphs.append((paragraph, prefix))
    prefixes = {prefix for _, prefix in toc_paragraphs}
    page_map = logical_page_map(rendered_pdf, prefixes)

    patched_pageref = 0
    for paragraph, prefix in toc_paragraphs:
        page_number = page_map[prefix]
        for parent in paragraph.iter():
            patched_pageref += _patch_pageref_in_parent(parent, page_number)
    if patched_pageref != len(toc_paragraphs):
        raise RuntimeError(f"patched {patched_pageref} PAGEREF fields for {len(toc_paragraphs)} TOC paragraphs")
    payloads["word/document.xml"] = ET.tostring(root, encoding="utf-8", xml_declaration=True)

    total_pages = len(PdfReader(str(rendered_pdf)).pages)
    patched_total = 0
    for name in list(payloads):
        if not re.fullmatch(r"word/header\d+\.xml", name):
            continue
        header_root = ET.fromstring(payloads[name])
        text_nodes = [node for node in header_root.iter(qn("t"))]
        for index, node in enumerate(text_nodes):
            value = (node.text or "").strip()
            if not value.isdigit():
                continue
            previous = next(((item.text or "").strip() for item in reversed(text_nodes[:index]) if (item.text or "").strip()), "")
            following = next(((item.text or "").strip() for item in text_nodes[index + 1:] if (item.text or "").strip()), "")
            if previous == "共" and following == "页":
                node.text = str(total_pages)
                patched_total += 1
        payloads[name] = ET.tostring(header_root, encoding="utf-8", xml_declaration=True)
    if not patched_total:
        raise RuntimeError("total-page header text was not patched")

    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".docx", dir=output.parent) as handle:
        temp_path = Path(handle.name)
    try:
        with ZipFile(temp_path, "w") as archive:
            for info in infos:
                archive.writestr(info, payloads[info.filename])
        temp_path.replace(output)
    finally:
        if temp_path.exists():
            temp_path.unlink()
    return {
        "toc_entry_count": len(toc_paragraphs),
        "patched_pageref_count": patched_pageref,
        "patched_total_page_count": patched_total,
        "total_pages": total_pages,
        "page_map": page_map,
    }
