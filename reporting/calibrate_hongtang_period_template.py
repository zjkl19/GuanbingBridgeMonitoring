from __future__ import annotations

import argparse
from pathlib import Path

from docx import Document

from build_monthly_report import replace_paragraph_text
from docx_header_fields import audit_header_pagination_fields, ensure_header_pagination_fields


REPLACEMENTS = (
    ("见图 2-6、图 2-7", "见图 2-3、图 2-4"),
    ("应变测点布置详见图 2-9、图 2-10", "应变测点布置详见图 2-6、图 2-7"),
    ("通过倾角值的变化来反应主塔的倾斜情况", "通过倾角值的变化来反映主塔的倾斜情况"),
    ("主梁加速度传感纵断面布置图", "主梁加速度传感器纵断面布置图"),
    ("主梁加速度传感横断面布置图", "主梁加速度传感器横断面布置图"),
    ("地震仪进行监测，编号为EQ，布置位置如如图 2-15所示", "地震仪进行监测，编号为EQ，布置位置如图 2-16所示"),
    ("布置位置如如图 2-15所示", "布置位置如图 2-15所示"),
    ("续表 4-6 （轴重单位：kg，轴距单位：m）", "续表 4-3 （轴重单位：kg，轴距单位：m）"),
    ("续表 4-7 （轴重单位：kg，轴距单位：m）", "续表 4-4 （轴重单位：kg，轴距单位：m）"),
    ("续表 4-9 （轴重单位：kg，轴距单位：m）", "续表 4-6 （轴重单位：kg，轴距单位：m）"),
    ("续表 4-10 （轴重单位：kg，轴距单位：m）", "续表 4-7 （轴重单位：kg，轴距单位：m）"),
    ("续表 4-12 （轴重单位：kg，轴距单位：m）", "续表 4-9 （轴重单位：kg，轴距单位：m）"),
    ("续表 4-13 （轴重单位：kg，轴距单位：m）", "续表 4-10 （轴重单位：kg，轴距单位：m）"),
    ("各截面应变的箱线图如图3-4所示", "各截面应变的箱线图如图 4-5所示"),
    ("桥塔的应变的时程图", "桥塔应变的时程图"),
    ("桥塔各截面位置应变箱线曲线图", "桥塔各截面位置应变箱线图"),
    ("每日选取05：30~05:40时间段", "每日选取05:30~05:40时间段"),
)


def calibrate_template(source: Path, destination: Path) -> dict:
    doc = Document(str(source))
    changes: list[dict] = []
    for paragraph in doc.paragraphs:
        text = paragraph.text
        updated = text
        for old, new in REPLACEMENTS:
            updated = updated.replace(old, new)
        if "选取典型监测数据进行分析，典型测点自振频率时程如图4-12所示" in updated:
            updated = (
                "选取典型监测数据进行分析，典型测点自振频率时程如下图所示，"
                "监测周期内主梁及主塔自振频率识别结果整体稳定，未见明显异常漂移。"
            )
        if updated.startswith("监测结果如表4-12所示。监测结果表明，桥面"):
            updated = (
                "监测结果如表 4-12所示。表中“瞬时最大风速”与10min平均风速最大值采用不同统计口径，"
                "报告生成时按当前监测结果分别列示。"
            )
        if updated != text:
            replace_paragraph_text(paragraph, updated)
            changes.append({"old": text, "new": updated})

    header_cells = ensure_header_pagination_fields(doc)
    if header_cells != 1:
        raise RuntimeError(f"Expected one Hongtang pagination header cell, found {header_cells}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(destination))
    audit = audit_header_pagination_fields(destination)
    if not audit.valid:
        raise RuntimeError("Header PAGE/NUMPAGES audit failed: " + "; ".join(audit.details))
    return {
        "source": str(source),
        "destination": str(destination),
        "paragraph_changes": len(changes),
        "header_cells": header_cells,
        "header_audit": audit,
    }


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    default_template = repo_root / "reports" / "洪塘大桥健康监测周期报模板-自动报告.docx"
    parser = argparse.ArgumentParser(description="Apply accepted Hongtang period-template proofreading fixes.")
    parser.add_argument("--source", type=Path, default=default_template)
    parser.add_argument("--output", type=Path, default=default_template)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    result = calibrate_template(args.source, args.output)
    print(f"Template written to: {result['destination']}")
    print(f"Paragraph changes: {result['paragraph_changes']}")
    print(f"Header audit: {result['header_audit']}")


if __name__ == "__main__":
    main()
