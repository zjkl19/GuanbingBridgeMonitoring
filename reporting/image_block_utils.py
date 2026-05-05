from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable
from zipfile import ZipFile

from PIL import Image, ImageOps


@dataclass(frozen=True)
class ImageStackResult:
    path: Path | None
    source_count: int
    missing_count: int


def existing_images(paths: Iterable[Path | None]) -> list[Path]:
    return [path for path in paths if path is not None and path.exists()]


def stack_images_vertical(
    paths: Iterable[Path | None],
    output_path: Path,
    *,
    gap: int = 18,
    background: str = "white",
    quality: int = 92,
) -> ImageStackResult:
    source_paths = list(paths)
    existing = existing_images(source_paths)
    if not existing:
        return ImageStackResult(None, 0, len(source_paths))

    images = [ImageOps.exif_transpose(Image.open(path).convert("RGB")) for path in existing]
    try:
        max_width = max(img.width for img in images)
        normalized: list[Image.Image] = []
        for img in images:
            if img.width != max_width:
                new_height = max(1, round(img.height * max_width / img.width))
                img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
            normalized.append(ImageOps.expand(img, border=0, fill=background))
        total_height = sum(img.height for img in normalized) + gap * (len(normalized) - 1)
        canvas = Image.new("RGB", (max_width, total_height), background)
        y = 0
        for img in normalized:
            canvas.paste(img, (0, y))
            y += img.height + gap
        output_path.parent.mkdir(parents=True, exist_ok=True)
        canvas.save(output_path, quality=quality)
        return ImageStackResult(output_path, len(existing), len(source_paths) - len(existing))
    finally:
        for img in images:
            img.close()


def count_docx_images(docx_path: Path) -> int:
    if not docx_path.exists():
        return 0
    with ZipFile(docx_path) as zf:
        return sum(1 for name in zf.namelist() if name.startswith("word/media/"))
