from __future__ import annotations

import argparse
import json
import math
from copy import deepcopy
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.shared import Mm
from docx.text.paragraph import Paragraph
from openpyxl import load_workbook
from PIL import Image, ImageDraw, ImageFont, ImageOps


@dataclass
class ImageItem:
    label: str
    path: Path | None
    lookup: dict | None = None


def parse_args() -> argparse.Namespace:
    repo_root = Path(__file__).resolve().parents[1]
    templates = sorted((repo_root / "reports").glob("*.docx"))
    default_template = templates[0] if templates else None
    parser = argparse.ArgumentParser(description="Build Hongtang monthly monitoring report.")
    parser.add_argument("--template", type=Path, default=default_template)
    parser.add_argument("--config", type=Path, default=repo_root / "config" / "hongtang_config.json")
    parser.add_argument("--result-root", type=Path, default=None)
    parser.add_argument("--analysis-root", type=Path, default=repo_root)
    parser.add_argument("--image-root", type=Path, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    parser.add_argument("--period-label", default="2025年12月")
    parser.add_argument("--monitoring-range", default="2025.12.01～2025.12.31")
    parser.add_argument("--report-date", default=datetime.now().strftime("%Y年%m月%d日"))
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def load_sheet_rows(path: Path) -> list[dict]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb[wb.sheetnames[0]]
    rows = list(ws.iter_rows(values_only=True))
    wb.close()
    if not rows:
        return []
    header = [str(v) if v is not None else "" for v in rows[0]]
    out = []
    for row in rows[1:]:
        item = {}
        for k, v in zip(header, row):
            item[k] = v
        out.append(item)
    return out


def resolve_existing_file(primary_root: Path | None, fallback_root: Path | None, filename: str) -> Path:
    candidates: list[Path] = []
    if primary_root is not None:
        candidates.append(primary_root / filename)
    if fallback_root is not None:
        fallback = fallback_root / filename
        if fallback not in candidates:
            candidates.append(fallback)
    for path in candidates:
        if path.exists():
            return path
    joined = ", ".join(str(p) for p in candidates)
    raise FileNotFoundError(f"Required file not found: {filename}. Checked: {joined}")


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def should_skip_search_dir(path: Path) -> bool:
    banned_parts = {".git", ".venv", "tests", "__pycache__"}
    return any(part in banned_parts for part in path.parts)


def resolve_output_dirs(root: Path, configured_dir: str) -> list[Path]:
    configured_path = Path(configured_dir)
    candidates: list[Path] = []
    direct = (root / configured_path).resolve()
    if direct.exists() and direct.is_dir():
        candidates.append(direct)

    target_name = configured_path.name
    if root.exists():
        for found in root.rglob(target_name):
            if not found.is_dir():
                continue
            resolved = found.resolve()
            if resolved in candidates or should_skip_search_dir(resolved):
                continue
            candidates.append(resolved)

    candidates.sort(key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return candidates


def find_latest_image(root: Path, configured_dir: str, stem_prefix: str) -> tuple[Path | None, dict]:
    resolved_dirs = resolve_output_dirs(root, configured_dir)
    patterns = [f"{stem_prefix}*.jpg", f"{stem_prefix}*.png", f"{stem_prefix}*.jpeg"]
    matched: list[Path] = []
    for folder in resolved_dirs:
        for pattern in patterns:
            matched.extend(folder.glob(pattern))
    matched = sorted({p.resolve() for p in matched}, key=lambda p: p.stat().st_mtime, reverse=True)
    return (
        matched[0] if matched else None,
        {
            "image_root": str(root),
            "configured_dir": configured_dir,
            "resolved_dirs": [str(p) for p in resolved_dirs],
            "patterns": patterns,
            "matched_files": [str(p) for p in matched[:10]],
            "selected_file": str(matched[0]) if matched else None,
        },
    )


def select_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    font_candidates = [
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/msyh.ttf",
        "C:/Windows/Fonts/simhei.ttf",
        "C:/Windows/Fonts/arial.ttf",
    ]
    for cand in font_candidates:
        if Path(cand).exists():
            try:
                return ImageFont.truetype(cand, size=size)
            except OSError:
                continue
    return ImageFont.load_default()


def build_tile(label: str, image_path: Path | None, tile_size: tuple[int, int]) -> Image.Image:
    tile_w, tile_h = tile_size
    canvas = Image.new("RGB", (tile_w, tile_h), "white")
    draw = ImageDraw.Draw(canvas)
    font = select_font(28)
    label_box_h = 52

    draw.rectangle((0, 0, tile_w - 1, tile_h - 1), outline=(180, 180, 180), width=2)
    draw.text((16, 12), label, fill=(20, 20, 20), font=font)

    content_box = (16, label_box_h + 8, tile_w - 16, tile_h - 16)
    if image_path is None or not image_path.exists():
        draw.rectangle(content_box, outline=(220, 80, 80), width=2)
        missing_font = select_font(24)
        draw.text((content_box[0] + 20, content_box[1] + 20), "未找到图片", fill=(180, 0, 0), font=missing_font)
        return canvas

    img = Image.open(image_path).convert("RGB")
    target_w = content_box[2] - content_box[0]
    target_h = content_box[3] - content_box[1]
    img = ImageOps.contain(img, (target_w, target_h))
    x0 = content_box[0] + (target_w - img.width) // 2
    y0 = content_box[1] + (target_h - img.height) // 2
    canvas.paste(img, (x0, y0))
    return canvas


def compose_grid(items: list[ImageItem], out_path: Path, cols: int = 2, tile_size: tuple[int, int] = (920, 560)) -> Path:
    rows = max(1, math.ceil(len(items) / cols))
    gap = 24
    canvas_w = cols * tile_size[0] + (cols + 1) * gap
    canvas_h = rows * tile_size[1] + (rows + 1) * gap
    canvas = Image.new("RGB", (canvas_w, canvas_h), (248, 248, 248))

    for idx, item in enumerate(items):
        row = idx // cols
        col = idx % cols
        x = gap + col * (tile_size[0] + gap)
        y = gap + row * (tile_size[1] + gap)
        tile = build_tile(item.label, item.path, tile_size)
        canvas.paste(tile, (x, y))

    ensure_dir(out_path.parent)
    canvas.save(out_path, quality=92)
    return out_path


def insert_paragraph_before(paragraph: Paragraph) -> Paragraph:
    new_p = OxmlElement("w:p")
    paragraph._p.addprevious(new_p)
    return Paragraph(new_p, paragraph._parent)


def replace_paragraph_text(paragraph: Paragraph, text: str) -> None:
    if paragraph.runs:
        for run in paragraph.runs:
            run.text = ""
        paragraph.runs[0].text = text
    else:
        paragraph.add_run(text)


def find_paragraph_indices(doc: Document, text: str) -> list[int]:
    indices = []
    for idx, para in enumerate(doc.paragraphs):
        if para.text.strip() == text:
            indices.append(idx)
    return indices


def find_paragraph_indices_contains(doc: Document, fragment: str) -> list[int]:
    indices = []
    for idx, para in enumerate(doc.paragraphs):
        if fragment in para.text.strip():
            indices.append(idx)
    return indices


def find_last_paragraph(doc: Document, text: str) -> Paragraph:
    indices = find_paragraph_indices(doc, text)
    if not indices:
        raise ValueError(f'Paragraph "{text}" not found in template')
    return doc.paragraphs[indices[-1]]


def find_first_paragraph_contains(doc: Document, fragment: str) -> Paragraph:
    indices = find_paragraph_indices_contains(doc, fragment)
    if not indices:
        raise ValueError(f'Paragraph containing "{fragment}" not found in template')
    return doc.paragraphs[indices[0]]


def find_last_paragraph_contains(doc: Document, fragment: str) -> Paragraph:
    indices = find_paragraph_indices_contains(doc, fragment)
    if not indices:
        raise ValueError(f'Paragraph containing "{fragment}" not found in template')
    return doc.paragraphs[indices[-1]]


def replace_next_nonempty_paragraph(doc: Document, anchor_fragment: str, new_text: str, use_last: bool = True, skip: int = 0) -> None:
    indices = find_paragraph_indices_contains(doc, anchor_fragment)
    if not indices:
        raise ValueError(f'Anchor containing "{anchor_fragment}" not found in template')
    anchor_idx = indices[-1] if use_last else indices[0]
    seen = 0
    for idx in range(anchor_idx + 1, len(doc.paragraphs)):
        txt = doc.paragraphs[idx].text.strip()
        if txt:
            if seen < skip:
                seen += 1
                continue
            replace_paragraph_text(doc.paragraphs[idx], new_text)
            return
    raise ValueError(f'No non-empty paragraph found after anchor "{anchor_fragment}"')


def replace_next_nonempty_after_exact(doc: Document, anchor_text: str, new_text: str, use_last: bool = True, skip: int = 0) -> None:
    indices = find_paragraph_indices(doc, anchor_text)
    if not indices:
        raise ValueError(f'Anchor "{anchor_text}" not found in template')
    anchor_idx = indices[-1] if use_last else indices[0]
    seen = 0
    for idx in range(anchor_idx + 1, len(doc.paragraphs)):
        txt = doc.paragraphs[idx].text.strip()
        if txt:
            if seen < skip:
                seen += 1
                continue
            replace_paragraph_text(doc.paragraphs[idx], new_text)
            return
    raise ValueError(f'No non-empty paragraph found after anchor "{anchor_text}"')


def insert_picture_before_caption(doc: Document, caption_text: str, image_path: Path, width_mm: float = 165.0) -> None:
    caption = find_last_paragraph(doc, caption_text)
    pic_para = insert_paragraph_before(caption)
    pic_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = pic_para.add_run()
    run.add_picture(str(image_path), width=Mm(width_mm))


def insert_picture_before_caption_contains(doc: Document, caption_fragment: str, image_path: Path, width_mm: float = 165.0) -> None:
    caption = find_last_paragraph_contains(doc, caption_fragment)
    pic_para = insert_paragraph_before(caption)
    pic_para.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = pic_para.add_run()
    run.add_picture(str(image_path), width=Mm(width_mm))


def replace_last_paragraph(doc: Document, exact_text: str, new_text: str) -> None:
    para = find_last_paragraph(doc, exact_text)
    replace_paragraph_text(para, new_text)


def replace_first_paragraph(doc: Document, exact_text: str, new_text: str) -> None:
    indices = find_paragraph_indices(doc, exact_text)
    if not indices:
        raise ValueError(f'Paragraph "{exact_text}" not found in template')
    replace_paragraph_text(doc.paragraphs[indices[0]], new_text)


def replace_first_paragraph_contains(doc: Document, fragment: str, new_text: str) -> None:
    para = find_first_paragraph_contains(doc, fragment)
    replace_paragraph_text(para, new_text)


def replace_last_paragraph_contains(doc: Document, fragment: str, new_text: str) -> None:
    para = find_last_paragraph_contains(doc, fragment)
    replace_paragraph_text(para, new_text)


def update_common_metadata(doc: Document, period_label: str, monitoring_range: str, report_date: str) -> None:
    old_period_prefix = "（监测时间："
    for para in doc.paragraphs:
        txt = para.text.strip()
        if txt.startswith(old_period_prefix) and txt.endswith("）"):
            replace_paragraph_text(para, f"（监测时间：{period_label}）")
        elif txt.startswith("报告日期："):
            replace_paragraph_text(para, f"报告日期：{report_date}")

    for table in doc.tables:
        for row in table.rows:
            for cell in row.cells:
                txt = cell.text.strip()
                if txt == "2025.12.01～2025.12.31":
                    cell.text = monitoring_range
                elif txt.startswith("报告日期："):
                    cell.text = f"报告日期：{report_date}"


def parse_alarm_bounds(cfg: dict, module: str, point_id: str) -> dict | None:
    per_point = cfg.get("per_point", {}).get(module, {})
    safe_id = point_id.replace("-", "_")
    point_cfg = per_point.get(safe_id, {})
    bounds = point_cfg.get("alarm_bounds")
    return bounds if isinstance(bounds, dict) else None


def max_alarm_level(records: Iterable[dict], cfg: dict, module: str, min_key: str, max_key: str) -> int:
    level = 0
    for record in records:
        pid = record.get("PointID")
        if not pid:
            continue
        bounds = parse_alarm_bounds(cfg, module, str(pid))
        if not bounds:
            continue
        min_val = record.get(min_key)
        max_val = record.get(max_key)
        if min_val is None or max_val is None:
            continue
        level2 = bounds.get("level2") or []
        level3 = bounds.get("level3") or []
        if len(level3) == 2 and (min_val < min(level3) or max_val > max(level3)):
            level = max(level, 3)
        elif len(level2) == 2 and (min_val < min(level2) or max_val > max(level2)):
            level = max(level, 2)
    return level


def alarm_status_text(level: int) -> str:
    if level >= 3:
        return "个别测点超过三级预警阈值，建议立即复核监测数据并结合现场情况进一步核查。"
    if level == 2:
        return "个别测点超过二级预警阈值，建议加强跟踪监测并复核数据。"
    return "均处于超限阈值范围之内，未出现超过各级超限阈值和报警的情况。"


def format_range(min_val: float | int | None, max_val: float | int | None, decimals: int = 1, unit: str = "") -> str:
    if min_val is None or max_val is None:
        return "--"
    return f"{min_val:.{decimals}f}{unit}~{max_val:.{decimals}f}{unit}"


def build_strain_section(cfg: dict, stats_root: Path, fallback_stats_root: Path | None, image_root: Path, assets_dir: Path) -> dict:
    rows = load_sheet_rows(resolve_existing_file(stats_root, fallback_stats_root, "strain_stats.xlsx"))
    girder_rows = [r for r in rows if str(r.get("PointID", "")).startswith(("SB-", "SC-", "SD-", "SE-", "SF-", "SG-", "SH-"))]
    tower_rows = [r for r in rows if str(r.get("PointID", "")).startswith(("SK-", "SL-"))]

    strain_style = cfg["plot_styles"]["strain"]
    girder_groups = ["B", "C", "D", "E", "F", "G", "H"]
    tower_groups = ["K", "L"]
    girder_imgs = []
    for group in girder_groups:
        img_path, lookup = find_latest_image(image_root, strain_style["boxplot_output_dir"], f"StrainBox_{group}_")
        girder_imgs.append(ImageItem(group, img_path, lookup))
    tower_imgs = []
    for group in tower_groups:
        img_path, lookup = find_latest_image(image_root, strain_style["boxplot_output_dir"], f"StrainBox_{group}_")
        tower_imgs.append(ImageItem(group, img_path, lookup))

    girder_asset = compose_grid(girder_imgs, assets_dir / "strain_girder_boxplot.jpg", cols=2)
    tower_asset = compose_grid(tower_imgs, assets_dir / "strain_tower_boxplot.jpg", cols=2)

    girder_min = min((r["Min"] for r in girder_rows if r.get("Min") is not None), default=None)
    girder_max = max((r["Max"] for r in girder_rows if r.get("Max") is not None), default=None)
    tower_min = min((r["Min"] for r in tower_rows if r.get("Min") is not None), default=None)
    tower_max = max((r["Max"] for r in tower_rows if r.get("Max") is not None), default=None)

    girder_level = max_alarm_level(girder_rows, cfg, "strain", "Min", "Max")
    tower_level = max_alarm_level(tower_rows, cfg, "strain", "Min", "Max")

    return {
        "chapter_girder": f"监测结果表明，各测点应变值在{format_range(girder_min, girder_max, 1, 'με')}之间，{alarm_status_text(girder_level)}",
        "chapter_tower": f"监测结果表明，各测点应变值在{format_range(tower_min, tower_max, 1, 'με')}之间，{alarm_status_text(tower_level)}",
        "girder_image": str(girder_asset),
        "tower_image": str(tower_asset),
        "girder_caption": "图 4-4 主梁各截面位置应变箱线图",
        "tower_caption": "图 4-5 桥塔各截面位置应变箱线图",
        "image_lookup": {
            "girder": [deepcopy(item.lookup) | {"label": item.label} for item in girder_imgs],
            "tower": [deepcopy(item.lookup) | {"label": item.label} for item in tower_imgs],
        },
    }


def build_tilt_section(cfg: dict, stats_root: Path, fallback_stats_root: Path | None, image_root: Path, assets_dir: Path) -> dict:
    rows = load_sheet_rows(resolve_existing_file(stats_root, fallback_stats_root, "tilt_stats.xlsx"))
    z_rows = [r for r in rows if str(r.get("PointID", "")).endswith("-Z")]
    h_rows = [r for r in rows if str(r.get("PointID", "")).endswith("-H")]
    style = cfg["plot_styles"]["tilt"]
    items = []
    for pid in ["Q1-Z", "Q1-H", "Q2-Z", "Q2-H"]:
        img_path, lookup = find_latest_image(image_root, style["output_dir"], f"Tilt_{pid}_")
        items.append(ImageItem(pid, img_path, lookup))
    asset = compose_grid(items, assets_dir / "tilt_timeseries.jpg", cols=2)

    z_min = min((r["Min"] for r in z_rows if r.get("Min") is not None), default=None)
    z_max = max((r["Max"] for r in z_rows if r.get("Max") is not None), default=None)
    h_min = min((r["Min"] for r in h_rows if r.get("Min") is not None), default=None)
    h_max = max((r["Max"] for r in h_rows if r.get("Max") is not None), default=None)
    level = max(max_alarm_level(z_rows, cfg, "tilt", "Min", "Max"), max_alarm_level(h_rows, cfg, "tilt", "Min", "Max"))
    summary = (
        f"监测结果表明，倾角纵桥向位移在{format_range(z_min, z_max, 3, '°')}之间，"
        f"横桥向位移在{format_range(h_min, h_max, 3, '°')}之间，{alarm_status_text(level)}"
    )
    return {
        "chapter": summary,
        "image": str(asset),
        "caption": "图 4-6 桥塔各截面位置倾角时程曲线图",
        "image_lookup": [deepcopy(item.lookup) | {"label": item.label} for item in items],
    }


def build_bearing_section(cfg: dict, stats_root: Path, fallback_stats_root: Path | None, image_root: Path, assets_dir: Path) -> dict:
    rows = load_sheet_rows(resolve_existing_file(stats_root, fallback_stats_root, "bearing_displacement_stats.xlsx"))
    configured_points = cfg.get("points", {}).get("bearing_displacement", [])
    configured_order = {str(pid): idx for idx, pid in enumerate(configured_points)}
    if configured_order:
        rows = [r for r in rows if str(r.get("PointID", "")) in configured_order]
        rows.sort(key=lambda r: configured_order.get(str(r.get("PointID", "")), 10**9))

    valid_rows = [r for r in rows if r.get("FiltMin_mm") is not None and r.get("FiltMax_mm") is not None]
    style = cfg["plot_styles"]["bearing_displacement"]
    items = []
    for record in valid_rows:
        pid = str(record["PointID"])
        img_path, lookup = find_latest_image(image_root, style["output_dir"], f"BearingDisp_{pid}_")
        items.append(ImageItem(pid, img_path, lookup))
    if not items:
        items = [ImageItem("支座位移", None, {
            "image_root": str(image_root),
            "configured_dir": style["output_dir"],
            "resolved_dirs": [],
            "patterns": [],
            "matched_files": [],
            "selected_file": None,
        })]
    asset = compose_grid(items, assets_dir / "bearing_timeseries.jpg", cols=2)

    min_val = min((r["FiltMin_mm"] for r in valid_rows), default=None)
    max_val = max((r["FiltMax_mm"] for r in valid_rows), default=None)
    level = max_alarm_level(valid_rows, cfg, "bearing_displacement", "FiltMin_mm", "FiltMax_mm")
    summary = (
        f"选取典型监测数据进行分析。监测结果表明，各测点支座位移在"
        f"{format_range(min_val, max_val, 1, 'mm')}之间，{alarm_status_text(level)}"
    )
    return {
        "chapter": summary,
        "image": str(asset),
        "caption": "图 4-7 典型测点支座变位时程曲线图",
        "image_lookup": [deepcopy(item.lookup) | {"label": item.label} for item in items],
    }


def build_manifest(cfg: dict, stats_root: Path, fallback_stats_root: Path | None, image_root: Path, template: Path, assets_dir: Path, period_label: str, monitoring_range: str, report_date: str) -> dict:
    return {
        "template": str(template),
        "analysis_root": str(stats_root),
        "fallback_analysis_root": str(fallback_stats_root) if fallback_stats_root is not None else None,
        "image_root": str(image_root),
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "period_label": period_label,
        "monitoring_range": monitoring_range,
        "report_date": report_date,
        "sections": {
            "strain": build_strain_section(cfg, stats_root, fallback_stats_root, image_root, assets_dir),
            "tilt": build_tilt_section(cfg, stats_root, fallback_stats_root, image_root, assets_dir),
            "bearing_displacement": build_bearing_section(cfg, stats_root, fallback_stats_root, image_root, assets_dir),
        },
    }


def apply_manifest_to_doc(doc: Document, manifest: dict) -> None:
    update_common_metadata(doc, manifest["period_label"], manifest["monitoring_range"], manifest["report_date"])

    strain = manifest["sections"]["strain"]
    replace_next_nonempty_after_exact(doc, "主梁应变", strain["chapter_girder"], use_last=True, skip=1)
    replace_next_nonempty_after_exact(doc, "桥塔应变", strain["chapter_tower"], use_last=True, skip=1)
    replace_last_paragraph_contains(doc, "图 4-4 主梁各截面位置应变时程曲线图", strain["girder_caption"])
    replace_last_paragraph_contains(doc, "图 4-5 桥塔各截面位置应变时程曲线图", strain["tower_caption"])
    insert_picture_before_caption_contains(doc, strain["girder_caption"], Path(strain["girder_image"]))
    insert_picture_before_caption_contains(doc, strain["tower_caption"], Path(strain["tower_image"]))

    tilt = manifest["sections"]["tilt"]
    replace_last_paragraph_contains(doc, "主塔倾角偏移的方向以闽侯上街-农林大学为纵桥向", "主塔倾角偏移的方向以闽侯上街-农林大学为纵桥向，上游-下游为横桥向。其中朝农林大学方向为正、闽侯上街方向为负，朝上游方向为正、朝下游方向为负。各测点的倾斜幅值如下图所示。" + tilt["chapter"])
    insert_picture_before_caption_contains(doc, tilt["caption"], Path(tilt["image"]))

    bearing = manifest["sections"]["bearing_displacement"]
    replace_last_paragraph_contains(doc, "支座变位的方向以闽侯上街-农林大学为纵桥向", "支座变位的方向以闽侯上街-农林大学为纵桥向，上游-下游为横桥向。其中朝农林大学方向为正、闽侯上街方向为负，朝上游方向为正、朝下游方向为负。各测点的支座位移时程如下图所示。" + bearing["chapter"])
    insert_picture_before_caption_contains(doc, bearing["caption"], Path(bearing["image"]))


def summarize_missing_images(manifest: dict) -> list[str]:
    missing: list[str] = []
    for section_name, section in manifest.get("sections", {}).items():
        lookup = section.get("image_lookup", {})
        if isinstance(lookup, dict):
            groups = lookup.values()
        else:
            groups = [lookup]
        for group in groups:
            if not isinstance(group, list):
                continue
            for item in group:
                if not isinstance(item, dict):
                    continue
                if item.get("selected_file"):
                    continue
                missing.append(f"{section_name}:{item.get('label', '<unknown>')}")
    return missing


def main() -> None:
    args = parse_args()
    if args.template is None or not args.template.exists():
        raise SystemExit("Template docx not found.")
    if not args.config.exists():
        raise SystemExit("Config file not found.")

    result_root = args.result_root
    stats_root = result_root if result_root is not None else args.analysis_root
    fallback_stats_root = args.analysis_root if result_root is not None else None
    image_root = args.image_root if args.image_root is not None else (result_root if result_root is not None else args.analysis_root)
    output_dir = args.output_dir if args.output_dir is not None else ((result_root / "自动报告") if result_root is not None else (Path(__file__).resolve().parents[1] / "outputs" / "reports"))
    output_dir = ensure_dir(output_dir)
    assets_dir = ensure_dir(output_dir / "generated_assets")

    cfg = load_json(args.config)
    manifest = build_manifest(cfg, stats_root, fallback_stats_root, image_root, args.template, assets_dir, args.period_label, args.monitoring_range, args.report_date)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    manifest_path = output_dir / f"report_manifest_{timestamp}.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    doc = Document(str(args.template))
    apply_manifest_to_doc(doc, manifest)

    template_stem = args.template.stem
    output_docx = output_dir / f"{template_stem}_自动生成_{timestamp}.docx"
    doc.save(str(output_docx))

    missing = summarize_missing_images(manifest)
    print(f"Manifest written to: {manifest_path}")
    print(f"Report written to:   {output_docx}")
    if missing:
        print("Missing source images:")
        for item in missing:
            print(f"  - {item}")


if __name__ == "__main__":
    main()
