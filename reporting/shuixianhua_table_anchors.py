from __future__ import annotations

from lxml import etree

W_NS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W_NS}

SHUIXIANHUA_RESULT_TABLES = {
    "acquisition": "本月监测数据获取情况统计表",
    "temperature": "温度监测结果汇总表",
    "humidity": "湿度监测结果汇总表",
    "wind": "风速风向监测结果汇总表",
    "earthquake": "地震动监测结果汇总表",
    "deflection_raw": "主梁挠度原始数据监测结果汇总表",
    "deflection_filtered": "主梁挠度滤波后数据监测结果汇总表",
    "bearing_raw": "支座及伸缩缝位移监测结果汇总表",
    "bearing_filtered": "支座及伸缩缝位移滤波后监测结果汇总表",
    "gnss": "拱顶、拱脚位移（GNSS）监测结果汇总表",
    "acceleration": "结构振动加速度监测结果汇总表",
    "strain": "结构应变统计表",
    "cable_accel": "吊杆及系杆索力加速度统计表",
}


def xml_text(element) -> str:
    return "".join(element.xpath(".//w:t/text()", namespaces=NS))


def _body_children(root):
    body = root.find("w:body", NS)
    if body is None:
        return []
    return list(body)


def tables_by_caption(root) -> dict[str, etree._Element]:
    """Map visible caption paragraph text to the following Word table."""
    result: dict[str, etree._Element] = {}
    last_caption = ""
    for child in _body_children(root):
        tag = etree.QName(child).localname
        if tag == "p":
            text = xml_text(child).strip()
            if text:
                last_caption = text
        elif tag == "tbl" and last_caption:
            result[last_caption] = child
    return result


def table_by_caption(root, caption_substring: str):
    for caption, table in tables_by_caption(root).items():
        if caption_substring in caption:
            return table
    raise KeyError(f"Cannot find table after caption containing: {caption_substring}")


def required_result_tables(root) -> dict[str, etree._Element]:
    return {key: table_by_caption(root, caption) for key, caption in SHUIXIANHUA_RESULT_TABLES.items()}
