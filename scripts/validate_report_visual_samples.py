from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
from pathlib import Path
from zipfile import BadZipFile, ZipFile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "reporting"))

from report_visual_qc import render_docx_visual_qc


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def docx_package_qc(path: Path) -> dict[str, object]:
    result: dict[str, object] = {"zip_integrity": False, "document_xml": False, "media_count": 0}
    try:
        with ZipFile(path) as archive:
            names = archive.namelist()
            result.update({
                "zip_integrity": archive.testzip() is None,
                "document_xml": "word/document.xml" in names,
                "media_count": sum(name.startswith("word/media/") and not name.endswith("/") for name in names),
            })
    except (BadZipFile, OSError) as exc:
        result["error"] = str(exc)
    return result


def parse_sample(value: str) -> tuple[str, Path]:
    if "=" not in value:
        raise argparse.ArgumentTypeError("sample must use bridge_id=path")
    bridge, raw_path = value.split("=", 1)
    if not bridge.strip() or not raw_path.strip():
        raise argparse.ArgumentTypeError("sample must use non-empty bridge_id=path")
    return bridge.strip(), Path(raw_path.strip()).expanduser().resolve()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Render and compare representative workbench report samples.")
    parser.add_argument("--sample", action="append", type=parse_sample, required=True)
    parser.add_argument("--output-root", type=Path, default=ROOT / "tmp" / "docs" / "workbench_report_visual_samples")
    args = parser.parse_args(argv)
    output_root = args.output_root.expanduser().resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    records = []
    for bridge, path in args.sample:
        started = time.perf_counter()
        if not path.is_file():
            records.append({"bridge_id": bridge, "docx_path": str(path), "status": "missing"})
            continue
        visual = render_docx_visual_qc(path, output_root / bridge)
        package = docx_package_qc(path)
        status = str(visual.get("status") or "failed")
        if not package.get("zip_integrity") or not package.get("document_xml"):
            status = "failed"
        records.append({
            "bridge_id": bridge,
            "docx_path": str(path),
            "docx_bytes": path.stat().st_size,
            "docx_sha256": sha256(path),
            "status": status,
            "elapsed_sec": round(time.perf_counter() - started, 3),
            "package": package,
            "visual": visual,
        })
    payload = {
        "schema_version": 1,
        "sample_count": len(records),
        "passed_count": sum(record.get("status") == "passed" for record in records),
        "warning_count": sum(record.get("status") == "warning" for record in records),
        "failed_count": sum(record.get("status") not in {"passed", "warning"} for record in records),
        "records": records,
    }
    result_path = output_root / "sample_matrix.json"
    result_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(result_path)
    return 1 if payload["failed_count"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
