from __future__ import annotations

import argparse
import json
import math
import shutil
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Mm
from docx.text.paragraph import Paragraph
from openpyxl import load_workbook
from PIL import Image, ImageOps


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE_TEMPLATE = REPO_ROOT / "reports" / "G104线管柄大桥监测月报20260410-M18.docx"
DEFAULT_TEMPLATE = REPO_ROOT / "reports" / "G104线管柄大桥监测月报模板-自动报告.docx"
DEFAULT_RESULT_ROOT = Path("F:/管柄大桥数据/2026年3月")


@dataclass
class RangeStats:
    min_value: float
    max_value: float
    mean_value: float | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build G104 Guanbing Bridge monthly report.")
    parser.add_argument("--source-template", type=Path, default=DEFAULT_SOURCE_TEMPLATE)
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--config", type=Path, default=REPO_ROOT / "config" / "default_config.json")
    parser.add_argument("--result-root", type=Path, default=DEFAULT_RESULT_ROOT)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--period-label", default="2026年03月")
    parser.add_argument("--monitoring-range", default="2026年02月26日~2026年03月25日")
    parser.add_argument("--report-date", default=datetime.now().strftime("%Y年%m月%d日"))
    parser.add_argument("--start-date", default="2026-02-26")
    parser.add_argument("--end-date", default="2026-03-25")
    parser.add_argument("--skip-image-replace", action="store_true")
    parser.add_argument("--refresh-template", action="store_true", help="Overwrite the auto-report template from source template.")
    return parser.parse_args()


def ensure_template(source_template: Path, template: Path, refresh: bool = False) -> Path:
    if refresh or not template.exists():
        if not source_template.exists():
            raise FileNotFoundError(f"Source template not found: {source_template}")
        template.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_template, template)
    return template


def load_sheet_rows(path: Path, sheet_name: str | None = None) -> list[dict]:
    if not path.exists():
        return []
    wb = load_workbook(path, read_only=True, data_only=True)
    try:
        ws = wb[sheet_name] if sheet_name else wb.worksheets[0]
        rows = list(ws.iter_rows(values_only=True))
    finally:
        wb.close()
    if not rows:
        return []
    headers = [str(v).strip() if v is not None else "" for v in rows[0]]
    out: list[dict] = []
    for row in rows[1:]:
        item = {key: value for key, value in zip(headers, row) if key}
        if any(value is not None for value in item.values()):
            out.append(item)
    return out


def load_workbook_sheet_rows(path: Path) -> dict[str, list[dict]]:
    if not path.exists():
        return {}
    wb = load_workbook(path, read_only=True, data_only=True)
    result: dict[str, list[dict]] = {}
    try:
        for ws in wb.worksheets:
            rows = list(ws.iter_rows(values_only=True))
            if not rows:
                result[ws.title] = []
                continue
            headers = [str(v).strip() if v is not None else "" for v in rows[0]]
            sheet_rows: list[dict] = []
            for row in rows[1:]:
                item = {key: value for key, value in zip(headers, row) if key}
                if any(value is not None for value in item.values()):
                    sheet_rows.append(item)
            result[ws.title] = sheet_rows
    finally:
        wb.close()
    return result


def as_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    if math.isnan(number) or math.isinf(number):
        return None
    return number


def fmt_num(value: float | None, digits: int = 1, keep_decimal: bool = False) -> str:
    if value is None:
        return "/"
    text = f"{value:.{digits}f}"
    if keep_decimal:
        return text
    return text.rstrip("0").rstrip(".")


def aggregate_range(rows: Iterable[dict], min_key: str = "Min", max_key: str = "Max", mean_key: str = "Mean") -> RangeStats | None:
    mins: list[float] = []
    maxs: list[float] = []
    means: list[float] = []
    for row in rows:
        min_value = as_float(row.get(min_key))
        max_value = as_float(row.get(max_key))
        mean_value = as_float(row.get(mean_key))
        if min_value is not None:
            mins.append(min_value)
        if max_value is not None:
            maxs.append(max_value)
        if mean_value is not None:
            means.append(mean_value)
    if not mins or not maxs:
        return None
    mean = sum(means) / len(means) if means else None
    return RangeStats(min(mins), max(maxs), mean)


def rows_by_points(rows: list[dict], points: set[str]) -> list[dict]:
    return [row for row in rows if str(row.get("PointID", "")).strip() in points]


def replace_text_in_paragraph(paragraph: Paragraph, text: str) -> None:
    if paragraph.runs:
        paragraph.runs[0].text = text
        for run in paragraph.runs[1:]:
            run.text = ""
    else:
        paragraph.add_run(text)


def replace_first_by_prefix(doc: Document, prefix: str, text: str, start_at: int = 0) -> bool:
    for paragraph in doc.paragraphs[start_at:]:
        if paragraph.text.strip().startswith(prefix):
            replace_text_in_paragraph(paragraph, text)
            return True
    return False


def replace_all_by_prefix(doc: Document, prefix: str, text: str, limit: int | None = None) -> int:
    count = 0
    paragraphs = doc.paragraphs[:limit] if limit is not None else doc.paragraphs
    for paragraph in paragraphs:
        if paragraph.text.strip().startswith(prefix):
            replace_text_in_paragraph(paragraph, text)
            count += 1
    return count


def find_paragraph_contains(doc: Document, fragment: str, occurrence: int = 1) -> Paragraph | None:
    seen = 0
    for paragraph in doc.paragraphs:
        if fragment in paragraph.text:
            seen += 1
            if seen == occurrence:
                return paragraph
    return None


def paragraph_has_image(paragraph: Paragraph) -> bool:
    return bool(paragraph._p.xpath(".//w:drawing") or paragraph._p.xpath(".//w:pict"))


def paragraph_from_element(element, parent) -> Paragraph:
    return Paragraph(element, parent)


def remove_paragraph(paragraph: Paragraph) -> None:
    element = paragraph._element
    parent = element.getparent()
    if parent is not None:
        parent.remove(element)


def previous_body_paragraphs(paragraph: Paragraph, limit: int = 8) -> list[Paragraph]:
    out: list[Paragraph] = []
    element = paragraph._p.getprevious()
    while element is not None and len(out) < limit:
        if element.tag == qn("w:p"):
            out.append(paragraph_from_element(element, paragraph._parent))
        element = element.getprevious()
    return out


def remove_nearby_picture_before(anchor: Paragraph, limit: int = 8) -> int:
    removed = 0
    for candidate in previous_body_paragraphs(anchor, limit=limit):
        text = candidate.text.strip()
        if paragraph_has_image(candidate):
            remove_paragraph(candidate)
            removed += 1
            continue
        # Stop at meaningful text before the anchor; blank paragraphs are harmless.
        if text:
            break
    return removed


def insert_picture_before(anchor: Paragraph, image_path: Path, width_mm: float = 145.0) -> None:
    paragraph = anchor.insert_paragraph_before()
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    paragraph.add_run().add_picture(str(image_path), width=Mm(width_mm))


def replace_picture_before_anchor(
    doc: Document,
    anchor_fragment: str,
    image_path: Path | None,
    occurrence: int = 1,
    width_mm: float = 145.0,
) -> tuple[bool, str]:
    if image_path is None or not image_path.exists():
        return False, f"missing image for anchor: {anchor_fragment}"
    anchor = find_paragraph_contains(doc, anchor_fragment, occurrence=occurrence)
    if anchor is None:
        return False, f"missing anchor: {anchor_fragment}"
    remove_nearby_picture_before(anchor)
    insert_picture_before(anchor, image_path, width_mm=width_mm)
    return True, str(image_path)


def find_latest_image(result_root: Path, folder_name: str, token: str, suffix: str = ".jpg") -> Path | None:
    folder = result_root / folder_name
    if not folder.exists():
        return None
    candidates = [p for p in folder.glob(f"*{suffix}") if token in p.stem]
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def find_latest_file(result_root: Path, folder_name: str, pattern: str) -> Path | None:
    folder = result_root / folder_name
    if not folder.exists():
        return None
    candidates = list(folder.glob(pattern))
    if not candidates:
        return None
    return max(candidates, key=lambda p: p.stat().st_mtime)


def stack_images_vertical(paths: list[Path], output_path: Path, gap: int = 18) -> Path | None:
    existing = [path for path in paths if path is not None and path.exists()]
    if not existing:
        return None
    images = [Image.open(path).convert("RGB") for path in existing]
    try:
        max_width = max(img.width for img in images)
        normalized: list[Image.Image] = []
        for img in images:
            if img.width != max_width:
                new_height = max(1, round(img.height * max_width / img.width))
                img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
            normalized.append(ImageOps.expand(img, border=0, fill="white"))
        total_height = sum(img.height for img in normalized) + gap * (len(normalized) - 1)
        canvas = Image.new("RGB", (max_width, total_height), "white")
        y = 0
        for img in normalized:
            canvas.paste(img, (0, y))
            y += img.height + gap
        output_path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(output_path, quality=92)
        return output_path
    finally:
        for img in images:
            img.close()


def build_accel_combined_image(result_root: Path, asset_dir: Path, point_id: str) -> Path | None:
    time_img = find_latest_image(result_root, "时程曲线_加速度", point_id)
    rms_img = find_latest_image(result_root, "时程曲线_加速度_RMS10min", f"AccelRMS10_{point_id}")
    return stack_images_vertical([time_img, rms_img], asset_dir / f"accel_{point_id}.jpg")


def build_stats_texts(result_root: Path, period_label: str) -> dict[str, str]:
    stats_dir = result_root / "stats"
    texts: dict[str, str] = {}

    temp_rows = load_sheet_rows(stats_dir / "temp_stats.xlsx")
    env_temp = aggregate_range(rows_by_points(temp_rows, {"GB-RTS-G05-001-03"}))
    box_temp = aggregate_range(rows_by_points(temp_rows, {"GB-RTS-G05-001-01", "GB-RTS-G05-001-02"}))
    if env_temp:
        texts["temp_env"] = (
            f"（1）本月监测周期内，环境最高温度为{fmt_num(env_temp.max_value, 1, True)}℃，"
            f"最低温度为{fmt_num(env_temp.min_value, 1, True)}℃，平均温度{fmt_num(env_temp.mean_value, 1, True)}℃。"
        )
    if box_temp:
        texts["temp_box"] = (
            f"（2）本月监测周期内，箱内最高温度为{fmt_num(box_temp.max_value, 1, True)}℃，"
            f"最低温度为{fmt_num(box_temp.min_value, 1, True)}℃，平均温度{fmt_num(box_temp.mean_value, 1, True)}℃。"
            "可知，箱内最高温度低于环境温度，温度幅值及波动剧烈程度低于环境温度。"
        )

    humidity_rows = load_sheet_rows(stats_dir / "humidity_stats.xlsx")
    env_humidity = aggregate_range(rows_by_points(humidity_rows, {"GB-RHS-G05-001-03"}))
    box_humidity = aggregate_range(rows_by_points(humidity_rows, {"GB-RHS-G05-001-01", "GB-RHS-G05-001-02"}))
    if env_humidity:
        texts["humidity_env"] = (
            f"（1）本月监测周期内，环境最高湿度为{fmt_num(env_humidity.max_value, 1)}%RH，"
            f"最低湿度为{fmt_num(env_humidity.min_value, 1)}%RH，平均湿度为{fmt_num(env_humidity.mean_value, 1)}%RH，"
            "湿度主要分布在80%~100%RH范围内。"
        )
    if box_humidity:
        texts["humidity_box"] = (
            f"（2）本月监测周期内，箱内最高湿度为{fmt_num(box_humidity.max_value, 1)}%RH，"
            f"最低湿度为{fmt_num(box_humidity.min_value, 1)}%RH，平均湿度为{fmt_num(box_humidity.mean_value, 1)}%RH。"
            "可知，箱内湿度低于环境湿度，湿度幅值及波动剧烈程度低于环境湿度。"
        )

    deflection_rows = load_sheet_rows(stats_dir / "deflection_stats.xlsx")
    if deflection_rows:
        orig_min = [as_float(row.get("OrigMin_mm")) for row in deflection_rows]
        orig_max = [as_float(row.get("OrigMax_mm")) for row in deflection_rows]
        orig_min = [value for value in orig_min if value is not None]
        orig_max = [value for value in orig_max if value is not None]
        if orig_min and orig_max:
            max_up = abs(min(orig_min))
            max_down = max(orig_max)
            texts["deflection_abs"] = (
                f"由以上各图可知，本月监测周期内，第2、3跨挠度最大上挠{fmt_num(max_up, 1)}mm，"
                f"最大下挠{fmt_num(max_down, 1)}mm，均处于超限阈值范围之内，"
                "未出现超过各级超限阈值和报警的情况。"
            )
        mid_rows = [row for row in deflection_rows if "-002-" in str(row.get("PointID", ""))]
        filt_min = [as_float(row.get("FiltMin_mm")) for row in mid_rows]
        filt_max = [as_float(row.get("FiltMax_mm")) for row in mid_rows]
        filt_min = [value for value in filt_min if value is not None]
        filt_max = [value for value in filt_max if value is not None]
        if filt_min and filt_max:
            trend_min = min(filt_min)
            trend_max = max(filt_max)
            texts["deflection_trend"] = (
                f"由以上各图可知，本月监测周期内，第2、3跨主梁跨中挠度变化范围为"
                f"{fmt_num(trend_min, 1)}mm~{fmt_num(trend_max, 1)}mm，挠度同一天中处于波动变化中。"
            )
            texts["conclusion_deflection"] = (
                f"（4）本月监测周期内，实测主梁挠度值处于设计理论挠度范围，"
                f"第2、3跨主梁跨中挠度变化范围为{fmt_num(trend_min, 1)}mm~{fmt_num(trend_max, 1)}mm，"
                "挠度同一天中处于波动变化中。"
            )

    tilt_sheets = load_workbook_sheet_rows(stats_dir / "tilt_stats.xlsx")
    tilt_x = aggregate_range(tilt_sheets.get("Tilt_X", []), min_key="Min", max_key="Max")
    tilt_y = aggregate_range(tilt_sheets.get("Tilt_Y", []), min_key="Min", max_key="Max")
    if tilt_x and tilt_y:
        tilt_x_abs = max(abs(tilt_x.min_value), abs(tilt_x.max_value))
        tilt_y_abs = max(abs(tilt_y.min_value), abs(tilt_y.max_value))
        texts["tilt"] = (
            f"由以上各图可知，本月监测周期内，主墩倾角纵桥向X最大为{fmt_num(tilt_x_abs, 3)}°，"
            f"横桥向Y最大为{fmt_num(tilt_y_abs, 3)}°，均处于超限阈值范围之内，"
            "未出现超过各级超限阈值和报警的情况。主墩未出现明显倾斜趋势。"
        )
        texts["conclusion_tilt"] = (
            f"（5）本月监测周期内，主墩倾角纵桥向X最大为{fmt_num(tilt_x_abs, 3)}°，"
            f"横桥向Y最大为{fmt_num(tilt_y_abs, 3)}°，均处于超限阈值范围之内，"
            "未出现超过各级超限阈值和报警的情况，主墩未出现明显倾斜趋势。"
        )

    hp_path = find_latest_file(result_root, "动应变箱线图_高通滤波", "boxplot_stats_*.xlsx")
    hp_sheets = load_workbook_sheet_rows(hp_path) if hp_path else {}
    if hp_sheets:
        pieces: list[str] = []
        for sheet, label in (("G05", "第2跨跨中截面"), ("G06", "第3跨跨中截面")):
            stats = aggregate_range(hp_sheets.get(sheet, []), min_key="Min", max_key="Max")
            if stats:
                pieces.append(
                    f"{label}测点活载作用下最大拉应变为{fmt_num(stats.max_value, 2)}με、"
                    f"最大压应变为{fmt_num(abs(stats.min_value), 2)}με"
                )
        if pieces:
            texts["strain_hp"] = (
                "由上图可知，本月监测周期内，"
                + "；".join(pieces)
                + "，均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"
                "图中各应变传感器的上下四分位数距离较小，整体活载水平不高；最值之间距离较大，表明桥上时有重车通过。"
            )

    lp_path = find_latest_file(result_root, "动应变箱线图_低通滤波", "boxplot_stats_*.xlsx")
    lp_rows_by_sheet = load_workbook_sheet_rows(lp_path) if lp_path else {}
    all_lp_rows: list[dict] = []
    for rows in lp_rows_by_sheet.values():
        all_lp_rows.extend(rows)
    lp_stats = aggregate_range(all_lp_rows, min_key="Min", max_key="Max")
    if lp_stats:
        texts["strain_lp"] = (
            f"由上图可知，应变测点最大拉应变{fmt_num(lp_stats.max_value, 2)}με，"
            f"最大压应变{fmt_num(abs(lp_stats.min_value), 2)}με，呈现缓慢变化，未超过设计最不利计算值。"
            "综上，截面整体受力未见明显异常。"
        )

    crack_rows = load_sheet_rows(stats_dir / "crack_stats.xlsx")
    g05_crack = aggregate_range([row for row in crack_rows if "G05" in str(row.get("PointID", ""))], min_key="CrkMin", max_key="CrkMax")
    g06_crack = aggregate_range([row for row in crack_rows if "G06" in str(row.get("PointID", ""))], min_key="CrkMin", max_key="CrkMax")
    if g05_crack and g06_crack:
        texts["crack"] = (
            "由以上各图可知，本月监测周期内，"
            f"顶板裂缝宽度变化量（相对2024年9月26日）在{fmt_num(g05_crack.min_value, 3)}mm~{fmt_num(g05_crack.max_value, 3)}mm之间，"
            f"底板裂缝宽度变化量（相对2024年9月26日）在{fmt_num(g06_crack.min_value, 3)}mm~{fmt_num(g06_crack.max_value, 3)}mm之间，"
            "裂缝宽度监测值同一天中处于波动变化中。"
        )

    freq_path = stats_dir / "accel_spec_stats.xlsx"
    freq_sheets = load_workbook_sheet_rows(freq_path)
    freq_ranges: list[tuple[float, float]] = []
    for idx in range(1, 4):
        values: list[float] = []
        for rows in freq_sheets.values():
            if not rows:
                continue
            keys = [key for key in rows[0].keys() if key.startswith("Freq_")]
            if len(keys) >= idx:
                for row in rows:
                    value = as_float(row.get(keys[idx - 1]))
                    if value is not None:
                        values.append(value)
        if values:
            freq_ranges.append((min(values), max(values)))
    if len(freq_ranges) == 3:
        f_text = "、".join(f"{fmt_num(lo, 3)}Hz~{fmt_num(hi, 3)}Hz" for lo, hi in freq_ranges)
        texts["freq"] = (
            f"由上图可知，本月监测周期内各个传感器实测竖向第一、二、三阶自振频率分别为{f_text}，"
            "均大于理论计算的主梁一、二、三阶竖弯频率0.975Hz、1.243Hz、1.528Hz，"
            "且处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况，桥梁结构实测刚度大于理论刚度且未见明显变化。"
        )

    accel_rows = [row for row in load_sheet_rows(stats_dir / "accel_stats.xlsx") if row.get("PointID")]
    accel_stats = aggregate_range(accel_rows, min_key="Min", max_key="Max")
    rms_values = [as_float(row.get("RMS10minMax")) for row in accel_rows]
    rms_values = [value for value in rms_values if value is not None]
    if accel_stats and rms_values:
        max_abs = max(abs(accel_stats.min_value), abs(accel_stats.max_value))
        texts["accel"] = (
            f"由以上各图可知，本月监测周期内，主梁竖向加速度各测点绝对最大值为{fmt_num(max_abs, 2)}mm/s²，"
            f"各测点10min加速度均方根值最大为{fmt_num(max(rms_values), 3)}mm/s²，未超过315mm/s²，"
            "均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"
        )

    if env_temp and box_temp:
        texts["conclusion_temp"] = (
            f"（2）本月监测周期内，环境最高温度为{fmt_num(env_temp.max_value, 1, True)}℃，最低温度为{fmt_num(env_temp.min_value, 1, True)}℃，"
            f"平均温度{fmt_num(env_temp.mean_value, 1, True)}℃；箱内最高温度为{fmt_num(box_temp.max_value, 1, True)}℃，"
            f"最低温度为{fmt_num(box_temp.min_value, 1, True)}℃，平均温度{fmt_num(box_temp.mean_value, 1, True)}℃。"
            "可知，箱内最高温度低于环境温度，温度幅值及波动剧烈程度低于环境温度。"
        )
    if env_humidity and box_humidity:
        texts["conclusion_humidity"] = (
            f"（3）本月监测周期内，环境最高湿度为{fmt_num(env_humidity.max_value, 1)}%RH，最低湿度为{fmt_num(env_humidity.min_value, 1)}%RH，"
            f"平均湿度为{fmt_num(env_humidity.mean_value, 1)}%RH，湿度主要分布在80%~100%RH范围内；"
            f"箱内最高湿度为{fmt_num(box_humidity.max_value, 1)}%RH，最低湿度为{fmt_num(box_humidity.min_value, 1)}%RH，"
            f"平均湿度为{fmt_num(box_humidity.mean_value, 1)}%RH。可知，箱内湿度低于环境湿度，湿度幅值及波动剧烈程度低于环境湿度。"
        )
    if "strain_hp" in texts and lp_stats:
        texts["conclusion_strain"] = (
            f"（6）本月监测周期内，主梁活载作用下动应变和温度、收缩徐变等作用下静应变均处于设计值范围内；"
            f"静应变最大拉应变{fmt_num(lp_stats.max_value, 2)}με，最大压应变{fmt_num(abs(lp_stats.min_value), 2)}με，截面整体受力未见明显异常。"
        )
    if "crack" in texts:
        texts["conclusion_crack"] = "（8）本月监测周期内，" + texts["crack"].split("本月监测周期内，", 1)[-1]
    if "freq" in texts and "accel" in texts:
        texts["conclusion_accel"] = "（7）" + texts["accel"].replace("由以上各图可知，本月监测周期内，", "本月监测周期内，") + "所测竖向第一、二、三阶自振频率均在理论值内，桥梁结构实测刚度大于理论刚度且未见明显变化。"

    texts["summary"] = f"综上所述，G104线管柄大桥{period_label}监测周期内，桥梁主要健康监测指标正常，桥梁运营状态良好，建议管养单位继续加强桥面和箱内的巡查。"
    return texts


def apply_text_updates(doc: Document, texts: dict[str, str], monitoring_range: str, report_date: str) -> list[str]:
    updated: list[str] = []
    if replace_all_by_prefix(doc, "（时间范围：", f"（时间范围：{monitoring_range}）", limit=30):
        updated.append("cover monitoring range")
    if replace_all_by_prefix(doc, "报告日期：", f"报告日期：{report_date}", limit=30):
        updated.append("cover report date")

    replacements = [
        ("（1）本月监测周期内，环境最高温度", texts.get("temp_env")),
        ("（2）本月监测周期内，箱内最高温度", texts.get("temp_box")),
        ("（1）本月监测周期内，环境最高湿度", texts.get("humidity_env")),
        ("（2）本月监测周期内，箱内最高湿度", texts.get("humidity_box")),
        ("由以上各图可知，本月监测周期内，第2、3跨挠度最大上挠", texts.get("deflection_abs")),
        ("由以上各图可知，本月监测周期内，第2、3跨主梁跨中挠度变化范围", texts.get("deflection_trend")),
        ("由以上各图可知，本月监测周期内，主墩倾角纵桥向X最大", texts.get("tilt")),
        ("由上图可知，本月监测周期内，第2跨跨中截面测点活载作用下", texts.get("strain_hp")),
        ("由上图可知，应变测点最大拉应变", texts.get("strain_lp")),
        ("由上图可知，本月监测周期内各个传感器实测竖向第一、二、三阶自振频率", texts.get("freq")),
        ("由以上各图可知，本月监测周期内，顶板裂缝宽度变化量", texts.get("crack")),
        ("（2）本月监测周期内，环境最高温度", texts.get("conclusion_temp")),
        ("（3）本月监测周期内，环境最高湿度", texts.get("conclusion_humidity")),
        ("（6）本月监测周期内，各截面上下缘应变", texts.get("conclusion_strain")),
        ("（4）本月监测周期内，实测主梁挠度值", texts.get("conclusion_deflection")),
        ("（5）本月监测周期内，主墩倾角纵桥向X最大", texts.get("conclusion_tilt")),
        ("（8）本月监测周期内，顶板裂缝宽度变化量", texts.get("conclusion_crack")),
        ("综上所述，G104线管柄大桥", texts.get("summary")),
    ]
    if texts.get("accel"):
        replacements.append(("由以上各图可知，本月监测周期内，主梁竖向加速度", texts["accel"]))
    if texts.get("conclusion_accel"):
        replacements.append(("（7）本月监测周期内，主梁竖向加速度", texts["conclusion_accel"]))

    for prefix, text in replacements:
        if text and replace_first_by_prefix(doc, prefix, text):
            updated.append(prefix)
    return updated


def apply_image_updates(doc: Document, result_root: Path, asset_dir: Path) -> tuple[list[dict], list[str]]:
    accel_combined = {
        point_id: build_accel_combined_image(result_root, asset_dir, point_id)
        for point_id in [
            "GB-VIB-G04-001-01",
            "GB-VIB-G05-002-01",
            "GB-VIB-G06-002-01",
            "GB-VIB-G07-001-01",
        ]
    }
    specs = [
        ("图 5 桥面环境温度测点时程图", find_latest_image(result_root, "时程曲线_温度", "GB-RTS-G05-001-03"), 1, 145.0),
        ("(a)GB-RTS-G05-001-01", find_latest_image(result_root, "时程曲线_温度", "GB-RTS-G05-001-01"), 1, 145.0),
        ("(b)GB-RTS-G05-001-02", find_latest_image(result_root, "时程曲线_温度", "GB-RTS-G05-001-02"), 1, 145.0),
        ("图 7 桥面环境湿度测点时程图", find_latest_image(result_root, "时程曲线_湿度", "GB-RHS-G05-001-03"), 1, 145.0),
        ("图 8 桥面环境湿度累积持续时间频次分布图", find_latest_image(result_root, "频次分布_湿度", "GB-RHS-G05-001-03_freq"), 1, 145.0),
        ("(a)GB-RHS-G05-001-01", find_latest_image(result_root, "时程曲线_湿度", "GB-RHS-G05-001-01"), 1, 145.0),
        ("(b)GB-RHS-G05-001-02", find_latest_image(result_root, "时程曲线_湿度", "GB-RHS-G05-001-02"), 1, 145.0),
        ("(a)GB-RHS-G05-001-01", find_latest_image(result_root, "频次分布_湿度", "GB-RHS-G05-001-01_freq"), 2, 145.0),
        ("(b)GB-RHS-G05-001-02", find_latest_image(result_root, "频次分布_湿度", "GB-RHS-G05-001-02_freq"), 2, 145.0),
        ("第2跨1/4跨", find_latest_image(result_root, "时程曲线_挠度", "Defl_G1_Orig"), 1, 145.0),
        ("第2跨1/2跨", find_latest_image(result_root, "时程曲线_挠度", "Defl_G2_Orig"), 1, 145.0),
        ("第2跨3/4跨", find_latest_image(result_root, "时程曲线_挠度", "Defl_G3_Orig"), 1, 145.0),
        ("第3跨1/4跨", find_latest_image(result_root, "时程曲线_挠度", "Defl_G4_Orig"), 1, 145.0),
        ("第3跨1/2跨", find_latest_image(result_root, "时程曲线_挠度", "Defl_G5_Orig"), 1, 145.0),
        ("第3跨3/4跨", find_latest_image(result_root, "时程曲线_挠度", "Defl_G6_Orig"), 1, 145.0),
        ("图 13 第2跨主梁位移变化趋势", find_latest_image(result_root, "时程曲线_挠度", "Defl_G2_Filt"), 1, 145.0),
        ("图 14 第3跨主梁位移变化趋势", find_latest_image(result_root, "时程曲线_挠度", "Defl_G5_Filt"), 1, 145.0),
        ("（a）纵桥向X", find_latest_image(result_root, "时程曲线_倾角", "Tilt_X"), 1, 145.0),
        ("（b）横桥向Y", find_latest_image(result_root, "时程曲线_倾角", "Tilt_Y"), 1, 145.0),
        ("（a）第2跨", find_latest_image(result_root, "动应变箱线图_高通滤波", "boxplot_G05"), 1, 145.0),
        ("（b）第3跨", find_latest_image(result_root, "动应变箱线图_高通滤波", "boxplot_G06"), 1, 145.0),
        ("（a）第2跨", find_latest_image(result_root, "时程曲线_动应变_低通滤波", "dynstrain_lp_G05"), 2, 145.0),
        ("（b）第3跨", find_latest_image(result_root, "时程曲线_动应变_低通滤波", "dynstrain_lp_G06"), 2, 145.0),
        ("（a）GB-VIB-G04-001-01", accel_combined["GB-VIB-G04-001-01"], 1, 145.0),
        ("（b）GB-VIB-G05-002-01", accel_combined["GB-VIB-G05-002-01"], 1, 145.0),
        ("（c）GB-VIB-G06-002-01", accel_combined["GB-VIB-G06-002-01"], 1, 145.0),
        ("（d）GB-VIB-G07-001-01", accel_combined["GB-VIB-G07-001-01"], 1, 145.0),
        ("（a）GB-VIB-G05-002-01", find_latest_image(result_root, "频谱峰值曲线_加速度", "SpecFreq_GB-VIB-G05-002-01"), 1, 145.0),
        ("（b）GB-VIB-G06-002-01", find_latest_image(result_root, "频谱峰值曲线_加速度", "SpecFreq_GB-VIB-G06-002-01"), 1, 145.0),
        ("(a)第2跨", find_latest_image(result_root, "时程曲线_裂缝宽度", "裂缝宽度_G05"), 1, 145.0),
        ("(b)第3跨", find_latest_image(result_root, "时程曲线_裂缝宽度", "裂缝宽度_G06"), 1, 145.0),
    ]
    replaced: list[dict] = []
    missing: list[str] = []
    for anchor, image_path, occurrence, width in specs:
        ok, info = replace_picture_before_anchor(doc, anchor, image_path, occurrence=occurrence, width_mm=width)
        if ok:
            replaced.append({"anchor": anchor, "occurrence": occurrence, "image": info})
        else:
            missing.append(info)
    return replaced, missing


def count_doc_images(docx_path: Path) -> int:
    import zipfile

    with zipfile.ZipFile(docx_path) as zf:
        return len([name for name in zf.namelist() if name.startswith("word/media/")])


def build_report(
    template: Path = DEFAULT_TEMPLATE,
    source_template: Path = DEFAULT_SOURCE_TEMPLATE,
    config_path: Path | None = None,
    result_root: Path = DEFAULT_RESULT_ROOT,
    output_dir: Path | None = None,
    period_label: str = "2026年03月",
    monitoring_range: str = "2026年02月26日~2026年03月25日",
    report_date: str | None = None,
    start_date: str = "2026-02-26",
    end_date: str = "2026-03-25",
    refresh_template: bool = False,
    skip_image_replace: bool = False,
) -> tuple[Path, Path]:
    del config_path, start_date, end_date  # Reserved for GUI/CLI compatibility and future config-driven generation.
    report_date = report_date or datetime.now().strftime("%Y年%m月%d日")
    template = ensure_template(source_template, template, refresh=refresh_template)
    if output_dir is None:
        output_dir = result_root / "自动报告"
    output_dir.mkdir(parents=True, exist_ok=True)

    doc = Document(str(template))
    image_count_before = count_doc_images(template)
    stats_texts = build_stats_texts(result_root, period_label)
    updated_paragraphs = apply_text_updates(doc, stats_texts, monitoring_range, report_date)
    replaced_images: list[dict] = []
    missing_images: list[str] = []
    if not skip_image_replace:
        replaced_images, missing_images = apply_image_updates(doc, result_root, output_dir / "_assets")

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_path = output_dir / f"G104线管柄大桥监测月报_{period_label}_自动生成_{timestamp}.docx"
    doc.save(str(output_path))

    manifest = {
        "generated_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "template": str(template),
        "source_template": str(source_template),
        "result_root": str(result_root),
        "output": str(output_path),
        "period_label": period_label,
        "monitoring_range": monitoring_range,
        "report_date": report_date,
        "updated_paragraph_count": len(updated_paragraphs),
        "updated_paragraphs": updated_paragraphs,
        "replaced_image_count": len(replaced_images),
        "replaced_images": replaced_images,
        "missing_images": missing_images,
        "image_count_before": image_count_before,
        "image_count_after": count_doc_images(output_path),
        "notes": [
            "如果当前结果目录缺少挠度、倾角、加速度时程图或对应统计，自动报告会保留模板原图/原文字。",
            "本次低通应变插图使用时程曲线_动应变_低通滤波，而不是原始应变组图。",
        ],
    }
    manifest_path = output_dir / f"G104线管柄大桥监测月报_manifest_{timestamp}.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    return output_path, manifest_path


def main() -> None:
    args = parse_args()
    output_path, manifest_path = build_report(
        template=args.template,
        source_template=args.source_template,
        config_path=args.config,
        result_root=args.result_root,
        output_dir=args.output_dir,
        period_label=args.period_label,
        monitoring_range=args.monitoring_range,
        report_date=args.report_date,
        start_date=args.start_date,
        end_date=args.end_date,
        refresh_template=args.refresh_template,
        skip_image_replace=args.skip_image_replace,
    )
    print(f"Report written: {output_path}")
    print(f"Manifest written: {manifest_path}")


if __name__ == "__main__":
    main()
