from __future__ import annotations

import hashlib
import json
import shutil
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


def _renderer(name: str) -> str | None:
    candidates = {
        "soffice": (
            "soffice.com", "soffice.exe", "soffice",
            r"C:\Users\eamdf\AppData\Local\Programs\LibreOfficeCodexFixed\program\soffice.com",
            r"C:\Program Files\LibreOffice\program\soffice.com",
        ),
        "pdftoppm": ("pdftoppm.exe", "pdftoppm"),
    }[name]
    for candidate in candidates:
        found = shutil.which(candidate)
        if found:
            return found
        path = Path(candidate)
        if path.is_file():
            return str(path)
    return None


def analyze_page_image(path: Path, *, edge_margin_px: int = 3) -> dict[str, Any]:
    with Image.open(path) as source:
        gray = source.convert("L")
        width, height = gray.size
        ink = gray.point(lambda value: 255 if value < 245 else 0)
        bbox = ink.getbbox()
        histogram = gray.histogram()
        white_pixels = sum(histogram[245:])
        white_ratio = white_pixels / max(1, width * height)
        edge_touch = False
        if bbox is not None:
            left, top, right, bottom = bbox
            edge_touch = (
                left <= edge_margin_px
                or top <= edge_margin_px
                or right >= width - edge_margin_px
                or bottom >= height - edge_margin_px
            )
        return {
            "path": str(path),
            "width": width,
            "height": height,
            "white_ratio": round(white_ratio, 6),
            "ink_bbox": list(bbox) if bbox is not None else None,
            "blank": bbox is None or white_ratio >= 0.9995,
            "edge_touch": edge_touch,
        }


def create_contact_sheet(page_paths: list[Path], output: Path, *, columns: int = 4) -> Path:
    if not page_paths:
        raise ValueError("cannot create a contact sheet without page images")
    thumb_width, thumb_height, label_height, gap = 260, 360, 24, 12
    rows = (len(page_paths) + columns - 1) // columns
    sheet = Image.new(
        "RGB",
        (columns * (thumb_width + gap) + gap, rows * (thumb_height + label_height + gap) + gap),
        "#d8dde5",
    )
    draw = ImageDraw.Draw(sheet)
    for index, path in enumerate(page_paths):
        with Image.open(path) as page:
            image = page.convert("RGB")
            image.thumbnail((thumb_width, thumb_height), Image.Resampling.LANCZOS)
            x = gap + (index % columns) * (thumb_width + gap)
            y = gap + (index // columns) * (thumb_height + label_height + gap)
            frame_x = x + (thumb_width - image.width) // 2
            sheet.paste(image, (frame_x, y))
            draw.rectangle((x, y, x + thumb_width, y + thumb_height), outline="#64748b", width=1)
            draw.text((x + 6, y + thumb_height + 4), f"Page {index + 1}", fill="#111827")
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, format="PNG")
    return output


def render_docx_visual_qc(
    docx_path: Path,
    output_root: Path,
    *,
    preferred_pdf_path: Path | None = None,
) -> dict[str, Any]:
    docx = docx_path.expanduser().resolve()
    if not docx.is_file():
        raise FileNotFoundError(f"DOCX does not exist: {docx}")
    preferred_pdf = (
        preferred_pdf_path.expanduser().resolve()
        if preferred_pdf_path is not None
        else None
    )
    if preferred_pdf is not None and not preferred_pdf.is_file():
        preferred_pdf = None
    pdftoppm = _renderer("pdftoppm")
    soffice = None if preferred_pdf is not None else _renderer("soffice")
    if not pdftoppm or (preferred_pdf is None and not soffice):
        return {
            "status": "unavailable",
            "message": "No authoritative PDF/LibreOffice renderer or pdftoppm is available",
            "renderer": "unavailable",
            "pdf_authoritative": False,
            "preview_pdf_path": "",
            "soffice": soffice or "",
            "pdftoppm": pdftoppm or "",
            "page_count": 0,
            "pages": [],
        }
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    source_key = hashlib.sha256(str(docx).encode("utf-8")).hexdigest()[:10]
    output_dir = output_root.expanduser().resolve() / f"{stamp}_{source_key}"
    output_dir.mkdir(parents=True, exist_ok=True)
    renderer_kind = "authoritative_pdf" if preferred_pdf is not None else "libreoffice_preview"
    if preferred_pdf is not None:
        pdf_path = preferred_pdf
    else:
        with tempfile.TemporaryDirectory(prefix="bms_lo_") as profile_folder:
            profile_uri = Path(profile_folder).resolve().as_uri()
            convert = subprocess.run(
                [
                    soffice,
                    f"-env:UserInstallation={profile_uri}",
                    "--headless", "--convert-to", "pdf", "--outdir", str(output_dir), str(docx),
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=240,
                check=False,
            )
        pdf_path = output_dir / f"{docx.stem}.pdf"
        if not pdf_path.is_file():
            converted_pdfs = list(output_dir.glob("*.pdf"))
            if len(converted_pdfs) == 1:
                pdf_path = converted_pdfs[0]
        if convert.returncode != 0 or not pdf_path.is_file():
            return {
                "status": "failed",
                "message": f"LibreOffice conversion failed ({convert.returncode}): {convert.stderr or convert.stdout}",
                "renderer": "libreoffice_preview",
                "pdf_authoritative": False,
                "preview_pdf_path": "",
                "output_dir": str(output_dir),
                "page_count": 0,
                "pages": [],
            }
    prefix = output_dir / "page"
    raster = subprocess.run(
        [pdftoppm, "-png", "-r", "110", str(pdf_path), str(prefix)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=300,
        check=False,
    )
    page_paths = sorted(output_dir.glob("page-*.png"), key=lambda path: int(path.stem.split("-")[-1]))
    if raster.returncode != 0 or not page_paths:
        return {
            "status": "failed",
            "message": f"PDF rasterization failed ({raster.returncode}): {raster.stderr or raster.stdout}",
            "renderer": renderer_kind,
            "pdf_authoritative": preferred_pdf is not None,
            "preview_pdf_path": "" if preferred_pdf is not None else str(pdf_path),
            "output_dir": str(output_dir),
            "pdf_path": str(pdf_path),
            "page_count": 0,
            "pages": [],
        }
    pages = [analyze_page_image(path) for path in page_paths]
    blank_pages = [index + 1 for index, page in enumerate(pages) if page["blank"]]
    edge_touch_pages = [index + 1 for index, page in enumerate(pages) if page["edge_touch"]]
    contact_sheet = create_contact_sheet(page_paths, output_dir / "contact_sheet.png")
    status = "warning" if blank_pages or edge_touch_pages else "passed"
    payload = {
        "status": status,
        "message": "" if status == "passed" else "存在空白页或页面边界触碰，请人工复核联系表和单页图",
        "docx_path": str(docx),
        "renderer": renderer_kind,
        "pdf_authoritative": preferred_pdf is not None,
        "preview_pdf_path": "" if preferred_pdf is not None else str(pdf_path),
        "output_dir": str(output_dir),
        "pdf_path": str(pdf_path),
        "contact_sheet": str(contact_sheet),
        "page_count": len(pages),
        "blank_pages": blank_pages,
        "edge_touch_pages": edge_touch_pages,
        "pages": pages,
    }
    (output_dir / "visual_qc.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return payload
