from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from docx import Document
from docx.document import Document as DocxDocument


@dataclass(frozen=True)
class TemplateIssue:
    code: str
    message: str


class TemplatePrecheckError(RuntimeError):
    def __init__(self, template: Path, issues: list[TemplateIssue]):
        self.template = template
        self.issues = issues
        details = "\n".join(f"- [{issue.code}] {issue.message}" for issue in issues)
        super().__init__(f"Template precheck failed: {template}\n{details}")


def _paragraph_texts(doc: DocxDocument) -> list[str]:
    return [para.text.strip() for para in doc.paragraphs if para.text.strip()]


def _table_texts(doc: DocxDocument) -> list[str]:
    texts: list[str] = []
    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                text = cell.text.strip()
                if text:
                    texts.append(text)
    return texts


def _all_texts(doc: DocxDocument) -> list[str]:
    return _paragraph_texts(doc) + _table_texts(doc)


def _field_instr_texts(doc: DocxDocument) -> list[str]:
    fields: list[str] = []
    for para in doc.paragraphs:
        text = "".join(node.text or "" for node in para._p.iter() if node.tag.endswith("}instrText"))
        if text.strip():
            fields.append(text)
    return fields


def _contains_any(texts: Iterable[str], fragment: str) -> bool:
    return any(fragment in text for text in texts)


def _add_missing_fragment(issues: list[TemplateIssue], texts: list[str], fragment: object, note: str) -> None:
    if isinstance(fragment, (list, tuple, set)):
        options = [str(item) for item in fragment if item]
        _add_missing_any_fragment(issues, texts, options, note)
        return
    if fragment is None:
        return
    fragment_text = str(fragment)
    if not _contains_any(texts, fragment_text):
        issues.append(TemplateIssue("missing-text", f"{note}: {fragment_text}"))


def _add_missing_any_fragment(issues: list[TemplateIssue], texts: list[str], fragments: list[str], note: str) -> None:
    if not any(_contains_any(texts, fragment) for fragment in fragments):
        issues.append(TemplateIssue("missing-text", f"{note}: {' / '.join(fragments)}"))


def _section_available(section: dict | None) -> bool:
    if not isinstance(section, dict):
        return False
    if not section.get("enabled", True):
        return False
    return bool(section.get("available", True))


def check_hongtang_period_template(template: Path, manifest: dict | None = None) -> list[TemplateIssue]:
    doc = Document(str(template))
    texts = _all_texts(doc)
    issues: list[TemplateIssue] = []

    # These anchors are used unconditionally by the period report writer.
    required = [
        ("健康监测系统运行状况", "1.4 health-status section anchor"),
        ("交通状况监测", "WIM section start anchor"),
        ("结构应变监测", "WIM section end / next-section anchor"),
        ("2026年3月交通状况监测", "WIM monthly heading template"),
        ("桥梁共通过车辆", "WIM paragraph template"),
        ("季度交通状况分月统计表", "WIM quarterly table caption template"),
        ("续表 4-3", "WIM continuation caption template"),
        ("桥梁交通流参数分析", "WIM figure caption template"),
    ]
    for fragment, note in required:
        _add_missing_fragment(issues, texts, fragment, note)

    if manifest:
        sections = manifest.get("sections", {})
        strain = sections.get("strain")
        if _section_available(strain):
            for key in (
                "girder_timeseries_caption",
                "girder_boxplot_caption",
                "tower_timeseries_caption",
                "tower_boxplot_caption",
            ):
                caption = strain.get(key)
                if caption:
                    _add_missing_fragment(issues, texts, caption, f"strain caption anchor ({key})")
            for fragment in ("主梁应变", "桥塔应变"):
                _add_missing_fragment(issues, texts, fragment, "strain section paragraph anchor")

        tilt = sections.get("tilt")
        if _section_available(tilt):
            _add_missing_fragment(issues, texts, "主塔倾角偏移的方向以闽侯上街-农林大学为纵桥向", "tilt narrative anchor")
            if tilt.get("caption"):
                _add_missing_fragment(issues, texts, tilt["caption"], "tilt caption anchor")

        bearing = sections.get("bearing_displacement")
        if _section_available(bearing):
            _add_missing_fragment(issues, texts, "支座变位的方向以闽侯上街-农林大学为纵桥向", "bearing narrative anchor")
            if bearing.get("caption"):
                _add_missing_fragment(issues, texts, bearing["caption"], "bearing caption anchor")

        cable = sections.get("cable_force")
        if _section_available(cable):
            if cable.get("accel_available"):
                _add_missing_fragment(issues, texts, "（1）索力加速度时程数据", "cable-acceleration subsection anchor")
                _add_missing_fragment(issues, texts, "（2）索力时程数据", "cable-acceleration subsection end anchor")
                if cable.get("accel_caption"):
                    _add_missing_fragment(issues, texts, cable["accel_caption"], "cable-acceleration caption anchor")
            if cable.get("force_available"):
                _add_missing_fragment(issues, texts, "（2）索力时程数据", "cable-force subsection anchor")
                _add_missing_fragment(issues, texts, "4.6 主梁、主塔振动监测", "cable-force subsection end anchor")
                if cable.get("force_caption"):
                    _add_missing_fragment(issues, texts, cable["force_caption"], "cable-force caption anchor")

        vibration = sections.get("vibration")
        if _section_available(vibration):
            for fragment in ("（1）振动时程数据", "（2）自振频率", "4.7 风向风速监测"):
                _add_missing_fragment(issues, texts, fragment, "vibration subsection anchor")
            for key in ("timeseries_caption", "freq_caption"):
                caption = vibration.get(key)
                if caption:
                    _add_missing_fragment(issues, texts, caption, f"vibration caption anchor ({key})")

        wind = sections.get("wind")
        if _section_available(wind):
            _add_missing_fragment(issues, texts, "风向风速监测", "wind section anchor")
            for key in ("speed_caption", "rose_caption"):
                caption = wind.get(key)
                if caption:
                    _add_missing_fragment(issues, texts, caption, f"wind caption anchor ({key})")

        eq = sections.get("eq")
        if _section_available(eq):
            _add_missing_fragment(issues, texts, "地震动监测", "earthquake section anchor")
            if eq.get("caption"):
                _add_missing_fragment(issues, texts, eq["caption"], "earthquake caption anchor")

    return issues


JLJ_SECTION_HEADINGS = [
    ("主桥环境与作用监测", "温度监测"),
    ("主桥环境与作用监测", "湿度监测"),
    ("主桥环境与作用监测", "雨量监测"),
    ("主桥环境与作用监测", "风向风速监测"),
    ("主桥环境与作用监测", "地震动监测"),
    ("主桥环境与作用监测", "车辆荷载监测"),
    ("主桥结构响应与结构变化监测", "主梁挠度监测"),
    ("主桥结构响应与结构变化监测", "支座、梁段纵向位移监测"),
    ("主桥结构响应与结构变化监测", "拱顶、拱脚位移监测（GNSS）"),
    ("主桥结构响应与结构变化监测", "结构振动监测"),
    ("主桥结构响应与结构变化监测", "结构应变监测"),
    ("主桥结构响应与结构变化监测", "裂缝监测"),
    ("主桥结构响应与结构变化监测", "吊杆索力监测"),
    ("北江滨匝道桥监测", "结构应变监测"),
    ("北江滨匝道桥监测", "支座位移监测"),
    ("北江滨匝道桥监测", "墩柱倾斜监测"),
    ("南江滨匝道桥监测", "结构应变监测"),
    ("南江滨匝道桥监测", "支座位移监测"),
    ("南江滨匝道桥监测", "墩柱倾斜监测"),
]


def check_jlj_monthly_template(template: Path) -> list[TemplateIssue]:
    doc = Document(str(template))
    texts = _all_texts(doc)
    fields = _field_instr_texts(doc)
    issues: list[TemplateIssue] = []

    required = [
        ("健康监测系统运行状况", "health-status heading"),
        ("本节用于填充主桥温度监测结果", "section body style placeholder"),
        ("监测结果", "summary table result cell"),
    ]
    for fragment, note in required:
        _add_missing_fragment(issues, texts, fragment, note)
    _add_missing_any_fragment(issues, texts, ["建 议", "建议"], "summary table advice cell")

    for parent, child in JLJ_SECTION_HEADINGS:
        _add_missing_fragment(issues, texts, parent, "Jiulongjiang level-2 section heading")
        _add_missing_fragment(issues, texts, child, f"Jiulongjiang child heading under {parent}")

    if not any("SEQ 图" in field for field in fields):
        issues.append(TemplateIssue("missing-field", "No auto figure caption field (SEQ 图) found."))
    if not any("SEQ 表" in field for field in fields):
        issues.append(TemplateIssue("missing-field", "No auto table caption field (SEQ 表) found."))

    return issues


def check_template(kind: str, template: Path, manifest: dict | None = None) -> list[TemplateIssue]:
    if not template.exists():
        return [TemplateIssue("missing-file", f"Template file does not exist: {template}")]
    if kind == "hongtang_period":
        return check_hongtang_period_template(template, manifest)
    if kind == "jlj_monthly":
        return check_jlj_monthly_template(template)
    raise ValueError(f"Unknown template kind: {kind}")


def raise_for_template(kind: str, template: Path, manifest: dict | None = None) -> None:
    issues = check_template(kind, template, manifest)
    if issues:
        raise TemplatePrecheckError(template, issues)


def main() -> None:
    parser = argparse.ArgumentParser(description="Precheck bridge report DOCX templates.")
    parser.add_argument("--kind", choices=["hongtang_period", "jlj_monthly"], required=True)
    parser.add_argument("--template", type=Path, required=True)
    args = parser.parse_args()

    issues = check_template(args.kind, args.template)
    if issues:
        raise TemplatePrecheckError(args.template, issues)
    print(f"Template precheck OK: {args.template}")


if __name__ == "__main__":
    main()
