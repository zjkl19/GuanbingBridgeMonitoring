from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True)
class PlotProvenanceRow:
    module_key: str
    path: Path
    status: str
    series_count: int
    source_count: int
    plotted_count: int
    incomplete_days: tuple[str, ...]
    message: str = ""

    @property
    def closed(self) -> bool:
        return self.status in {"closed", "closed_incomplete_source"}


@dataclass(frozen=True)
class PlotProvenanceSummary:
    rows: tuple[PlotProvenanceRow, ...]

    @property
    def closed_count(self) -> int:
        return sum(row.closed for row in self.rows)

    @property
    def failed_count(self) -> int:
        return sum(not row.closed for row in self.rows)

    @property
    def incomplete_source_count(self) -> int:
        return sum(row.status == "closed_incomplete_source" for row in self.rows)


def _artifact_paths(raw: Any) -> Iterable[Path]:
    if isinstance(raw, str):
        yield Path(raw)
    elif isinstance(raw, dict):
        value = raw.get("path") or raw.get("file")
        if value:
            yield Path(str(value))
    elif isinstance(raw, list):
        for item in raw:
            yield from _artifact_paths(item)


def manifest_plot_provenance_paths(payload: dict[str, Any]) -> list[tuple[str, Path]]:
    found: list[tuple[str, Path]] = []
    seen: set[str] = set()
    records = payload.get("module_results") or payload.get("module_logs") or []
    if not isinstance(records, list):
        records = []
    for record in records:
        if not isinstance(record, dict):
            continue
        module = str(record.get("key") or record.get("module") or "")
        for path in _artifact_paths(record.get("artifacts")):
            normalized = str(path.expanduser().resolve(strict=False)).casefold()
            if path.name.lower().endswith(".plot.json") and normalized not in seen:
                found.append((module, path.expanduser().resolve(strict=False)))
                seen.add(normalized)
    for path in _artifact_paths(payload.get("artifacts")):
        normalized = str(path.expanduser().resolve(strict=False)).casefold()
        if path.name.lower().endswith(".plot.json") and normalized not in seen:
            found.append(("", path.expanduser().resolve(strict=False)))
            seen.add(normalized)
    return found


def _nonnegative(value: Any) -> float:
    number = float(value)
    if not math.isfinite(number) or number < 0:
        raise ValueError("count must be a finite non-negative number")
    return number


def inspect_plot_provenance(module_key: str, path: Path) -> PlotProvenanceRow:
    try:
        if not path.is_file():
            raise FileNotFoundError(f"provenance file does not exist: {path}")
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        if not isinstance(payload, dict):
            raise ValueError("root must be an object")
        raw_series = payload.get("series")
        series = [raw_series] if isinstance(raw_series, dict) else raw_series
        if not isinstance(series, list) or not series or not all(isinstance(item, dict) for item in series):
            raise ValueError("series must contain at least one object")
        source_total = 0.0
        plotted_total = 0.0
        incomplete_days: list[str] = []
        has_source = True
        for index, item in enumerate(series, start=1):
            if str(item.get("sampling_mode") or "").lower() != "full":
                raise ValueError(f"series {index} is not full sampling")
            if item.get("reduction_applied") is not False:
                raise ValueError(f"series {index} reports reduction_applied != false")
            finite = _nonnegative(item.get("finite_count"))
            plotted = _nonnegative(item.get("plotted_finite_count"))
            if finite != plotted:
                raise ValueError(f"series {index} finite/plotted counts differ")
            plotted_total += plotted
            source = item.get("source")
            if not isinstance(source, dict):
                has_source = False
                source_total += _nonnegative(item.get("input_count", finite))
                continue
            input_count = _nonnegative(item.get("input_count"))
            source_count = _nonnegative(source.get("source_sample_count"))
            finite_source = _nonnegative(source.get("finite_source_sample_count"))
            if source_count != input_count or finite_source != finite:
                raise ValueError(f"series {index} source/input/finite counts do not close")
            if str(source.get("completeness_scope") or "") != "required_export_contribution":
                raise ValueError(f"series {index} has unsupported source completeness scope")
            if not isinstance(source.get("internal_gap_coverage_assessed"), bool):
                raise ValueError(f"series {index} lacks internal-gap coverage assessment")
            requested = int(_nonnegative(source.get("calendar_day_count_requested")))
            complete = int(_nonnegative(source.get("complete_day_count")))
            incomplete = int(_nonnegative(source.get("incomplete_day_count")))
            days = source.get("incomplete_days")
            if requested != complete + incomplete:
                raise ValueError(f"series {index} source day counts do not close")
            if not isinstance(days, list) or len(days) != incomplete:
                raise ValueError(f"series {index} incomplete day list does not close")
            missing_sources = source.get("missing_required_sources")
            if not isinstance(missing_sources, list) or not all(
                isinstance(value, str) and value.strip() for value in missing_sources
            ):
                raise ValueError(f"series {index} missing-source disclosure is invalid")
            incomplete_days.extend(str(day) for day in days)
            source_total += source_count
        status = "failed" if not has_source else (
            "closed_incomplete_source" if incomplete_days else "closed"
        )
        message = "部分序列缺少源数据日级 provenance" if not has_source else ""
        return PlotProvenanceRow(
            module_key,
            path,
            status,
            len(series),
            int(source_total),
            int(plotted_total),
            tuple(dict.fromkeys(incomplete_days)),
            message,
        )
    except Exception as exc:  # noqa: BLE001
        return PlotProvenanceRow(module_key, path, "failed", 0, 0, 0, (), str(exc))


def inspect_manifest_plot_provenance(path: Path) -> PlotProvenanceSummary:
    payload = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(payload, dict):
        raise ValueError("analysis manifest must be a JSON object")
    rows = tuple(
        inspect_plot_provenance(module, provenance)
        for module, provenance in manifest_plot_provenance_paths(payload)
    )
    return PlotProvenanceSummary(rows)
