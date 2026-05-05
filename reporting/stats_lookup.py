from __future__ import annotations

from pathlib import Path

from analysis_manifest import analysis_manifest_context, manifest_stats_path


STATS_FILENAME_KEYS: dict[str, str] = {
    "temp_stats.xlsx": "temperature",
    "humidity_stats.xlsx": "humidity",
    "rainfall_stats.xlsx": "rainfall",
    "gnss_stats.xlsx": "gnss",
    "deflection_stats.xlsx": "deflection",
    "bearing_displacement_stats.xlsx": "bearing_displacement",
    "tilt_stats.xlsx": "tilt",
    "crack_stats.xlsx": "crack",
    "strain_stats.xlsx": "strain",
    "accel_stats.xlsx": "acceleration",
    "cable_accel_stats.xlsx": "cable_accel",
    "accel_spec_stats.xlsx": "accel_spectrum",
    "cable_accel_spec_stats.xlsx": "cable_accel_spectrum",
    "wind_stats.xlsx": "wind",
    "eq_stats.xlsx": "earthquake",
}


def stats_key_for_filename(filename: str) -> str | None:
    return STATS_FILENAME_KEYS.get(str(filename))


def manifest_search_root(stats_root: Path | None) -> Path | None:
    if stats_root is None:
        return None
    root = Path(stats_root)
    return root.parent if root.name.lower() == "stats" else root


def resolve_from_analysis_manifest(primary_root: Path | None, fallback_root: Path | None, filename: str) -> Path | None:
    key = stats_key_for_filename(filename)
    if key is None:
        return None
    for candidate_root in (manifest_search_root(primary_root), manifest_search_root(fallback_root)):
        if candidate_root is None:
            continue
        context = analysis_manifest_context(candidate_root)
        path = manifest_stats_path(context.get("manifest"), key, filename)
        if path is not None:
            return path
    return None
