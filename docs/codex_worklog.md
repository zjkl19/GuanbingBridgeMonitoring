# Codex Worklog

This file records durable handoff notes for Guanbing work. Append to it at the end of each meaningful phase so a new Codex thread can continue without relying on long conversation history.

## 2026-05-25

Created the long-session recovery notes before starting the Zhishan Bridge data processing task.

What was recorded:

- Current repository status and recent commits.
- Existing uncommitted files that should not be reverted.
- Zhishan input materials, source data, staged data target, and March processing range.
- Confirmed point-to-file ID mappings from the Zhishan equipment table.
- Threshold and unit notes from the trial operation report, including the `SX-2` likely typo correction.
- Intended implementation scope: add Zhishan profile/config, cable-force handling through the existing cable-acceleration path, staging script, GUI/CLI wiring, tests, data index validation, March processing, and light regression checks.
- Recovery rule for future Codex context-compaction stalls.

Next suggested action:

- Start a dedicated Zhishan data-processing thread and begin by reading `D:\MatlabProjects\Guanbing\docs\current_task_state.md`, `git status`, `git diff`, and recent commits.

## 2026-05-25 Zhishan Data Processing Connection

Implemented the Zhishan data-processing connection without adding a direct `cable_force` module. The user corrected the earlier scope: cable force remains computed through the existing `cable_accel` / `cable_accel_spectrum` path.

What changed:

- Added `config/zhishan_config.json` with SX/DX/AZ/CF mappings, thresholds, spectrum targets, and CF `rho/L` from `报告及数据处理\索力\索力计算.xlsx`.
- Added the Zhishan profile to `config/bridge_profiles.json` and `BridgeProfileRegistry`.
- Added `scripts/stage_zhishan_subset.m` to copy only configured Zhishan CSV IDs out of the mixed Hongtang source tree.
- Fixed data indexing for derived modules so `dynamic_strain_highpass`, `accel_spectrum`, and `cable_accel_spectrum` resolve the underlying `strain`, `acceleration`, and `cable_accel` file IDs.
- Made the CSV loader prefer UTF-16LE when a BOM is present, reducing noisy warnings on Zhishan wave files.
- Extended structural warning-line generation to support `alarm_bounds.level1` alongside level2/level3.

Validation completed:

- Ran focused MATLAB tests for loader, data source/index, Zhishan config, bridge profile, warning lines, and config integration; all passed.
- Staged March data from `E:\洪塘大桥数据\2026年1-3月` to `D:\芝山大桥数据\2026年1-3月`: 756 files copied, 28/31 source dates present, missing dates `2026-03-01`, `2026-03-02`, `2026-03-12`, missing configured point files `0`.
- Preflight on staged March data passed: 7 modules, 50 module-point entries, 50 found, 0 missing, 1400 indexed module files.
- Smoke-read verified real `2026-03-03` files for `SX-1`, `DX-1`, `AZ-1`, and `CF-1`.

Not yet done:

- Full March analysis/stat/plot generation has not been run yet.

## 2026-05-25 Zhishan March Full Run

Ran the full Zhishan March processing chain for `D:\芝山大桥数据\2026年1-3月`, `2026-03-01` to `2026-03-31`.

Run results:

- `run_all` status: `ok`
- Elapsed: `4340.94 sec`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260525_230049.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260525_214829.txt`
- All 7 requested analysis modules completed OK:
  - `bearing_displacement`
  - `strain`
  - `acceleration`
  - `cable_accel`
  - `accel_spectrum`
  - `cable_accel_spectrum`
  - `dynamic_strain_highpass`
- Generated 7 expected stats workbooks under `D:\芝山大桥数据\2026年1-3月\stats`.
- Generated 966 figure files under the result tree (`439 .jpg`, `439 .fig`, `88 .emf`).

Post-run health:

- Latest data index: `D:\芝山大桥数据\2026年1-3月\run_logs\data_index_20260525_230812.json`
- Latest stats inventory: `D:\芝山大桥数据\2026年1-3月\run_logs\stats_inventory_20260525_230810.json`
- Latest run health: `D:\芝山大桥数据\2026年1-3月\run_logs\run_health_20260525_230812.json`
- Result: `preflight=ok`, 50/50 indexed points found, 7/7 stats present, run health issues/errors/warnings all `0`.

Additional code fix:

- Fixed `RunPreflight.checkPreviousManifestArtifacts` so figures generated inside the same module run window are not flagged as stale just because the module writes stats after figures.
- Added `test_run_preflight/sameRunFigureBeforeStatsDoesNotWarnFromManifest`.

Validation:

- `tests/test_run_preflight.m` passed.
- Focused regression suite passed: `test_time_series_loader`, `test_datasource_services`, `test_zhishan_config`, `test_bridge_profile`, `test_plot_warning_line_resolver`, `test_config_integration_regression`, and `test_run_preflight`.

Residual note:

- The full run stdout log contains repeated MATLAB BOM mismatch warnings from `readtable` fallback while loading UTF-16LE Zhishan CSVs. The data were still read and cached successfully; post-run health is clean.

## 2026-05-28 Zhishan March Reprocessing

Updated the Zhishan March processing configuration according to the latest user-confirmed rules and reran the data chain.

What changed:

- Added dynamic first-valid-day mean offset correction support in `+bms/+data/CleaningPipeline.m`.
- Updated Zhishan config so March `acceleration` is clipped to `[-0.2, 0.2]`, `cable_accel` is zero-corrected then clipped to `[-1, 1]`, `bearing_displacement` and `strain` use first-valid-day zero correction, and bearing displacement is filtered by each point's level-3 bounds.
- Updated strain display rule to only use the yellow second-level warning line.
- Updated structural spectrum targets to `AZ-1=0.610`, `AZ-2=0.623`, `AZ-3=0.620`, `AZ-4=0.620`, `AZ-5=0.640`, with theoretical frequency `0.385 Hz`.
- Updated `CF-1~CF-8` cable spectrum/force parameters from the user-provided OCR table; cable force still uses the existing `cable_accel_spectrum` path.
- Made RMS peak statistics tolerate sparse NaNs after cleaning by using omitted-NaN moving RMS with a 70% valid-window coverage requirement.

Important data note:

- Raw `CF-*` cable acceleration data have large DC offsets. Applying `[-1, 1]` directly would remove all cable data. The implemented rule applies first-valid-day mean zero correction first, then applies the `[-1, 1]` filter.

Run results:

- Run status: `ok`
- Elapsed: `3480.08 sec`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_182739.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_172938.txt`
- Offset report: `D:\芝山大桥数据\2026年1-3月\run_logs\offset_correction_applied_20260528_172938.xlsx`
- Post-run health passed on 2026-05-28: 50/50 module-point files found, 7/7 stats workbooks present, 0 run-health issues/errors/warnings.

Verification:

- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_dynamic_series_service`, `test_zhishan_config`, `test_spectrum_peak_service`, `test_plot_warning_line_resolver`.
- Custom workbook checks passed:
  - `AZ-1~AZ-5` stats min/max are inside `[-0.2, 0.2]`.
  - `CF-1~CF-8` stats min/max are inside `[-1, 1]`.
  - Bearing displacement filtered stats stay inside configured level-3 bounds.
  - AZ spectrum sheets use the confirmed point-specific targets and all non-empty frequencies are within `±0.05 Hz`.
  - Cable spectrum/force sheets exist for `CF-1~CF-8`; force values were generated for all cable points.
- Direct load check confirmed first-valid-day zero correction: `DX-1≈-0.001`, `SX-1≈0`, `CF-1≈-0.0025`.

Residual note:

- Some `cable_accel_stats.xlsx` 10-minute RMS cells are blank for `CF-1`, `CF-2`, `CF-7`, and `CF-8` because the strict `[-1, 1]` filter leaves insufficient continuous 10-minute valid coverage. Frequency/force outputs still exist.

## 2026-05-28 Zhishan Cable Acceleration Follow-Up

Investigated the poor `CF-*` cable acceleration figures reported by the user and reran the cable modules.

What changed:

- Extended `+bms/+data/CleaningPipeline.m` so cleaning rules can apply `value_scale` after offset correction and before threshold clipping.
- Added daily grouped offset modes, including `daily_median`, for channels with day-by-day DC drift.
- Updated `config/zhishan_config.json` so `cable_accel` uses `daily_median` baseline removal, converts raw cm/s^2-like data by `value_scale=0.01`, then applies the confirmed `[-1, 1]` m/s^2 March filter.
- Updated `tests/test_cleaning_pipeline.m` and `tests/test_zhishan_config.m` for the new cleaning behavior.

Run results:

- Reran `cable_accel` and `cable_accel_spectrum`.
- Run status: `ok`
- Elapsed: `890.32 sec`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_191054.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_185604.txt`
- Updated stats:
  - `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_spec_stats.xlsx`
- Post-run cable-only preflight passed: 16/16 indexed module-point files found, 2/2 stats files present, run-health issues/errors/warnings all `0`.

Data assessment:

- The data are not wholly unrecoverable. After daily median offset correction and unit conversion, valid rates are roughly `97%~99.99%`, and all `CF-1~CF-8` stats stay inside `[-1, 1]`.
- `CF-3/4/6` are comparatively clean; `CF-1/2/5/7/8` have materially wider broadband amplitude even after cleaning.
- Month-scale raw 20 Hz waveform figures still look dense because each point has about 46 million samples and a small proportion of near-threshold values is enough to fill the plot visually. This is a plotting/reporting representation problem, not evidence that spectrum/force data cannot be processed.
- Preferred report view for this channel should be the regenerated `时程曲线_索力加速度_RMS10min` and `时程曲线_索力加速度_RMS10min_组图` images, while keeping cleaned raw data for spectrum and force calculations.

Validation:

- Focused MATLAB tests passed for `test_cleaning_pipeline`, `test_zhishan_config`, and `test_dynamic_series_service`.
- Direct load check computed valid rates, percentiles, threshold proximity, and RMS for all `CF-1~CF-8`.

## 2026-05-28 Zhishan Cable Acceleration Unit Correction

The user clarified that CF cable acceleration is already in `m/s^2`, so the previous `0.01` conversion should not be used.

What changed:

- Updated `config/zhishan_config.json` to remove `value_scale` from `defaults.cable_accel`.
- Updated the CF cleaning threshold from `[-1,1]` to `[-2,2] m/s^2`.
- Kept `daily_median` baseline removal because the CF data still show day-by-day baseline drift.
- Updated `tests/test_zhishan_config.m` accordingly.

Run results:

- Reran `cable_accel` and `cable_accel_spectrum`.
- Run status: `ok`
- Elapsed: `597.06 sec`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_204936.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_203939.txt`
- Cable-only post-run preflight passed: 16/16 indexed module-point files found, 2/2 stats files present, run-health issues/errors/warnings all `0`.

Data assessment:

- Direct load check confirmed `value_scale_applied=0`.
- `cable_accel_stats.xlsx` min/max are all within `[-2,2]`.
- Valid-point retention after cleaning is uneven: `CF-1=7.976%`, `CF-2=6.201%`, `CF-3=88.140%`, `CF-4=87.539%`, `CF-5=22.970%`, `CF-6=51.908%`, `CF-7=5.963%`, `CF-8=8.965%`.
- The raw monthly plots for `CF-1/2/7/8` remain dense because most values outside `[-2,2]` are removed and the remaining valid points still span the clipping band. This result suggests the strict `[-2,2]` filter makes those point time histories sparse, not that the pipeline failed.
- `cable_accel_spec_stats.xlsx` still produced force values for all CF points, mostly 27 valid days each (`CF-5=25`).

## 2026-05-28 Zhishan Cable Acceleration `[-10,10]` Trial

The user asked to try `[-10,10] m/s^2` filtering for CF cable acceleration.

What changed:

- Updated `config/zhishan_config.json` to use `[-10,10] m/s^2` for `defaults.cable_accel.thresholds`.
- Kept `daily_median` baseline removal and no `value_scale`.
- Updated `tests/test_zhishan_config.m` accordingly.

Run results:

- A normal run with cable group plots was stopped because the raw full-month `cable_accel` group plot reached very high memory.
- Reran `cable_accel` and `cable_accel_spectrum` with `cfg.groups.cable_accel=struct()` so single-point plots, RMS plots, stats, and spectrum/force are regenerated, while the raw cable group plot is skipped.
- Final run status: `ok`
- Elapsed: `1170.10 sec`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_222416.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_220447.txt`
- Cable-only post-run preflight passed with no group plots expected: 16/16 indexed module-point files found, 2/2 stats files present, run-health issues/errors/warnings all `0`.

Data assessment:

- `cable_accel_stats.xlsx` min/max are all within `[-10,10]`.
- RMS10minMax: `CF-1=8.544`, `CF-2=7.447`, `CF-3=9.611`, `CF-4=9.653`, `CF-5=9.738`, `CF-6=8.736`, `CF-7=8.253`, `CF-8=9.048`.
- Valid-point retention after cleaning: `CF-1=37.455%`, `CF-2=29.904%`, `CF-3=99.087%`, `CF-4=99.111%`, `CF-5=61.800%`, `CF-6=96.489%`, `CF-7=28.376%`, `CF-8=41.913%`.
- Visual check: `CF-3` is much more interpretable under `[-10,10]`; `CF-1` and `CF-8` remain dense bands, so their poor raw monthly waveform appearance is likely dominated by actual wide-amplitude/noisy signal and overplotting, not only by an overly tight threshold.
- Spectrum/force outputs exist for all CF points, 27 valid days each.

## 2026-05-28 Zhishan Cable Acceleration Threshold Sweep

The user stopped the manual `[-20,20]` trial and asked Codex to search thresholds instead of trying them one by one.

What changed:

- Added `tmp/evaluate_zhishan_cable_accel_thresholds.m` to evaluate candidate thresholds without full plotting.
- The script loads each CF point once after daily median baseline removal, no unit scaling, and no threshold clipping, then evaluates global absolute thresholds `[2 5 10 15 20 30 40 50 75 100 150 200]`.
- Wrote threshold evaluation workbook:
  - `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_eval_20260528_225644.xlsx`

Sweep result:

- `±20`: minimum retention `52.315%`, mean retention `77.104%`.
- `±50`: minimum retention `89.594%`, mean retention `94.528%`.
- `±75`: minimum retention `94.738%`, mean retention `97.908%`.
- `±100`: minimum retention `97.234%`, mean retention `99.042%`.
- `±150`: minimum retention `98.950%`, mean retention `99.724%`.

Selected candidate:

- Updated `config/zhishan_config.json` to `[-100,100] m/s^2`.
- Reason: `±100` is the smallest evaluated threshold that keeps at least `97.2%` of every point while still removing extreme spikes up to tens of thousands of `m/s^2`.
- Kept `daily_median` baseline removal and no `value_scale`.

Run results:

- Reran `cable_accel` and `cable_accel_spectrum` with `cfg.groups.cable_accel=struct()` to skip raw full-month group plots, because those caused high memory use.
- Run status: `ok`
- Elapsed: `598.24 sec`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_230859.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_225902.txt`
- Cable-only post-run preflight passed with no group plots expected: 16/16 indexed module-point files found, 2/2 stats files present, run-health issues/errors/warnings all `0`.

Data assessment:

- `cable_accel_stats.xlsx` min/max are all within `[-100,100]`.
- RMS10minMax: `CF-1=55.986`, `CF-2=54.739`, `CF-3=29.779`, `CF-4=29.833`, `CF-5=97.222`, `CF-6=18.886`, `CF-7=71.575`, `CF-8=60.559`.
- Spectrum/force outputs exist for all CF points, 27 valid days each.
- Visual check: `CF-3` raw monthly plot is readable under `±100`, but `CF-1/8` remain dense raw monthly bands. This indicates threshold tuning alone cannot make every raw full-month waveform clean; report readability should use RMS/envelope-style views for those points.
- Generated 30-minute envelope/RMS diagnostic plots with `tmp/plot_zhishan_cable_accel_envelope.m`.
- Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_包络30min`; manifest: `cable_accel_envelope30_manifest.xlsx`.
- Updated `config/zhishan_config.json` so `groups.cable_accel` is empty by default. This prevents ordinary runs from trying to draw the raw all-CF full-month group plot that previously caused high memory use; single-point raw/RMS plots and spectrum/force outputs remain enabled.
- Focused tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
- Current-config cable-only preflight passed: data index `16/16`, stats inventory `2/2`, run-health issues/errors/warnings all `0`, reporting contract `groups=0`.

## 2026-05-29 Zhishan Cable Acceleration Formal Envelope Output

Followed up on the active threshold-search goal by comparing strategy candidates and making the report-friendly output repeatable in the formal pipeline.

Strategy evaluation:

- Added `tmp/evaluate_zhishan_cable_accel_strategies.m`.
- Output workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_strategy_eval_20260528_233314\cable_accel_strategy_eval.xlsx`.
- Compared `global100`, `perpoint95`, `perpoint98`, and `perpoint99`.
- `perpoint95` thresholds are `CF-1=50`, `CF-2=75`, `CF-3=5`, `CF-4=5`, `CF-5=100`, `CF-6=10`, `CF-7=75`, `CF-8=75`.
- Assessment: `perpoint95` improves some RMS views but is too aggressive for formal spectrum/force calculation. Keep `global100` for calculation and use envelope/RMS plots for readability.

Pipeline update:

- Added `DynamicAccelerationPlotService.plotEnvelopeCurve`.
- Enabled 30 min envelope/RMS plots only for `cable_accel`.
- Added test coverage in `tests/test_dynamic_series_service.m`.

Verification:

- Focused tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
- Formal `run_all` with `doCableAccel=true` completed with status `ok`.
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260529_000952.json`.
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260529_000159.txt`.
- Formal envelope output: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_包络30min`.
- Current-config `doCableAccel` preflight passed: data index `8/8`, stats inventory `1/1`, run-health issues/errors/warnings all `0`, reporting contract `groups=0`.
- Review board for quick visual approval:
  - `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_envelope30_review_board_20260529_001853.jpg`.

## 2026-05-29 Zhishan Cable Acceleration Strategy Decision Summary

- Added `tmp/summarize_zhishan_cable_accel_strategy.m`.
- Generated decision summary:
  - `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_strategy_decision_20260529_002850.md`
  - `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_strategy_decision_20260529_002850.csv`
- Quantified comparison against formal `global100`:
  - `CF-1/3/4/6`: `perpoint95` can be used as display-only clipping if the user wants cleaner visual review.
  - `CF-5/8`: tightening threshold has little benefit.
  - `CF-2/7`: moderate improvement but not enough to justify changing formal calculation.
- Recommendation remains: formal calculation uses `daily_median + [-100,100] m/s^2`; report/review should use the 30 min envelope/RMS output.

## 2026-05-29 Zhishan Cable Acceleration Envelope Gap Fix

- Fixed `DynamicAccelerationPlotService.fillEnvelopeBand` so percentile bands are split into continuous valid runs instead of bridging missing bins.
- Added regression test: `test_dynamic_series_service/envelopeBandBreaksAcrossMissingBins`.
- Reran formal `run_all` with `doCableAccel=true` only.
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260529_004630.json`.
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260529_003841.txt`.
- Current-config `doCableAccel` preflight passed: data index `8/8`, stats inventory `1/1`, run-health issues/errors/warnings all `0`, reporting contract `groups=0`.
- New review board after the gap fix:
  - `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_envelope30_review_board_20260529_004723.jpg`.

## 2026-05-29 Zhishan Cable Acceleration Auto Tune Script

- Added `scripts/auto_tune_zhishan_cable_accel_thresholds.m`.
- Purpose: make the threshold search reproducible instead of manually trying `[-2,2]`, `[-10,10]`, `[-20,20]`, etc.
- Selection rules:
  - Formal calculation: smallest global threshold where all CF points keep at least `97%`.
  - Display/review: use a point-level `95%` keep candidate only when RMS30 max is reduced by at least `25%` and keep loss is at most `5%`.
- Latest run:
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest.html`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest_render.png`
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest.json`
  - Output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_065044`
  - Summary: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_065044\cable_accel_auto_tune_summary.md`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_065044\cable_accel_auto_tune.xlsx`
  - Selected-display review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_065044\auto_tune_selected_visual_review_board.jpg`
  - Formal-vs-selected review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_065044\auto_tune_formal_vs_selected_review_board.jpg`
  - Per-point comparison images: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_065044\formal_vs_selected_compare\FormalVsSelected_CF-*.jpg`
- Browser render check used Microsoft Edge headless through Playwright with system Edge; the latest HTML page rendered the Chinese title/note, loaded `10/10` images, has the expected 9 table rows, and highlights `CF-1/3/4/6`.
- Result:
  - Formal threshold: `[-100,100] m/s^2`.
  - Display thresholds: `CF-1=50`, `CF-3=5`, `CF-4=5`, `CF-6=10`, and `CF-2/5/7/8=100`.

## 2026-05-29 Zhishan Cable Acceleration `[-20,20]` Preview

- Added `scripts/preview_zhishan_cable_accel_threshold.m` so a requested one-off CF threshold can be evaluated without changing `zhishan_config.json` or overwriting formal outputs.
- Ran `preview_zhishan_cable_accel_threshold(20)`.
- Output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_071800_abs20`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_071800_abs20\cable_accel_threshold_preview.xlsx`.
- Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_071800_abs20\cable_accel_threshold_preview_abs20_review_board.jpg`.
- Keep rates: `CF-1=66.157%`, `CF-2=54.897%`, `CF-3=99.821%`, `CF-4=99.821%`, `CF-5=77.167%`, `CF-6=99.916%`, `CF-7=52.315%`, `CF-8=66.741%`.
- Assessment: `±20` is still too destructive for `CF-1/2/5/7/8`. It makes `CF-3/4/6` readable but does not solve broad high-amplitude/noisy monthly bands on all points. Keep the formal calculation at `[-100,100]` unless the user explicitly accepts the data loss or chooses point-specific display thresholds.

## 2026-05-29 Zhishan Cable Acceleration Auto Diagnosis Update

- Updated `scripts/auto_tune_zhishan_cable_accel_thresholds.m` to write point-level diagnosis and acceptance outputs, so future work does not continue blind threshold trials.
- Reran the auto-tune script.
- Latest run folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_072726`.
- Acceptance Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_acceptance_latest.md`.
- Acceptance JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_acceptance_latest.json`.
- Latest HTML: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest.html`.
- Main conclusion: no single stricter global threshold satisfies both data retention and clean monthly visualization. Keep formal spectrum/force calculation at `[-100,100]`; use point-level display clipping plus 30 min envelope/RMS plots for review.
- Point diagnosis:
  - Threshold display tuning helps: `CF-1`, `CF-3`, `CF-4`, `CF-6`.
  - Threshold-limited or data-quality review points: `CF-2`, `CF-5`, `CF-7`, `CF-8`.
- Browser render check passed for latest HTML: `10/10` images loaded, diagnosis column present, expected changed rows `CF-1/3/4/6`, no missing sources.
- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.

## 2026-05-29 Zhishan Cable Acceleration Segment Quality Diagnosis

- Added `scripts/diagnose_zhishan_cable_accel_segments.m` for the hard points `CF-2/5/7/8`.
- The diagnostic keeps formal `±100 m/s^2`, then sweeps display-only removal of the top `2/5/10/15/20%` high-RMS 1-hour segments.
- Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_segment_quality_20260529_074646`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_segment_quality_20260529_074646\cable_accel_segment_quality.xlsx`.
- Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_segment_quality_20260529_074646\cable_accel_segment_quality_review_board.jpg`.
- Selected candidate for all four points is top `5%` high-RMS hour removal because `10%+` drops kept data below `90%`.
- Results:
  - `CF-2`: keep `94.273%`, RMS max reduction `14.7%`; limited benefit, likely persistent wide-amplitude/noisy signal.
  - `CF-5`: keep `93.901%`, RMS max reduction `32.7%`; segment filtering helps display.
  - `CF-7`: keep `94.783%`, RMS max reduction `25.0%`; segment filtering helps display.
  - `CF-8`: keep `93.227%`, RMS max reduction `14.5%`; limited benefit, likely persistent wide-amplitude/noisy signal.
- Current recommendation after this pass: formal calculation remains `daily_median + [-100,100]`; report display can use point threshold display clipping for `CF-1/3/4/6`, and optionally segment-quality display filtering for `CF-5/7`. `CF-2/8` should be documented as original signal quality/overplotting limitations unless a stronger, explicitly display-only smoothing approach is acceptable.

## 2026-05-29 Zhishan Cable Acceleration Combined Display Candidate

- Added `scripts/build_zhishan_cable_accel_display_candidate.m`.
- Purpose: generate one full `CF-1~CF-8` display-only candidate instead of separate threshold and segment experiments.
- Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest.md`.
- Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest.json`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest_render.png`.
- Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_083413`.
- Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_083413\cable_accel_display_candidate_review_board.jpg`.
- Stable report output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate`.
- Stable report board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayCandidate_ReviewBoard.jpg`.
- Stable manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayCandidate_manifest.xlsx`.
- Display strategy:
  - `CF-1`: `abs<=50`, keep `95.013%`, RMS30 max reduction `45.9%`.
  - `CF-3`: `abs<=5`, keep `95.863%`, RMS30 max reduction `83.1%`.
  - `CF-4`: `abs<=5`, keep `95.901%`, RMS30 max reduction `82.9%`.
  - `CF-6`: `abs<=10`, keep `96.489%`, RMS30 max reduction `37.8%`.
  - `CF-5`: formal `abs<=100` plus top `5%` RMS30 segment filtering, keep `93.505%`, RMS30 max reduction `30.7%`.
  - `CF-7`: formal `abs<=100` plus top `5%` RMS30 segment filtering, keep `94.795%`, RMS30 max reduction `30.1%`.
  - `CF-2/8`: keep formal `abs<=100`; label as persistent wide-band signal / quality limitation.
- Formal spectrum/force calculation remains unchanged at `daily_median + [-100,100]`.
- Plot style now uses a light `5%~95%` band plus a stronger `25%~75%` band and median line. This keeps `CF-2/8` more readable without deleting additional data.
- HTML render check passed after the stable-output update: `9/9` images loaded, 9 table rows, 2 quality-limitation rows highlighted, no missing image sources.

## 2026-05-29 Zhishan Cable Acceleration Trend Candidate Update

- Updated `scripts/build_zhishan_cable_accel_display_candidate.m` to also write trend-focused figures.
- Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_085916`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest_render.png`.
- Stable report output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate`.
- Stable detail board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayCandidate_ReviewBoard.jpg`.
- Stable trend board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayTrend_ReviewBoard.jpg`.
- Stable manifest Markdown now uses local file names rather than full Chinese paths to avoid MATLAB/Windows Markdown mojibake.
- HTML render check passed with headless Edge: `18/18` images loaded, 9 table rows, 2 quality-limitation rows highlighted, no missing image sources.
- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
- Current interpretation remains unchanged: `±20` is too destructive for several points; formal spectrum/force stays at `daily_median + [-100,100]`; display candidate uses point clipping for `CF-1/3/4/6`, top `5%` RMS30 segment display filtering for `CF-5/7`, and quality-limitation notes for `CF-2/8`.

## 2026-05-29 Zhishan Cable Acceleration Display Grid Search

- Added `scripts/optimize_zhishan_cable_accel_display_grid.m`.
- Purpose: search threshold and top-RMS segment removal together, so the workflow does not continue one threshold at a time.
- Search implementation: score each point on sampled data for speed, then recompute the selected candidate using full data before writing the selected summary and figures.
- Search grid: thresholds `[5 10 15 20 30 40 50 75 100] m/s^2`; top-RMS 30 min segment removal `[0 2 5 8 10]%`; selected candidates must keep at least `90%` of finite data.
- Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_latest_render.png`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242\cable_accel_display_grid_search.xlsx`.
- Detail board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242\cable_accel_display_grid_selected_review_board.jpg`.
- Trend board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242\cable_accel_display_grid_selected_trend_board.jpg`.
- Selected display candidates:
  - `CF-1`: `abs<=50 + top 2% RMS30`, keep `93.317%`, RMS30 max down `52.3%`.
  - `CF-2`: `abs<=75 + top 2% RMS30`, keep `95.042%`, RMS30 max down `25.3%`.
  - `CF-3`: `abs<=5 + top 2% RMS30`, keep `94.891%`, RMS30 max down `88.3%`.
  - `CF-4`: `abs<=5 + top 2% RMS30`, keep `94.862%`, RMS30 max down `88.2%`.
  - `CF-5`: `abs<=75 + top 5% RMS30`, keep `91.742%`, RMS30 max down `42.7%`.
  - `CF-6`: `abs<=10 + top 5% RMS30`, keep `93.633%`, RMS30 max down `54.3%`.
  - `CF-7`: `abs<=75 + top 5% RMS30`, keep `93.991%`, RMS30 max down `34.5%`.
  - `CF-8`: `abs<=75 + top 2% RMS30`, keep `93.280%`, RMS30 max down `26.0%`.
- HTML render check passed with headless Edge: `18/18` images loaded, 9 table rows, no missing image sources.
- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
- Formal spectrum/force calculation remains unchanged at `daily_median + [-100,100]`. This grid output is the current aggressive display candidate; do not apply it to formal calculation without user approval.

## 2026-05-29 Zhishan Cable Acceleration Candidate Comparison

- Added `scripts/compare_zhishan_cable_accel_display_candidates.m`.
- Purpose: put the conservative candidate and aggressive grid-search candidate on one review page.
- Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_20260529_093755`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_latest_render.png`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_20260529_093755\cable_accel_display_compare.xlsx`.
- Review-page conclusions:
  - Prefer grid display: `CF-2`, `CF-6`.
  - Grid improves previously limited point: `CF-8`.
  - Aggressive, review data loss: `CF-5`.
  - Conservative display acceptable: `CF-1`, `CF-3`, `CF-4`, `CF-7`.
- HTML render check passed with headless Edge: `4/4` images loaded, 9 table rows, 3 preferred-grid rows, 1 aggressive row, no missing image sources.
- This comparison page is the current user-facing review artifact for deciding whether the automated threshold/grid search is satisfactory.

## 2026-05-29 Zhishan Cable Acceleration Display Recommendation

- Added `scripts/build_zhishan_cable_accel_display_recommendation.m`.
- Purpose: synthesize the conservative and grid-search candidates into one recommended display policy.
- Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_20260529_095537`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_latest_render.png`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_20260529_095537\cable_accel_display_recommendation.xlsx`.
- Stable output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation`.
- Stable manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendation_manifest.xlsx`.
- Stable policy JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendation_policy.json`.
- Recommendation:
  - Grid-search result: `CF-2`, `CF-6`, `CF-8`.
  - Conservative result: `CF-1`, `CF-3`, `CF-4`, `CF-5`, `CF-7`.
  - `CF-5` stays conservative because the grid option was marked aggressive/data-loss review.
- HTML render check passed with headless Edge after switching to stable image paths: `16/16` images loaded, all 16 from `report_cable_accel_display_recommendation`, 9 table rows, 3 grid-picked rows, no missing image sources.
- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
- Formal spectrum/force calculation remains unchanged at `daily_median + [-100,100]`. This is the main display/review artifact to show the user.

## 2026-05-29 Zhishan Cable Acceleration Recommendation vs Formal Review

- Added `scripts/review_zhishan_cable_accel_recommendation_vs_formal.m`.
- Purpose: use the stable display `policy.json` and source data to recompute the recommended display, compare it against the formal `daily_median + abs<=100` display baseline, and generate side-by-side review plots.
- Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_20260529_100515`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_latest_render.png`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_20260529_100515\cable_accel_recommendation_vs_formal.xlsx`.
- Stable review directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\formal_baseline_review`.
- Stable review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\formal_baseline_review\CableAccelRecommendationVsFormal_ReviewBoard.jpg`.
- Full-data recomputation shows every `CF` point has material RMS30 max reduction versus formal baseline; keep-rate loss ranges from about `3.7%` to `6.4%`.
- HTML render check passed with headless Edge: `9/9` images loaded, 9 table rows, 3 grid-picked rows, no missing image sources.
- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.

## 2026-05-29 Zhishan Cable Acceleration Recommended Display Export

- Added `scripts/export_zhishan_cable_accel_recommended_display.m`.
- Purpose: generate report-ready recommended display charts from source data and stable `CableAccelDisplayRecommendation_policy.json`.
- Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommended_display_export_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommended_display_export_latest_render.png`.
- Review board: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示\CableAccelRecommendationDisplay_ReviewBoard.jpg`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示\CableAccelRecommendationDisplay_manifest.xlsx`.
- Per-point images: `CableAccelRecommendationDisplay_CF-1_20260301_20260331.jpg` through `CF-8` in the output directory.
- Markdown pointers were revised to use ASCII filenames only; this avoids MATLAB/PowerShell mojibake for Chinese directory names while preserving the actual Chinese output folder.
- HTML render check passed with headless Edge: `9/9` images loaded, 9 table rows, 3 grid-picked rows, no missing image sources.
- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.

## 2026-05-29 Zhishan Cable Acceleration Display Acceptance

- Added `scripts/validate_zhishan_cable_accel_display_recommendation.m`.
- Purpose: provide a machine-readable final gate for the recommended display results.
- Acceptance gates:
  - Formal `cable_accel` config still uses `daily_median + [-100,100] m/s^2`.
  - Stable policy JSON is `display_only`.
  - Report-ready review board and manifest exist.
  - All `CF-1~CF-8` have export images.
  - Per point: keep rate `>=93%`, RMS30 max reduction `>=25%`, keep-rate loss no worse than `-7%`.
- Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_latest.html`.
- Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_latest_render.png`.
- Latest workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_20260529_104445\cable_accel_display_acceptance.xlsx`.
- Result: overall pass `1`; all global checks and all 8 point checks pass.
- Acceptance Markdown now uses ASCII file names for the review board to avoid MATLAB/PowerShell mojibake for Chinese directories.
- HTML render check passed with headless Edge after the Markdown cleanup: `1/1` image loaded, 16 table rows, `passText=1`, no missing image sources.
- Focused MATLAB tests passed: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.

## 2026-05-29 Zhishan Cable Acceleration Stable Review Pack

- Added `scripts/publish_zhishan_cable_accel_display_review_pack.m`.
- Purpose: provide one stable entry page for the final recommended display policy, detailed figures, trend figures, formal-baseline review, acceptance gate, and report-ready output.
- Added `scripts/build_zhishan_cable_accel_display_contact_sheet.m` to generate a compact 2x4 quick-review board from the existing report-ready per-point figures.
- Stable entry page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\index.html`.
- README: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\README.md`.
- Summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendation_review_summary.json`.
- Compact contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示\CableAccelRecommendationDisplay_ContactSheet.jpg`.
- Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\index_render.png`.
- Render check passed with headless Edge: `19/19` images loaded, 9 strategy table rows, 3 grid-picked rows, `Acceptance pass: 1`, no missing image sources.
- README and JSON were adjusted to avoid embedding the Chinese report-ready folder name directly, preventing MATLAB/PowerShell mojibake while preserving actual HTML links.
- The package remains display-only: formal spectrum/force calculation is still `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Tiered Candidate Ladder

- Added `scripts/build_zhishan_cable_accel_display_ladder.m`.
- Purpose: stop manual one-threshold-at-a-time experimentation by generating four tiers for every `CF` point: formal baseline, current recommendation, cleaner candidate, and aggressive candidate.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review`.
- HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review\CableAccelDisplayLadder_manifest.xlsx`.
- Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review\CableAccelDisplayLadder_ReviewBoard.jpg`.
- Main stable review page now links to `ladder_review/index.html`.
- Render checks:
  - Ladder page: `9/9` images loaded, 33 table rows, 8 current rows, 8 cleaner rows, 8 aggressive rows.
  - Main stable page after linking: `19/19` images loaded, 9 table rows, 3 grid-picked rows, ladder link present.
- Current recommendation remains the safe default. Cleaner tier generally keeps about `92%+`; aggressive tier keeps about `85%~87%` and reduces RMS more, so it requires human approval before being promoted to report/default display.

## 2026-05-29 Zhishan Cable Acceleration Cleaner Display Export

- Added `scripts/export_zhishan_cable_accel_ladder_tier_display.m`.
- Purpose: export one automatically searched ladder tier into standalone review/report figures without editing formal calculation settings.
- Ran `export_zhishan_cable_accel_ladder_tier_display('cleaner')`.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export`.
- HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\CableAccelCleanerDisplay_manifest.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\CableAccelCleanerDisplay_ContactSheet.jpg`.
- Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\CableAccelCleanerDisplay_ReviewBoard.jpg`.
- Main stable review page now links to `cleaner_display_export/index.html`.
- Render checks:
  - Cleaner page: `10/10` images loaded, 9 table rows, contact sheet and review board present.
  - Main stable page after linking: `19/19` images loaded, 9 strategy rows, 3 grid-picked rows, acceptance shown, ladder link and cleaner link present.
- Cleaner tier remains display-only. It is the next stricter candidate if the current recommendation still looks insufficient; aggressive tier remains available but is intentionally not exported as the default because it keeps only about `85%~87%`.

## 2026-05-29 Zhishan Cable Acceleration Current vs Cleaner Review

- Added `scripts/compare_zhishan_cable_accel_current_vs_cleaner.m`.
- Purpose: generate a point-by-point side-by-side comparison between the current recommended display and the cleaner-tier display.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review`.
- HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review\CableAccelCurrentVsCleaner_manifest.xlsx`.
- Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review\CableAccelCurrentVsCleaner_ReviewBoard.jpg`.
- Main stable review page now links to `current_vs_cleaner_review/index.html`.
- Render checks:
  - Current-vs-cleaner page: `9/9` images loaded, 9 table rows, 5 improved rows, 3 same rows.
  - Main stable page after linking: `19/19` images loaded, 9 strategy rows, 3 grid-picked rows, acceptance shown, ladder link, cleaner link, and comparison link present.
- Cleaner improves `CF-1/2/3/4/7` versus current and is identical for `CF-5/6/8`. The strongest improvements are `CF-3` and `CF-4`, with about `26%` additional RMS30 max reduction for about `3.8%` additional data loss.

## 2026-05-29 Zhishan Cable Acceleration Balanced Final Pick

- Added `scripts/build_zhishan_cable_accel_balanced_display_pick.m`.
- Purpose: automatically choose between current and cleaner per point using a simple rule, so the user does not need to manually promote individual points.
- Selection rule: choose cleaner when cleaner keep rate is `>=92%` and RMS improvement is `>=2%`; otherwise keep current.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick`.
- HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_manifest.xlsx`.
- Policy JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_policy.json`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_ContactSheet.jpg`.
- Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_ReviewBoard.jpg`.
- Main stable review page now links to `balanced_display_pick/index.html`.
- Selected cleaner for `CF-1/2/3/4/7`; selected current for `CF-5/6/8`.
- Render checks:
  - Balanced page: `10/10` images loaded, 9 table rows, 5 cleaner rows, 3 current rows.
  - Main stable page after linking: `19/19` images loaded, 9 strategy rows, 3 grid-picked rows, acceptance shown, ladder link, cleaner link, comparison link, and balanced link present.
- This is now the best automatic final display candidate, still display-only. Formal spectrum/force calculation remains unchanged.

## 2026-05-29 Zhishan Cable Acceleration Balanced Acceptance

- Added `scripts/validate_zhishan_cable_accel_balanced_display_pick.m`.
- Purpose: validate the automatic balanced final display pick as a machine-checkable acceptance gate.
- Output workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_acceptance.xlsx`.
- Output JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_acceptance.json`.
- Acceptance HTML: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\acceptance.html`.
- Acceptance screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\acceptance_render.png`.
- Main stable review page now links to `balanced_display_pick/acceptance.html`.
- Acceptance result:
  - Overall pass `1`.
  - All global checks pass: formal config unchanged, policy `display_only`, selection rule recorded, manifest has 8 points, HTML/contact sheet/review board exist.
  - All 8 point checks pass.
- Render checks:
  - Balanced acceptance page: `1/1` image loaded, 18 table rows, pass shown, 8 point `ok` rows.
  - Main stable page after linking: `19/19` images loaded, 9 strategy rows, 3 grid-picked rows, acceptance shown, balanced link and balanced acceptance link present.

## 2026-05-29 Zhishan Cable Acceleration Final Display Pack

- Added `scripts/publish_zhishan_cable_accel_final_display_pack.m`.
- Purpose: create a concise final user-facing entry for the automatic balanced final pick, separate from the full evidence/review pack.
- Final entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`.
- Final README: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\FINAL_README.md`.
- Final summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_summary.json`.
- Final rules workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.xlsx`.
- Final rules CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.csv`.
- Final render screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index_render.png`.
- Full review page now links to `final_index.html` as the default recommended entry.
- Render checks:
  - Final entry: `2/2` images loaded, 9 strategy rows, 5 cleaner rows, 3 current rows, balanced acceptance pass shown, rules link, full-pack link, and acceptance link present.
  - Main stable page after linking: `19/19` images loaded, final link present, acceptance shown.
- Final rules table now exposes each point's selected source, absolute threshold, RMS30 top-percent segment removal, keep rate, RMS30 max, and acceptance pass flag.
- This final page is now the default page to show the user; the broader `index.html` remains the complete review trail.

## 2026-05-29 Zhishan Cable Acceleration Final Report Images

- Added `scripts/export_zhishan_cable_accel_final_display_images.m`.
- Purpose: export the accepted automatic balanced final pick into a report-facing folder, without changing formal spectrum/force calculation settings.
- Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示`.
- HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\CableAccelFinalDisplay_manifest.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\CableAccelFinalDisplay_ContactSheet.jpg`.
- Review board: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\CableAccelFinalDisplay_ReviewBoard.jpg`.
- Per-point report images: `CableAccelFinalDisplay_CF-1_20260301_20260331.jpg` through `CableAccelFinalDisplay_CF-8_20260301_20260331.jpg`.
- Final exported mix:
  - `CF-1/2/3/4/7`: cleaner.
  - `CF-5/6/8`: current.
- File and render checks:
  - Report image page: 10 image refs, 0 missing/unreadable, 9 table rows, 5 cleaner rows, 3 current rows.
  - Report image render screenshot: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\index_render.png`, readable `1600x1200`.
  - Final entry after relinking report images: 2 image refs, 0 missing images, 9 table rows, 5 cleaner rows, 3 current rows, balanced acceptance pass shown, all required links present.
  - Final entry render screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index_render.png`, readable `1600x1000`.
- `publish_zhishan_cable_accel_final_display_pack.m` now adds links to the final report-image HTML and manifest in `final_index.html`, `FINAL_README.md`, and `CableAccelFinalDisplay_summary.json`.
- Formal cable-acceleration spectrum/force policy remains unchanged: `daily_median + [-100,100] m/s^2`. These final images are display/report outputs only.

## 2026-05-29 Zhishan Cable Acceleration Polished Min90 Candidate

- Added `scripts/build_zhishan_cable_accel_polished_min90_display_pick.m`.
- Purpose: create a stricter visual fallback when the balanced final pick still looks insufficient, without overwriting the safer final recommendation.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick`.
- HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\CableAccelPolishedMin90_manifest.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\CableAccelPolishedMin90_ContactSheet.jpg`.
- Render screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\index_render.png`.
- Selection target: keep at least `90%` of finite data and reduce RMS30 max more than the balanced final display.
- Result:
  - All 8 points pass the `>=90%` keep target.
  - Compared with balanced final, RMS30 max improves by `8.96%` on `CF-1`, `26.17%` on `CF-3`, `27.28%` on `CF-4`, `27.01%` on `CF-5`, `13.15%` on `CF-6`, `13.62%` on `CF-7`, and `6.18%` on `CF-8`; `CF-2` is unchanged.
  - Keep rates are approximately `90.31%~92.50%`.
- File checks passed: 9 image refs, 0 missing images, 9 table rows, 8 pass rows, 0 fail rows.
- Render screenshot is readable at `1600x1200`.
- Updated stable entry scripts:
  - `scripts/publish_zhishan_cable_accel_final_display_pack.m` links to polished min90 from the default final entry.
  - `scripts/publish_zhishan_cable_accel_display_review_pack.m` links to polished min90 from the full review pack and summary JSON.
- Re-published and checked:
  - `final_index.html`: 2 image refs, 0 missing images, 9 table rows, polished link present, acceptance present.
  - Full `index.html`: 19 image refs, 0 missing images, 9 table rows, polished link present, acceptance present.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Keep-Rate Ladder Review

- Added `scripts/build_zhishan_cable_accel_keep_ladder_review.m`.
- Purpose: stop one-off threshold retries by generating a full visual matrix across keep-rate targets for every cable-acceleration point.
- Keep targets: `95%`, `93%`, `92%`, `90%`, `88%`, `85%`.
- Method: reuse the existing threshold/RMS30 grid-search workbook, then recompute selected candidates on full data for each point and keep target.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review`.
- HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review\CableAccelKeepLadder_manifest.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review\CableAccelKeepLadder_ContactSheet.jpg`.
- Result:
  - `48` candidate rows: `8` points x `6` keep-rate targets.
  - Every point has all 6 target rows.
  - All selected rows pass their target keep-rate check after full-data recomputation.
  - HTML/file check passed: 9 image refs, 0 missing images, 49 table rows, 48 manifest rows.
- Useful examples from the matrix:
  - `CF-5`: `93%` keep gives RMS30 max `68.5`; `90%` keep gives `50.0`; `85%` keep gives `32.8`.
  - `CF-8`: `93%` keep gives `42.6`; `88%` keep gives `35.2`; `85%` keep gives `29.5`.
- Updated stable entry scripts:
  - `scripts/publish_zhishan_cable_accel_final_display_pack.m` links keep-ladder from the default final entry.
  - `scripts/publish_zhishan_cable_accel_display_review_pack.m` links keep-ladder from the full review pack and summary JSON.
- Re-published and checked:
  - `final_index.html`: 2 image refs, 0 missing images, 9 table rows, polished link present, keep-ladder link present, acceptance present.
  - Full `index.html`: 19 image refs, 0 missing images, 9 table rows, polished link present, keep-ladder link present, acceptance present.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Tradeoff Dashboard

- Added `scripts/build_zhishan_cable_accel_tradeoff_dashboard.m`.
- Purpose: turn the keep-rate ladder into a per-point keep-rate/RMS30 tradeoff curve and compute an automatic knee suggestion.
- Guardrail: the automatic suggestion is not allowed to be worse than the current balanced final pick; if no stricter candidate has enough net gain, it keeps the balanced final pick.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard`.
- HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard\index.html`.
- Suggestions workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard\CableAccelTradeoffDashboard_suggestions.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard\CableAccelTradeoffDashboard_ContactSheet.jpg`.
- Current automatic knee suggestions:
  - Keep balanced final for `CF-1`, `CF-2`, `CF-6`, `CF-7`, and `CF-8`.
  - `CF-3`: use keep-target `92%`, keep `92.674%`, RMS30 max `2.862`, `16.86%` below current final while keeping slightly more data.
  - `CF-4`: use keep-target `90%`, keep `90.354%`, RMS30 max `2.513`, `27.28%` below current final, with `1.67%` extra data loss.
  - `CF-5`: use keep-target `90%`, keep `90.396%`, RMS30 max `50.000`, `27.01%` below current final, with `3.11%` extra data loss.
- HTML/file check passed:
  - Tradeoff page: 9 image refs, 0 missing images, 9 table rows.
  - `final_index.html`: 2 image refs, 0 missing images, 9 table rows, tradeoff link present, keep-ladder link present.
  - Full `index.html`: 19 image refs, 0 missing images, 9 table rows, tradeoff link present, keep-ladder link present.
- Updated stable entry scripts:
  - `scripts/publish_zhishan_cable_accel_final_display_pack.m` links tradeoff dashboard from the default final entry.
  - `scripts/publish_zhishan_cable_accel_display_review_pack.m` links tradeoff dashboard from the full review pack and summary JSON.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Auto-Knee Display Pick

- Added `scripts/build_zhishan_cable_accel_auto_knee_display_pick.m`.
- Purpose: turn the tradeoff-dashboard knee suggestions into a complete 8-point visual candidate with single-point charts and a contact sheet.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick`.
- HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_manifest.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_ContactSheet.jpg`.
- Strategy:
  - Keep balanced final for `CF-1`, `CF-2`, `CF-6`, `CF-7`, and `CF-8`.
  - Use auto-knee stricter settings for `CF-3`, `CF-4`, and `CF-5`.
- Auto-knee candidate metrics:
  - `CF-3`: `abs<=5 + drop top 5% RMS30`, keep `92.674%`, RMS30 max `2.862`, `16.86%` below balanced final.
  - `CF-4`: `abs<=5 + drop top 8% RMS30`, keep `90.354%`, RMS30 max `2.513`, `27.28%` below balanced final.
  - `CF-5`: `abs<=50`, keep `90.396%`, RMS30 max `50.000`, `27.01%` below balanced final.
- Result:
  - Auto-knee pass `1`; all 8 rows pass.
  - HTML/file check passed: 9 image refs, 0 missing images, 9 table rows, 3 auto-knee rows, 5 balanced-final rows, 8 manifest rows.
  - Visual contact sheet was inspected.
- Updated stable entry scripts:
  - `scripts/publish_zhishan_cable_accel_final_display_pack.m` links auto-knee from the default final entry and summary JSON.
  - `scripts/publish_zhishan_cable_accel_display_review_pack.m` links auto-knee from the full review pack and summary JSON.
- Re-published and checked:
  - `final_index.html`: 2 image refs, 0 missing images, 9 table rows, auto-knee link present, tradeoff link present.
  - Full `index.html`: 19 image refs, 0 missing images, 9 table rows, auto-knee link present, tradeoff link present.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Auto-Knee Report Images

- Added `scripts/export_zhishan_cable_accel_auto_knee_report_images.m`.
- Purpose: export the auto-knee display candidate into a report-ready chart folder after the candidate passed numeric and visual checks.
- Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示`.
- HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示\CableAccelAutoKneeReport_manifest.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示\CableAccelAutoKneeReport_ContactSheet.jpg`.
- Per-point report images: `CableAccelAutoKneeReport_CF-1_20260301_20260331.jpg` through `CableAccelAutoKneeReport_CF-8_20260301_20260331.jpg`.
- File checks:
  - Auto-knee report page: 9 image refs, 0 missing images, 9 table rows, 3 auto-knee rows, 5 balanced-final rows, 8 manifest rows.
  - `final_index.html`: 2 image refs, 0 missing images, auto-knee report link present.
  - Full `index.html`: 19 image refs, 0 missing images, auto-knee report link present.
- Updated stable entry scripts:
  - `scripts/publish_zhishan_cable_accel_final_display_pack.m` links auto-knee report images and manifest from the default final entry and summary JSON.
  - `scripts/publish_zhishan_cable_accel_display_review_pack.m` links auto-knee report images from the full review pack and summary JSON.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration +/-20 Preview

- Ran `preview_zhishan_cable_accel_threshold(20)` for the user-requested `[-20,20] m/s^2` global preview.
- Output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20\cable_accel_threshold_preview.xlsx`.
- Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20\cable_accel_threshold_preview_abs20_review_board.jpg`.
- Keep rates:
  - `CF-1=66.157%`, `CF-2=54.897%`, `CF-3=99.821%`, `CF-4=99.821%`.
  - `CF-5=77.167%`, `CF-6=99.916%`, `CF-7=52.315%`, `CF-8=66.741%`.
- RMS30 max:
  - `CF-1=18.450`, `CF-2=17.860`, `CF-3=13.249`, `CF-4=13.335`.
  - `CF-5=19.920`, `CF-6=13.800`, `CF-7=19.365`, `CF-8=16.201`.
- Conclusion: single global `[-20,20]` is not a good final choice. It removes too much data for `CF-1/2/7/8`, leaves `CF-5` visually and statistically noisy, and does not beat the point-specific/auto-knee display candidates.
- This preview is diagnostic only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Balanced vs Auto-Knee Review

- Added `scripts/compare_zhishan_cable_accel_balanced_vs_auto_knee.m`.
- Purpose: make the automatic knee suggestion reviewable without switching between two separate folders.
- Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review`.
- HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review\index.html`.
- Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review\CableAccelBalancedVsAutoKnee_manifest.xlsx`.
- Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review\CableAccelBalancedVsAutoKnee_ContactSheet.jpg`.
- Visual layout: each point shows balanced final on the left and auto-knee on the right.
- Numeric result:
  - `CF-1`, `CF-2`, `CF-6`, `CF-7`, and `CF-8` are unchanged from balanced final.
  - `CF-3`: keep delta `+0.652%`, RMS30 max delta `+16.858%` improvement.
  - `CF-4`: keep delta `-1.668%`, RMS30 max delta `+27.279%` improvement.
  - `CF-5`: keep delta `-3.109%`, RMS30 max delta `+27.010%` improvement.
- Improved the contact sheet generation to use direct image composition instead of tiled axes, avoiding a large blank gap between rows.
- Re-published `final_index.html` and the full `index.html` review pack with links to `balanced_vs_auto_knee_review/index.html`.
- File checks passed:
  - Side-by-side page: 9 image refs, 0 missing images, 9 table rows, 3 auto-knee rows, 5 balanced-final rows.
  - Final entry: compare link present, 2 image refs, 9 table rows.
  - Full review entry: compare link present, 19 image refs, 9 table rows.
  - `git diff --check` passed for changed scripts/docs.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Auto-Knee Acceptance

- Added `scripts/validate_zhishan_cable_accel_auto_knee_display_pick.m`.
- Purpose: give the auto-knee candidate the same kind of auditable gate as the earlier balanced final pick.
- Output files:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\acceptance.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_acceptance.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_acceptance.json`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_acceptance.md`
- Acceptance result: pass `1`.
- Global checks passed:
  - Formal config still uses `daily_median + [-100,100]`.
  - Manifest has 8 points.
  - Auto-knee HTML/contact sheet/report-ready output/side-by-side comparison exist.
  - All point checks pass.
  - Candidate composition is exactly `3` auto-knee rows and `5` balanced-final rows.
- Point-level result:
  - `CF-3`: keep `92.674%`, RMS30 max improvement `16.858%`.
  - `CF-4`: keep `90.354%`, RMS30 max improvement `27.279%`.
  - `CF-5`: keep `90.396%`, RMS30 max improvement `27.010%`.
  - The remaining points are unchanged from balanced final and pass the unchanged-row checks.
- Re-published `final_index.html` and the full `index.html` review pack:
  - Default final entry now says auto-knee is the current first-review candidate.
  - Both entries link to `auto_knee_display_pick/acceptance.html`.
  - `CableAccelFinalDisplay_summary.json` and `CableAccelDisplayRecommendation_review_summary.json` expose the acceptance link.
- File checks passed:
  - Auto-knee acceptance page: 1 image ref, 0 missing images.
  - Final entry: 2 image refs, 0 missing images, auto-knee acceptance link present.
  - Full review entry: 19 image refs, 0 missing images, auto-knee acceptance link present.
  - `git diff --check` passed for changed scripts/docs.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Current-Best Pack

- Added `scripts/publish_zhishan_cable_accel_current_best_pack.m`.
- Purpose: make the accepted auto-knee candidate the stable current recommendation instead of leaving it only as a candidate page beside the older balanced table.
- Output files:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_rules.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_rules.csv`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_summary.json`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CURRENT_BEST_README.md`
- Current-best policy: accepted auto-knee candidate.
- Rules source: `auto_knee_display_pick/CableAccelAutoKnee_manifest.csv`.
- Rule mix:
  - Auto-knee: `CF-3`, `CF-4`, `CF-5`.
  - Balanced final retained: `CF-1`, `CF-2`, `CF-6`, `CF-7`, `CF-8`.
- Re-published `final_index.html` and full `index.html` with current-best links.
- File checks passed:
  - `current_best_index.html`: 2 image refs, 0 missing images, 9 table rows.
  - `final_index.html`: 2 image refs, 0 missing images, 9 table rows, current-best link present.
  - Full `index.html`: 19 image refs, 0 missing images, 9 table rows, current-best link present.
  - `CableAccelCurrentBestDisplay_summary.json` has `acceptance_pass=true` and `current_best_policy=Accepted auto-knee candidate`.
  - `git diff --check` passed for changed scripts/docs.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Final Rules Sync

- Updated `scripts/publish_zhishan_cable_accel_final_display_pack.m` so the default final rules table is no longer the older balanced manifest.
- New source for `CableAccelFinalDisplay_rules.xlsx/csv`: `auto_knee_display_pick/CableAccelAutoKnee_manifest.csv`.
- Current `CableAccelFinalDisplay_rules.csv` mix:
  - `auto_knee`: `CF-3`, `CF-4`, `CF-5`.
  - `balanced_final`: `CF-1`, `CF-2`, `CF-6`, `CF-7`, `CF-8`.
- `final_index.html` now labels the main table as `Current-Best Strategy`.
- `CableAccelFinalDisplay_summary.json` now records:
  - `acceptance_pass=true`
  - `auto_knee_acceptance_pass=true`
  - `balanced_acceptance_pass=true`
  - `current_best_entry=current_best_index.html`
- Re-published:
  - `current_best_index.html`
  - `final_index.html`
  - Full review `index.html`
- Verification:
  - `CableAccelFinalDisplay_rules.csv` was read back and confirmed to contain the auto-knee/current-best mix.
  - `final_index.html`: 2 image refs, 0 missing images, 9 table rows.
  - `current_best_index.html`: 2 image refs, 0 missing images, 9 table rows.
  - Full `index.html`: 19 image refs, 0 missing images, 9 table rows.
  - `git diff --check` passed for changed scripts/docs.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Current-Best Report Images

- Added `scripts/export_zhishan_cable_accel_current_best_report_images.m`.
- Purpose: create a neutral report-facing folder for the accepted current-best display, so report authors do not need to choose between older balanced and auto-knee-named folders.
- Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_当前最佳推荐展示`.
- Output files:
  - `index.html`
  - `CableAccelCurrentBestReport_manifest.xlsx`
  - `CableAccelCurrentBestReport_manifest.csv`
  - `CableAccelCurrentBestReport_ContactSheet.jpg`
  - `CableAccelCurrentBestReport_CF-1_20260301_20260331.jpg` through `CF-8`
- Rule mix remains:
  - `auto_knee`: `CF-3`, `CF-4`, `CF-5`.
  - `balanced_final`: `CF-1`, `CF-2`, `CF-6`, `CF-7`, `CF-8`.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m` so `current_best_index.html` links to the neutral current-best report-ready folder.
- Re-published current-best, final, and full review entries.
- File checks passed:
  - Current-best report page: 9 image refs, 0 missing images, 9 table rows.
  - Current-best entry: 2 image refs, 0 missing images, 9 table rows.
  - Final entry: 2 image refs, 0 missing images, 9 table rows.
  - Full review entry: 19 image refs, 0 missing images, 9 table rows.
  - Manifest workbook, manifest CSV, and contact sheet all exist.
  - Local `href` link checks passed for current-best entry, final entry, full review entry, and current-best report page: 0 missing targets.
  - `git diff --check` passed for changed scripts/docs.
- This remains display-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Current-Best Acceptance

- Added `scripts/validate_zhishan_cable_accel_current_best_pack.m`.
- Purpose: validate the whole current-best package after switching the default final rules and report-ready images to the accepted current-best mix.
- Output files:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_acceptance.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_acceptance.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_acceptance.json`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_acceptance.md`
- Ran:
  - `matlab -batch "addpath(genpath(pwd)); e = export_zhishan_cable_accel_current_best_report_images(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); disp(v.html);"`
- Acceptance result: pass `1`.
- Global checks passed:
  - Formal config still uses `daily_median + [-100,100]`.
  - Current-best summary has `acceptance_pass=true`.
  - Auto-knee acceptance has `pass=true`.
  - Current-best rules, final rules, and current-best report manifest each have 8 points.
  - Rule mix is exactly `3` auto-knee rows and `5` balanced-final rows.
  - All point checks pass.
  - Required files exist.
  - HTML image refs and local links pass for current-best, final, full review, and current-best report pages.
- Point checks passed for `CF-1` through `CF-8`; `CF-3/CF-4/CF-5` are auto-knee rows and the other five rows are balanced-final rows.
- Post-update checks passed: required current-best files exist, `CableAccelCurrentBestDisplay_acceptance.json` reports `pass=true`, and `git diff --check` passed for the changed current-best scripts/docs.
- This remains display/report-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Stricter Alternatives

- Re-exported the existing aggressive ladder tier:
  - Command: `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); r = export_zhishan_cable_accel_ladder_tier_display('aggressive'); disp(r.html);"`
  - Output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\aggressive_display_export\index.html`
  - Manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\aggressive_display_export\CableAccelAggressiveDisplay_manifest.xlsx`
- Added `scripts/compare_zhishan_cable_accel_current_best_vs_aggressive.m`.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_vs_aggressive_review\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_vs_aggressive_review\CableAccelCurrentBestVsAggressive_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_vs_aggressive_review\CableAccelCurrentBestVsAggressive_ReviewBoard.jpg`
- Aggressive vs current-best summary:
  - `CF-1`: keep `87.189%`, RMS30 max improvement `20.279%`.
  - `CF-2`: keep `85.803%`, RMS30 max improvement `24.544%`.
  - `CF-3`: keep `87.304%`, RMS30 max improvement `41.527%`.
  - `CF-4`: keep `86.928%`, RMS30 max improvement `33.121%`.
  - `CF-5`: keep `85.384%`, RMS30 max improvement `32.777%`.
  - `CF-6`: keep `87.273%`, RMS30 max improvement `28.982%`.
  - `CF-7`: keep `85.377%`, RMS30 max improvement `25.423%`.
  - `CF-8`: keep `86.025%`, RMS30 max improvement `30.734%`.
- Added `scripts/export_zhishan_cable_accel_target_keep_display.m`.
- Ran `export_zhishan_cable_accel_target_keep_display(80)`.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target80_display_export\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target80_display_export\CableAccelTarget80Display_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target80_display_export\CableAccelTarget80Display_ContactSheet.jpg`
- Target80 vs current-best RMS30 max improvements: `CF-1=29.593%`, `CF-2=31.540%`, `CF-3=17.075%`, `CF-4=6.411%`, `CF-5=44.362%`, `CF-6=47.200%`, `CF-7=33.178%`, `CF-8=46.472%`.
- Target80 keeps about `80%~82%` for most points, so it is cleaner but too aggressive for the default report recommendation.
- Wrote combined numeric summary: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_aggressive_target80_summary.csv`.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m`, `scripts/publish_zhishan_cable_accel_final_display_pack.m`, and `scripts/publish_zhishan_cable_accel_display_review_pack.m` so the stable entry pages link to `current_best_vs_aggressive_review` and `target80_display_export`.
- Re-published current-best, final, and full review entries.
- Re-ran `validate_zhishan_cable_accel_current_best_pack`; pass remained `1`, including HTML image/link checks.
- Current recommendation after this pass:
  - Default: keep current-best because it preserves at least `90%` finite data and passes acceptance.
  - First stricter backup: aggressive, if the user wants cleaner charts and accepts `85%~87%` keep rates.
  - Extreme visual reference: target80, if chart cleanliness matters more than data retention.
- This remains display/report-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Three-Level Tradeoff

- Added `scripts/compare_zhishan_cable_accel_three_level_review.m`.
- Purpose: avoid opening current-best, aggressive, and target80 outputs separately while deciding whether the charts are visually satisfactory.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\three_level_tradeoff_review\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\three_level_tradeoff_review\CableAccelThreeLevelTradeoff_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\three_level_tradeoff_review\CableAccelThreeLevelTradeoff_ReviewBoard.jpg`
- The page shows three columns per point: current-best, aggressive, and target80.
- Automatic next-review suggestions:
  - `CF-1`, `CF-2`, `CF-3`, `CF-4`, `CF-7`: `aggressive_first_backup`.
  - `CF-5`, `CF-6`, `CF-8`: `target80_visual_reference`.
- Re-published:
  - `current_best_index.html`
  - `final_index.html`
  - Full review `index.html`
- Re-ran `validate_zhishan_cable_accel_current_best_pack`; pass remained `1`, including HTML image/link checks.
- This remains display/report-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Visual-Best Mixed Pick

- Added `scripts/export_zhishan_cable_accel_visual_best_display.m`.
- Purpose: create one single stricter visual package from the three-level suggestions, so the user does not have to manually choose between aggressive and target80 point by point.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_best_display_export\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_best_display_export\CableAccelVisualBestDisplay_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_best_display_export\CableAccelVisualBestDisplay_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_best_display_export\CableAccelVisualBestDisplay_ReviewBoard.jpg`
- Selected tiers:
  - `aggressive`: `CF-1`, `CF-2`, `CF-3`, `CF-4`, `CF-7`.
  - `target80`: `CF-5`, `CF-6`, `CF-8`.
- RMS30 max improvement versus current-best:
  - `CF-1=20.279%`, `CF-2=24.544%`, `CF-3=41.527%`, `CF-4=33.121%`.
  - `CF-5=44.362%`, `CF-6=47.200%`, `CF-7=25.423%`, `CF-8=46.472%`.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m`, `scripts/publish_zhishan_cable_accel_final_display_pack.m`, and `scripts/publish_zhishan_cable_accel_display_review_pack.m` so stable entries link to the visual-best mixed pick.
- Re-published current-best, final, and full review entries.
- Re-ran `validate_zhishan_cable_accel_current_best_pack`; pass remained `1`, including HTML image/link checks.
- Current default remains current-best because it keeps at least `90%` of finite data. Visual-best is the stricter no-pick backup when chart cleanliness has priority.
- This remains display/report-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Retention Tradeoff Summary

- Ran `export_zhishan_cable_accel_target_keep_display(75)`.
- Target75 output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target75_display_export\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target75_display_export\CableAccelTarget75Display_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target75_display_export\CableAccelTarget75Display_ContactSheet.jpg`
- Target75 result:
  - `CF-1`: keep `76.337%`, RMS30 max `17.553`.
  - `CF-2`: keep `76.191%`, RMS30 max `22.826`.
  - `CF-3`: keep `89.056%`, RMS30 max `2.373`.
  - `CF-4`: keep `88.970%`, RMS30 max `2.352`.
  - `CF-5`: keep `75.330%`, RMS30 max `17.365`.
  - `CF-6`: keep `80.930%`, RMS30 max `3.529`.
  - `CF-7`: keep `79.307%`, RMS30 max `31.515`.
  - `CF-8`: keep `76.770%`, RMS30 max `19.625`.
- Added `scripts/publish_zhishan_cable_accel_retention_tradeoff_summary.m`.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\retention_tradeoff_summary\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\retention_tradeoff_summary\CableAccelRetentionTradeoff_summary.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\retention_tradeoff_summary\CableAccelRetentionTradeoff_summary.csv`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\retention_tradeoff_summary\CableAccelRetentionTradeoff_decisions.csv`
- Decision table:
  - `CF-1`, `CF-2`, `CF-5`: `target75_review_only`.
  - `CF-3`, `CF-4`, `CF-6`, `CF-7`, `CF-8`: `visual_best_backup`.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m`, `scripts/publish_zhishan_cable_accel_final_display_pack.m`, and `scripts/publish_zhishan_cable_accel_display_review_pack.m` so stable entries link to the retention tradeoff summary.
- Re-published current-best, final, and full review entries.
- Re-ran `validate_zhishan_cable_accel_current_best_pack`; pass remained `1`, including HTML image/link checks.
- This remains display/report-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Cleaner-Priority Report Images

- Rechecked the user-requested global `[-20,20] m/s^2` preview:
  - Folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20`
  - Keep rates: `CF-1=66.157%`, `CF-2=54.897%`, `CF-3=99.821%`, `CF-4=99.821%`, `CF-5=77.167%`, `CF-6=99.916%`, `CF-7=52.315%`, `CF-8=66.741%`.
  - Conclusion: `[-20,20]` is too destructive for a global formal rule.
- Added `scripts/export_zhishan_cable_accel_decisive_visual_report_images.m`.
- Exported neutral cleaner-priority report images:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_更干净优先展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_更干净优先展示\CableAccelDecisiveVisualReport_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_更干净优先展示\CableAccelDecisiveVisualReport_ContactSheet.jpg`
  - `CableAccelDecisiveVisualReport_CF-1_20260301_20260331.jpg` through `CableAccelDecisiveVisualReport_CF-8_20260301_20260331.jpg`.
- Selected tiers:
  - `target75`: `CF-1`, `CF-2`, `CF-5`.
  - `visual_best`: `CF-3`, `CF-4`, `CF-6`, `CF-7`, `CF-8`.
- Cleaner-priority keep/RMS30 max summary:
  - `CF-1 76.337% / 17.553`, `CF-2 76.191% / 22.826`, `CF-3 87.304% / 1.673`, `CF-4 86.928% / 1.681`.
  - `CF-5 75.330% / 17.365`, `CF-6 80.930% / 3.529`, `CF-7 85.377% / 36.045`, `CF-8 80.635% / 22.828`.
- Added `scripts/validate_zhishan_cable_accel_visual_alternatives.m`.
- Validation output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_alternatives_validation.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelVisualAlternatives_validation.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelVisualAlternatives_validation.json`
- Updated `current_best_index.html`, `final_index.html`, and full review `index.html` to link to the cleaner-priority report-ready image folder.
- Ran full refresh and validation:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); e = export_zhishan_cable_accel_decisive_visual_report_images(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
- `validate_zhishan_cable_accel_current_best_pack` pass remained `1`; `validate_zhishan_cable_accel_visual_alternatives` pass was `1`.
- `git diff --check` passed for the touched scripts/docs.
- Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`; all threshold search and cleaner-priority outputs remain display/report review only.

## 2026-05-29 Zhishan Cable Acceleration Cleanest70 Auto Pick

- Ran `export_zhishan_cable_accel_target_keep_display(70)` to test the 70% keep-rate floor:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target70_display_export\index.html`
- Target70 result:
  - `CF-1`: keep `76.337%`, RMS30 max `17.553`.
  - `CF-2`: keep `71.233%`, RMS30 max `20.660`.
  - `CF-3`: keep `89.056%`, RMS30 max `2.373`.
  - `CF-4`: keep `88.970%`, RMS30 max `2.352`.
  - `CF-5`: keep `71.762%`, RMS30 max `13.794`.
  - `CF-6`: keep `80.930%`, RMS30 max `3.529`.
  - `CF-7`: keep `70.126%`, RMS30 max `27.524`.
  - `CF-8`: keep `73.594%`, RMS30 max `17.544`.
- Added `scripts/export_zhishan_cable_accel_cleanest70_display.m`.
- Rule: for each point, choose the lowest RMS30 max candidate from generated tiers with keep `>=70%`.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\CableAccelCleanest70Display_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\CableAccelCleanest70Display_score_matrix.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\CableAccelCleanest70Display_ContactSheet.jpg`
- Selected tiers:
  - `CF-1`: `target75`, keep `76.337%`, RMS30 max `17.553`, improvement vs current-best `41.152%`.
  - `CF-2`: `target70`, keep `71.233%`, RMS30 max `20.660`, improvement `46.186%`.
  - `CF-3`: `aggressive`, keep `87.304%`, RMS30 max `1.673`, improvement `41.527%`.
  - `CF-4`: `aggressive`, keep `86.928%`, RMS30 max `1.681`, improvement `33.121%`.
  - `CF-5`: `target70`, keep `71.762%`, RMS30 max `13.794`, improvement `72.412%`.
  - `CF-6`: `target80`, keep `80.930%`, RMS30 max `3.529`, improvement `47.200%`.
  - `CF-7`: `target70`, keep `70.126%`, RMS30 max `27.524`, improvement `43.053%`.
  - `CF-8`: `target70`, keep `73.594%`, RMS30 max `17.544`, improvement `58.861%`.
- Updated stable entries and validation to include `target70` and `cleanest70`.
- Ran:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
- `validate_zhishan_cable_accel_current_best_pack` pass remained `1`; `validate_zhishan_cable_accel_visual_alternatives` pass was `1`.
- This is the strictest automatic visual backup so far and is not a formal/default replacement without user approval. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Cleanest70 Report Images

- Added `scripts/export_zhishan_cable_accel_cleanest70_report_images.m`.
- Exported neutral report-facing cleanest70 images:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最干净自动展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最干净自动展示\CableAccelCleanest70Report_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最干净自动展示\CableAccelCleanest70Report_ContactSheet.jpg`
  - `CableAccelCleanest70Report_CF-1_20260301_20260331.jpg` through `CableAccelCleanest70Report_CF-8_20260301_20260331.jpg`.
- Updated `current_best_index.html`, `final_index.html`, and full review `index.html` to link to the cleanest70 report folder.
- Updated `validate_zhishan_cable_accel_visual_alternatives.m` to check the cleanest70 report manifest, contact sheet, review board, 8 per-point images, and linked HTML page.
- Ran:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
- `validate_zhishan_cable_accel_current_best_pack` pass remained `1`; `validate_zhishan_cable_accel_visual_alternatives` pass was `1`.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; cleanest70 is display/report review only.

## 2026-05-29 Zhishan Cable Acceleration Decisive Visual Pick

- Added `scripts/export_zhishan_cable_accel_decisive_visual_display.m`.
- Purpose: create the strictest no-pick review package from the retention tradeoff decision table.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\decisive_visual_display_export\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\decisive_visual_display_export\CableAccelDecisiveVisualDisplay_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\decisive_visual_display_export\CableAccelDecisiveVisualDisplay_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\decisive_visual_display_export\CableAccelDecisiveVisualDisplay_ReviewBoard.jpg`
- Selected tiers:
  - `target75`: `CF-1`, `CF-2`, `CF-5`.
  - `visual_best`: `CF-3`, `CF-4`, `CF-6`, `CF-7`, `CF-8`.
- RMS30 max improvement versus current-best:
  - `CF-1=41.152%`, `CF-2=40.544%`, `CF-3=41.527%`, `CF-4=33.121%`.
  - `CF-5=65.270%`, `CF-6=47.200%`, `CF-7=25.423%`, `CF-8=46.472%`.
- Caveat: `CF-1`, `CF-2`, and `CF-5` keep rates are about `75%~76%`, so this is the strictest review backup and not the default recommendation.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m`, `scripts/publish_zhishan_cable_accel_final_display_pack.m`, and `scripts/publish_zhishan_cable_accel_display_review_pack.m` so stable entries link to the decisive visual pick.
- Re-published current-best, final, and full review entries.
- Re-ran `validate_zhishan_cable_accel_current_best_pack`; pass remained `1`, including HTML image/link checks.
- This remains display/report-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration `[-20,20]` Rerun

- Reran `preview_zhishan_cable_accel_threshold(20)` after the user's latest request.
- Output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_165624_abs20`.
- Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_165624_abs20\cable_accel_threshold_preview.xlsx`.
- Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_165624_abs20\cable_accel_threshold_preview_abs20_review_board.jpg`.
- Keep rates: `CF-1=66.157%`, `CF-2=54.897%`, `CF-3=99.821%`, `CF-4=99.821%`, `CF-5=77.167%`, `CF-6=99.916%`, `CF-7=52.315%`, `CF-8=66.741%`.
- Visual review: `CF-2` and `CF-7` remain heavily clipped around the `±20` boundaries; `CF-1` and `CF-8` also lose about one third of finite samples. `CF-3/CF-4/CF-6` keep almost all samples, which confirms the global threshold is uneven rather than a clean cross-point solution.
- Conclusion: keep `[-20,20]` as an exploratory preview only. Do not change the formal cable-acceleration configuration from `daily_median + [-100,100] m/s^2` based on this run.

## 2026-05-29 Zhishan Cable Acceleration Satisfaction-Auto Report Images

- Added `scripts/export_zhishan_cable_accel_satisfaction_auto_report_images.m`.
- Purpose: turn the `satisfaction_review` automatic recommendations into one neutral report-facing image folder, so the user does not need to manually combine cleaner-priority and cleanest70 folders.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_满意度自动推荐展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_满意度自动推荐展示\CableAccelSatisfactionAutoReport_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_满意度自动推荐展示\CableAccelSatisfactionAutoReport_ContactSheet.jpg`
  - `CableAccelSatisfactionAutoReport_CF-1_20260301_20260331.jpg` through `CF-8`.
- Selected tiers:
  - `cleaner_priority`: `CF-1`, `CF-3`, `CF-4`, `CF-6`.
  - `cleanest70`: `CF-2`, `CF-5`, `CF-7`, `CF-8`.
- Keep/RMS30 max summary:
  - `CF-1 76.337% / 17.553`, `CF-2 71.233% / 20.660`, `CF-3 87.304% / 1.673`, `CF-4 86.928% / 1.681`.
  - `CF-5 71.762% / 13.794`, `CF-6 80.930% / 3.528`, `CF-7 70.126% / 27.524`, `CF-8 73.594% / 17.544`.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m`, `scripts/publish_zhishan_cable_accel_final_display_pack.m`, `scripts/publish_zhishan_cable_accel_display_review_pack.m`, and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check this folder.
- Full refresh and validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = export_zhishan_cable_accel_satisfaction_auto_report_images(); s = compare_zhishan_cable_accel_satisfaction_review(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
- Visual-alternative validation now checks the satisfaction-auto manifest, contact sheet, review board, eight per-point images, and HTML links/images.
- This remains display/report-only. Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Low-Keep Tradeoff Review

- Ran additional target-keep exports:
  - `export_zhishan_cable_accel_target_keep_display(60)`
  - `export_zhishan_cable_accel_target_keep_display(50)`
- Added `scripts/export_zhishan_cable_accel_cleanest_keep_display.m`.
  - `cleanest60_display_export`: picks the lowest RMS30 max candidate per point with keep `>=60%`.
  - `cleanest50_display_export`: picks the lowest RMS30 max candidate per point with keep `>=50%`.
- Added `scripts/compare_zhishan_cable_accel_low_keep_review.m`.
  - Output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_tradeoff_review\index.html`
  - Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_tradeoff_review\CableAccelLowKeepTradeoff_Board.jpg`
  - Decision CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_tradeoff_review\CableAccelLowKeepTradeoff_decision.csv`
- Cleanest60 selected tiers:
  - `CF-1`: `target60`, keep `61.582%`, RMS30 max `12.484`.
  - `CF-2`: `target60`, keep `66.888%`, RMS30 max `17.786`.
  - `CF-3`: `aggressive`, keep `87.304%`, RMS30 max `1.673`.
  - `CF-4`: `aggressive`, keep `86.928%`, RMS30 max `1.681`.
  - `CF-5`: `target50`, keep `60.062%`, RMS30 max `9.258`.
  - `CF-6`: `target80`, keep `80.930%`, RMS30 max `3.528`.
  - `CF-7`: `target60`, keep `67.679%`, RMS30 max `23.907`.
  - `CF-8`: `target60`, keep `62.968%`, RMS30 max `12.395`.
- Low-keep decision:
  - Review `cleanest60` next for `CF-1`, `CF-2`, `CF-5`, `CF-7`, and `CF-8`.
  - Keep `satisfaction_auto` for `CF-3`, `CF-4`, and `CF-6`; lower-keep candidates do not improve RMS.
  - Treat `cleanest50` as an extreme fallback only for `CF-1`, `CF-2`, `CF-7`, and `CF-8`, because it lowers RMS further but drops keep rate to about `50%~53%`.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m`, `scripts/publish_zhishan_cable_accel_final_display_pack.m`, `scripts/publish_zhishan_cable_accel_display_review_pack.m`, and `scripts/validate_zhishan_cable_accel_visual_alternatives.m`.
- Full refresh and validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); r60 = export_zhishan_cable_accel_target_keep_display(60); r50 = export_zhishan_cable_accel_target_keep_display(50); c60 = export_zhishan_cable_accel_cleanest_keep_display(60); c50 = export_zhishan_cable_accel_cleanest_keep_display(50); lr = compare_zhishan_cable_accel_low_keep_review(); p = export_zhishan_cable_accel_satisfaction_auto_report_images(); s = compare_zhishan_cable_accel_satisfaction_review(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; these outputs are still display/review candidates only.

## 2026-05-29 Zhishan Cable Acceleration Low-Keep Auto Report Images

- Fixed `scripts/publish_zhishan_cable_accel_display_review_pack.m` so `writeReadme` defines the low-keep auto report folder before linking its manifest.
- Added/ran `scripts/export_zhishan_cable_accel_low_keep_auto_report_images.m`.
- Purpose: create one report-facing image folder from the low-keep tradeoff decision, avoiding manual mixing of `satisfaction_auto` and `cleanest60` outputs.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\CableAccelLowKeepAutoReport_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\CableAccelLowKeepAutoReport_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\CableAccelLowKeepAutoReport_ReviewBoard.jpg`
  - `CableAccelLowKeepAutoReport_CF-1_20260301_20260331.jpg` through `CF-8`.
- Selected tiers:
  - `cleanest60`: `CF-1`, `CF-2`, `CF-5`, `CF-7`, `CF-8`.
  - `satisfaction_auto`: `CF-3`, `CF-4`, `CF-6`.
- Keep/RMS30 max summary:
  - `CF-1 61.582% / 12.484`, `CF-2 66.888% / 17.786`, `CF-3 87.304% / 1.673`, `CF-4 86.928% / 1.681`.
  - `CF-5 60.062% / 9.258`, `CF-6 80.930% / 3.528`, `CF-7 67.679% / 23.907`, `CF-8 62.968% / 12.395`.
- Improvement versus satisfaction-auto RMS30 max:
  - `CF-1=28.876%`, `CF-2=13.909%`, `CF-5=32.883%`, `CF-7=13.142%`, `CF-8=29.350%`; `CF-3/CF-4/CF-6=0%` because they remain on satisfaction-auto.
- Full refresh and validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); lp = export_zhishan_cable_accel_low_keep_auto_report_images(); lr = compare_zhishan_cable_accel_low_keep_review(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
- Current judgment: this is the most useful next report-facing candidate if the user wants cleaner images than satisfaction-auto and accepts about `60%~68%` keep on the noisier points. `cleanest50` remains an extreme fallback only because `CF-1/CF-2/CF-7/CF-8` drop to about `50%~53%` keep.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; these outputs are still display/review candidates only.

## 2026-05-29 Zhishan Cable Acceleration Extreme Fallback Report Images

- Added `scripts/export_zhishan_cable_accel_extreme_fallback_report_images.m`.
- Purpose: generate the strictest report-facing fallback without manually selecting point images. It uses `cleanest50` only for points that the low-keep tradeoff decision marked as `cleanest50_extreme`; all other points keep the low-keep recommendation.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示\CableAccelExtremeFallbackReport_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示\CableAccelExtremeFallbackReport_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示\CableAccelExtremeFallbackReport_ReviewBoard.jpg`
  - `CableAccelExtremeFallbackReport_CF-1_20260301_20260331.jpg` through `CF-8`.
- Selected tiers:
  - `cleanest50`: `CF-1`, `CF-2`, `CF-7`, `CF-8`.
  - `cleanest60`: `CF-5`.
  - `satisfaction_auto`: `CF-3`, `CF-4`, `CF-6`.
- Keep/RMS30 max summary:
  - `CF-1 50.337% / 9.513`, `CF-2 50.988% / 12.132`, `CF-3 87.304% / 1.673`, `CF-4 86.928% / 1.681`.
  - `CF-5 60.062% / 9.258`, `CF-6 80.930% / 3.528`, `CF-7 50.614% / 15.453`, `CF-8 52.961% / 9.364`.
- Improvement versus satisfaction-auto RMS30 max:
  - `CF-1=45.805%`, `CF-2=41.276%`, `CF-5=32.883%`, `CF-7=43.856%`, `CF-8=46.625%`; `CF-3/CF-4/CF-6=0%`.
- Updated `scripts/publish_zhishan_cable_accel_current_best_pack.m`, `scripts/publish_zhishan_cable_accel_final_display_pack.m`, `scripts/publish_zhishan_cable_accel_display_review_pack.m`, and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` so stable pages link/check this folder.
- Full refresh and validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); ex = export_zhishan_cable_accel_extreme_fallback_report_images(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(a.pass);"`
- Current judgment: this is visually cleaner than the low-keep auto package for `CF-1/CF-2/CF-7/CF-8`, but it is intentionally labeled an extreme fallback because those four points keep only about `50%~53%` of display samples.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; these outputs are still display/review candidates only.

## 2026-05-29 Zhishan Cable Acceleration Low-Keep vs Extreme Decision Page

- Added `scripts/compare_zhishan_cable_accel_low_keep_vs_extreme_report.m`.
- Purpose: compare the low-keep auto report images against the extreme fallback images in one self-contained review folder, with explicit keep-rate loss and extra RMS30 gain per point.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_vs_extreme_report\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_vs_extreme_report\CableAccelLowKeepVsExtreme_decision.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_vs_extreme_report\CableAccelLowKeepVsExtreme_Board.jpg`
- Decision table:
  - `CF-1`: keep low-keep auto by default; extra RMS30 gain `23.8%` for `11.2%` keep loss.
  - `CF-2`: review extreme tradeoff; extra RMS30 gain `31.8%` for `15.9%` keep loss.
  - `CF-3`: same as low-keep auto.
  - `CF-4`: same as low-keep auto.
  - `CF-5`: same as low-keep auto.
  - `CF-6`: same as low-keep auto.
  - `CF-7`: review extreme tradeoff; extra RMS30 gain `35.4%` for `17.1%` keep loss.
  - `CF-8`: keep low-keep auto by default; extra RMS30 gain `24.5%` for `10.0%` keep loss.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check the new comparison page.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); cmp = compare_zhishan_cable_accel_low_keep_vs_extreme_report(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: if the user accepts the low-keep auto visual quality, keep that package as the safer report-facing candidate. If the user wants additional cleanup, only `CF-2` and `CF-7` clearly justify a close look at the extreme fallback based on extra RMS30 gain.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this comparison is display/review only.

## 2026-05-29 Zhishan Cable Acceleration Hybrid Recommended Report Images

- Added `scripts/export_zhishan_cable_accel_hybrid_recommended_report_images.m`.
- Purpose: create a single no-pick candidate that keeps the low-keep auto package by default, but switches the points marked `review_extreme_tradeoff` in the low-keep-vs-extreme decision table to the extreme fallback.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示\CableAccelHybridRecommendedReport_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示\CableAccelHybridRecommendedReport_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示\CableAccelHybridRecommendedReport_ReviewBoard.jpg`
- Selected packages:
  - `low_keep_auto`: `CF-1`, `CF-3`, `CF-4`, `CF-5`, `CF-6`, `CF-8`.
  - `extreme_fallback`: `CF-2`, `CF-7`.
- Keep/RMS30 max summary:
  - `CF-1 61.582% / 12.484`, `CF-2 50.988% / 12.132`, `CF-3 87.304% / 1.673`, `CF-4 86.928% / 1.681`.
  - `CF-5 60.062% / 9.258`, `CF-6 80.930% / 3.528`, `CF-7 50.614% / 15.453`, `CF-8 62.968% / 12.395`.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check the hybrid folder.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); h = export_zhishan_cable_accel_hybrid_recommended_report_images(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: this is the best single-folder candidate to show next. It improves the two most worthwhile points (`CF-2`, `CF-7`) while avoiding extra 50% retention cuts on `CF-1` and `CF-8`.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this comparison is display/review only.

## 2026-05-29 Zhishan Cable Acceleration Hybrid Recommended Parameters

- Added `scripts/build_zhishan_cable_accel_hybrid_recommended_parameters.m`.
- Purpose: convert the hybrid recommended image package into a structured parameter proposal with per-point `abs<=...` display threshold and `drop top ...% RMS30 segments` settings.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\CableAccelHybridRecommended_parameters.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\CableAccelHybridRecommended_parameters.csv`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\CableAccelHybridRecommended_parameters.json`
- Parsed display/review parameters:
  - `CF-1`: `abs<=20`, drop top `10%` RMS30 segments, keep `61.582%`, RMS30 max `12.484`.
  - `CF-2`: `abs<=20`, drop top `10%` RMS30 segments, keep `50.988%`, RMS30 max `12.132`.
  - `CF-3`: `abs<=3`, drop top `10%` RMS30 segments, keep `87.304%`, RMS30 max `1.673`.
  - `CF-4`: `abs<=3`, drop top `10%` RMS30 segments, keep `86.928%`, RMS30 max `1.681`.
  - `CF-5`: `abs<=10`, drop top `10%` RMS30 segments, keep `60.062%`, RMS30 max `9.258`.
  - `CF-6`: `abs<=5`, drop top `10%` RMS30 segments, keep `80.930%`, RMS30 max `3.528`.
  - `CF-7`: `abs<=20`, drop top `10%` RMS30 segments, keep `50.614%`, RMS30 max `15.453`.
  - `CF-8`: `abs<=20`, drop top `10%` RMS30 segments, keep `62.968%`, RMS30 max `12.395`.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check this parameter proposal.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = build_zhishan_cable_accel_hybrid_recommended_parameters(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: this is the reproducible parameter proposal for the hybrid display candidate. It is not written into formal config.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Refined55 Candidate

- Added `scripts/export_zhishan_cable_accel_refined55_report_images.m`.
- Added `scripts/build_zhishan_cable_accel_refined55_parameters.m`.
- Purpose: improve on the hybrid candidate after the `[-20,20]` global threshold trial. The rule is to keep the hybrid candidate and switch only `CF-8` to the `cleanest55` option, because `CF-2` and `CF-7` still need the 50% tier while `CF-8` has a useful middle option.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合55推荐展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合55推荐展示\CableAccelRefined55Report_manifest.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合55推荐展示\CableAccelRefined55Report_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\refined55_parameters\index.html`
- Selected packages:
  - `low_keep_auto`: `CF-1`, `CF-3`, `CF-4`, `CF-5`, `CF-6`.
  - `extreme_fallback`: `CF-2`, `CF-7`.
  - `cleanest55_refinement`: `CF-8`.
- Parameter summary:
  - `CF-1 abs<=20, drop top 10%, keep 61.582%, RMS30 max 12.484`.
  - `CF-2 abs<=20, drop top 10%, keep 50.988%, RMS30 max 12.132`.
  - `CF-3 abs<=3, drop top 10%, keep 87.304%, RMS30 max 1.673`.
  - `CF-4 abs<=3, drop top 10%, keep 86.928%, RMS30 max 1.681`.
  - `CF-5 abs<=10, drop top 10%, keep 60.062%, RMS30 max 9.258`.
  - `CF-6 abs<=5, drop top 10%, keep 80.930%, RMS30 max 3.528`.
  - `CF-7 abs<=20, drop top 10%, keep 50.614%, RMS30 max 15.453`.
  - `CF-8 abs<=15, drop top 2%, keep 55.826%, RMS30 max 10.567`.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check the refined55 image folder and parameter page.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p55 = build_zhishan_cable_accel_refined55_parameters(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: refined55 is the best current single-folder review candidate. It is still display/report-review only and does not change formal spectrum/force calculation.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Dense Auto-Visual Search

- Added `scripts/optimize_zhishan_cable_accel_auto_visual_search.m`.
- Purpose: replace manual threshold trial-and-error with a dense non-LLM search. The script searches display threshold and high-RMS segment deletion grids, assigns an adaptive per-point minimum keep floor, then exports one no-manual-pick image package.
- Search grid:
  - Absolute threshold: `3, 5, 7.5, 10, 12.5, 15, 17.5, 20, 25, 30, 40, 50, 75, 100 m/s^2`.
  - Top-RMS30 segment deletion: `0, 1, 2, 3, 5, 8, 10, 12, 15%`.
  - Search uses sampled data for speed and recomputes a short candidate list on the full March data before final selection.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_search\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_search\CableAccelAutoVisualSearch_score_matrix.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_search\CableAccelAutoVisualSearch_parameters.json`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示\CableAccelAutoVisualReport_ContactSheet.jpg`
- Selected parameters:
  - `CF-1`: `moderate_noise`, min keep `55%`, `abs<=17.5`, drop top `12%`, keep `55.220%`, RMS30 max `10.651`.
  - `CF-2`: `severe_noise`, min keep `50%`, `abs<=20`, drop top `12%`, keep `50.032%`, RMS30 max `11.925`.
  - `CF-3`: `stable_signal`, min keep `80%`, `abs<=3`, drop top `15%`, keep `83.076%`, RMS30 max `1.448`.
  - `CF-4`: `stable_signal`, min keep `80%`, `abs<=3`, drop top `15%`, keep `82.967%`, RMS30 max `1.478`.
  - `CF-5`: `mixed_noise`, min keep `60%`, `abs<=10`, drop top `10%`, keep `60.062%`, RMS30 max `9.258`.
  - `CF-6`: `stable_signal`, min keep `80%`, `abs<=5`, drop top `10%`, keep `80.930%`, RMS30 max `3.528`.
  - `CF-7`: `severe_noise`, min keep `50%`, `abs<=20`, drop top `12%`, keep `50.004%`, RMS30 max `15.088`.
  - `CF-8`: `moderate_noise`, min keep `55%`, `abs<=17.5`, drop top `15%`, keep `55.990%`, RMS30 max `10.499`.
- Fixed the auto-visual plot renderer so percentile bands split at missing intervals instead of drawing diagonal fill surfaces, and constrained the legend to the intended three items.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check the auto-visual search page, report image folder, 91-row full-data short-list score matrix, parameters JSON, manifest, contact sheet, review board, and eight per-point images.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: this is the best current non-manual candidate. It moves the workflow from manual `[-2,2]`, `[-10,10]`, `[-20,20]` trials to a repeatable dense search.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this output is display/report-review only.

## 2026-05-29 Zhishan Cable Acceleration Auto-Visual Review

- Added `scripts/compare_zhishan_cable_accel_auto_visual_review.m`.
- Purpose: compare the current dense auto-visual candidate with refined55 and the latest isolated `[-20,20] m/s^2` preview, then diagnose whether any score-matrix row gives a low-cost further cleanup.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\CableAccelAutoVisualReview_decision.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\CableAccelAutoVisualReview_Board.jpg`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\CableAccelAutoVisualReview_summary.json`
- Diagnosis summary:
  - `CF-2` and `CF-7` are `data_limited_at_floor`: both are already at the adaptive 50% keep floor.
  - `CF-1`, `CF-3`, `CF-4`, `CF-5`, `CF-6`, and `CF-8` are `near_knee`: no score-matrix candidate has meaningful low-cost RMS30 improvement over the current auto pick.
  - `±20` is worse as a global display rule: the auto-visual candidate reduces RMS30 max by `22.1%` to `89.1%` relative to the latest `±20` preview depending on point.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check the new review page, decision CSV, summary JSON, board, copied image sets, and HTML links/images.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); c = compare_zhishan_cable_accel_auto_visual_review(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: keep the current auto-visual candidate as the best non-manual report-review path. Further cleanup of `CF-2/CF-7` would require going below 50% retention and should be a user-approved tradeoff, not an automatic default.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this output is display/report-review only.

## 2026-05-29 Zhishan Cable Acceleration Ultra-Clean Review

- Added `scripts/build_zhishan_cable_accel_ultra_clean_review.m`.
- Purpose: quantify the final remaining tradeoff by searching only `CF-2` and `CF-7` below the current 50% keep floor.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanReview_decision.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanReview_Board.jpg`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanPackage_ContactSheet.jpg`
- Search grid:
  - Thresholds: `7.5, 10, 12.5, 15, 17.5, 20 m/s^2`.
  - Top-RMS30 segment deletion: `12, 15, 18, 20, 25, 30%`.
  - Keep floors evaluated: `45, 40, 35%`.
- Results:
  - `CF-2`: ultra-clean candidate `abs<=17.5`, drop top `20%`, keep `41.778%`, RMS30 max `10.143`; compared with current auto visual, keep loss `8.254%`, RMS30 gain `14.9%`.
  - `CF-7`: ultra-clean candidate `abs<=17.5`, drop top `12%`, keep `45.131%`, RMS30 max `12.899`; compared with current auto visual, keep loss `4.872%`, RMS30 gain `14.5%`.
- Both are marked `review_destructive_tradeoff`, not default recommendations.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to link/check the ultra-clean review page, package manifest, decision CSV, sample matrix, JSON, board, contact sheet, copied image sets, and HTML links/images.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); u = build_zhishan_cable_accel_ultra_clean_review(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: do not promote the below-50% options as the default. They give moderate visual/RMS improvement but clearly sacrifice more data; keep `auto_visual` as the default display/report candidate.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this output is display/report-review only.

## 2026-05-29 Zhishan Cable Acceleration Auto-Visual Final Entry

- Added `scripts/publish_zhishan_cable_accel_auto_visual_final_pack.m`.
- Purpose: replace the old auto-knee/balanced default stable entries with the latest dense auto-visual recommendation, so `current_best_index.html` and `final_index.html` no longer point to stale candidates.
- Updated stable files:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_acceptance.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_acceptance.json`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_rules.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.xlsx`
- Default report image package is now:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示\index.html`
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` text so the current-best/final notes describe auto-visual rather than auto-knee.
- Updated `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to check current-best/final 8-row rules and current-best/final JSON evidence.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); f = publish_zhishan_cable_accel_auto_visual_final_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(f.acceptance_pass); assert(rv.acceptance_pass); assert(a.pass);"`
- Current judgment: auto-visual is the default display/report candidate. Ultra-clean below-50% is retained only as an explicit backup for `CF-2/CF-7`.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration Auto Display Pipeline

- Added `scripts/run_zhishan_cable_accel_auto_display_pipeline.m`.
- Purpose: provide a single repeatable entry for the current索力加速度 display/report review workflow.
- `reuse` mode uses the existing dense auto-visual search output, then rebuilds:
  - auto-visual review;
  - ultra-clean below-50% backup review;
  - stable current-best/final entries;
  - stable review pack;
  - validation report.
- `full` mode reruns the dense auto-visual search before the same publish/validate sequence.
- Latest successful command:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = run_zhishan_cable_accel_auto_display_pipeline('reuse'); disp(p.final_index); disp(p.report_images); disp(p.validation_html);"`
- Output:
  - Final/default page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
  - Default report image package: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示\index.html`
  - Stable validation page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_alternatives_validation.html`
  - Summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelAutoDisplayPipeline_summary.json`
  - Readme: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\AUTO_DISPLAY_PIPELINE_README.md`
- Current judgment as of 2026-05-30: `strict_report_candidate` has superseded `auto_visual` as the stable final/current-best display recommendation. `auto_visual` remains the conservative baseline.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-30 Zhishan Cable Acceleration Strict Report Candidate

- Added `scripts/build_zhishan_cable_accel_strict_report_candidate.m`.
- Purpose: continue the threshold/search work beyond the conservative `auto_visual` default by building a cleaner display-only report candidate from the existing auto-visual score matrix plus the ultra-clean `CF-2/CF-7` review.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\CableAccelStrictReport_decision.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\CableAccelStrictReport_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\CableAccelStrictReport_CompareBoard.jpg`
- Selection rule:
  - Promote stricter score-matrix candidates when RMS30 gain is at least `3%` and keep loss is `<=5%`.
  - Promote ultra-clean `CF-2/CF-7` candidates when RMS30 gain is at least `10%`, keep loss is `<=10%`, and keep rate is `>=40%`.
- Result:
  - `CF-2`: `abs<=17.5`, drop top `20%`, keep `41.778%`, RMS30 max `10.143`, RMS30 gain `14.945%`.
  - `CF-5`: `abs<=10`, drop top `12%`, keep `59.113%`, RMS30 max `8.870`, RMS30 gain `4.192%`.
  - `CF-7`: `abs<=17.5`, drop top `12%`, keep `45.131%`, RMS30 max `12.899`, RMS30 gain `14.509%`.
  - `CF-8`: `abs<=15`, drop top `12%`, keep `52.152%`, RMS30 max `9.234`, RMS30 gain `12.046%`.
  - `CF-1/CF-3/CF-4/CF-6`: unchanged from `auto_visual`.
- Updated `scripts/run_zhishan_cable_accel_auto_display_pipeline.m` so `reuse` and `full` modes rebuild this strict candidate.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` and `scripts/validate_zhishan_cable_accel_visual_alternatives.m` so the stable review pack links and validates the strict candidate.
- Latest pipeline validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = run_zhishan_cable_accel_auto_display_pipeline('reuse'); disp(p.final_index); disp(p.report_images); disp(p.validation_html);"`
- Current judgment: `strict_report_candidate` is now the stable final/current-best display recommendation. It is cleaner than `auto_visual` but intentionally accepts lower retention on `CF-2/CF-7/CF-8`; formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-05-30 Zhishan Cable Acceleration Strict Final Entry

- Added `scripts/publish_zhishan_cable_accel_strict_final_pack.m`.
- Added `scripts/export_zhishan_cable_accel_strict_final_report_images.m`.
- Updated `scripts/run_zhishan_cable_accel_auto_display_pipeline.m` so step 5 exports strict report-ready images and publishes strict current-best/final entries instead of the conservative auto-visual final pack.
- Updated `scripts/validate_zhishan_cable_accel_visual_alternatives.m` with explicit checks:
  - `current_best_rules_strict_candidate`
  - `final_display_rules_strict_candidate`
  - strict final report manifest/images/contact sheet/review board/index.
- Current stable final/current-best outputs:
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_index.html`
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.csv`
- Current report-ready image package:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\CableAccelStrictFinalReport_manifest.csv`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\CableAccelStrictFinalReport_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\CableAccelStrictFinalReport_ReviewBoard.jpg`
- Final summary now reports:
  - `default_display_candidate = strict_report_candidate`
  - `report_images = ../时程曲线_索力加速度_严格最终推荐展示/index.html`
- Final rule sources:
  - `CF-1/CF-3/CF-4/CF-6`: `auto_visual_default`
  - `CF-2/CF-7`: `strict_ultra_clean`
  - `CF-5/CF-8`: `strict_score_matrix`
- Re-published the stable review pack after updating text so it no longer describes auto-visual as the default.
- Latest validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = run_zhishan_cable_accel_auto_display_pipeline('reuse'); disp(p.final_index); disp(p.report_images); disp(p.validation_html);"`
- Manual visual check opened `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\CableAccelStrictFinalReport_ContactSheet.jpg`; all 8 point panels rendered.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this is still a display/report-review promotion only.

## 2026-05-30 Zhishan Cable Acceleration Visual Priority Backup

- Added `scripts/build_zhishan_cable_accel_visual_priority_report_candidate.m`.
- Purpose: continue the automatic search after strict final by testing a more visually aggressive backup candidate, without changing the formal calculation.
- Output:
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\index.html`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_manifest.csv`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_decision.csv`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_ContactSheet.jpg`
  - `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_CompareBoard.jpg`
- Changes versus strict final:
  - `CF-1`: `abs<=15`, drop top `3%`, keep `52.079%`, band gain `13.15%`, RMS30 max `1.37%` worse.
  - `CF-2`: `abs<=15`, drop top `12%`, keep `39.441%`, RMS30 gain `11.68%`, band gain `13.64%`.
  - `CF-7`: `abs<=15`, drop top `18%`, keep `38.509%`, RMS30 gain `20.02%`, band gain `8.39%`.
  - Other points unchanged from strict final.
- Judgment: this is a useful review backup, not the default. It improves `CF-2/CF-7` visually but drops below 40% keep; strict final remains the better default unless the user chooses visual cleanliness over retention.
- Updated `scripts/publish_zhishan_cable_accel_display_review_pack.m` to link the visual-priority candidate.
- Updated `scripts/validate_zhishan_cable_accel_visual_alternatives.m` to check the visual-priority manifest, decision CSV, images, boards, JSON, index, and local HTML references.
- Validation passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

## 2026-06-01 Release v1.7.5 Preparation

- Prepared release `v1.7.5` after the Zhishan Bridge March data-processing iterations.
- Updated GUI version strings:
  - MATLAB GUI `ui/run_gui.m`: `v1.7.5`.
  - Report GUI `reporting/report_gui.py`: `v1.7.5`.
- Updated README/release notes and task-state documentation for the Zhishan March workflow.
- Final Zhishan formal config state before release:
  - Strain SX-1~SX-10: level-2 alarm bounds `[-200, 400]`, March cleaning `[-200, 200]`, group warning lines enabled.
  - Bearing displacement DX-1~DX-4: level-2 `[-80, 80]`, level-3 `[-100, 100]`, March cleaning `[-100, 100]`.
  - Cable acceleration CF-1~CF-8: unit label `mm/s^2`, daily median offset correction, per-point March cleaning and display limits:
    - CF-1/CF-2/CF-7/CF-8 cleaning `[-300, 300]`, plot y-limit `[-500, 500]`.
    - CF-5 cleaning `[-100, 120]`, plot y-limit `[-150, 150]`.
    - CF-3/CF-4/CF-6 cleaning `[-100, 100]`.
- Latest self-checks before release:
  - Strain group `.fig` contains 10 SX curves and warning lines at `-200` and `400`.
  - Cable acceleration `.fig` y-limits checked for CF-1/CF-2/CF-7/CF-8 `[-500, 500]` and CF-5 `[-150, 150]`.
  - Cable acceleration stats refreshed at `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_stats.xlsx`.
