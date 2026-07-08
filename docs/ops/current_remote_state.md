# Current Remote State

Last updated: 2026-07-08 20:05 CST

This file is the recoverable status anchor for remote machines and long-running
jobs. It complements `docs/current_task_state.md`; use this file for operations
state and keep algorithm/report decisions in the normal project docs.

## Access Summary

- `gb-133`: `ssh -p 2222 dell@192.168.100.133`
- `gb-126`: WinRM verified with `Administrator`; SSH port 22 exists but should
  be verified before relying on it.
- `gb-office`: `ssh gb-office "hostname; whoami"` after installing
  `docs/ops/ssh_config.template`. The actual path is
  `Administrator@192.168.254.34:2222` through `ProxyJump gb-133`; direct SSH
  from this workstation is not routable.
- 126 storage target: `\\192.168.100.126\H$\Guanbingwork`

## gb-133 Zhishan April 2026 Refinement

- Status: completed on 2026-07-08.
- Production data root:
  `F:\芝山大桥数据\2026年4月`.
- Code was copied to `F:\Guanbing` for the production run; after local commit
  and push, sync 133 with git so the remote worktree returns to a clean same-HEAD
  state.
- Full/refinement task directories:
  - `F:\Guanbing\run_logs\remote_tasks\zhishan_202604_refine_20260708_1500`
  - `F:\Guanbing\run_logs\remote_tasks\zhishan_202604_cable_resume_20260708_1615`
- Important operational note:
  - the first full run stalled at cable acceleration `CF-5` after logging
    `2026-04-30`; CPU was idle and the batch PIDs were stopped;
  - cause was a valid raw MAT cache whose metadata source path was stored as
    mojibake, so the loader falsely missed the cache and fell back to rereading
    the 131 MB CSV;
  - after syncing the cache fingerprint fix, `CF-5` cache validation returned
    `cache_ok=true` in `0.30` seconds.
- Cable resume result:
  - `status.json`: `stage=complete`, `status=ok`;
  - offset rows: `8`;
  - offset log:
    `F:\芝山大桥数据\2026年4月\run_logs\offset_correction_applied_20260708_162311.xlsx`;
  - updated stats:
    `F:\芝山大桥数据\2026年4月\stats\cable_accel_stats.xlsx`,
    `F:\芝山大桥数据\2026年4月\stats\cable_accel_spec_stats.xlsx`.
- Report generated on 133:
  `F:\芝山大桥数据\2026年4月\自动报告\芝山大桥健康监测2026年4月份月报_自动生成_20260708_162640.docx`.
- Report manifest:
  `F:\芝山大桥数据\2026年4月\自动报告\zhishan_report_build_manifest_20260708_162640.json`.
  Result: `status=ok`, `warnings=[]`, `missing_count=0`,
  `output_docx_image_count=58`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_202604_refine_20260708`.
  Rendered page count: `47`; text QA found no reference errors, placeholders,
  or stale `2026年3月`.

## gb-133 Zhishan May/June 2026 Refinement

- Status: completed on 2026-07-08.
- Production data roots:
  - `F:\芝山大桥数据\2026年5月`
  - `F:\芝山大桥数据\2026年6月`
- Code/config was temporarily copied to `F:\Guanbing` for production
  validation before commit. After the local commit and push, fast-forward
  `F:\Guanbing` from git so the remote worktree returns to a clean same-HEAD
  state.
- Focused remote validation task:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_202605_202606_prepare_20260708_182139`.
  It confirmed MATLAB resolved
  `F:\Guanbing\pipeline\resolve_post_filter_thresholds.m` and passed:
  `tests/test_zhishan_config.m`, `tests/test_post_filter_thresholds.m`,
  and `tests/test_time_series_loader.m`.
- Full/refinement task directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_202605_202606_run_20260708_182426`.
  - May analysis: `...\202605`; completed successfully.
  - June analysis: `...\202606`; completed successfully.
- Operational note:
  background `Start-Process matlab` did not keep the batch run alive under SSH
  in this session and produced no status file; foreground
  `matlab -sd <taskDir> -batch run_task` completed normally. Prefer the
  foreground pattern or a scheduled-task wrapper for long unattended runs.
- Source-data note:
  `F:\芝山大桥数据\2026年6月` is missing the `2026-06-19` dated source folder.
- Stats QA:
  `0` threshold violations across bearing displacement, static strain,
  dynamic-strain high/lowpass, and cable acceleration. Cable spectrum sheets
  contain `31` rows for May and `30` rows for June.
- Report outputs:
  - `F:\芝山大桥数据\2026年5月\自动报告\芝山大桥健康监测2026年5月份月报_自动生成_20260708_195300.docx`
  - `F:\芝山大桥数据\2026年6月\自动报告\芝山大桥健康监测2026年6月份月报_自动生成_20260708_195312.docx`
- Report manifests:
  - `F:\芝山大桥数据\2026年5月\自动报告\zhishan_report_build_manifest_20260708_195300.json`
  - `F:\芝山大桥数据\2026年6月\自动报告\zhishan_report_build_manifest_20260708_195312.json`
  Both returned `status=ok`, `warnings=[]`, `missing_count=0`, and
  `output_docx_image_count=58`.
- Local QA bundle:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_202605_202606_20260708_195312`.
  Both reports rendered to `47` PNG pages and passed text/visual spot checks.

## Donghua PHM Exports On 126

### Hongtang Bridge Scheduled Export Recovery

- Status: completed on 2026-07-06 02:01 CST.
- Scope recovered: scheduled Donghua exports for 2026-06-28 to 2026-07-05,
  both `Wave_Export_Task_*` and `Eigen_Export_Task_*`.
  - 2026-06-28 to 2026-07-03 had original PHM task rows and DataCenter
    records.
  - 2026-07-04 and 2026-07-05 had DataCenter timing records and incomplete
    direct CSV folders but no matching PHM `et_system_task` rows; they were
    recovered by updating the original DataCenter records.
- Formal output root:
  `H:\DHtest\定时导出\<date>\波形` and
  `H:\DHtest\定时导出\<date>\特征值`.
- Final validation:
  - Each recovered date has one wave zip, one eigen zip, and one
    `condition.param` in each output folder.
  - All 12 original PHM task records from 2026-06-28 to 2026-07-03 have
    `ExecuteStatus=1`, `ExecuteProgress=1`, and paths that exist on disk.
  - All 16 matching DataCenter export records from 2026-06-28 to 2026-07-05
    have `ExportStatus=1`, `ExportingProgress=1`, and paths that exist on disk.
  - All recovered zips have `139` entries and include the previously missing
    key patterns: `CX3`, wind speed/direction, tower wind speed/direction, and
    sanitized point names for point IDs 83 and 84.
- Initial 2026-06-28 to 2026-07-03 validation:
  - All 12 original PHM task records had `ExecuteStatus=1`,
    `ExecuteProgress=1`, and paths that exist on disk.
  - All 12 matching DataCenter export records have `ExportStatus=1`,
    `ExportingProgress=1`, and paths that exist on disk.
  - Each recovered zip has `139` entries and includes the previously missing
    key patterns: `CX3`, wind speed/direction, tower wind speed/direction, and
    sanitized point names for point IDs 83 and 84.
- Root cause: point IDs 83 and 84 had PHM point names containing `/`, which
  DataCenter used as part of CSV file names during scheduled export. Windows
  treated the slash as a path separator, so the exporter failed around point 83
  and later points such as cable-force, wind, and CX were not exported.
- Permanent point-name fix applied through PHM API:
  - Point 83: `C1802190786_GD1-2`
  - Point 84: `S25020650541_GL3-4`
- Important scripting note: when calling DataCenter export APIs from Windows
  PowerShell 5.1, send JSON as UTF-8 bytes with
  `application/json; charset=utf-8`. Passing a PowerShell string body can
  corrupt Chinese file names and create invalid-path false failures.
- Recovery log and script on 126:
  - `H:\DHtest\codex_recovery_logs\recover_failed_exports_20260705_220106.log`
  - `H:\DHtest\codex_recovery_logs\recover_failed_exports_20260705_215338_bom.ps1`
  - `H:\DHtest\codex_recovery_logs\recover_0704_0705_exports_20260706_005603.log`
  - `H:\DHtest\codex_recovery_logs\recover_0704_0705_exports_20260706.ps1`
- Failed pre-recovery output folders were moved to:
  `H:\DHtest\定时导出_codex_backup\20260705_220106`.
- Incomplete 2026-07-04 and 2026-07-05 folders were moved to:
  `H:\DHtest\定时导出_codex_backup\0704_0705_20260706_005603`.
- Cleanup already done: removed the one-shot Windows scheduled task
  `Codex_DHRecover_20260705_2158`, removed one-shot task
  `Codex_DHRecover_0704_0705_20260706`, and removed temporary Codex PHM UI
  task rows. Recovery logs and backup folders were retained.
- 2026-07-06 09:00 automatic run after the point rename succeeded. At
  09:32 CST, `H:\DHtest\定时导出\2026-07-06` contained one wave zip and one
  eigen zip, both readable and both with `139` entries. Temporary CSV files
  were gone, and both zips included `CX3` plus wind speed/direction entries.
  Vendor support is not needed for this incident unless a later scheduled
  export fails again.

## Office PC DESKTOP-500FVB6

- Alias: `gb-office`.
- Host: `192.168.254.34`, reachable from 133 but not directly from this
  workstation.
- Verified command on 2026-07-01 after service handoff:
  `ssh -J dell@192.168.100.133:2222 -p 2222 Administrator@192.168.254.34 "hostname; whoami"`.
- Result: `DESKTOP-500FVB6`, `desktop-500fvb6\administrator`.
- OpenSSH note: Windows `sshd` service is now `Running` / `Automatic` and
  listens on TCP 2222 through `C:\Windows\System32\OpenSSH\sshd.exe -D`.
- Root cause of earlier service startup failure: host private key files under
  `C:\ProgramData\ssh` had owner `DESKTOP-500FVB6\Administrator`; OpenSSH
  service mode rejected them as too open. Owner was changed to `SYSTEM` and ACL
  was reduced to `SYSTEM` plus `BUILTIN\Administrators`.
- Scheduled-task fallback `Guanbing-OpenSSH-2222-OfficePC-Fallback` is retained
  as manual recovery only; it is not running after the successful handoff.
- Use this machine for office file cleanup and light remote-control tasks only;
  avoid heavy MATLAB/report jobs unless explicitly requested.

## Active Remote Tasks On 133

### Hongtang Bridge Q2 SL-8 Negative Strain Cleaning

- Status: completed on 2026-07-07 17:31 CST.
- 133 code state during validation: `F:\Guanbing` had a working-tree patch on
  top of `109a7bd` / `v1.7.22`.
- Final 133 code state: clean `F:\Guanbing` at the committed `origin/main`
  state for this `SL-8` cleanup.
- Config policy applied:
  - `SL-8` static strain now cleans values `< 0` and `> 150`;
  - other static-strain thresholds, alarm bounds, and offset corrections were
    not changed.
- Remote focused MATLAB tests passed:
  `tests/test_config_integration_regression.m`,
  `tests/test_hongtang_lowfreq_loader.m`,
  `tests/test_cleaning_pipeline.m`,
  `tests/test_post_filter_thresholds.m`.
- Strain rerun:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_sl8_negative_clean_20260707_172058`
  - Run status: `ok`.
  - MATLAB elapsed inside run: `352.20` seconds.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\strain_stats.xlsx`.
  - Analysis manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260707_172811.json`.
  - Stats check: `SL-8 Min=0.378`, `Max=127.25`, `Mean=75.545`.
- Report regeneration:
  - DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260707_173019.docx`.
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260707_173019.json`.
  - Manifest status: `ok`; `missing_count=0`; `report_qc_status=ok`; report
    number `BG02FQJC2600002-J2`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_sl8_negative_clean_20260707_173019`.
- Render note: local Word COM automation was unavailable in this run, and
  133 Word COM direct PDF export failed to open the regenerated DOCX. The
  DOCX/manifest/QC/stat checks passed, but strict Word-rendered PDF evidence
  was not produced in this run.

### Hongtang Bridge Q2 v1.7.22 Period Template Hardening

- Status: completed on 2026-07-07 15:25 CST.
- 133 code state during validation: `F:\Guanbing` had the `v1.7.22`
  working-tree patch applied on top of `f1c9b21` / `v1.7.21`.
- Final 133 code state: clean `F:\Guanbing` at `origin/main` / `v1.7.22`.
  The pre-publish validation patch is retained as
  `stash@{0}: pre_v1722_validation_backup`.
- Remote focused tests passed with `D:\Python310\python.exe`:
  `tests_py.test_docx_image_blocks`,
  `tests_py.test_wim_auto_captions`,
  `tests_py.test_build_period_report_word_update`,
  `tests_py.test_hongtang_period_followups`,
  `tests_py.test_bridge_profiles`.
- Remote compile check passed for `reporting` and `tests_py`.
- Report generation:
  - Runtime `110.38` seconds, below the 10-minute failure threshold.
  - DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260707_150151.docx`.
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260707_150151.json`.
  - Manifest status: `ok`; `missing_count=0`; `warnings_count=0`;
    `report_qc_status=ok`; report number `BG02FQJC2600002-J2`.
  - Checked PDF copied back to 133:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_template_report_20260707_150151_word_checked.pdf`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_template_report_20260707_150151`.
  - Word COM exported an `82` page PDF; all `82` pages rendered to PNG.
  - PDF text checks found no missing-reference/bookmark/template-token errors.
  - Visual spot checks covered the cover, alarm table, WIM/strain transition,
    acceleration plots, wind rose/table, and earthquake pages.
- Bugs fixed during validation:
  - copied WIM continuation tables from a manual template can be structurally
    incompatible with the generated 12-column continuation data; the generator
    now validates row/column access and falls back to a standard table;
  - using a filled report as a template can retain old picture blocks before
    captions; the generator now removes stale picture/short-label blocks before
    inserting fresh figures.
- Publish/sync note: direct GitHub `fetch/pull` on 133 hung during this run, so
  the final fast-forward was completed through a local git bundle copied from
  the development machine. The temporary bundle was deleted after sync.

### Hongtang Bridge Q2 v1.7.21 Plot Extrema Consistency

- Status: completed on 2026-07-06 21:45 CST.
- 133 code state: `F:\Guanbing` has the current `v1.7.21` working-tree patch
  applied on top of `e2f32e6` / `v1.7.20` for production verification.
- Task directory:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_extrema_20260706_210820`.
- Remote earthquake rerun:
  - RunSession elapsed `91.56` seconds; module run elapsed `86.08` seconds.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\eq_stats.xlsx`.
  - Analysis manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260706_211605.json`.
  - New stats values: `EQ-X 0.005`, `EQ-Y 0.018`, `EQ-Z 0.019` m/s^2.
- Remote `.fig` validation passed: `EQ-X`, `EQ-Y`, and `EQ-Z` each matched
  the regenerated stats row against the plotted curve, red marker, and text
  label within display precision.
- Report generation:
  - Runtime `87.27` seconds.
  - DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_213107.docx`.
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_213107.json`.
  - Checked PDF copied back to 133:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_period_v1721_20260706_213107_word_checked.pdf`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_v1721_20260706_213107`.
  - Manifest `status=ok`, `missing_count=0`, `warnings=0`,
    `report_qc_status=ok`.
  - Independent report QC passed with `0` issues.
  - Word COM exported an `81` page PDF; all `81` pages rendered to PNG.
  - Rendered PDF text states earthquake horizontal peak `0.018m/s²` and
    vertical peak `0.019m/s²`.
- Next action: publish `v1.7.21`, then fast-forward 133 to the committed
  `origin/main` state.

### Hongtang Bridge Q2 v1.7.20 Report Follow-up Correction

- Status: completed on 2026-07-06 17:55 CST.
- Code state during production rerun: `F:\Guanbing` fast-forwarded from
  `349df53` to `6519192` (`Fix Hongtang Q2 report follow-ups`) and tracked
  `origin/main`.
- Release version: MATLAB GUI/report GUI `v1.7.20`.
- Remote validation:
  - Python report tests passed:
    `D:\Python310\python.exe -m unittest tests_py.test_hongtang_period_followups tests_py.test_artifact_lookup tests_py.test_build_period_report_word_update`.
  - JSON threshold assertion passed: all `10` Hongtang bearing-displacement
    points have thresholds equal to level-2 alarm bounds `[-240, 240]`.
  - MATLAB tests passed:
    `tests/test_main_gui_smoke.m`,
    `tests/test_hongtang_lowfreq_loader.m`,
    `tests/test_cleaning_pipeline.m`,
    `tests/test_structural_time_series_plot_service.m`,
    `tests/test_post_filter_thresholds.m`.
- Bearing-displacement rerun:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1720_bearing_20260706_174310`
  - MATLAB elapsed: `135.18` seconds; task status elapsed `142.25` seconds.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\bearing_displacement_stats.xlsx`.
  - Analysis manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260706_174539.json`.
  - Stats check: `10` rows; no original or filtered min/max values outside
    `[-240, 240]`.
- Report regeneration:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1720_report_20260706_174646`
  - Runtime: `105.84` seconds, below the 10-minute report-generation failure
    threshold.
  - Output DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_174718.docx`.
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_174718.json`
    with `missing=0` and `warnings=0`.
  - Checked PDF copied back to:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_174718_word_checked.pdf`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_v1720_20260706_174718`.
  Word COM exported an `81` page PDF and all `81` pages rendered to PNG.
  Table 1-2 was visually checked as Q2-only `15` maintenance rows; support
  displacement text now reads `-60.3mm~173.0mm`; earthquake text now reads
  horizontal `0.018m/s²` and vertical `0.019m/s²`. No reference-error or
  placeholder tokens were found.

### Hongtang Bridge Q2 Strain Cleaning Threshold Update

- Status: completed on 2026-07-06 16:45 CST.
- Code state during production rerun: `F:\Guanbing` clean at `43c2b99`
  (`Tighten Hongtang Q2 strain cleaning thresholds`) and tracking
  `origin/main`.
- Remote validation:
  - JSON parse and threshold assertions passed for `config/hongtang_config.json`.
  - MATLAB tests passed:
    `tests/test_hongtang_lowfreq_loader.m`,
    `tests/test_cleaning_pipeline.m`, and
    `tests/test_post_filter_thresholds.m`.
- Config policy applied:
  - main girder static-strain groups `B/C/D/E/F/G/H`: clean values outside
    `[-200, 200]`;
  - tower static-strain groups `K/L`: clean values outside `[-150, 150]`;
  - offset corrections and alarm bounds unchanged.
- Strain rerun:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_strain_thresholds_20260706_163317`
  - Run status: `ok`.
  - MATLAB elapsed inside run: `146.42` seconds.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\strain_stats.xlsx`.
  - Analysis manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260706_163554.json`.
  - Stats check: 64 strain rows; no main-girder stats outside `[-200, 200]`
    and no tower stats outside `[-150, 150]`.
- Report regeneration:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_report_strain_thresholds_20260706_163656`
  - Runtime: `88.98` seconds.
  - Output DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_163731.docx`
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_163731.json`
  - Checked PDF copied back to 133:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_163731_checked.pdf`.
- Final local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_strain_thresholds_20260706_163731`.
  Word COM exported an 82-page PDF; all pages rendered; text checks found no
  reference errors or placeholders. The report summary now states main girder
  strain `-60.3με~152.3με` and tower strain `-148.9με~127.2με`.

### Hongtang Bridge Q2 v1.7.19 Final Closure

- Status: completed on 2026-07-06 16:05 CST.
- Code state: `F:\Guanbing` is clean at `bf43de2` and tracks `origin/main`.
- Remote focused validation passed:
  `D:\Python310\python.exe -m unittest tests_py.test_wim_auto_captions tests_py.test_artifact_lookup tests_py.test_build_period_report_word_update`
- Relevant accepted fixes on this line:
  - restored Q2 `SG-6` and `SL-8` strain thresholds to normal transitional bounds `[-1000, 1000]`;
  - made Hongtang low-frequency `abs_max_valid` sensor-specific so strain is not pre-filtered before offset correction;
  - changed Hongtang low-frequency cache to raw-only `__raw_v3.mat` files;
  - fixed bearing-displacement report image lookup for production filenames ending in `*_Orig.jpg`;
  - preserved Word caption bookmarks when converting static figure/table captions to auto-number fields.
- Final report generation:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1719_report_final_20260706_155715`
  - Runtime: `89.31` seconds.
  - Output DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_155749.docx`
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_155749.json`
  - Manifest check: `missing_entries=0`, bearing-displacement missing paths `0`.
  - DOCX XML check: `_Ref4508` and `_Ref4616` present; no raw reference-error tokens.
- Final local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_v1719_final_20260706_155749`
  - Word COM exported `hongtang_q2_report.pdf` with `82` pages.
  - All pages rendered to PNG; text checks found no `引用源未找到`, `错误!`, `错误！未定义书签`, stale placeholders, or template tokens.
  - Page 37 bridge-tower strain cross-references were verified as `图 4-6` and `图 4-7`.

### Hongtang Bridge Q2 v1.7.18 Report Correction

- Status: completed on 2026-07-06 13:05 CST.
- Code state: `F:\Guanbing` is clean at `82fa278` / `v1.7.18` and tracks
  `origin/main`.
- Remote focused validation:
  - `D:\Python310\python.exe -m unittest tests_py.test_wim_auto_captions tests_py.test_build_period_report_word_update`
    passed.
  - MATLAB focused tests for structural plotting, offset correction, and GUI
    version smoke passed.
- Affected-module rerun:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1718_strain_bearing_20260706_123551`
  - Scope: `strain` and `bearing_displacement` only.
  - Exit code: `0`.
  - MATLAB runtime: about `171.49` seconds.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\strain_stats.xlsx` and
    `E:\洪塘大桥数据\2026年4-6月\stats\bearing_displacement_stats.xlsx`.
  - Offset report:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\offset_correction_applied_20260706_123706.xlsx`
    confirmed `Z11-2 = 250` on `2184` rows and `SG-6 = -1220` on `6552`
    rows.
  - Bearing displacement outputs:
    `E:\洪塘大桥数据\2026年4-6月\时程曲线_支座位移_原始` and
    `E:\洪塘大桥数据\2026年4-6月\时程曲线_支座位移_滤波`, each with `10` JPG
    and `10` EMF files. Hongtang has no bearing-displacement groups configured.
- Final report generation:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1718_report_20260706_1242`
  - Runtime: `104.32` seconds.
  - Output DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_124340.docx`
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_124340.json`
    with `status=ok`, `missing_count=0`, `warnings=[]`, and report QC `ok`.
  - Locally checked Word-exported PDF was copied back to:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_124340_word_checked.pdf`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_tasks\hongtang_q2_v1718_report_20260706_1242\bundle_from_133`.
  Word rendered an 82-page PDF, and text/visual checks found no reference
  errors, stale Q1 date text, or missing placeholders.

### Zhishan Bridge 2026-04/05 Sync To 126

- Status: completed.
- Run directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_sync126_202604_202605_20260701_file`
- Status file: `sync_status.json`
- Target:
  - `\\192.168.100.126\H$\Guanbingwork\芝山大桥\2026年4月`
  - `\\192.168.100.126\H$\Guanbingwork\芝山大桥\2026年5月`

### Zhishan Bridge 2026-06 Pipeline

- Status: completed.
- Run directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_202606_pipeline_20260701`
- Status file: `june_pipeline_status.json`
- Current stage at last check: backing up June data/results to 126.
- Latest observed progress:
  - `bearing_displacement_stats.xlsx` generated.
  - `strain_stats.xlsx` generated.
  - `accel_stats.xlsx` generated.
  - `cable_accel_stats.xlsx` generated.
  - `accel_spec_stats.xlsx` generated.
  - `cable_accel_spec_stats.xlsx` generated.
  - `dynamic_strain_highpass_stats.xlsx` generated.
  - `dynamic_strain_lowpass_stats.xlsx` generated.
- Generated report:
  `F:\芝山大桥数据\2026年6月\自动报告\芝山大桥健康监测2026年6月份月报_自动生成_20260701_162108.docx`
- Report manifest:
  `F:\芝山大桥数据\2026年6月\自动报告\zhishan_report_build_manifest_20260701_162108.json`
- Backup to 126 completed according to `june_pipeline_status.json`.
- MATLAB process had exited at last check.

### Zhishan Bridge 2026-04 To 2026-06 Refilter

- Status: paused after 2026-05 by user request.
- Run directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_202604_202606_refilter_20260703_1200_sched`
- Scheduled task:
  `Guanbing_Zhishan_Refilter_202604_202606_20260703_SCHED`
- Task state on 2026-07-03 17:47 CST: `Disabled`.
- 2026-04 and 2026-05 were processed under the stricter filter rule before the
  pause. 2026-06 should be rerun only after manual review of April/May results.

### Guanbing Bridge 2026-06 Refixed Verification

- Status: completed after Donghua nested-export compatibility fix.
- Latest verified run directory:
  `F:\Guanbing\run_logs\remote_tasks\guanbing_202606_refixed_20260704`
- Generated report after the fix:
  `F:\管柄数据\2026年6月\自动报告\G104线管柄大桥监测月报_2026年06月_自动生成_20260704_035056.docx`
- Report manifest:
  `F:\管柄数据\2026年6月\自动报告\G104线管柄大桥监测月报_manifest_20260704_035056.json`
- Field note: Guanbing site equipment failure means the available data only
  covers 2026-05-26 to 2026-05-28; the low ZIP/data count is expected.
- Root cause of the earlier "only one day processed" symptom: Donghua's newer
  export package used nested `波形\GUID\*.csv` and `特征值\GUID\*.csv`
  folders. The legacy preprocessing chain only scanned direct CSV files. The
  normalizer now moves nested CSVs into the legacy direct folders and deletes
  identical nested duplicates, so only one raw CSV copy is kept.
- Verified day coverage after the fix:
  - `2026-05-26`: 波形/特征值 direct CSVs present.
  - `2026-05-27`: 波形/特征值 direct CSVs present.
  - `2026-05-28`: 波形/特征值 direct CSVs present.
- Duplicate nested CSV cleanup completed on 2026-07-04 for
  `F:\管柄数据\2026年6月(已算)`.
  - Cleanup run directory:
    `F:\Guanbing\run_logs\remote_tasks\donghua_dedupe_20260704`
  - Deleted nested CSVs: `352`, manifest bytes: `32,595,017,703`.
  - Post-cleanup counts for `2026-05-26` to `2026-05-28`:
    `波形` and `特征值` each have `direct=88`, `nested=0`.
- Known caveat: this already-extracted-CSV run still reports ZIP precheck/unzip
  failures in the manifest because no ZIP packages were present. Downstream
  analysis and report generation completed. See `docs/known_issues.md`.

### Guanbing Bridge 2026-06 CLI Run

- Status: completed.
- Run directory:
  `F:\Guanbing\run_logs\remote_tasks\guanbing_202606_cli_20260703_124216`
- Scheduled task:
  `Guanbing_Guanbing_202606_CLI_20260703_124216`
- Generated report:
  `F:\管柄数据\2026年6月\自动报告\G104线管柄大桥监测月报_2026年06月_自动生成_20260703_132120.docx`
- Field note: Guanbing site equipment failure means the available data only
  covers 2026-05-26 to 2026-05-28; the low ZIP/data count is expected.

### Hongtang Bridge 2026 Q2 Pipeline

- Status: completed after the 2026-07-06 late-June patch and report rerun.
- 2026-07-06 patch scope: only `2026-06-28` to `2026-06-30` were supplemented
  from recovered Donghua exports on 126.
- Source patch run:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_donghua_patch_20260706_061724`
- High-frequency refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_patch_refresh_20260706_063728`
- RMS refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_patch_rms_refresh_20260706_083341`
  - Result: acceleration `12/12`, cable acceleration `24/24`, no skipped
    points.
- Final checked 2026-07-06 report copied back to 133:
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_090831_checked.docx`
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_090831_checked.pdf`
- Report generation runtime was `146.629` seconds; Word export produced `79`
  pages. Local render QA found no `错误`, `引用源未找到`, stale Q1 date, old
  `共 63 页` header text, or mojibake error/reference text.
- MAT-only follow-up for patched dates:
  - canonical MAT caches generated for wind speed/direction and earthquake;
  - MAT-only smoke passed before and after deleting direct wave CSV;
  - deleted only `2026-06-28` to `2026-06-30` direct `波形\*.csv` files:
    `417` files / `37,572,244,652` bytes;
  - feature CSV files were retained.
- 2026-07-06 wind/earthquake report correction:
  - Root cause: the first corrected wind/earthquake plots were generated before
    canonical MAT aliases existed for timestamp-named Donghua CSVs such as
    `风速_*.csv`, `塔顶风速_*.csv`, and `X_*.csv`.
  - Refresh run:
    `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_wind_eq_refresh_20260706_0945`.
  - Corrected report run:
    `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_report_wind_eq_fix_20260706_1050`.
  - Corrected checked report:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_105133_wind_eq_checked.docx`
  - Corrected checked PDF:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_105133_wind_eq_checked.pdf`
  - Figure-axis check: W1/W2 wind speed/direction reached
    `2026-06-30 09:00:02`, W1/W2 10-minute wind reached
    `2026-06-30 23:55`, and EQ-X/Y/Z reached `2026-06-30 09:00:05`.
- Active high-frequency source state: MAT-only for dated `波形` data.
  On 2026-07-05, after validating MAT-only loading, the direct raw CSV files
  under `E:\洪塘大桥数据\2026年4-6月\20??-??-??\波形\*.csv` were deleted to
  save disk space. Do not expect those active folders to contain raw CSV files.
- MAT-only deletion run:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_mat_only_delete_20260705_133553`
  - Pre-delete direct wave CSV inventory: `9,675` files,
    `853,816,533,340` bytes.
  - Configured non-empty CSV-backed sources checked in MAT-only mode:
    `3,662`; MAT ok: `3,662`; missing MAT: `0`; bad MAT: `0`.
  - Empty configured source CSVs: `36` files, all `2` bytes, treated as empty
    raw-source placeholders rather than cacheable data.
  - Deleted direct wave CSVs: `9,675`; remaining direct wave CSVs: `0`.
  - Remaining MAT caches under dated `波形\cache`: `3,662` files,
    `37,899,893,177` bytes.
  - Post-delete MAT-only smoke passed for `CS1`, `A1`, and `W1` on
    `2026-04-01`, all reading `cache\*.mat`.
- Final full run directory:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_full_20260705_022000`
- Final RMS refresh directory:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_rms_refresh_20260705_102937`
- RMS refresh result: acceleration `12/12`, cable acceleration `24/24`, no
  skipped points.
- Final checked report copied back to 133:
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260705_105401_checked.docx`
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260705_105401_checked.pdf`
- Local render QA after copying from 133 produced `110` PNG pages and found no
  `错误` / `引用源未找到` / stale Q1 date / old `共 63 页` text.
- Report generator runtime for the checked Q2 build was about `80` seconds.
- Report-field update note: 133 has Word COM but no Python `pythoncom`; the
  report builder now falls back to PowerShell Word COM, verified on 133 with
  `WORD_UPDATE_WARNINGS=[]`.
- Python environment update on 2026-07-05: `D:\Python310` already had
  `python-docx`, `openpyxl`, `Pillow`, `pandas`, `numpy`, `matplotlib` and
  `lxml`; installed missing `pywin32 312` and `PySide6 6.11.1` so
  `pythoncom`, `win32com` and direct report GUI imports are available.
- Historical first run directory:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_20260701`
- Status file: `hongtang_q2_status.json`
- Scheduled tasks:
  - `Guanbing_Hongtang_Q2_20260701`
  - `Guanbing_Hongtang_Q2_Backup_Retry5_20260702` (disabled)
- Lowfreq workbook now exists:
  `E:\洪塘大桥数据\2026年4-6月\lowfreq\data.xlsx`
  - Generated through the MATLAB Jikang lowfreq sync module on 2026-07-04.
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\hongtang_lowfreq_sync_20260704_183004.json`
  - Q2 workbook check: `2184` Q2 rows, `79` columns, `90033` non-missing Q2
    value cells, `80319` missing Q2 value cells.
- 2026-07-04 layout cleanup completed on 133 for:
  `E:\洪塘大桥数据\2026年4-6月`
  - Previous wrapper layout: `波形\<YYYY-MM-DD>\波形`
  - Current layout: `<YYYY-MM-DD>\波形`
  - Move manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\layout_move_20260704_175616\move_result.json`
  - Moved `89` date folders; CSV total remained `9675`; wrapper `波形` folder
    was removed after it became empty.
  - Missing/reduced source data remains a data-source issue, not a move issue:
    missing dates include `2026-04-02` and `2026-06-19`; `2026-06-28` to
    `2026-06-30` have only `43` CSV files each.
- Lowfreq is Jikang workbook data and should be filled through the MATLAB
  lowfreq sync module. WIM/称重 remains on the SQL pipeline.

## Disk Snapshot

Last observed on 133 at 2026-07-03 19:49 CST:

- `E:` free space about `898 GB`.
- `F:` free space about `854 GB`.
- No MATLAB process was running. The previous user GUI MATLAB process
  (`PID 28576`) had been stopped by the user.

## Recent Code Sync Notes

133 `F:\Guanbing` was fast-forwarded to the 2026-07-06 `v1.7.17` release line
at 11:07 CST.

- Release commit: `75e82fd Fix Hongtang wind earthquake source matching`
- Release tag: `v1.7.17`
- Remote `git status --short --branch`: clean, `main...origin/main`.
- Remote focused test after the `v1.7.17` pull passed:
  `matlab -batch "cd('F:\Guanbing'); addpath(genpath(pwd)); results = runtests({'tests/test_time_series_loader.m'}); assertSuccess(results);"`
- Previous report-field release commit: `4c87599 Fix Hongtang report page totals`
- Previous report-field release tag: `v1.7.16`
- Remote focused report-field test after the `v1.7.16` pull passed:
  `D:\Python310\python.exe -m unittest tests_py.test_build_period_report_word_update`
- Previous remote release commit: `c77ba32 Add MAT-only time series source
  support`
- Previous remote release tag: `v1.7.15`
- Before the fast-forward pull, the duplicate dirty worktree was backed up as
  `stash@{0}: pre-v1.7.14 duplicate Hongtang Q2 worktree backup`.
- Report generator file `reporting/build_period_report.py` was synchronized to
  133 before the accepted Q2 report, re-smoke-tested there, and is now tracked
  through git at `v1.7.17`.
- Remote focused tests passed:
  - `D:\Python310\python.exe -m unittest tests_py.test_build_period_report_word_update`
  - real Word COM smoke test on a copied DOCX returned `WORD_UPDATE_WARNINGS=[]`.
  - earlier focused MATLAB tests for lowfreq, GUI/config, gap mode and dynamic
    services passed on this recovery line.
  - `matlab -batch` focused MATLAB test passed:
    `tests/test_time_series_loader.m`.
  - Hongtang Q1 MAT-only smoke passed on 133:
    `E:\洪塘大桥数据\2026年1-3月\2026-01-01\波形\cache\CS1_148.mat`
    was read through `load_timeseries_range` and dynamic RMS collection.
  - Hongtang Q2 CSV + cache smoke passed on 133:
    `E:\洪塘大桥数据\2026年4-6月\2026-04-01\波形\CS1_148.csv`
    was read through the default `auto` source mode.

Known accepted fixes from the July 2026 remote runs:

- `+bms/+data/TimeSeriesLoader.m`: UTF-16/BOM CSV fallback parsing.
- `+bms/+app/AsyncRunService.m`: write generated PowerShell launchers as UTF-8
  with BOM so Windows PowerShell 5.1 does not corrupt Chinese paths.
- `+bms/+analyzer/SpectrumPlotService.m`: skip all-NaN/empty spectrum plots
  cleanly and avoid date-tick errors.
- `reporting/build_jlj_monthly_report.py`: missing stats files should not crash
  the report builder; local `main` already contains this.
- `reporting/build_shuixianhua_monthly_report.py`: monitoring period and output
  filename should be generated from the selected period; local `main` already
  contains this.
- `+bms/+data/DonghuaExportNormalizer.m`: staged on local and 133 during
  Guanbing 2026-06 repair; commit/push this snapshot before treating it as a
  release baseline.

## Zhishan April 2026 Production Run

Last observed on 133 at 2026-07-08 CST.

- Data root: `F:\芝山大桥数据\2026年4月`
- Source-data gap: `2026-04-02` dated folder was absent. The regenerated cable
  force spectrum workbook therefore keeps 2026-04-02 blank; this is a source
  coverage issue rather than a processing failure.
- Main run directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_202604_april_clean_20260708_121250`
  - Final status: `complete`, `ok`.
  - Runtime: about `28` minutes.
  - Updated modules: bearing displacement, structural strain, cable
    acceleration, cable acceleration spectrum, and offset report.
- Dynamic strain refresh directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_dynamic_20260708_131627`
  - Final status: `complete`, `ok`.
  - Refreshed highpass and lowpass dynamic strain outputs after the report QA
    found that derived dynamic strain figures still needed the same April
    level-2 cleaning rules.
- Final report:
  `F:\芝山大桥数据\2026年4月\自动报告\芝山大桥健康监测2026年4月份月报_自动生成_20260708_133148.docx`
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_report_20260708_133148\zhishan_202604_report_20260708_133148.docx`
- Local rendered pages:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_report_20260708_133148\rendered`
- Validation summary:
  - bearing displacement Orig/Filt min/max stayed within `[-80,80]`;
  - structural strain stayed within the configured April level-2 thresholds;
  - dynamic strain highpass/lowpass stayed within the configured April level-2
    thresholds after the refresh;
  - cable acceleration stayed within `[-3000,3000]`;
  - CF-1..CF-8 fixed offsets were logged in
    `offset_correction_applied_20260708_121344.xlsx`;
  - report manifest was `ok`, with `missing_count=0`, `warnings=0`;
  - local render produced `47` pages and no `引用源未找到`, `错误`, `未定义书签`,
    replacement tokens, or common mojibake were found.
