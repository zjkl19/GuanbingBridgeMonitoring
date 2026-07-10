from __future__ import annotations

import json
from io import BytesIO
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image


def png_bytes(color: str, size: tuple[int, int] = (20, 10)) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


def write_png(path: Path, color: str, size: tuple[int, int] = (20, 10)) -> Path:
    Image.new("RGB", size, color).save(path, format="PNG")
    return path


def write_plot_provenance(
    candidate_path: Path,
    *,
    sampling_mode: str = "full",
    reduction_applied: bool = False,
    finite_count: int = 10,
    plotted_finite_count: int = 10,
    series: object | None = None,
    file_stub: str | None = None,
) -> Path:
    if series is None:
        series = {
            "sampling_mode": sampling_mode,
            "reduction_applied": reduction_applied,
            "finite_count": finite_count,
            "plotted_finite_count": plotted_finite_count,
        }
    provenance_path = candidate_path.with_suffix(".plot.json")
    provenance_path.write_text(
        json.dumps(
            {
                "schema_version": 1,
                "file_stub": file_stub if file_stub is not None else candidate_path.stem,
                "series": series,
            }
        ),
        encoding="utf-8",
    )
    return provenance_path


def write_analysis_manifest(
    path: Path,
    artifact_groups: list[list[Path]],
    *,
    status: str = "ok",
) -> Path:
    module_results = []
    for index, group in enumerate(artifact_groups, start=1):
        artifacts = []
        for artifact_path in group:
            is_provenance = artifact_path.name.endswith(".plot.json")
            artifacts.append(
                {
                    "kind": "plot_provenance" if is_provenance else "figure",
                    "role": "plot_provenance" if is_provenance else "time_history",
                    "path": str(artifact_path.resolve()),
                }
            )
        module_results.append(
            {
                "key": f"module_{index}",
                "status": "ok",
                "artifacts": artifacts,
            }
        )
    path.write_text(
        json.dumps({"status": status, "module_results": module_results}),
        encoding="utf-8",
    )
    return path


def create_minimal_docx(path: Path, *, color: str = "red", shared_reference: bool = False) -> Path:
    drawing = """
      <w:p><w:r><w:drawing><wp:inline>
        <wp:extent cx="720000" cy="360000"/>
        <a:graphic><a:graphicData><a:blip r:embed="rId1"/></a:graphicData></a:graphic>
      </wp:inline></w:drawing></w:r></w:p>
    """
    drawings = drawing + (drawing if shared_reference else "")
    document_xml = f"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:document
      xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
      xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
      xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
      xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <w:body>{drawings}<w:p><w:r><w:t>unchanged text</w:t></w:r></w:p></w:body>
    </w:document>
    """
    relationships_xml = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image"
        Target="media/image1.png"/>
    </Relationships>
    """
    root_relationships = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1"
        Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"
        Target="word/document.xml"/>
    </Relationships>
    """
    content_types = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Default Extension="png" ContentType="image/png"/>
      <Override PartName="/word/document.xml"
        ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
    </Types>
    """
    with ZipFile(path, "w", compression=ZIP_DEFLATED) as zf:
        # Include an explicit directory entry to exercise strict member-order
        # preservation without treating the directory as a media file.
        zf.writestr("word/media/", b"")
        zf.writestr("[Content_Types].xml", content_types.encode("utf-8"))
        zf.writestr("_rels/.rels", root_relationships.encode("utf-8"))
        zf.writestr("word/document.xml", document_xml.encode("utf-8"))
        zf.writestr("word/_rels/document.xml.rels", relationships_xml.encode("utf-8"))
        zf.writestr("word/styles.xml", b"<styles>unchanged</styles>")
        zf.writestr("word/media/image1.png", png_bytes(color))
    return path
