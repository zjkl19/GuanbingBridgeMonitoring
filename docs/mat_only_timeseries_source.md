# MAT-only Time-series Source

Last updated: 2026-07-05

## Purpose

Large Hongtang high-frequency CSV exports can be archived after they have been
converted into MATLAB `times` / `vals` series caches. The normal processing
chain now supports using those `.mat` files as the working data source, so the
local production disk does not need to keep both CSV and MAT copies.

This is an archive/space-saving mode. The original CSV or compressed raw export
should still be retained outside the active production folder, such as cloud
storage or a backup server.

## Source Modes

The time-series loader supports these modes:

- `auto`: default. If a CSV exists, use the CSV path and its validated MAT
  cache. If the CSV has been archived and a matching MAT file exists under a
  `cache` folder, read the MAT file directly.
- `csv_cache`: legacy behavior. Only CSV files are discovered; MAT files are
  used only as CSV read-through caches.
- `prefer_mat`: use MAT first when a matching cache exists, otherwise fall back
  to CSV.
- `mat_only`: only discover MAT files. Missing CSV files are normal in this
  mode.

Hongtang uses `auto` in `config/hongtang_config.json`.

## Validation Rules

MAT files must contain both variables:

- `times`
- `vals`

New caches also write `*.meta.json` beside the MAT file with the cache version
and source-file metadata. Hongtang Q1 already contains older MAT caches that do
not have this metadata, so Hongtang currently sets
`data_adapter.time_series.require_metadata=false`. Those legacy caches are
still structurally validated by loading `times` and `vals`, and point matching
uses filename boundaries so names like `A1` do not match `A10`.

For new data periods, keep the metadata files when archiving CSV.

## Safe CSV Archive Procedure

1. Confirm the raw CSV ZIP/RAR packages are backed up outside the active data
   folder.
2. Run the target period once with CSV present to generate MAT caches.
3. Run a MAT-only smoke test by temporarily moving or hiding a small CSV subset,
   not by deleting production data first.
4. Confirm `load_timeseries_range` and the relevant downstream service read the
   MAT file path from `cache\*.mat`.
5. Only after the smoke test passes, archive or remove the active CSV copy.

Do not clean `cache\*.mat` for a period that has already switched to MAT-only
operation. Those files are the active working data source.

## Verified Checks

Local checks on 2026-07-05:

- Unit coverage for automatic MAT fallback after CSV archival.
- Unit coverage for `mat_only` not falling back to CSV.
- Unit coverage for rejecting metadata-less MAT when strict metadata is
  required.
- Unit coverage for point-name boundary matching.
- Hongtang Q1 real-data smoke:
  `E:\洪塘大桥数据\2026年1-3月\2026-01-01\波形\cache\CS1_148.mat`
  was read by `load_timeseries_range` and by
  `bms.analyzer.DynamicSeriesService.collectRecord`.
