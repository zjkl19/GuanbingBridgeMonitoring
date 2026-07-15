# MAT-only Time-series Source

Last updated: 2026-07-16

## Purpose

Large Hongtang high-frequency CSV exports can be archived after they have been
converted into MATLAB `times` / `vals` series caches. The normal processing
chain now supports using those `.mat` files as the working data source, so the
local production disk does not need to keep both CSV and MAT copies.

This is an archive/space-saving mode. A recoverable original source must still
be retained. For the verified daily-export cleanup workflow, the original ZIP
stays in place as a read-only recovery source; other layouts should keep the
original CSV or a compressed raw export in cloud storage or on a backup server.

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
and source-file metadata. Transactional caches carry the same `pair_id` in the
MAT and metadata, and metadata records the exact `mat_bytes`. A cache pair used
as evidence for source-CSV deletion must satisfy that identity/byte contract and
must load independently after the CSV is gone. Hongtang Q1 already contains
older MAT caches that do not have this metadata, so Hongtang currently sets
`data_adapter.time_series.require_metadata=false`. Those legacy caches are
still structurally validated by loading `times` and `vals`, and point matching
uses filename boundaries so names like `A1` do not match `A10`.

For new data periods, keep the metadata files when archiving CSV. A readable
legacy pairless cache may remain compatible for analysis, but it is not proof
that the verified deletion transaction was completed.

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

## Automated Verified Daily-Export Cleanup

The workbench has a separate, task-scoped cleanup option for archive-backed
`jlj_daily_export` data such as Jiulongjiang and Shuixianhua daily exports. It
is disabled by default and is not available for `dated_folders` or
`hongtang_period` data.

The option is intentionally stricter than the manual procedure above:

1. It must run as a dedicated preprocessing task. ZIP precheck, extraction and
   cache prebuild are allowed; analysis and CSV-mutating preprocessing steps are
   not allowed in the same task.
2. The operator must explicitly enable the task option and enter the exact
   confirmation token `DELETE_VERIFIED_EXTRACTED_CSV`.
3. When extraction and cache prebuild are selected together, one natural day is
   completed before the next starts. The parent process, not a cache worker,
   commits each day only after all eligible configured CSV files have successful
   standalone MAT/metadata pairs.
4. The daily extraction manifest and the original ZIP path/entry/size/CRC proof
   must still match. The source ZIP remains open for verification during the
   commit and is never deleted by this workflow.
5. A durable `.bms_cache_source_cleanup_receipt.json` is written in the daily
   partition. It binds the day, source paths, cache paths, cache contract,
   configuration hash and recovery proof. Do not edit or delete it manually.
6. Only configured, eligible time-series CSV files are removed. WIM, Excel,
   unconfigured CSV, non-CSV data, ZIP archives, MAT caches, metadata and cleanup
   receipts are retained.
7. If cache validation, recovery verification, rename, deletion or receipt
   publication fails, the day does not become a successful commit and the batch
   stops before later analysis. Re-run with the same data root, configuration
   and task options after inspecting the receipt; do not bypass it by deleting
   locks, temporary files or evidence.

After a successful cleanup, an ordinary GUI analysis should remain in `auto`.
The loader will use the validated MAT cache because the corresponding CSV is no
longer present. Use explicit `mat_only` only for an isolation/acceptance test.

This automated path cannot be used for already-extracted data that has no
verified original ZIP and extraction manifest. It also does not turn cache
prebuild for other bridge layouts into a general-purpose file deletion tool.

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
