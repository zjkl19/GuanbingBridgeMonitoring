# Known Issues And Follow-Up Items

Last updated: 2026-07-06

This file tracks recoverable technical risks that are too important to leave in
chat history but not always urgent enough to fix immediately.

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

## Rendered Report QA

Status: improved in `v1.7.16`; keep as an acceptance rule.

Raw DOCX QC is not enough when reports contain Word fields, table-of-contents
entries, cross-references or page-count headers. On 133, Python COM may be
missing even though Word COM is available. The period-report builder now falls
back to PowerShell Word COM, repaginates the document, updates header/footer
shape fields, and patches stale hard-coded total-page text in header/footer XML
when Word reports the final page count. Final acceptance should still include
render/export QA when a production report is generated.

Recommended check:

- export or render the DOCX to PDF/pages;
- search rendered text for `错误`, `引用源未找到`, stale quarter/month text, and
  old total-page headers;
- spot-check representative plotted pages before sending the report out.

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
