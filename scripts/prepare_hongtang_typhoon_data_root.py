#!/usr/bin/env python
"""Prepare a time-windowed Hongtang data root from scheduled-export ZIPs.

The source archives are opened read-only and CSV entries are decoded and
filtered one line at a time.  Output CSVs contain only data rows whose
timestamps fall in the inclusive ``[start, end]`` window.  Non-data header
lines are deliberately omitted from the prepared data root.
"""

from __future__ import annotations

import argparse
import codecs
import hashlib
import io
import json
import os
import re
import shutil
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path, PurePosixPath
from typing import Iterable
from zipfile import ZipFile, ZipInfo


CATEGORIES = ("波形", "特征值")
DEFAULT_MANIFEST_NAME = "prepare_hongtang_typhoon_data_manifest.json"
DATE_LIKE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?$")
DAY_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


@dataclass
class EntryAudit:
    entry_name: str
    output_path: str | None
    status: str
    encoding: str | None = None
    compressed_bytes: int = 0
    uncompressed_bytes: int = 0
    source_rows: int = 0
    kept_rows: int = 0
    rejected_rows: int = 0
    non_data_rows: int = 0
    invalid_timestamp_rows: int = 0
    source_first_time: str | None = None
    source_last_time: str | None = None
    kept_first_time: str | None = None
    kept_last_time: str | None = None


def parse_naive_datetime(value: str, *, label: str) -> datetime:
    """Parse an ISO-like local timestamp and reject timezone-aware values."""

    try:
        parsed = datetime.fromisoformat(value.strip())
    except ValueError as exc:
        raise ValueError(f"invalid {label} timestamp: {value!r}") from exc
    if parsed.tzinfo is not None:
        raise ValueError(f"{label} must be a timezone-naive local timestamp: {value!r}")
    return parsed


def parse_row_timestamp(line: str) -> tuple[datetime | None, bool]:
    """Return ``(timestamp, date_like)`` for one decoded CSV line.

    ``date_like`` distinguishes malformed timestamp rows from ordinary export
    metadata/header lines.  Values after the first comma are intentionally not
    parsed because a valid row may contain more than two CSV columns.
    """

    if "," not in line:
        return None, False
    timestamp_text = line.split(",", 1)[0].lstrip("\ufeff").strip()
    if not DATE_LIKE_RE.fullmatch(timestamp_text):
        return None, timestamp_text[:1].isdigit()
    try:
        return datetime.fromisoformat(timestamp_text.replace("T", " ", 1)), True
    except ValueError:
        return None, True


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(chunk_size), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def _can_decode_prefix(sample: bytes, encoding: str) -> bool:
    decoder = codecs.getincrementaldecoder(encoding)(errors="strict")
    try:
        decoder.decode(sample, final=False)
    except UnicodeDecodeError:
        return False
    return True


def detect_csv_encoding(archive: ZipFile, info: ZipInfo, sample_size: int = 64 * 1024) -> str:
    """Detect the supported source encoding without loading an entry in memory."""

    with archive.open(info, "r") as raw:
        sample = raw.read(sample_size)
    if sample.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        return "utf-16"
    if sample.startswith(codecs.BOM_UTF8):
        return "utf-8-sig"

    # Scheduled exports normally include a BOM.  This heuristic also accepts
    # BOM-less UTF-16 files while avoiding a full second in-memory decode.
    if sample:
        even_nuls = sample[0::2].count(0)
        odd_nuls = sample[1::2].count(0)
        pairs = max(1, len(sample) // 2)
        if odd_nuls / pairs > 0.25 and even_nuls / pairs < 0.05:
            return "utf-16-le"
        if even_nuls / pairs > 0.25 and odd_nuls / pairs < 0.05:
            return "utf-16-be"

    if _can_decode_prefix(sample, "utf-8-sig"):
        return "utf-8-sig"
    if _can_decode_prefix(sample, "gb18030"):
        return "gb18030"
    raise UnicodeError(f"unsupported or corrupt CSV encoding in {info.filename!r}")


def entry_basename(entry_name: str) -> str:
    """Return a safe leaf name for a ZIP member."""

    normalized = entry_name.replace("\\", "/")
    name = PurePosixPath(normalized).name
    if not name or name in {".", ".."}:
        raise ValueError(f"unsafe ZIP entry name: {entry_name!r}")
    return name


def _update_range(
    timestamp: datetime,
    first: datetime | None,
    last: datetime | None,
) -> tuple[datetime, datetime]:
    return (timestamp if first is None else min(first, timestamp), timestamp if last is None else max(last, timestamp))


def _atomic_output_path(destination: Path) -> Path:
    return destination.with_name(f".{destination.name}.tmp-{os.getpid()}-{uuid.uuid4().hex}")


def filter_csv_entry(
    archive: ZipFile,
    info: ZipInfo,
    *,
    start: datetime,
    end: datetime,
    output_path: Path,
    dry_run: bool = False,
) -> EntryAudit:
    """Stream one CSV entry, optionally writing its windowed rows atomically."""

    encoding = detect_csv_encoding(archive, info)
    audit = EntryAudit(
        entry_name=info.filename,
        output_path=str(output_path.resolve()),
        status="dry-run" if dry_run else "prepared",
        encoding=encoding,
        compressed_bytes=info.compress_size,
        uncompressed_bytes=info.file_size,
    )
    source_first: datetime | None = None
    source_last: datetime | None = None
    kept_first: datetime | None = None
    kept_last: datetime | None = None
    temp_path: Path | None = None
    output_binary = None
    writer = None
    try:
        if not dry_run:
            output_path.parent.mkdir(parents=True, exist_ok=True)
            temp_path = _atomic_output_path(output_path)
            output_binary = temp_path.open("wb")
            writer = io.TextIOWrapper(output_binary, encoding=encoding, errors="strict", newline="")
        with archive.open(info, "r") as raw:
            with io.TextIOWrapper(raw, encoding=encoding, errors="strict", newline="") as reader:
                for line in reader:
                    timestamp, date_like = parse_row_timestamp(line)
                    if timestamp is None:
                        if date_like:
                            audit.invalid_timestamp_rows += 1
                        else:
                            audit.non_data_rows += 1
                        continue
                    audit.source_rows += 1
                    source_first, source_last = _update_range(timestamp, source_first, source_last)
                    if start <= timestamp <= end:
                        audit.kept_rows += 1
                        kept_first, kept_last = _update_range(timestamp, kept_first, kept_last)
                        if writer is not None:
                            writer.write(line)
                    else:
                        audit.rejected_rows += 1
        if writer is not None:
            writer.flush()
            writer.detach()
            writer = None
            output_binary.close()
            output_binary = None
            os.replace(temp_path, output_path)
            temp_path = None
    finally:
        if writer is not None and not writer.closed:
            writer.close()
        elif output_binary is not None and not output_binary.closed:
            output_binary.close()
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)

    audit.source_first_time = source_first.isoformat(sep=" ") if source_first else None
    audit.source_last_time = source_last.isoformat(sep=" ") if source_last else None
    audit.kept_first_time = kept_first.isoformat(sep=" ") if kept_first else None
    audit.kept_last_time = kept_last.isoformat(sep=" ") if kept_last else None
    if audit.source_rows != audit.kept_rows + audit.rejected_rows:
        raise RuntimeError(f"row-count closure failed for {info.filename!r}")
    return audit


def discover_archives(source_root: Path, export_days: Iterable[str]) -> list[tuple[str, str, Path]]:
    archives: list[tuple[str, str, Path]] = []
    for day in export_days:
        if not DAY_RE.fullmatch(day):
            raise ValueError(f"invalid export day {day!r}; expected YYYY-MM-DD")
        day_dir = source_root / day
        if not day_dir.is_dir():
            raise FileNotFoundError(f"export-day directory not found: {day_dir}")
        for category in CATEGORIES:
            category_dir = day_dir / category
            candidates = sorted(path for path in category_dir.glob("*.zip") if path.is_file())
            if not candidates:
                raise FileNotFoundError(f"no ZIP archive found under {category_dir}")
            archives.extend((day, category, path) for path in candidates)
    return archives


def _planned_destinations(
    archives: list[tuple[str, str, Path]],
    output_root: Path,
) -> dict[tuple[Path, str], Path]:
    planned: dict[tuple[Path, str], Path] = {}
    destinations: dict[Path, tuple[Path, str]] = {}
    for day, category, zip_path in archives:
        with ZipFile(zip_path) as archive:
            for info in archive.infolist():
                if info.is_dir() or not info.filename.lower().endswith(".csv"):
                    continue
                destination = output_root / day / category / entry_basename(info.filename)
                key = (zip_path, info.filename)
                if destination in destinations:
                    previous_zip, previous_entry = destinations[destination]
                    raise ValueError(
                        "duplicate output CSV name: "
                        f"{previous_zip}:{previous_entry} and {zip_path}:{info.filename} -> {destination}"
                    )
                destinations[destination] = key
                planned[key] = destination
    return planned


def _copy_file_atomically(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    temp_path = _atomic_output_path(destination)
    try:
        shutil.copy2(source, temp_path)
        os.replace(temp_path, destination)
    finally:
        temp_path.unlink(missing_ok=True)


def _write_json_atomically(path: Path, payload: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = _atomic_output_path(path)
    try:
        temp_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(temp_path, path)
    finally:
        temp_path.unlink(missing_ok=True)


def prepare_data_root(
    source_root: Path,
    output_root: Path,
    export_days: Iterable[str],
    start: datetime,
    end: datetime,
    *,
    copy_condition_param: bool = False,
    dry_run: bool = False,
    overwrite: bool = False,
    manifest_path: Path | None = None,
) -> dict[str, object]:
    """Prepare and audit a windowed data root.

    A dry run reads and audits every CSV entry but performs no filesystem
    writes, including the manifest.  Normal runs protect every planned output
    and the manifest unless ``overwrite`` is explicitly enabled.
    """

    source_root = source_root.resolve()
    output_root = output_root.resolve()
    if not source_root.is_dir():
        raise FileNotFoundError(f"source root not found: {source_root}")
    if start.tzinfo is not None or end.tzinfo is not None:
        raise ValueError("start and end must be timezone-naive local timestamps")
    if start > end:
        raise ValueError(f"start must be <= end: {start.isoformat()} > {end.isoformat()}")
    days = list(dict.fromkeys(export_days))
    if not days:
        raise ValueError("at least one export day is required")

    archives = discover_archives(source_root, days)
    planned = _planned_destinations(archives, output_root)
    resolved_manifest_path = (manifest_path or output_root / DEFAULT_MANIFEST_NAME).resolve()
    condition_records: list[dict[str, object]] = []
    condition_plans: list[tuple[Path, Path, dict[str, object]]] = []
    if copy_condition_param:
        for day in days:
            for category in CATEGORIES:
                source = source_root / day / category / "condition.param"
                destination = output_root / day / category / "condition.param"
                record: dict[str, object] = {
                    "export_day": day,
                    "category": category,
                    "source_path": str(source),
                    "output_path": str(destination),
                    "status": "missing" if not source.is_file() else ("dry-run" if dry_run else "copied"),
                }
                if source.is_file():
                    record["sha256"] = sha256_file(source)
                    record["size_bytes"] = source.stat().st_size
                    condition_plans.append((source, destination, record))
                condition_records.append(record)

    planned_paths = list(planned.values()) + [destination for _, destination, _ in condition_plans]
    if resolved_manifest_path in planned_paths:
        raise ValueError(f"manifest path collides with a planned data output: {resolved_manifest_path}")
    if not dry_run:
        planned_paths.append(resolved_manifest_path)
    conflicts = sorted({path for path in planned_paths if path.exists()}, key=str)
    if conflicts and not overwrite:
        preview = "\n".join(f"  - {path}" for path in conflicts[:20])
        suffix = f"\n  ... and {len(conflicts) - 20} more" if len(conflicts) > 20 else ""
        raise FileExistsError(f"refusing to overwrite {len(conflicts)} existing output(s):\n{preview}{suffix}")

    zip_records: list[dict[str, object]] = []
    totals = {
        "zip_count": 0,
        "zip_entry_count": 0,
        "csv_entry_count": 0,
        "source_rows": 0,
        "kept_rows": 0,
        "rejected_rows": 0,
        "non_data_rows": 0,
        "invalid_timestamp_rows": 0,
    }
    for day, category, zip_path in archives:
        zip_record: dict[str, object] = {
            "export_day": day,
            "category": category,
            "source_zip": str(zip_path),
            "sha256": sha256_file(zip_path),
            "size_bytes": zip_path.stat().st_size,
            "entry_count": 0,
            "file_entry_count": 0,
            "csv_entry_count": 0,
            "entries": [],
        }
        entry_records: list[dict[str, object]] = []
        with ZipFile(zip_path) as archive:
            infos = archive.infolist()
            zip_record["entry_count"] = len(infos)
            zip_record["file_entry_count"] = sum(not info.is_dir() for info in infos)
            totals["zip_count"] += 1
            totals["zip_entry_count"] += len(infos)
            for info in infos:
                if info.is_dir():
                    entry_records.append(
                        asdict(EntryAudit(entry_name=info.filename, output_path=None, status="skipped_directory"))
                    )
                    continue
                if not info.filename.lower().endswith(".csv"):
                    entry_records.append(
                        asdict(
                            EntryAudit(
                                entry_name=info.filename,
                                output_path=None,
                                status="skipped_non_csv",
                                compressed_bytes=info.compress_size,
                                uncompressed_bytes=info.file_size,
                            )
                        )
                    )
                    continue
                destination = planned[(zip_path, info.filename)]
                audit = filter_csv_entry(
                    archive,
                    info,
                    start=start,
                    end=end,
                    output_path=destination,
                    dry_run=dry_run,
                )
                entry_records.append(asdict(audit))
                zip_record["csv_entry_count"] = int(zip_record["csv_entry_count"]) + 1
                totals["csv_entry_count"] += 1
                for key in (
                    "source_rows",
                    "kept_rows",
                    "rejected_rows",
                    "non_data_rows",
                    "invalid_timestamp_rows",
                ):
                    totals[key] += int(getattr(audit, key))
        zip_record["entries"] = entry_records
        zip_records.append(zip_record)

    if not dry_run:
        for source, destination, _ in condition_plans:
            _copy_file_atomically(source, destination)

    missing_condition_count = sum(record["status"] == "missing" for record in condition_records)
    manifest: dict[str, object] = {
        "schema_version": 1,
        "status": "dry-run" if dry_run else ("warning" if missing_condition_count else "ok"),
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "source_root": str(source_root),
        "output_root": str(output_root),
        "manifest_path": None if dry_run else str(resolved_manifest_path),
        "export_days": days,
        "window": {
            "start": start.isoformat(sep=" "),
            "end": end.isoformat(sep=" "),
            "bounds": "inclusive",
        },
        "dry_run": dry_run,
        "overwrite": overwrite,
        "copy_condition_param": copy_condition_param,
        "totals": totals,
        "condition_params": condition_records,
        "zips": zip_records,
    }
    if not dry_run:
        _write_json_atomically(resolved_manifest_path, manifest)
    return manifest


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Prepare an inclusive time-windowed Hongtang data root from scheduled-export ZIPs"
    )
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument(
        "--export-day",
        dest="export_days",
        action="append",
        required=True,
        help="scheduled-export day (YYYY-MM-DD); repeat for multiple days",
    )
    parser.add_argument("--start", required=True, help="inclusive local start timestamp")
    parser.add_argument("--end", required=True, help="inclusive local end timestamp")
    parser.add_argument("--copy-condition-param", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="audit only; do not create any file or directory")
    parser.add_argument("--overwrite", action="store_true", help="replace only the planned destination files")
    parser.add_argument("--manifest", type=Path, help=f"manifest path (default: OUTPUT_ROOT/{DEFAULT_MANIFEST_NAME})")
    return parser


def main() -> None:
    args = build_parser().parse_args()
    manifest = prepare_data_root(
        args.source_root,
        args.output_root,
        args.export_days,
        parse_naive_datetime(args.start, label="start"),
        parse_naive_datetime(args.end, label="end"),
        copy_condition_param=args.copy_condition_param,
        dry_run=args.dry_run,
        overwrite=args.overwrite,
        manifest_path=args.manifest,
    )
    print(
        json.dumps(
            {
                "status": manifest["status"],
                "output_root": manifest["output_root"],
                "manifest_path": manifest["manifest_path"],
                "window": manifest["window"],
                "totals": manifest["totals"],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
