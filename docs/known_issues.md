# Known Issues And Follow-Up Items

Last updated: 2026-07-09

This file tracks recoverable technical risks that are too important to leave in
chat history but not always urgent enough to fix immediately.

## High-Frequency Report Plot Sampling

Status: improved in `caffd0e`; keep as a report QA rule.

The previous extrema-preserving cap fixed dropped extrema, but some monthly or
quarterly raw high-frequency time-history figures still looked visually sparse
when they used the ordinary common cap. Hongtang Q2 and Zhishan April to June
now use dedicated report-facing raw dynamic plot limits:

- `plot_common.dynamic_raw_fig_max_points=900000`
- `plot_common.dynamic_raw_min_points_per_day=10000`

This path still preserves finite min/max/absolute-peak samples. It should make
valid high-frequency data look close to the original full-resolution waveform
while keeping report rendering practical.

Important distinction:

- high-density sampling improves visual continuity where finite source data
  exists;
- `gap_mode=connect` connects finite plotted points;
- neither setting creates missing raw dates or values.

Recommended checks:

- for any report refresh that changes high-frequency figures, inspect at least
  one raw acceleration page and one raw cable-acceleration page at rendered
  page scale;
- compare report stats extrema against the plotted extrema labels;
- if a figure still has daily blank bands, check the raw dated folders and MAT
  cache coverage before changing plot code.

## Hongtang Q2 Raw High-Frequency Gaps

Status: narrowed after the 2026-07-06 late-June recovery.

The `v1.7.14` fixes removed several false missing-data causes in the Hongtang
Q2 run, including stale cache reuse, dated-folder lookup problems, gap-mode
propagation gaps, and the bad CS8 offset rule. The later Donghua export
recovery supplied 2026-06-28 to 2026-06-30, and those three days were copied
to 133, reprocessed, cached as MAT, and then smoke-tested in MAT-only mode
after deleting the direct wave CSV copies. Any remaining gaps should be checked
against the specific dated raw folders instead of treated as a known general
late-June gap.

Resolved follow-up: the 09:08 corrected report still used wind and earthquake
figures generated before canonical MAT aliases existed for the recovered
timestamp-named Donghua CSVs. Hongtang now has per-point timestamp fallback
patterns for wind speed/direction and EQ-X/Y/Z, and the corrected 10:51 report
was rendered and checked with wind/earthquake x-axes reaching 2026-06-30.

Important distinction:

- `plot_common.gap_mode=connect` connects finite plotted points.
- It does not synthesize missing raw dates or values.
- If the time series ends before 2026-06-30, first check the raw dated folders
  before changing plot code.

Reference: `docs/hongtang_q2_2026_recovery.md`.

## MAT-Only Dynamic RMS Refresh

Status: operational hazard; avoid as an acceptance path until fixed.

During the 2026-07-09 Hongtang Q2 high-frequency plot refresh, the direct-wave
CSV copies had already been removed and the run depended on the formal MAT
data-source mode. A manual `refresh_dynamic_rms_only` pass refreshed `0`
points and overwrote `accel_stats.xlsx` / `cable_accel_stats.xlsx` with
header-only files. The accepted state was restored by rerunning the main
`acceleration` and `cable_accel` analyzers, which correctly read the MAT data
and rebuilt both plots and stats.

Recommended fix:

- make `refresh_dynamic_rms_only` use the same MAT alias/source-discovery
  logic as the main dynamic analyzers;
- refuse to write stats when the refreshed point count is `0` unless an
  explicit empty-output override is supplied;
- add a regression test that simulates a MAT-only Hongtang direct-wave source.

## Per-Point Suppression Hidden In Thresholds

Status: workaround preserved; follow-up recommended.

Some old runs intentionally used an inverted threshold range such as
`min: 1000, max: -1000` to suppress all finite values for a damaged point.
That behavior is still supported for backward compatibility, but it is easy to
forget when a point later recovers. Hongtang Q2 SG-6 and SL-8 were restored to
normal transitional bounds `[-1000, 1000]` after the two points showed usable
data again. The same fix also made Hongtang low-frequency `abs_max_valid`
sensor-specific; otherwise raw strain values could be removed before
offset-correction had a chance to bring them back into range.

Recommended fix:

- add an explicit point-suppression config with start/end dates and reason;
- make reports and preflight logs list suppressed points by period;
- stop using inverted thresholds as the long-term way to mark damaged points.

## Rendered Report QA

Status: improved in `v1.7.16`; keep as an acceptance rule.

Raw DOCX QC is not enough when reports contain Word fields, table-of-contents
entries, cross-references or page-count headers. On 133, Python COM may be
missing even though Word COM is available. The period-report builder now falls
back to PowerShell Word COM, repaginates the document, updates header/footer
shape fields, and patches stale hard-coded total-page text in header/footer XML
when Word reports the final page count. Final acceptance should still include
render/export QA when a production report is generated.

Additional v1.7.19 lesson: converting static figure/table captions to Word
auto-number fields must preserve any `bookmarkStart` / `bookmarkEnd` elements
around the caption number. Otherwise existing template cross-references can
update to `错误！未定义书签` even though raw DOCX XML looked clean before Word
field refresh. The Hongtang Q2 bridge-tower strain paragraph exposed this with
missing `_Ref4508` / `_Ref4616` bookmarks; the accepted fix keeps bookmark starts
before the generated caption number and puts bookmark ends after the number but
before the title text.

Recommended check:

- export or render the DOCX to PDF/pages;
- search rendered text for `错误`, `引用源未找到`, stale quarter/month text, and
  old total-page headers;
- spot-check representative plotted pages before sending the report out.

Additional v1.7.21 lesson: when a report sentence or table cites a max/min/peak,
the rendered figure must be checked against the same source sample. The
Hongtang Q2 earthquake section exposed this because full-resolution earthquake
stats were correct, but the old plot marker used the largest positive plotted
sample and downsampling could drop the true absolute peak. The common plotting
helpers now preserve extrema, but report QA should still compare stats rows,
figure markers, and rendered text for representative modules. See
`docs/hongtang_q2_extrema_plot_audit.md`.

Additional Zhishan Q2 lesson: dense high-frequency monthly time histories can
look visually broken when reduced by uniform index sampling, even if `gap_mode`
is `connect` and the underlying data are present. For acceleration-like data,
sampling must preserve local extrema at both stages that may reduce point
counts: the plot helper and the dynamic-series day-reduction helper. Report QA
should include at least one rendered high-frequency raw/group time-history
spot check after changing `fig_max_points`, cleaning rules, or dynamic-series
performance code.

Additional Hongtang Q2 v1.7.23 lesson: the same high-frequency visual issue can
appear in seasonal Hongtang acceleration and cable-acceleration plots. After
rerunning figures, stale old-dated files such as `20260627` can still coexist
in output folders; acceptance should check the report manifest, not only the
folder listing. The 2026-07-09 accepted Hongtang report had no image references
to the old `20260627` files and used the new `20260630` figures.

Additional v1.7.22 lesson: a manually checked report can be used as a template
base only after generator-owned figure blocks are treated as replaceable
content. The Hongtang Q2 auto template initially retained old picture blocks
before target captions, so new figures were inserted in addition to the old
ones; this inflated the rendered report from the expected `82` pages to `127`
pages. The report builder now removes nearby stale picture/short-label blocks
before inserting fresh figures, and report QA should compare media/drawing
counts and rendered page counts against the accepted baseline.

Additional v1.7.22 WIM lesson: copied template tables are not guaranteed to be
addressable with the row/column layout required by generated continuation
tables. The Hongtang Q2 manual template exposed this as a WIM continuation
`IndexError`. The generator now validates table access and falls back to a
standard table when the copied template table is incompatible.

## Donghua Export Layout

Status: fixed in the current snapshot.

Donghua export packages can appear in two compatible layouts:

- legacy direct layout: `日期\波形\*.csv` and `日期\特征值\*.csv`;
- newer nested layout: `日期\波形\GUID\*.csv` and
  `日期\特征值\GUID\*.csv`.

The pipeline now normalizes the newer layout by moving missing nested CSV files
to the direct parent folder before legacy preprocessing, so only one raw CSV
copy is kept. If a canonical direct CSV already exists, identical nested
duplicates are deleted; different-content conflicts are left untouched for
manual review. This is handled by
`+bms/+data/DonghuaExportNormalizer.m` and called from the rename/header/remap
preprocessing scripts.

Regression coverage:

- `tests/test_donghua_export_normalizer.m`
- related GUI smoke coverage in `tests/test_main_gui_smoke.m`

## Already-Extracted CSV Runs Without ZIP Packages

Status: known follow-up.

Some production reruns use already-extracted CSV data and intentionally have no
raw ZIP package in the period directory. In that case the analysis/report can be
valid, but the run manifest may still mark ZIP precheck or unzip stages as
failed.

Observed case:

- bridge: Guanbing Bridge
- data root: `F:\管柄数据\2026年6月`
- available data: `2026-05-26` to `2026-05-28`
- valid report:
  `F:\管柄数据\2026年6月\自动报告\G104线管柄大桥监测月报_2026年06月_自动生成_20260704_035056.docx`

Recommended fix:

- add an explicit "existing CSV mode" or "skip unzip when direct CSVs exist"
  switch;
- report ZIP stages as `skipped` instead of `failed` when enough CSV data is
  already present.

## MATLAB Batch Process May Linger After Work Completes

Status: known operational issue.

Several remote runs completed their output work but left a batch MATLAB process
alive for longer than expected. Completion should be judged by status JSON,
diary/stdout logs, expected stats files, and report artifacts, not by MATLAB
process presence alone.

Recommended behavior:

- do not stop user GUI MATLAB processes unless explicitly identified;
- only stop batch MATLAB processes after confirming no status/log progress and
  the relevant task has completed or failed.

## PowerShell 5.1 And Chinese Paths

Status: partially fixed.

Generated PowerShell launchers should be written as UTF-8 with BOM so Windows
PowerShell 5.1 does not decode Chinese paths as ANSI. This was fixed for the
GUI async launcher path, but future generated scripts should follow the same
rule.

Recommended check:

- if a remote task shows mojibake paths in logs, inspect the launcher encoding
  before changing MATLAB code.

## GUI Testability

Status: improved, keep extending.

The main GUI now supports hidden smoke tests through `run_gui('Visible','off')`
and exposes stable controls in `fig.UserData.controls`. Future GUI work should
prefer stable handles, shortcut callbacks, and preflight checks that can be
verified without manual clicking.

Recommended tests:

- `tests/test_main_gui_smoke.m`
- `tests/test_gui_state_services.m`
- `tests/test_path_profile_resolver.m`

## Dynamic Filter Performance On Large Periods

Status: partially fixed for Zhishan dynamic strain; keep monitoring on other
bridges.

Large dynamic-strain highpass/lowpass runs can spend most of their wall time in
filtering and figure export. The 2026-07-08 Zhishan April refresh enabled:

- chunked highpass with overlap, so long-period runs do not need one
  full-period highpass vector;
- downsample-before-lowpass for long cutoff trends, enabled for Zhishan with
  60 second bins.

Remaining caveat:

- raw full-resolution loading can still dominate wall time for about
  48 million samples per point;
- this optimization is suitable for engineering monthly-report trend plots, but
  future bridges should still compare representative full-resolution outputs
  against the optimized path before changing defaults bridge-wide.

Recommended checks:

- validate extrema, trend shape, and report-table consistency after enabling
  the optimized path for a new bridge;
- keep enough highpass overlap for boundary stability;
- avoid naive independent daily lowpass filtering for 12 hour cutoffs.

## Time-Series Cache Metadata With Mojibake Paths

Status: fixed for raw CSV MAT caches; keep as a regression risk.

Some older Windows runs wrote `cache\*.mat.meta.json` source paths with Chinese
characters already decoded as mojibake. The MAT cache itself can still be valid,
but exact source-path matching caused false cache misses and forced the loader
to reread very large CSV files. On Zhishan April, `CF-5` 2026-04-30 had a valid
MAT cache but a mojibake source path in metadata; the fallback 131 MB CSV read
left the batch MATLAB process effectively stuck.

Current fix:

- exact source-record matching still wins;
- if paths differ, raw cache reuse is allowed when filename, bytes, and source
  mtime fingerprints match;
- regression coverage: `tests/test_time_series_loader.m` includes a mojibake
  source-path cache-hit case.

Recommended check:

- when a run stalls after logging a large CSV day, check whether the MAT cache
  exists and whether its metadata path is mojibake before blaming the analysis
  algorithm.

## Report Caption Field Refresh

Status: fixed for the current Zhishan monthly report builder; keep in QA.

The Zhishan April report initially rendered captions such as
`表 错误：引用源未找到-11` even though `python-docx` saw normal visible text. The
cause was stale Word `REF` fields hidden inside caption paragraphs. The
Zhishan builder now normalizes generated captions to plain text before Word
field refresh.

Recommended check:

- every regenerated DOCX that uses an edited/manual template should still be
  rendered locally or on the remote machine;
- search rendered text for `引用源未找到`, `未定义书签`, `错误`, replacement tokens,
  and common mojibake before accepting the report.

## Remote MATLAB Launch With Chinese Paths

Status: known operational issue.

On 133, launching MATLAB through PowerShell `Start-Process` can fail or silently
drop work when `-batch` arguments contain Chinese paths and nested quoting. The
Zhishan dynamic refresh succeeded by using an ASCII task script that rebuilt the
Chinese data path inside MATLAB with `native2unicode(uint8(...), 'UTF-8')` and
tracking progress through a status JSON file.

Recommended behavior:

- prefer ASCII launcher scripts plus status JSON for unattended remote runs;
- avoid treating a lingering MATLAB process as failure when status JSON and
  output artifacts already show completion;
- only stop batch MATLAB PIDs after confirming they belong to the current task,
  and never stop a user GUI MATLAB process by name alone.
