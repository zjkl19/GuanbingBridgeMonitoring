# Hongtang Q2 2026 Recovery Notes

Last updated: 2026-07-06

This note records the accepted Hongtang Bridge 2026 Q2 recovery run and the
code changes that should be reused for later quarterly reruns.

## Accepted Outputs

The 2026-07-05 outputs below are retained as the original accepted baseline.
The latest accepted report after supplementing `2026-06-28` to `2026-06-30`
is recorded in the 2026-07-06 addendum.

- Production machine: `gb-133` / `192.168.100.133`
- Code root on 133: `F:\Guanbing`
- Data root on 133: `E:\洪塘大桥数据\2026年4-6月`
- Final full run:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_full_20260705_022000`
- Final RMS refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_rms_refresh_20260705_102937`
- Final checked report:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260705_105401_checked.docx`
- Final checked PDF:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260705_105401_checked.pdf`

Local render QA copied the report back, exported/rendered it, and produced 110
page PNGs. The rendered text check found no `错误`, `引用源未找到`, stale Q1
date text, or old `共 63 页` header text. The user manually spot-checked the Word
document on 133 and accepted it as basically OK.

## 2026-07-06 Accepted Addendum

- Supplemented date scope: only `2026-06-28` to `2026-06-30`.
- Late-June source patch:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_donghua_patch_20260706_061724`
- Final high-frequency refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_patch_refresh_20260706_063728`
- Final RMS refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_patch_rms_refresh_20260706_083341`
- Final checked report:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_090831_checked.docx`
- Final checked Word-exported PDF:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_090831_checked.pdf`
- Report generation runtime: `146.629` seconds; Word export produced `79`
  pages.
- Local render QA copied the report bundle back to
  `D:\MatlabProjects\Guanbing\tmp\docs\hongtang_q2_patch_report_20260706_090700`,
  rendered the Word PDF, and found no `错误`, `引用源未找到`, stale Q1 date
  text, old `共 63 页` header text, or mojibake error/reference text.
- The affected high-frequency modules were rerun: wind, earthquake,
  acceleration, cable acceleration, acceleration spectrum, and cable
  acceleration spectrum.
- RMS refresh rebuilt acceleration and cable-acceleration RMS artifacts:
  acceleration `12/12`, cable acceleration `24/24`, no skipped points.
- Canonical MAT caches were generated for wind speed/direction and earthquake
  channels for the patched days before deleting direct wave CSV.
- MAT-only smoke passed before and after deleting direct `波形\*.csv` for the
  patched dates. Deletion scope was only those direct wave CSVs:
  `417` files / `37,572,244,652` bytes. Feature CSV files were retained.

### Wind/Earthquake Figure Correction

After user review, the wind and earthquake figures in the 09:08 report were
found to stop near 2026-06-27. The recovered 2026-06-28 to 2026-06-30 waveform
files existed, but their Donghua names were timestamp based
(`风速_*.csv`, `塔顶风速_*.csv`, `X_*.csv`, `Y_*.csv`, `Z_*.csv`) and did not
include the configured numeric IDs (`风速_162`, `X_144`, etc.). The first plot
refresh happened before the canonical MAT aliases were generated.

Corrective actions:

- Added Hongtang per-point timestamp fallback patterns for W1/W2 wind
  speed/direction and EQ-X/Y/Z while keeping exact `{file_id}.csv` first.
- Reran wind and earthquake on 133 after the canonical MAT aliases existed:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_wind_eq_refresh_20260706_0945`.
- Regenerated the report:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_105133_wind_eq_checked.docx`
  and PDF:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_105133_wind_eq_checked.pdf`.
- Figure-axis checks confirmed W1/W2 wind speed/direction ended at
  `2026-06-30 09:00:02`, W1/W2 10-minute wind figures ended at
  `2026-06-30 23:55`, and EQ-X/Y/Z ended at `2026-06-30 09:00:05`.

## Root Causes Found

1. Cable-acceleration cable-force gaps were not only raw-data gaps.
   The main code causes were:
   - Hongtang Q2 dated folders were not preferred consistently.
   - Time-series cache matching was loose enough to reuse stale data.
   - The CS8 offset rule in `config/hongtang_config.json` pushed otherwise valid
     raw values outside the usable range.
   - Full-quarter high-frequency arrays were too large for stable plotting/RMS
     generation.

2. `plot_common.gap_mode=connect` existed in config but was not propagated
   through all plot services. Some module plotters still called
   `prepare_plot_series` without runtime options.

3. Wind speed/direction data existed, but full-quarter loading tried to hold too
   much data at once. The old path could look like missing output even when raw
   source data was available.

4. Report QC checked the DOCX structure but did not prove rendered Word fields.
   On 133, Python lacked `pythoncom/win32com`; Word COM itself existed, so the
   old Python-only field update silently left cross-references/page fields at
   risk until the report was exported/rendered elsewhere.

5. Some gaps remain true source-data gaps. In particular, late-June
   high-frequency data is incomplete. `gap_mode=connect` connects finite plotted
   points; it does not synthesize absent raw days.

## Code Changes

- `+bms/+data/TimeSeriesRangeLoader.m`
  - Prefer standard dated folders under the period root for Hongtang Q2.

- `+bms/+data/TimeSeriesLoader.m`
  - Tighten cache metadata matching so stale loads are not reused across changed
    point/date/sensor requests.

- `pipeline/prepare_plot_series.m` and `+bms/+plot/PlotService.m`
  - Add runtime plot options and propagate `gap_mode`.

- Plot services and pipelines
  - Propagate runtime plot options into acceleration, cable acceleration, strain,
    dynamic strain, GNSS, wind, earthquake, spectrum and scalar-series plots.

- `+bms/+analyzer/DynamicSeriesService.m`
  - Add by-day collection for acceleration and cable acceleration.
  - Downsample plot series by configured `plot_common.fig_max_points`.
  - Compute RMS by time bins and keep RMS series for report plots/groups.

- `+bms/+analyzer/DynamicAccelerationSeriesService.m`
  - Reuse collected records for individual plots and group plots instead of
    reloading the full quarter.

- `+bms/+analyzer/WindSeriesService.m`
  - Aggregate wind speed/direction by day and generate 10-minute curves without
    full-quarter memory spikes.

- `+bms/+analyzer/EarthquakeSeriesService.m`
  - Collect by day, preserve peak metadata, and downsample plot series.

- `config/hongtang_config.json`
  - Set `plot_common.gap_mode` to `connect`.
  - Set a bounded `plot_common.fig_max_points`.
  - Remove the bad CS8 offset rule.

- `scripts/refresh_dynamic_rms_only.m`
  - Add a targeted refresh entrypoint for dynamic RMS artifacts after loader/RMS
    fixes.

- `reporting/build_period_report.py`
  - Fall back from missing Python COM to PowerShell Word COM.
  - Run PowerShell through a temporary `.ps1` with `-File`, which is more stable
    on 133 than a long `-Command` string.
  - Return field-update failures as report-manifest warnings.

- `reporting/analysis_manifest.py` and report builder warning handling
  - Avoid stale preflight warnings masking successful module reruns.

## Verification Commands

Local Python:

```powershell
C:\Users\eamdf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe -m unittest tests_py.test_build_period_report_word_update tests_py.test_report_qc tests_py.test_analysis_manifest
```

Local MATLAB:

```powershell
matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); issues = checkcode('scripts/refresh_dynamic_rms_only.m'); disp(numel(issues)); results = runtests({'tests/test_dynamic_series_service.m','tests/test_bms_services.m'}); assertSuccess(results);"
```

Remote 133 report-field fallback:

```powershell
ssh -p 2222 dell@192.168.100.133
cd /d F:\Guanbing
D:\Python310\python.exe -m unittest tests_py.test_build_period_report_word_update
```

For a real smoke test, copy an existing report DOCX to a temporary path and run
`update_fields_with_word()` from `reporting/build_period_report.py`. The
accepted smoke test returned `WORD_UPDATE_WARNINGS=[]`.

## Operational Notes

- For 133, prefer git-based code updates after the `v1.7.14` commit is pushed.
  Before pulling, verify `git status --short`; the 133 worktree had matching
  dirty files during the accepted run.
- Keep generated reports, rendered PNGs, run logs and copied report artifacts
  out of git.
- If another quarterly report shows sudden widespread missing high-frequency
  data, first check dated-folder layout, stale cache metadata, and per-point
  offset rules before assuming raw source data is absent.
- If rendered reports show field errors or old page counts, inspect the Word
  field-update path and render/export the generated DOCX before accepting it.
