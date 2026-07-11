from __future__ import annotations

import copy
import re
import tempfile
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import ZipFile


W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W_NS}
TARGET_FIELD_RE = re.compile(r"^\s*(?:STYLEREF|REF)\b", re.IGNORECASE)


def qn(local: str) -> str:
    return f"{{{W_NS}}}{local}"


def _field_type(run: ET.Element) -> str:
    field = run.find("w:fldChar", NS)
    return "" if field is None else str(field.attrib.get(qn("fldCharType")) or "")


def _staticize_complex_fields(parent: ET.Element) -> int:
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
            separate = frame.get("separate")
            instructions = "".join(frame.get("instructions") or [])
            if separate is not None and TARGET_FIELD_RE.match(instructions):
                targets.append((int(frame["begin"]), int(separate), index))

    outer_targets = [
        target
        for target in targets
        if not any(
            other[0] < target[0] and target[2] < other[2]
            for other in targets
        )
    ]
    count = 0
    for begin, separate, end in sorted(outer_targets, reverse=True):
        current = list(parent)
        if end >= len(current):
            continue
        result_nodes = [copy.deepcopy(node) for node in current[separate + 1:end]]
        for node in current[begin:end + 1]:
            parent.remove(node)
        for offset, node in enumerate(result_nodes):
            parent.insert(begin + offset, node)
        count += 1
    return count


def _staticize_simple_fields(root: ET.Element) -> int:
    count = 0
    for parent in root.iter():
        for child in list(parent):
            if child.tag != qn("fldSimple"):
                continue
            instructions = str(child.attrib.get(qn("instr")) or "")
            if not TARGET_FIELD_RE.match(instructions):
                continue
            index = list(parent).index(child)
            replacements = [copy.deepcopy(node) for node in list(child)]
            parent.remove(child)
            for offset, node in enumerate(replacements):
                parent.insert(index + offset, node)
            count += 1
    return count


def staticize_reference_fields_xml(xml_bytes: bytes) -> tuple[bytes, dict[str, int]]:
    root = ET.fromstring(xml_bytes)
    complex_count = 0
    simple_count = 0
    for _ in range(20):
        pass_complex = 0
        for parent in root.iter():
            pass_complex += _staticize_complex_fields(parent)
        pass_simple = _staticize_simple_fields(root)
        complex_count += pass_complex
        simple_count += pass_simple
        if pass_complex + pass_simple == 0:
            break
    else:
        raise RuntimeError("reference-field staticization did not converge")
    remaining = []
    for node in root.iter():
        if node.tag == qn("instrText") and TARGET_FIELD_RE.match(node.text or ""):
            remaining.append(node.text or "")
        if node.tag == qn("fldSimple") and TARGET_FIELD_RE.match(str(node.attrib.get(qn("instr")) or "")):
            remaining.append(str(node.attrib.get(qn("instr")) or ""))
    if remaining:
        raise RuntimeError(f"reference fields remain after staticization: {remaining[:5]}")
    return ET.tostring(root, encoding="utf-8", xml_declaration=True), {
        "complex_field_count": complex_count,
        "simple_field_count": simple_count,
        "total_field_count": complex_count + simple_count,
    }


def staticize_reference_fields_docx(source: Path | str, output: Path | str) -> dict[str, int]:
    source_path = Path(source)
    output_path = Path(output)
    with ZipFile(source_path, "r") as archive:
        infos = archive.infolist()
        payloads = {info.filename: archive.read(info.filename) for info in infos}
    document, audit = staticize_reference_fields_xml(payloads["word/document.xml"])
    payloads["word/document.xml"] = document
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False, suffix=".docx", dir=output_path.parent) as handle:
        temp_path = Path(handle.name)
    try:
        with ZipFile(temp_path, "w") as archive:
            for info in infos:
                archive.writestr(info, payloads[info.filename])
        temp_path.replace(output_path)
    finally:
        if temp_path.exists():
            temp_path.unlink()
    return audit
