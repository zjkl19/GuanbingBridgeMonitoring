# Current Task State

Last updated: 2026-07-04

## Purpose

This file is the handoff point for long Codex sessions. New conversations should read this file first, then read `git status`, `git diff`, recent commits, and relevant output files before continuing.

## 2026-07-04 Latest Engineering Snapshot

This is the current recovery point for the Donghua export compatibility,
GUI/path-profile visibility, and remote production-state cleanup work.

Current repository:

- Root: `D:\MatlabProjects\Guanbing`
- Branch: `main`
- Latest baseline before this snapshot: `ede75d6 Document 133 code sync status`
- MATLAB GUI version in `ui/run_gui.m`: `v1.7.13`
- Report GUI version in `reporting/report_gui.py`: unchanged from the previous report-generator release.

Accepted local changes in this snapshot:

- Added `+bms/+data/DonghuaExportNormalizer.m`.
  - Supports Donghua's older direct `日期\波形\*.csv` layout and the newer
    nested `日期\波形\GUID\*.csv` / `日期\特征值\GUID\*.csv` layout.
  - Copies missing nested CSV files up to the legacy direct folder before the
    existing preprocessing scripts run.
  - Canonicalizes `_原始数据...` and known mojibake variants while preserving
    the original nested files.
- Wired the normalizer into:
  - `scripts/batch_rename_csv.m`
  - `scripts/batch_remove_header.m`
  - `scripts/batch_resample_data_parallel.m`
- Improved MATLAB GUI operability:
  - visible path-profile note showing how local/remote data-root paths were
    selected;
  - green progress bar / status text for asynchronous runs;
  - `Ctrl+R` preflight now fails before launching a batch run when the data
    root is missing.
- Improved machine path-profile resolution:
  - explicit `GUANBING_PATH_PROFILE` still has priority;
  - hostname matching is still preferred;
  - if hostnames drift after production-machine rename, existing-path fallback
    can still pick the right profile.
- Test coverage added/extended:
  - `tests/test_donghua_export_normalizer.m`
  - `tests/test_main_gui_smoke.m`
  - `tests/test_gui_state_services.m`
  - `tests/test_path_profile_resolver.m`

Latest local test evidence before committing this snapshot:

- `git diff --check`: passed, only line-ending warnings.
- Full MATLAB default suite was previously green at `166 Passed, 0 Failed, 0 Incomplete`.
- Focused local/remote GUI and normalizer smoke tests should be rerun after any
  follow-up edit touching these files.

Remote Guanbing 2026-06 verification on `192.168.100.133`:

- Root cause of the earlier "only 2026-05-27 was processed" symptom was
  Donghua's newer nested GUID export layout, not missing raw data.
- After normalization, direct CSVs exist for all three available days:
  `2026-05-26`, `2026-05-27`, and `2026-05-28`.
- New report generated on 133:
  `F:\管柄数据\2026年6月\自动报告\G104线管柄大桥监测月报_2026年06月_自动生成_20260704_035056.docx`
- The report text was checked locally and covers `2026年05月26日~2026年05月28日`.
- Known caveat: because this site had already-extracted CSV data and no ZIP
  package for the period, the run manifest can still show ZIP precheck/unzip as
  failed even though the downstream analysis and report are valid. Track this in
  `docs/known_issues.md`.

New conversation bootstrap for Guanbing code work:

```text
阅读 D:\MatlabProjects\Guanbing\docs\current_task_state.md、
D:\MatlabProjects\Guanbing\docs\ops\current_remote_state.md、
D:\MatlabProjects\Guanbing\docs\ops\machines.md 和
D:\MatlabProjects\Guanbing\docs\known_issues.md，然后读取 git status/diff、
最近提交，再继续当前任务。
```

New conversation bootstrap for remote machine work:

```text
阅读 D:\MatlabProjects\Guanbing\docs\ops\current_remote_state.md、
D:\MatlabProjects\Guanbing\docs\ops\machines.md 和
D:\MatlabProjects\Guanbing\docs\known_issues.md，然后先只读检查目标机器状态，
不要直接执行破坏性操作。
```

## 2026-07-03 Latest Engineering Snapshot

This section is the current recovery point. Older sections below remain useful
for release and bridge-processing history.

Current repository:

- Root: `D:\MatlabProjects\Guanbing`
- Branch: `main`
- Latest baseline before this snapshot: `24486ed Stabilize remote operations and CSV/spectrum handling`
- MATLAB GUI version in `ui/run_gui.m`: `v1.7.13`
- Report GUI version in `reporting/report_gui.py`: unchanged from the previous report-generator release.

Current accepted local changes:

- Added machine path profiles:
  - `config/path_profiles.json`
  - optional untracked override: `config/path_profiles.local.json`
  - implementation: `+bms/+profile/PathProfileResolver.m`
- Bridge profile default data roots now pass through the active path profile.
  This is the preferred fix for local/remote path drift such as local
  `E:\水仙花大桥数据` versus 133 `F:\水仙花大桥数据`.
- Main MATLAB GUI now supports hidden smoke testing:
  `fig = run_gui('Visible','off')`.
- Main MATLAB GUI exposes stable handles in `fig.UserData.controls`.
- Main-window shortcuts:
  - `Ctrl+R`: run
  - `Ctrl+.`: stop
  - `Ctrl+K`: clear log
  - `Ctrl+S`: save preset
  - `Ctrl+L`: load preset
  - `Ctrl+G`: check config
  - `Ctrl+B`: open report builder
- `GuiStatusPanel.clearLog()` now uses a MATLAB-UI-valid empty value.

Latest verified command:

```powershell
matlab -batch "addpath(pwd); run_tests('default');"
```

Result observed: `166 Passed, 0 Failed, 0 Incomplete`.

Remote operations documentation:

- Machine inventory: `docs/ops/machines.md`
- Current remote state: `docs/ops/current_remote_state.md`
- SSH config template: `docs/ops/ssh_config.template`
- Helper scripts: `scripts/ops/`

When starting a new conversation for a remote machine task, read
`docs/ops/current_remote_state.md` first, then `docs/ops/machines.md`.
When starting a new conversation for Guanbing code work, read this file,
then `git status`, `git diff`, and recent commits.

## 2026-06-30 Operational Snapshot

This section is the current recovery point. Older sections below remain useful for Zhishan March processing history, but some of their "Current Goal" / version notes are historical.

Current repository:

- Root: `D:\MatlabProjects\Guanbing`
- Branch: `main`
- Latest pushed commit: `22b86b8 Release v1.7.12 Shuixianhua report filename fix`
- Latest pushed tag: `v1.7.12`
- Recent release chain:
  - `v1.7.12`: commits ShuiXianHua monthly report generator period-label/date-span/output-filename fix; keeps source, CLI, smoke tests, and packaged exe builds consistent.
  - `v1.7.11`: fixes packaged report generator so `reporting\dist\BridgeReportBuilder\config\*.json` is copied into the exe folder/package.
  - `v1.7.10`: fixes Jiulongjiang report generation defaults and missing optional stats handling; profile default uses the accepted Jiulongjiang `0508` template and includes static strain.
- Current MATLAB GUI version in `ui/run_gui.m`: `v1.7.12`
- Current report GUI version in `reporting/report_gui.py`: `v1.7.12`

Latest verified commands:

```powershell
.\reporting\.venv\Scripts\python.exe -m unittest tests_py.test_shuixianhua_report_generator tests_py.test_bridge_profiles
```

```powershell
matlab -batch "addpath(genpath(pwd)); results = runtests({'tests/test_bridge_profile.m','tests/test_run_request.m','tests/test_gui_state_services.m'}); assertSuccess(results);"
```

```powershell
powershell -ExecutionPolicy Bypass -File reporting\build_gui_exe.ps1 -PythonExe reporting\.venv\Scripts\python.exe
```

```powershell
reporting\dist\BridgeReportBuilder\BridgeReportBuilder.exe --self-test-shuixianhua --self-test-no-word-update --self-test-output-root tmp\exe_selftest_v1712_sxh
```

Known report generator status:

- Packaged exe path: `D:\MatlabProjects\Guanbing\reporting\dist\BridgeReportBuilder\BridgeReportBuilder.exe`
- `BridgeReportBuilder.exe --self-test-shuixianhua` passed after rebuild and reported `version=v1.7.12`.
- Earlier `v1.7.11` packaged self-tests also passed for ShuiXianHua and Zhishan after config-copy packaging was fixed.
- The packaged report-builder archive smoke check confirmed these entries in zip:
  - `BridgeReportBuilder.exe`
  - `VERSION.txt`
  - `config\bridge_profiles.json`
  - `config\shuixianhua_config.json`
  - `config\zhishan_config.json`
  - `config\jiulongjiang_config.json`

Remote production/test machine `192.168.100.133`:

- SSH user used by Codex: `dell`
- SSH command: `ssh -p 2222 -o BatchMode=yes -o StrictHostKeyChecking=no dell@192.168.100.133`
- Port 2222 was enabled as an alternate OpenSSH port on 133.
- 133 has been used for remote Guanbing runs under `F:\Guanbing`.
- For long remote runs, prefer status JSON/log files and sparse polling instead of frequent chat updates.
- Remote operations inventory now lives under `docs/ops/`:
  - `docs/ops/machines.md`
  - `docs/ops/current_remote_state.md`
  - `docs/ops/ssh_config.template`
  - helper scripts in `scripts/ops/`

Jiulongjiang 2026-05 remote run status:

- `F:\九龙江数据\2026年5月\stats\strain_stats.xlsx` was eventually generated on 133.
- Remote report generated successfully:
  - `F:\九龙江数据\2026年5月\自动报告\九龙江大桥健康监测2026年3月份月报_0508_2026年5月份_自动生成_20260630_062224.docx`
  - Size observed: `18,259,786` bytes.
- The code fixes from that work were committed in `v1.7.10`.
- The previous heartbeat automation for Jiulongjiang strain补跑 was turned off by user request; resume checks manually when requested.

Windows / Codex issue observed:

- Codex sandbox setup error popup: `codex-windows-sandbox-setup.exe 找不到指定的模块`.
- No code fix has been made for this local Codex-app issue. Treat separately from Guanbing project correctness.

Local non-release items organized on 2026-06-30:

- `CODE_REVIEW_HANDOFF.md` moved to `local_notes\reviews\CODE_REVIEW_HANDOFF_20260615.md`.
- Cloud-platform algorithm drafts moved to `local_notes\cloud_platform_algorithm\`.
- VPN/account request documents and VPN manual moved to `ops_local\vpn_ssh_133\`.
- SSH/VPN helper scripts for `192.168.100.133` moved to `ops_local\vpn_ssh_133\scripts\`.
- Previous `release\remote_133_sync` content moved to `ops_local\release_archives\release\`.
- The accidental `%SystemDrive%\...` path-expansion artifact moved to `local_notes\quarantine\%SystemDrive%\` for review before deletion.
- `.gitignore` now ignores `local_notes/`, `ops_local/`, `release/`, and `%SystemDrive%/`.

Do not include these local items in normal release commits unless the user explicitly asks. They are mostly operational docs/scripts from VPN/SSH/cloud-platform work, not core Guanbing source.

Remote data transfer recommendation:

- For server `192.168.100.126`, the simplest current approach is still RDP over VPN:
  - Try `mstsc` to `192.168.100.126:9833`.
  - If VPN gives direct LAN access, also test `192.168.100.126:3389`.
- For data movement between 126 and 133, prefer SMB share + `robocopy` from 133 as the first practical replacement for "RDP + FeiQ":

```powershell
robocopy \\192.168.100.126\监测数据 F:\来自126服务器\监测数据 /E /XO /R:2 /W:5 /MT:16 /NP /LOG+:F:\Guanbing\run_logs\sync_126.log
```

- Do not open port 135 just for file transfer.
- Avoid plain FTP for production credentials/data. If command-line remote control is needed later, install OpenSSH/SFTP on 126 with firewall limited to 133/VPN network.

State-file writing policy:

- It is acceptable for `docs/current_task_state.md` to be fairly detailed because file size is small.
- Still prefer concise, recoverable facts over full chat logs:
  - paths, versions, commits/tags, commands that passed, generated report locations, active remote hosts, data-cleaning口径, known open risks.
  - avoid raw terminal dumps, repeated failed attempts, or long temporary screenshots unless they define a future decision.
- If this file gets too long to scan, add a latest snapshot near the top and keep older bridge-specific sections below as history instead of deleting them.

## Current Goal

Add Zhishan Bridge data processing support to the Guanbing project. This phase only needs to connect and validate the data processing chain. Do not build a Zhishan report template or report generator yet.

## Repository State To Preserve

Repository root: `D:\MatlabProjects\Guanbing`

Recent commits:

- `dd65960` Release v1.7.4 config and report contract refactors
- `d134ee2` Refactor config layering and report contracts
- `e00ba14` Refactor config resolution and linting
- `f734c27` Release v1.7.3 report generator refactors
- `8d0ef49` Release v1.7.2 Shuixianhua reporting updates

Uncommitted files observed before starting the Zhishan task:

- Modified: `ui/run_gui.m`
- Untracked: `+bms/+config/AutoThresholdProposalService.m`
- Untracked: `tests/test_auto_threshold_proposal_service.m`
- Untracked: `ui/build_auto_threshold_tab.m`
- Untracked: one report document under `reports/HT20YU2600004 ... 月度考核表.doc`

These appear to come from the prior auto-threshold/GUI work. Do not revert or overwrite them unless the user explicitly asks.

## Zhishan Task Inputs

Reference materials:

- Equipment table: `E:\芝山大桥-彭仲鑫\芝山大桥设备参数表（20230308改）.xlsx`
- Threshold reference: `E:\芝山大桥-彭仲鑫\验收报告\20221114芝山大桥系统建设安装及试运营分析报告-FNIAL(1).docx`

Source data:

- Mixed Hongtang/Zhishan package: `E:\洪塘大桥数据\2026年1-3月`

Target staged data:

- `D:\芝山大桥数据\2026年1-3月`

Processing range:

- `2026-03-01` to `2026-03-31`
- Known missing March date folders: `2026-03-01`, `2026-03-02`, `2026-03-12`
- March has 28 actual date folders.

Data handling rule:

- Copy the Zhishan subset from the mixed source data. Do not move or delete the Hongtang source data.
- Data files are not tracked in git.

## Confirmed Zhishan Point Mapping

Use engineering point IDs in configs and reports. Use equipment-table sensor IDs as `file_id` for CSV matching.

Strain:

- `SX-1`: `C1802191464`
- `SX-2`: `C1802191462`
- `SX-3`: `C1802191467`
- `SX-4`: `C1802191469`
- `SX-5`: `C1802191470`
- `SX-6`: `C1802191481`
- `SX-7`: `C2006010002`
- `SX-8`: `C2006010003`
- `SX-9`: `C2006010053`
- `SX-10`: `C2006010049`

Beam-end longitudinal displacement:

- `DX-1`: `C210419100`
- `DX-2`: `C210419103`
- `DX-3`: `C210419101`
- `DX-4`: `C210419102`

Structural acceleration:

- `AZ-1`: `C2007120226`
- `AZ-2`: `C2006070240`
- `AZ-3`: `C2007120286`
- `AZ-4`: `C2007120373`
- `AZ-5`: `C2007120369`

Cable force via cable acceleration:

- `CF-1`: `C200303008`
- `CF-2`: `C200303004`
- `CF-3`: `C200303009`
- `CF-4`: `C200303005`
- `CF-5`: `C200303011`
- `CF-6`: `C200303006`
- `CF-7`: `C200303010`
- `CF-8`: `C200303007`

Important correction from the user on 2026-05-25: these are still processed through the existing `cable_accel` / `cable_accel_spectrum` chain. Do not add or enable a new direct `cable_force` analysis module. The config may use existing `groups.cable_force` only because the current cable-acceleration spectrum pipeline already uses that key for computed-force group plots.

Temperature/humidity design points:

- `WS-T`: `2207073069`
- `WS-H`: `2207073070`

Temperature/humidity were confirmed by the user as offline. Keep them as design points if useful, but default-disable those analysis modules and record the offline/missing status in QC/run information.

## Threshold Notes

Strain thresholds are from the trial operation report. Historical note:

- `SX-2` first-level lower threshold appears as `-1897` in the source report, likely a typo. Use `-189` by same-group口径 and record this correction in config/QC notes.

Latest user rule for the March 2026 Zhishan reprocessing: strain uses first-valid-day zero correction and only one second-level warning line, drawn yellow.

Acceleration:

- Raw `AZ` data are in `m/s^2`.
- Trial operation RMS thresholds are in `mm/s^2`; convert to `m/s^2` in processing/config.
- `AZ-1~AZ-5` RMS thresholds: first level `0.315 m/s^2`, second level `0.500 m/s^2`.

Acceleration spectrum:

- Theoretical vertical first frequency for all `AZ` points: `0.385 Hz`.
- Peak search targets with tolerance `±0.05 Hz`:
  - `AZ-1`: `0.610 Hz`
  - `AZ-2`: `0.623 Hz`
  - `AZ-3`: `0.620 Hz`
  - `AZ-4`: `0.620 Hz`
  - `AZ-5`: `0.640 Hz`

Cable force:

- `CF-1~CF-8` force values are computed from cable-acceleration spectrum peak frequency using existing `CableForceService`: `T = 4 * rho * L^2 * f^2 / 1000`.
- Use `per_point.cable_accel.<CF>.rho`, `L`, `target_freqs`, and `force_alarm_bounds`.
- Cable parameters came from `E:\芝山大桥-彭仲鑫\报告及数据处理\索力\索力计算.xlsx`.
- Latest user-confirmed OCR mapping uses `编号 1~8` as `CF-1~CF-8` with line density `57.687` and first-order frequencies:
  - `CF-1`: `L=75.61`, `f1=1.621`, OCR force `3466 kN`, completed force `3496 kN`
  - `CF-2`: `L=87.45`, `f1=1.465`, OCR force `3787 kN`, completed force `3694 kN`
  - `CF-3`: `L=87.45`, `f1=1.4665`, OCR force `3795 kN`, completed force `3799 kN`
  - `CF-4`: `L=75.61`, `f1=1.641`, OCR force `3552 kN`, completed force `3386 kN`
  - `CF-5`: `L=79.91`, `f1=1.564`, OCR force `3604 kN`, completed force `3860 kN`
  - `CF-6`: `L=82.99`, `f1=1.527`, OCR force `3706 kN`, completed force `3842 kN`
  - `CF-7`: `L=82.99`, `f1=1.536`, OCR force `3749 kN`, completed force `3786 kN`
  - `CF-8`: `L=79.91`, `f1=1.565`, OCR force `3609 kN`, completed force `3659 kN`

March 2026 cleaning rules confirmed on 2026-05-28:

- `acceleration`: filter `2026-03-01 00:00:00` to `2026-03-31 23:59:59` outside `[-0.2, 0.2]`.
- `bearing_displacement`: first-valid-day mean zero correction, then filter March values outside each point's level-3 alarm bounds.
- `cable_accel`: raw CF data are already `m/s^2`. Apply daily median baseline removal first, then the current sweep-selected `[-100, 100] m/s^2` filter. Earlier strict `[-1,1]`, `[-2,2]`, `[-10,10]`, and the later `[-20,20]` preview were too destructive for several CF points.
- `strain`: first-valid-day mean zero correction; display only the yellow second-level warning line.

## Intended Code Changes

Added or updated in this phase:

- `config/zhishan_config.json`
- `config/bridge_profiles.json`
- `+bms/+profile/BridgeProfileRegistry.m`
- `+bms/+data/DataIndex.m` so derived modules resolve underlying sensor file IDs (`dynamic_strain_highpass -> strain`, `accel_spectrum -> acceleration`, `cable_accel_spectrum -> cable_accel`)
- `+bms/+data/TimeSeriesLoader.m` UTF-16LE BOM preference for Zhishan CSVs
- `+bms/+analyzer/StructuralPlotConfigService.m` level1/level2/level3 `alarm_bounds` support
- `+bms/+app/RunPreflight.m` result-artifact health check now ignores figures generated inside the same module run window, so normal "figures first, stats last" runs are not misreported as stale
- A reusable staging script for copying the Zhishan subset from mixed Hongtang data
- Focused tests for profile/config loading, point ID mapping, cable-force computation through cable acceleration spectrum, data-index derived-module file IDs, UTF-16LE CSV loading, and non-regression of existing bridges

Default Zhishan modules:

- `strain`
- `dynamic_strain_highpass`
- `bearing_displacement`
- `acceleration`
- `accel_spectrum`
- `cable_accel`
- `cable_accel_spectrum`

Default-disable:

- `temperature`
- `humidity`

## Test And Validation Expectations

Before real processing:

- Validate Zhishan config JSON can load.
- Confirm GUI/CLI profile selection recognizes Zhishan.
- Confirm non-temperature points match expected CSV files under staged data.

Real data validation:

- Staged March subset into `D:\芝山大桥数据\2026年1-3月` with `scripts/stage_zhishan_subset.m`.
- Staging result: 28/31 source date folders, 756 copied source CSVs, missing dates `2026-03-01`, `2026-03-02`, `2026-03-12`, missing point files `0`.
- Preflight/data index on staged March data passed: 7 modules, 50 module-point entries, 50 found, 0 missing, 1400 indexed module files.
- Smoke-read verified real `2026-03-03` CSVs for `SX-1`, `DX-1`, `AZ-1`, and `CF-1` through `load_timeseries_range`.
- Full March analysis run completed on `2026-05-25 23:00:49` for `2026-03-01` to `2026-03-31`.
  - Status: `ok`
  - Elapsed: `4340.94 sec`
  - Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260525_230049.json`
  - Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260525_214829.txt`
  - Module status counts: 8 ok, 0 fail, 0 skip (includes offset correction report)
  - Manifest artifact count: 943
  - Actual figure files under result tree: 966 (`439 .jpg`, `439 .fig`, `88 .emf`)
- Generated stats outputs:
  - `D:\芝山大桥数据\2026年1-3月\stats\bearing_displacement_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\strain_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\accel_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\accel_spec_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_spec_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\dynamic_strain_highpass_stats.xlsx`
- Latest post-run health outputs:
  - `D:\芝山大桥数据\2026年1-3月\run_logs\data_index_20260525_230812.json`
  - `D:\芝山大桥数据\2026年1-3月\run_logs\data_index_summary_20260525_230812.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\run_logs\stats_inventory_20260525_230810.json`
  - `D:\芝山大桥数据\2026年1-3月\run_logs\stats_inventory_summary_20260525_230810.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\run_logs\run_health_20260525_230812.json`
  - `D:\芝山大桥数据\2026年1-3月\run_logs\run_health_summary_20260525_230812.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_reporting_contract_20260525_230812.json`
- Latest post-run health result: `preflight=ok`, data index found 50/50 points with 0 missing, stats inventory expected 7/existing 7/missing 0/read_failed 0, run health issues 0/errors 0/warnings 0.

Run note:

- The first full run log contains repeated MATLAB BOM mismatch warnings from `readtable` fallback while reading UTF-16LE CSVs. The loader still read and cached all expected files, and the post-run health check passed. The warnings are noisy but not blocking.

Regression:

- Do a light config/profile check for Guanbing, Hongtang, Jiulongjiang, and Shuixianhua.
- Do not let new Zhishan config or cable-acceleration spectrum force plotting change existing bridge defaults.

## Latest Verification

Commands run successfully on 2026-05-25:

```matlab
matlab -batch "addpath(genpath(pwd)); r = runtests({'tests/test_time_series_loader.m','tests/test_datasource_services.m','tests/test_zhishan_config.m','tests/test_bridge_profile.m','tests/test_plot_warning_line_resolver.m','tests/test_config_integration_regression.m'}); disp(table(r)); assertSuccess(r);"
```

```matlab
matlab -batch "addpath(genpath(pwd)); r = runtests({'tests/test_time_series_loader.m','tests/test_datasource_services.m','tests/test_zhishan_config.m','tests/test_bridge_profile.m','tests/test_plot_warning_line_resolver.m','tests/test_config_integration_regression.m','tests/test_run_preflight.m'}); disp(table(r)); assertSuccess(r);"
```

```matlab
matlab -batch "addpath(genpath(pwd)); cfg = load_config(fullfile(pwd,'config','zhishan_config.json')); opts = struct('doStrain',true,'doDynStrainBoxplot',true,'doBearingDisplacement',true,'doAccel',true,'doAccelSpectrum',true,'doCableAccel',true,'doCableAccelSpectrum',true,'buildDataIndex',true); pf = bms.app.RunPreflight.check('D:\芝山大桥数据\2026年1-3月','2026-03-01','2026-03-31',opts,cfg); lines = bms.app.RunPreflight.toLogLines(pf); fprintf('%s\n', lines{:}); if ~isempty(pf.errors), error('preflight errors present'); end; if isfield(pf,'data_index') && isfield(pf.data_index,'summary') && pf.data_index.summary.missing_point_count ~= 0, error('data index missing points'); end"
```

```matlab
matlab -batch "addpath(genpath(pwd)); cfg = load_config(fullfile(pwd,'config','zhishan_config.json')); cfg.notify.enabled = false; opts = struct('doStrain',true,'doDynStrainBoxplot',true,'doBearingDisplacement',true,'doAccel',true,'doAccelSpectrum',true,'doCableAccel',true,'doCableAccelSpectrum',true,'buildDataIndex',true,'buildStatsInventory',true,'buildRunHealthReport',true); pf = bms.app.RunPreflight.check('D:\芝山大桥数据\2026年1-3月','2026-03-01','2026-03-31',opts,cfg); lines = bms.app.RunPreflight.toLogLines(pf); fprintf('%s\n', lines{:}); if ~isempty(pf.errors), error('post-run preflight errors present'); end; if isfield(pf,'data_index') && isfield(pf.data_index,'summary') && pf.data_index.summary.missing_point_count ~= 0, error('post-run data index missing points'); end; if isfield(pf,'stats_inventory') && isfield(pf.stats_inventory,'summary') && pf.stats_inventory.summary.stats_missing_count ~= 0, error('post-run stats inventory missing stats'); end; if isfield(pf,'run_health_report') && isfield(pf.run_health_report,'issue_counts') && pf.run_health_report.issue_counts.error ~= 0, error('post-run health errors present'); end"
```

Auto-threshold GUI follow-up completed on 2026-05-27:

- Fixed preview failure caused by `grid` layout variable shadowing MATLAB's `grid(ax,...)` function.
- Generated preview data is now sampled and cached for points that actually produce suggestions, so switching table rows avoids repeated full data loads.
- Local time-window suggestions now draw a highlighted time range and short threshold segments over `t_range_start` to `t_range_end` instead of full-width horizontal threshold lines.
- The right preview pane is wider, the inline info panel is shorter, and a separate popup preview is available.
- Added algorithm/parameter explanations in tooltips, the preview info panel, and a help dialog.
- Export strips `preview_series` so the generated JSON stays compact.

Commands run successfully on 2026-05-27:

```matlab
matlab -batch "addpath(genpath(pwd)); r = runtests('tests/test_auto_threshold_proposal_service.m'); disp(table(r)); assertSuccess(r);"
```

```matlab
matlab -batch "addpath(genpath(pwd)); files = {'tests/test_auto_threshold_proposal_service.m','tests/test_time_series_loader.m','tests/test_datasource_services.m','tests/test_run_preflight.m','tests/test_config_integration_regression.m','tests/test_bridge_profile.m','tests/test_plot_warning_line_resolver.m','tests/test_zhishan_config.m'}; r = runtests(files); disp(table(r)); assertSuccess(r);"
```

GUI smoke test run on 2026-05-27 passed: constructed the auto-threshold tab in an invisible `uifigure`, generated suggestions from a temporary CSV/config, selected the first suggestion, rendered inline preview, opened popup preview, and verified no preview failure text.

Auto-threshold spike-window algorithm follow-up completed on 2026-05-27:

- `spike_window` no longer keeps the earliest `max_window_proposals_per_point` windows. It now collects all candidate windows, merges nearby windows, ranks candidates by peak excess severity, then keeps the highest-scoring windows.
- Added default `spike_window_merge_gap_seconds=600` and `spike_window_padding_seconds=1` so high-frequency same-second spikes are covered by second-resolution `t_range` strings.
- Preview sampling now preserves per-bucket minima/maxima instead of fixed-stride sampling, so narrow spikes are less likely to disappear from the preview curve.
- For real `strain / SX-4` with the screenshot parameters, the updated algorithm generated 3 high-severity spike windows, with peak-excess scores around `510`.

Additional commands run successfully on 2026-05-27:

```matlab
matlab -batch "addpath(genpath(pwd)); r = runtests('tests/test_auto_threshold_proposal_service.m'); disp(table(r)); assertSuccess(r);"
```

```matlab
matlab -batch "addpath(genpath(pwd)); files = {'tests/test_auto_threshold_proposal_service.m','tests/test_time_series_loader.m','tests/test_datasource_services.m','tests/test_run_preflight.m','tests/test_config_integration_regression.m','tests/test_bridge_profile.m','tests/test_plot_warning_line_resolver.m','tests/test_zhishan_config.m'}; r = runtests(files); disp(table(r)); assertSuccess(r);"
```

Auto-threshold smart cutline follow-up completed on 2026-05-27:

- Added a deterministic `auto_cut` / `智能切线` algorithm as the primary auto-clean suggestion path. It detects clear one-sided gaps between normal data and extreme tails, prefers one full-period cutline when safe, and falls back to local window cutlines when a global line would cover a long continuous span.
- The GUI now exposes `智能切线` with a simple mode selector (`标准` / `保守` / `激进`) and defaults older quantile/MAD/IQR/spike-window methods off for a simpler main workflow.
- Threshold application now supports one-sided rules by allowing `min`-only or `max`-only proposals; non-finite sides are ignored during cleaning.
- Existing threshold arrays are normalized before appending new suggestions so legacy min/max-only rules can be combined with time-windowed and one-sided rules.
- Real-data check with `strain / SX-7` produced one full-period lower cutline `min≈-2000.95`, close to the manually drawn cutline in the screenshot. `strain / SX-10` produced one lower cutline `min≈-265.84`.

Additional verification on 2026-05-27:

- Auto-threshold GUI smoke test passed with default `智能切线` enabled: generated an `auto_cut` proposal from a temporary CSV/config, selected it, and rendered preview without failure.
- The focused and related regression commands listed above were rerun and passed after the smart-cutline change.

Zhishan March reprocessing completed on 2026-05-28 after applying the latest cleaning/frequency/force rules above:

- Run status: `ok`
- Elapsed: `3480.08 sec`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_182739.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_172938.txt`
- Offset report: `D:\芝山大桥数据\2026年1-3月\run_logs\offset_correction_applied_20260528_172938.xlsx`
- Updated stats:
  - `bearing_displacement_stats.xlsx`
  - `strain_stats.xlsx`
  - `accel_stats.xlsx`
  - `cable_accel_stats.xlsx`
  - `accel_spec_stats.xlsx`
  - `cable_accel_spec_stats.xlsx`
  - `dynamic_strain_highpass_stats.xlsx`
- Post-run health on 2026-05-28 passed: data index found 50/50 module-point files, stats inventory expected/existing 7/7, run health issues/errors/warnings all `0`.
- Direct verification:
  - `accel_stats.xlsx`: all `AZ-1~AZ-5` min/max are inside `[-0.2, 0.2]`.
  - `cable_accel_stats.xlsx`: all `CF-1~CF-8` min/max are inside `[-1, 1]`; some RMS cells are blank because the strict `±1` filter leaves insufficient continuous 10-minute valid coverage.
  - `bearing_displacement_stats.xlsx`: filtered values stay inside configured level-3 bounds.
  - Cleaned first valid day means: `DX-1≈-0.001`, `SX-1≈0`, `CF-1≈-0.0025`.
  - Cable force values were produced for all `CF-1~CF-8`; valid day counts were `CF-1=27`, `CF-2=26`, `CF-3=20`, `CF-4=24`, `CF-5=2`, `CF-6=25`, `CF-7=20`, `CF-8=25`.
- Commands passed:

```matlab
matlab -batch "addpath(genpath(pwd)); files = {'tests/test_cleaning_pipeline.m','tests/test_dynamic_series_service.m','tests/test_zhishan_config.m','tests/test_spectrum_peak_service.m','tests/test_plot_warning_line_resolver.m'}; r = runtests(files); disp(table(r)); assertSuccess(r);"
```

```matlab
matlab -batch "addpath(genpath(pwd)); cfg = load_config(fullfile(pwd,'config','zhishan_config.json')); cfg.notify.enabled = false; opts = struct('doStrain',true,'doDynStrainBoxplot',true,'doBearingDisplacement',true,'doAccel',true,'doAccelSpectrum',true,'doCableAccel',true,'doCableAccelSpectrum',true,'buildDataIndex',true,'buildStatsInventory',true,'buildRunHealthReport',true); pf = bms.app.RunPreflight.check('D:\芝山大桥数据\2026年1-3月','2026-03-01','2026-03-31',opts,cfg); lines = bms.app.RunPreflight.toLogLines(pf); fprintf('%s\n', lines{:}); if ~isempty(pf.errors), error('post-run preflight errors present'); end; if isfield(pf,'data_index') && isfield(pf.data_index,'summary') && pf.data_index.summary.missing_point_count ~= 0, error('post-run data index missing points'); end; if isfield(pf,'stats_inventory') && isfield(pf.stats_inventory,'summary') && pf.stats_inventory.summary.stats_missing_count ~= 0, error('post-run stats inventory missing stats'); end; if isfield(pf,'run_health_report') && isfield(pf.run_health_report,'issue_counts') && pf.run_health_report.issue_counts.error ~= 0, error('post-run health errors present'); end"
```

Cable-acceleration follow-up on 2026-05-28:

- Root cause of the poor `CF-*` cable acceleration March plots was not a total raw-data failure. The raw cable acceleration channel is in cm/s^2-like units and contains daily DC offsets; the previous first-day mean zero correction plus `[-1, 1]` m/s^2 clipping removed too much valid signal and made the month-long raw waveform plots misleading.
- Updated `CleaningPipeline` to support `value_scale` and daily grouped offset modes (`daily_mean`, `daily_median`).
- Updated Zhishan `cable_accel` cleaning to apply `daily_median` zero correction, then `value_scale=0.01`, then the confirmed `[-1, 1]` m/s^2 filter.
- Reran only `cable_accel` and `cable_accel_spectrum`.
- New run status: `ok`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_191054.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_185604.txt`
- Updated stats:
  - `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_stats.xlsx`
  - `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_spec_stats.xlsx`
- Post-run health on 2026-05-28 passed for the cable modules: data index found 16/16 module-point files, stats inventory expected/existing 2/2, run health issues/errors/warnings all `0`.
- Direct cable-load verification after cleaning:
  - `CF-1`: finite 99.513%, RMS 0.2347 m/s^2, 1%~99% range `[-0.6612, 0.5915]`.
  - `CF-2`: finite 98.739%, RMS 0.2913 m/s^2, 1%~99% range `[-0.7835, 0.7075]`.
  - `CF-3`: finite 99.993%, RMS 0.0240 m/s^2, 1%~99% range `[-0.0361, 0.0964]`.
  - `CF-4`: finite 99.993%, RMS 0.0243 m/s^2, 1%~99% range `[-0.0351, 0.0956]`.
  - `CF-5`: finite 97.234%, RMS 0.2360 m/s^2, 1%~99% range `[-0.2952, 0.8551]`.
  - `CF-6`: finite 99.995%, RMS 0.0402 m/s^2, 1%~99% range `[-0.1288, 0.0747]`.
  - `CF-7`: finite 99.384%, RMS 0.2863 m/s^2, 1%~99% range `[-0.7811, 0.4829]`.
  - `CF-8`: finite 97.488%, RMS 0.2652 m/s^2, 1%~99% range `[-0.7664, 0.7876]`.
- Interpretation: `CF-1/2/5/7/8` still have much broader high-frequency amplitude than `CF-3/4/6`. The data are usable after unit conversion and daily baseline removal, but month-scale raw 20 Hz waveform plots contain about 46 million samples per point and will remain visually dense. Use the generated `时程曲线_索力加速度_RMS10min` and `时程曲线_索力加速度_RMS10min_组图` figures as the preferred report view; keep cleaned raw data for spectrum/force analysis.

Additional commands passed:

```matlab
matlab -batch "addpath(genpath(pwd)); files = {'tests/test_cleaning_pipeline.m','tests/test_zhishan_config.m','tests/test_dynamic_series_service.m'}; r = runtests(files); disp(table(r)); assertSuccess(r);"
```

```matlab
matlab -batch "addpath(genpath(pwd)); cfg=load_config(fullfile(pwd,'config','zhishan_config.json')); cfg.notify.enabled=false; opts=struct('doCableAccel',true,'doCableAccelSpectrum',true,'buildDataIndex',true,'buildStatsInventory',true,'buildRunHealthReport',true); pf=bms.app.RunPreflight.check('D:\芝山大桥数据\2026年1-3月','2026-03-01','2026-03-31',opts,cfg); lines=bms.app.RunPreflight.toLogLines(pf); fprintf('%s\n', lines{:}); if ~isempty(pf.errors), error('post-run preflight errors present'); end; if isfield(pf,'data_index') && isfield(pf.data_index,'summary') && pf.data_index.summary.missing_point_count ~= 0, error('post-run data index missing points'); end; if isfield(pf,'stats_inventory') && isfield(pf.stats_inventory,'summary') && pf.stats_inventory.summary.stats_missing_count ~= 0, error('post-run stats inventory missing stats'); end; if isfield(pf,'run_health_report') && isfield(pf.run_health_report,'issue_counts') && pf.run_health_report.issue_counts.error ~= 0, error('post-run health errors present'); end"
```

Cable-acceleration unit correction after user clarification on 2026-05-28:

- User clarified CF cable acceleration is already `m/s^2`; no unit conversion should be applied.
- Updated `config/zhishan_config.json` so `cable_accel` keeps daily median baseline removal, removes `value_scale`, and filters by `[-2, 2] m/s^2`.
- Reran `cable_accel` and `cable_accel_spectrum`.
- New run status: `ok`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_204936.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_203939.txt`
- Post-run cable-only preflight passed: data index found 16/16 module-point files, stats inventory expected/existing 2/2, run health issues/errors/warnings all `0`.
- Direct check confirmed `value_scale_applied=0` for CF data.
- New `cable_accel_stats.xlsx` min/max all stay within `[-2,2]`; RMS10minMax values are:
  - `CF-1=1.224`, `CF-2=1.031`, `CF-3=1.784`, `CF-4=1.797`, `CF-5=1.760`, `CF-6=1.732`, `CF-7=1.310`, `CF-8=1.157`.
- Cleaned valid-point ratios after daily median removal and `[-2,2]` filtering:
  - `CF-1=7.976%`, `CF-2=6.201%`, `CF-3=88.140%`, `CF-4=87.539%`, `CF-5=22.970%`, `CF-6=51.908%`, `CF-7=5.963%`, `CF-8=8.965%`.
- Interpretation: with CF units treated as native `m/s^2`, the `[-2,2]` filter is very aggressive for `CF-1/2/7/8` and still aggressive for `CF-5/6`; these monthly raw waveform plots remain visually dense/saturated. `CF-3/4` retain most data. Frequency/force outputs still exist for all CF points, mostly 27 valid days each (`CF-5=25`).

Cable-acceleration `[-10,10] m/s^2` follow-up on 2026-05-28:

- Updated `config/zhishan_config.json` so `cable_accel` keeps daily median baseline removal, no `value_scale`, and filters by `[-10, 10] m/s^2`.
- The first full run with normal CF group plotting reached very high memory while generating the raw full-month group plot; it was stopped and rerun with `cfg.groups.cable_accel=struct()` to skip only the raw/RMS cable group plots. Single-point time-history images, single-point RMS images, stats, and spectrum/force outputs were regenerated.
- Final no-group run status: `ok`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_222416.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_220447.txt`
- Post-run cable-only preflight passed with the no-group config: data index found 16/16 module-point files, stats inventory expected/existing 2/2, run health issues/errors/warnings all `0`.
- New `cable_accel_stats.xlsx` min/max all stay within `[-10,10]`; RMS10minMax values are:
  - `CF-1=8.544`, `CF-2=7.447`, `CF-3=9.611`, `CF-4=9.653`, `CF-5=9.738`, `CF-6=8.736`, `CF-7=8.253`, `CF-8=9.048`.
- Cleaned valid-point ratios after daily median removal and `[-10,10]` filtering:
  - `CF-1=37.455%`, `CF-2=29.904%`, `CF-3=99.087%`, `CF-4=99.111%`, `CF-5=61.800%`, `CF-6=96.489%`, `CF-7=28.376%`, `CF-8=41.913%`.
- Spectrum/force outputs exist for all `CF-1~CF-8`, 27 valid days each.
- Interpretation: `[-10,10]` is much less destructive than `[-2,2]`. `CF-3/4/6` become broadly usable by retention, while `CF-1/2/7/8` still have low retention and visually dense raw monthly plots. For these points, report interpretation should rely more on 10 min RMS and spectrum/force outputs than on raw full-month waveform plots.

Cable-acceleration threshold sweep and `[-100,100] m/s^2` candidate on 2026-05-28:

- User asked to stop manual one-by-one trials and let Codex search candidate thresholds.
- Added and ran `tmp/evaluate_zhishan_cable_accel_thresholds.m`, which loads each CF point once after daily median baseline removal and no unit scaling, then evaluates global absolute thresholds `[2 5 10 15 20 30 40 50 75 100 150 200]`.
- Threshold evaluation output:
  - `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_eval_20260528_225644.xlsx`
- Global threshold summary from the sweep:
  - `±20`: minimum retention `52.315%`, mean retention `77.104%`.
  - `±50`: minimum retention `89.594%`, mean retention `94.528%`.
  - `±75`: minimum retention `94.738%`, mean retention `97.908%`.
  - `±100`: minimum retention `97.234%`, mean retention `99.042%`.
  - `±150`: minimum retention `98.950%`, mean retention `99.724%`.
- Selected `[-100,100] m/s^2` as the current global candidate because it keeps at least `97.2%` of each point while still removing very large spikes (`AbsMax` before threshold reaches `~4.5e4~6.6e4` on several points).
- Updated `config/zhishan_config.json` to `[-100,100]`, kept `daily_median`, no `value_scale`.
- Reran `cable_accel` and `cable_accel_spectrum` with cable group plots disabled to avoid raw full-month group plot memory spikes.
- Updated `config/zhishan_config.json` so `groups.cable_accel` is empty by default. Single-point raw plots, single-point RMS plots, stats, and cable spectrum/force outputs remain enabled; raw all-CF monthly group plotting is intentionally disabled for this high-sample-rate channel.
- Final `[-100,100]` no-group run status: `ok`
- Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260528_230859.json`
- Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260528_225902.txt`
- Post-run cable-only preflight passed with no group plots expected: data index found 16/16 module-point files, stats inventory expected/existing 2/2, run health issues/errors/warnings all `0`.
- Current-config cable-only preflight after disabling `groups.cable_accel` also passed:
  - `preflight=ok`, data index `16/16`, stats inventory `2/2`, run-health issues/errors/warnings all `0`, reporting contract `groups=0`.
  - Data index: `D:\芝山大桥数据\2026年1-3月\run_logs\data_index_20260528_232759.json`
  - Run health: `D:\芝山大桥数据\2026年1-3月\run_logs\run_health_20260528_232759.json`
- `cable_accel_stats.xlsx` min/max all stay within `[-100,100]`; RMS10minMax values:
  - `CF-1=55.986`, `CF-2=54.739`, `CF-3=29.779`, `CF-4=29.833`, `CF-5=97.222`, `CF-6=18.886`, `CF-7=71.575`, `CF-8=60.559`.
- Spectrum/force outputs exist for all `CF-1~CF-8`, 27 valid days each.
- Visual assessment: `CF-3` is readable under `[-100,100]`; `CF-1/8` still show dense raw monthly bands. Further threshold changes alone will not make those raw month plots clean without deleting too much real/high-amplitude data. Use RMS/envelope-style plots for report readability while keeping `[-100,100]` as the data-cleaning candidate.
- Generated diagnostic 30-minute envelope/RMS plots with `tmp/plot_zhishan_cable_accel_envelope.m`:
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_包络30min`
  - Manifest: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_包络30min\cable_accel_envelope30_manifest.xlsx`
  - The envelope plots are much more readable than raw full-month waveform plots, but `CF-1/8` still show broad real/noisy amplitude bands. This supports the conclusion that visualization/aggregation is needed; threshold tuning alone is not enough.
- Added formal cable-acceleration 30 min envelope/RMS plotting to `+bms/+analyzer/DynamicAccelerationPlotService.m` and enabled it only for `cable_accel` in `DynamicAccelerationPipeline.spec`.
- Added strategy evaluation script `tmp/evaluate_zhishan_cable_accel_strategies.m`, which compares `global100`, `perpoint95`, `perpoint98`, and `perpoint99` without overwriting config.
  - Output: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_strategy_eval_20260528_233314\cable_accel_strategy_eval.xlsx`
  - Representative `perpoint95` thresholds: `CF-1=50`, `CF-2=75`, `CF-3=5`, `CF-4=5`, `CF-5=100`, `CF-6=10`, `CF-7=75`, `CF-8=75`.
  - Assessment: `perpoint95` improves some RMS plots but is too aggressive for formal spectrum/force calculation because it deletes up to about 5% of high-amplitude samples. Keep formal cleaning at `global100` and use the new envelope/RMS plot for report readability.
- Reran formal `run_all` for `doCableAccel` only after integrating envelope plotting.
  - Status: `ok`
  - Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260529_000952.json`
  - Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260529_000159.txt`
  - New formal envelope images: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_包络30min\CableAccelEnvelope30_CF-1_20260302_20260330.jpg` through `CF-8`.
  - Current-config `doCableAccel` preflight after the formal run passed: data index `8/8`, stats inventory `1/1`, run-health issues/errors/warnings all `0`, reporting contract `groups=0`.
- Added a quick review board for user-side visual approval:
  - `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_envelope30_review_board_20260529_001853.jpg`
  - It is only for overview; use the individual `CableAccelEnvelope30_CF-*` images for detailed inspection because the review board necessarily downscales each wide monthly plot.
- Added a threshold strategy decision summary:
  - Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_strategy_decision_20260529_002850.md`
  - CSV: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_strategy_decision_20260529_002850.csv`
  - Conclusion: keep formal calculation at `global100`. `perpoint95` is only a visual/display-clipping candidate for `CF-1/3/4/6`; it gives little benefit for `CF-5/8` and should not be used for spectrum/force calculation by default.
- Fixed the 30 min envelope plot fill so percentile bands break at missing bins instead of drawing triangular bridges across data gaps.
  - Added regression coverage: `test_dynamic_series_service/envelopeBandBreaksAcrossMissingBins`.
  - Reran formal `run_all` for `doCableAccel` only after the fix.
  - Status: `ok`
  - Manifest: `D:\芝山大桥数据\2026年1-3月\run_logs\analysis_manifest_20260529_004630.json`
  - Run log: `D:\芝山大桥数据\2026年1-3月\run_logs\run_log_20260529_003841.txt`
  - Updated formal envelope images: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_包络30min\CableAccelEnvelope30_CF-1_20260302_20260330.jpg` through `CF-8` (last written 2026-05-29 00:41~00:46).
  - Current-config `doCableAccel` preflight after the rerun passed: data index `8/8`, stats inventory `1/1`, run-health issues/errors/warnings all `0`, reporting contract `groups=0`.
  - Supersedes the earlier quick review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_envelope30_review_board_20260529_004723.jpg`.
- Added a reusable auto-tuning script for the user's "do not try thresholds one by one" request:
  - Script: `D:\MatlabProjects\Guanbing\scripts\auto_tune_zhishan_cable_accel_thresholds.m`
  - Rule: choose the formal global threshold as the smallest grid value where every CF point keeps at least `97%`; choose a point-level display threshold from the `95%` keep candidate only when RMS30 max drops by at least `25%` and keep loss is at most `5%`.
  - The script now also writes a point-level diagnosis so the output distinguishes "threshold display tuning helps" from "safe tighter threshold has limited RMS benefit" or "no safe tighter threshold at target keep rate".
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest.html`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest_render.png`
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_latest.json`
  - Latest acceptance Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_acceptance_latest.md`
  - Latest acceptance JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_acceptance_latest.json`
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_072726`
  - Summary: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_072726\cable_accel_auto_tune_summary.md`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_072726\cable_accel_auto_tune.xlsx`
  - Selected-display review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_072726\auto_tune_selected_visual_review_board.jpg`
  - Formal-vs-selected review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_072726\auto_tune_formal_vs_selected_review_board.jpg`
  - Per-point comparison images: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_auto_tune_20260529_072726\formal_vs_selected_compare\FormalVsSelected_CF-*.jpg`
  - Auto-selected formal threshold remains `[-100,100] m/s^2`.
  - Auto-selected display thresholds: `CF-1=50`, `CF-3=5`, `CF-4=5`, `CF-6=10`; `CF-2/5/7/8` stay at `100`.
  - Point diagnosis: threshold display tuning helps `CF-1/3/4/6`; threshold-limited or data-quality review points are `CF-2/5/7/8`.
  - Acceptance conclusion: no single stricter global threshold satisfies both data retention and clean monthly visualization. Use global formal clipping for spectrum/force; use point-level display clipping plus 30 min envelope/RMS plots for review.
  - This is for review/report display only; formal spectrum/force calculation should still use the global `[-100,100] m/s^2` cleaning unless the user explicitly approves point-level calculation changes.
  - Browser render check used Microsoft Edge headless through Playwright with system Edge; Chinese title/note rendered, `imageCount=10`, `completeCount=10`, `tableRows=9`, highlighted `changedRows=[CF-1,CF-3,CF-4,CF-6]`, diagnosis column present, no missing image sources.
  - Focused MATLAB tests passed after this update: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
- Added a reusable single-threshold preview script:
  - Script: `D:\MatlabProjects\Guanbing\scripts\preview_zhishan_cable_accel_threshold.m`
  - It removes cable-accel thresholds only in memory, keeps daily median correction, applies the requested absolute threshold, and writes a separate preview folder without overwriting formal outputs or `zhishan_config.json`.
- Ran requested `[-20,20] m/s^2` preview:
  - Output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_071800_abs20`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_071800_abs20\cable_accel_threshold_preview.xlsx`
  - Markdown summary: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_071800_abs20\cable_accel_threshold_preview.md`
  - Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_071800_abs20\cable_accel_threshold_preview_abs20_review_board.jpg`
  - Keep rates: `CF-1=66.157%`, `CF-2=54.897%`, `CF-3=99.821%`, `CF-4=99.821%`, `CF-5=77.167%`, `CF-6=99.916%`, `CF-7=52.315%`, `CF-8=66.741%`.
  - Assessment: `±20` improves `CF-3/4/6` but still deletes about one third to one half of `CF-1/2/7/8` and about one quarter of `CF-5`. The broad monthly bands for those points look like actual high-amplitude/noisy signal plus overplotting; a global threshold alone will not make every raw full-month plot clean without excessive data loss.
- Added a segment-quality diagnostic for the remaining hard points:
  - Script: `D:\MatlabProjects\Guanbing\scripts\diagnose_zhishan_cable_accel_segments.m`
  - It reads `CF-2/5/7/8`, keeps daily median correction, applies formal `±100`, then sweeps removal of top `2/5/10/15/20%` high-RMS 1-hour segments. This is display/quality diagnosis only and does not change formal config.
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_segment_quality_20260529_074646`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_segment_quality_20260529_074646\cable_accel_segment_quality.xlsx`
  - Summary: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_segment_quality_20260529_074646\cable_accel_segment_quality.md`
  - Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_segment_quality_20260529_074646\cable_accel_segment_quality_review_board.jpg`
  - Selected segment candidate uses top `5%` high-RMS hours for all four points because it is the best option with at least `90%` kept data.
  - Results:
    - `CF-2`: keep `94.273%`, RMS max reduction `14.7%`; limited benefit. This behaves like persistent wide-amplitude/noisy signal, not isolated bad intervals.
    - `CF-5`: keep `93.901%`, RMS max reduction `32.7%`; segment filter helps display, but should remain display/quality filtering unless user accepts data removal.
    - `CF-7`: keep `94.783%`, RMS max reduction `25.0%`; segment filter helps display.
    - `CF-8`: keep `93.227%`, RMS max reduction `14.5%`; limited benefit. This also behaves like persistent/noisy signal rather than a few isolated spikes.
  - Segment sweep table in the workbook confirms more aggressive `10/15/20%` segment removal improves RMS further but drops kept data below `90%` for these points, so it is not a good default.
- Added a combined display-candidate generator:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_display_candidate.m`
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest.json`
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest.html`
  - Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_latest_render.png`
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_085916`
  - Summary: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_085916\cable_accel_display_candidate.md`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_085916\cable_accel_display_candidate.xlsx`
  - Detail review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_085916\cable_accel_display_candidate_review_board.jpg`
  - Trend review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_candidate_20260529_085916\cable_accel_display_trend_review_board.jpg`
  - Stable report output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate`
  - Stable detail board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayCandidate_ReviewBoard.jpg`
  - Stable trend board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayTrend_ReviewBoard.jpg`
  - Stable manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayCandidate_manifest.xlsx`
  - Stable per-point images: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayCandidate_CF-1.jpg` through `CF-8.jpg`
  - Stable per-point trend images: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_candidate\CableAccelDisplayTrend_CF-1.jpg` through `CF-8.jpg`
  - Combined display strategy:
    - `CF-1`: display threshold `abs<=50`, keep `95.013%`, RMS30 max reduction `45.9%`.
    - `CF-3`: display threshold `abs<=5`, keep `95.863%`, RMS30 max reduction `83.1%`.
    - `CF-4`: display threshold `abs<=5`, keep `95.901%`, RMS30 max reduction `82.9%`.
    - `CF-6`: display threshold `abs<=10`, keep `96.489%`, RMS30 max reduction `37.8%`.
    - `CF-5`: formal `abs<=100` plus display-only top `5%` RMS30 segment filtering, keep `93.505%`, RMS30 max reduction `30.7%`.
    - `CF-7`: formal `abs<=100` plus display-only top `5%` RMS30 segment filtering, keep `94.795%`, RMS30 max reduction `30.1%`.
    - `CF-2` and `CF-8`: keep formal `abs<=100`; mark as persistent wide-band signal / quality limitation rather than forcing more deletion.
  - The detailed plot style overlays a light `5%~95%` band, stronger `25%~75%` band, median line, and RMS30 panel. The trend plots zoom the central `25%~75%`/median range so persistent wide-band points like `CF-2/8` remain readable without extra deletion.
  - HTML render check passed using headless Edge after the trend-output update: title/note rendered, `imageCount=18`, `completeCount=18`, `tableRows=9`, `qualityRows=2`, no missing image sources.
  - Focused MATLAB tests passed after this update: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
  - This combined candidate is the conservative display proposal. It does not alter formal spectrum/force calculation.

- Added an automatic display grid-search optimizer:
  - Script: `D:\MatlabProjects\Guanbing\scripts\optimize_zhishan_cable_accel_display_grid.m`
  - Purpose: stop manual threshold trials by searching `threshold abs` and top-RMS 30 min segment removal together.
  - The search uses sampled data for scoring speed, then recomputes the selected candidate for each point with the full data before writing the selected summary and plots.
  - Search grid: thresholds `[5 10 15 20 30 40 50 75 100] m/s^2`; segment removal `[0 2 5 8 10]%` of highest-RMS 30 min bins; minimum kept-data target `90%`.
  - Formal spectrum/force calculation remains unchanged at `daily_median + [-100,100]`.
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_latest.json`
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_latest.html`
  - Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_latest_render.png`
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242\cable_accel_display_grid_search.xlsx`
  - Selected CSV: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242\cable_accel_display_grid_search_selected.csv`
  - Detail review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242\cable_accel_display_grid_selected_review_board.jpg`
  - Trend review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_grid_search_20260529_092242\cable_accel_display_grid_selected_trend_board.jpg`
  - Selected strategies after full-data recomputation:
    - `CF-1`: `abs<=50 + top 2% RMS30 removal`, keep `93.317%`, RMS30 max reduction `52.3%`.
    - `CF-2`: `abs<=75 + top 2% RMS30 removal`, keep `95.042%`, RMS30 max reduction `25.3%`.
    - `CF-3`: `abs<=5 + top 2% RMS30 removal`, keep `94.891%`, RMS30 max reduction `88.3%`.
    - `CF-4`: `abs<=5 + top 2% RMS30 removal`, keep `94.862%`, RMS30 max reduction `88.2%`.
    - `CF-5`: `abs<=75 + top 5% RMS30 removal`, keep `91.742%`, RMS30 max reduction `42.7%`.
    - `CF-6`: `abs<=10 + top 5% RMS30 removal`, keep `93.633%`, RMS30 max reduction `54.3%`.
    - `CF-7`: `abs<=75 + top 5% RMS30 removal`, keep `93.991%`, RMS30 max reduction `34.5%`.
    - `CF-8`: `abs<=75 + top 2% RMS30 removal`, keep `93.280%`, RMS30 max reduction `26.0%`.
  - HTML render check passed with headless Edge: title/note rendered, `imageCount=18`, `completeCount=18`, `tableRows=9`, no missing image sources.
  - Focused MATLAB tests passed after this update: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
  - This is the latest aggressive display candidate. It is better than the conservative candidate for `CF-2/8`, but still should stay display-only unless the user explicitly approves applying these stricter rules to formal calculation.

- Added a display-candidate comparison package:
  - Script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_display_candidates.m`
  - Purpose: compare the conservative candidate and aggressive grid-search candidate in one review page.
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_latest.json`
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_latest.html`
  - Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_latest_render.png`
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_20260529_093755`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_20260529_093755\cable_accel_display_compare.xlsx`
  - CSV: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_compare_20260529_093755\cable_accel_display_compare.csv`
  - Comparison conclusions:
    - Prefer grid display: `CF-2`, `CF-6`.
    - Grid improves previously limited point: `CF-8`.
    - Aggressive/review data loss: `CF-5`.
    - Conservative display acceptable: `CF-1`, `CF-3`, `CF-4`, `CF-7`.
  - HTML render check passed with headless Edge: title/note rendered, `imageCount=4`, `completeCount=4`, `tableRows=9`, `preferRows=3`, `aggressiveRows=1`, no missing image sources.
  - This comparison page is now the easiest artifact for user review of whether the threshold-search result is satisfactory.

- Added a final recommended display package:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_display_recommendation.m`
  - Purpose: turn the comparison result into one recommended display policy so the user does not need to choose point by point.
  - Recommendation logic:
    - Use grid-search result for `CF-2`, `CF-6`, and `CF-8`.
    - Keep the conservative result for `CF-1`, `CF-3`, `CF-4`, `CF-5`, and `CF-7`.
    - `CF-5` remains conservative because the grid option was marked aggressive/data-loss review.
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_latest.json`
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_latest.html`
  - Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_latest_render.png`
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_20260529_095537`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_20260529_095537\cable_accel_display_recommendation.xlsx`
  - CSV: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_recommendation_20260529_095537\cable_accel_display_recommendation.csv`
  - Stable output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation`
  - Stable manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendation_manifest.xlsx`
  - Stable policy JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendation_policy.json`
  - Stable detail images: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendationDetail_CF-1.jpg` through `CF-8.jpg`
  - Stable trend images: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendationTrend_CF-1.jpg` through `CF-8.jpg`
  - Recommended policies:
    - `CF-1`: `abs<=50`, keep `95.013%`, RMS30 max reduction `45.9%`.
    - `CF-2`: `abs<=75 + top 2% RMS30 removal`, keep `95.042%`, RMS30 max reduction `25.3%`.
    - `CF-3`: `abs<=5`, keep `95.863%`, RMS30 max reduction `83.1%`.
    - `CF-4`: `abs<=5`, keep `95.901%`, RMS30 max reduction `82.9%`.
    - `CF-5`: `formal abs<=100 + top 5% RMS30 removal`, keep `93.505%`, RMS30 max reduction `30.7%`.
    - `CF-6`: `abs<=10 + top 5% RMS30 removal`, keep `93.633%`, RMS30 max reduction `54.3%`.
    - `CF-7`: `formal abs<=100 + top 5% RMS30 removal`, keep `94.795%`, RMS30 max reduction `30.1%`.
    - `CF-8`: `abs<=75 + top 2% RMS30 removal`, keep `93.280%`, RMS30 max reduction `26.0%`.
  - HTML render check passed with headless Edge after switching to stable image paths: title/note rendered, `imageCount=16`, `completeCount=16`, `stableImageCount=16`, `tableRows=9`, `gridRows=3`, no missing image sources.
  - Focused MATLAB tests passed after this update: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.
  - This recommendation page is now the main artifact to show the user as the automated-search result.

- Added a formal-baseline recomputation review for the final recommendation:
  - Script: `D:\MatlabProjects\Guanbing\scripts\review_zhishan_cable_accel_recommendation_vs_formal.m`
  - Purpose: load original `CF-1~CF-8` source data, recompute formal display baseline `daily_median + abs<=100`, recompute the recommended display policy from stable `policy.json`, and plot them side by side.
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_latest.json`
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_latest.html`
  - Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_latest_render.png`
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_20260529_100515`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommendation_vs_formal_20260529_100515\cable_accel_recommendation_vs_formal.xlsx`
  - Stable review directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\formal_baseline_review`
  - Stable review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\formal_baseline_review\CableAccelRecommendationVsFormal_ReviewBoard.jpg`
  - Full-data recomputation results:
    - `CF-1`: keep delta `-4.500%`, RMS30 max reduction `45.9%`.
    - `CF-2`: keep delta `-3.697%`, RMS30 max reduction `25.3%`.
    - `CF-3`: keep delta `-4.130%`, RMS30 max reduction `83.1%`.
    - `CF-4`: keep delta `-4.092%`, RMS30 max reduction `82.9%`.
    - `CF-5`: keep delta `-3.728%`, RMS30 max reduction `30.7%`.
    - `CF-6`: keep delta `-6.362%`, RMS30 max reduction `54.3%`.
    - `CF-7`: keep delta `-4.589%`, RMS30 max reduction `30.1%`.
    - `CF-8`: keep delta `-4.207%`, RMS30 max reduction `26.0%`.
  - HTML render check passed with headless Edge: title/note rendered, `imageCount=9`, `completeCount=9`, `tableRows=9`, `gridRows=3`, no missing image sources.
  - Focused MATLAB tests passed after this update: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.

- Added final machine-readable acceptance check:
  - Script: `D:\MatlabProjects\Guanbing\scripts\validate_zhishan_cable_accel_display_recommendation.m`
  - Purpose: validate the final display recommendation without manually opening every chart.
  - Acceptance gates:
    - Formal config still uses `daily_median + [-100,100] m/s^2` for `cable_accel`.
    - Stable policy JSON scope is `display_only`.
    - Report-ready review board and manifest exist.
    - All `CF-1~CF-8` are present.
    - Per point: recommendation keep rate `>=93%`, RMS30 max reduction `>=25%`, keep-rate loss from formal baseline no worse than `-7%`, and export image exists.
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_latest.json`
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_latest.html`
  - Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_latest_render.png`
  - Latest workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_display_acceptance_20260529_104445\cable_accel_display_acceptance.xlsx`
  - Result: overall pass `1`; all global checks pass; all 8 point checks pass.
  - Acceptance Markdown uses ASCII file names for the review board to avoid MATLAB/PowerShell mojibake for Chinese directories.
  - HTML render check passed with headless Edge after the Markdown cleanup: title rendered, `imageCount=1`, `completeCount=1`, `tableRows=16`, `passText=1`, no missing image sources.
  - Focused MATLAB tests passed after this update: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.

- Added report-ready recommended display export:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_recommended_display.m`
  - Purpose: use stable `CableAccelDisplayRecommendation_policy.json` and source data to generate final recommended cable-acceleration display charts in a fixed report-style output directory.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示`
  - Latest pointer Markdown: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommended_display_export_latest.md`
  - Latest pointer JSON: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommended_display_export_latest.json`
  - Latest HTML review page: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommended_display_export_latest.html`
  - Latest HTML render-check screenshot: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_recommended_display_export_latest_render.png`
  - Review board: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示\CableAccelRecommendationDisplay_ReviewBoard.jpg`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示\CableAccelRecommendationDisplay_manifest.xlsx`
  - Per-point report-ready images: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示\CableAccelRecommendationDisplay_CF-1_20260301_20260331.jpg` through `CF-8`.
  - The generated Markdown pointers use ASCII filenames only to avoid MATLAB/Windows UTF-8 path mojibake, while the files remain in the Chinese report directory.
  - HTML render check passed with headless Edge: title/note rendered, `imageCount=9`, `completeCount=9`, `tableRows=9`, `gridRows=3`, no missing image sources.
  - Focused MATLAB tests passed after this update: `test_cleaning_pipeline`, `test_zhishan_config`, `test_dynamic_series_service`.

- Added a stable review entry package for the final recommendation:
  - Script: `D:\MatlabProjects\Guanbing\scripts\publish_zhishan_cable_accel_display_review_pack.m`
  - Purpose: collect the final display recommendation, formal-baseline review, acceptance gate, and report-ready export into one stable entry page.
  - Stable review entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\index.html`
  - Stable README: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\README.md`
  - Stable summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelDisplayRecommendation_review_summary.json`
  - Compact contact sheet script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_display_contact_sheet.m`
  - Compact contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_推荐展示\CableAccelRecommendationDisplay_ContactSheet.jpg`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\index_render.png`
  - Result: acceptance pass `1`; HTML render check passed with headless Edge: `19/19` images loaded, `9` strategy table rows, `3` grid-picked rows, no missing image sources.
  - README and JSON now avoid embedding the Chinese report-ready directory name directly, preventing MATLAB/PowerShell mojibake while keeping the HTML link to the actual output folder.
  - This is the current stable artifact to show the user for the automatic cable-acceleration display-search result. Formal spectrum/force calculation remains unchanged at `daily_median + [-100,100] m/s^2` unless the user explicitly approves applying display rules to formal calculation.

- Added a tiered candidate ladder for further "not clean enough" review:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_display_ladder.m`
  - Purpose: automatically compare `formal baseline`, `current recommendation`, `cleaner candidate`, and `aggressive candidate` for every `CF-1~CF-8` point without manually trying one threshold at a time.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review`
  - HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review\CableAccelDisplayLadder_manifest.xlsx`
  - Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review\CableAccelDisplayLadder_ReviewBoard.jpg`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ladder_review\index_render.png`
  - Main stable entry now links to `ladder_review/index.html`.
  - Ladder HTML render check passed with headless Edge: `9/9` images loaded, `33` table rows, `8` current rows, `8` cleaner rows, `8` aggressive rows.
  - Search conclusions:
    - Current recommendation keeps all points around `93%+` and is the safer report/display default.
    - Cleaner tier keeps roughly `92%+`; for some points it equals the current recommendation, for others it removes a little more high-RMS content.
    - Aggressive tier keeps about `85%~87%` and materially reduces RMS further; use only after human approval because it drops substantially more data.

- Added a standalone cleaner-tier display export:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_ladder_tier_display.m`
  - Command used: `export_zhishan_cable_accel_ladder_tier_display('cleaner')`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export`
  - HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\CableAccelCleanerDisplay_manifest.xlsx`
  - Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\CableAccelCleanerDisplay_ReviewBoard.jpg`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\CableAccelCleanerDisplay_ContactSheet.jpg`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleaner_display_export\index_render.png`
  - Main stable entry now links to `cleaner_display_export/index.html`.
  - Cleaner HTML render check passed with headless Edge: `10/10` images loaded, `9` table rows, contact sheet and review board present.
  - Main stable page after adding cleaner link still passes: `19/19` images loaded, `9` strategy rows, `3` grid-picked rows, acceptance shown, ladder link and cleaner link present.
  - Cleaner tier strategies:
    - `CF-1`: `abs<=50 + drop top 2% RMS30`, keep `93.317%`.
    - `CF-2`: `abs<=75 + drop top 5% RMS30`, keep `92.496%`.
    - `CF-3`: `formal abs<=100 + drop top 8% RMS30`, keep `92.022%`.
    - `CF-4`: `formal abs<=100 + drop top 8% RMS30`, keep `92.022%`.
    - `CF-5`: same as current recommendation, keep `93.505%`.
    - `CF-6`: same as current recommendation, keep `93.633%`.
    - `CF-7`: `abs<=75 + drop top 5% RMS30`, keep `93.991%`.
    - `CF-8`: same as current recommendation, keep `93.280%`.

- Added a current-vs-cleaner side-by-side review:
  - Script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_current_vs_cleaner.m`
  - Purpose: compare the current recommendation and cleaner export point by point so the user can judge whether cleaner is worth promoting.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review`
  - HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review\CableAccelCurrentVsCleaner_manifest.xlsx`
  - Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review\CableAccelCurrentVsCleaner_ReviewBoard.jpg`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_vs_cleaner_review\index_render.png`
  - Main stable entry now links to `current_vs_cleaner_review/index.html`.
  - Current-vs-cleaner HTML render check passed with headless Edge: `9/9` images loaded, `9` table rows, `5` improved rows, `3` same rows.
  - Main stable page after adding comparison link still passes: `19/19` images loaded, `9` strategy rows, `3` grid-picked rows, acceptance shown, ladder link, cleaner link, and comparison link present.
  - Cleaner deltas versus current:
    - `CF-1`: keep delta `-1.696%`, RMS30 max improves `11.8%`.
    - `CF-2`: keep delta `-2.545%`, RMS30 max improves `3.5%`.
    - `CF-3`: keep delta `-3.841%`, RMS30 max improves `25.9%`.
    - `CF-4`: keep delta `-3.880%`, RMS30 max improves `26.6%`.
    - `CF-5`: same as current.
    - `CF-6`: same as current.
    - `CF-7`: keep delta `-0.804%`, RMS30 max improves `6.3%`.
    - `CF-8`: same as current.

- Added an automatic balanced final display pick:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_balanced_display_pick.m`
  - Purpose: automatically promote the best current-vs-cleaner choice per point so the user does not need to decide point by point.
  - Selection rule: use `cleaner` when cleaner keep rate is `>=92%` and RMS improvement is `>=2%`; otherwise use `current`.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick`
  - HTML review page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_manifest.xlsx`
  - Policy JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_policy.json`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_ContactSheet.jpg`
  - Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_ReviewBoard.jpg`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\index_render.png`
  - Main stable entry now links to `balanced_display_pick/index.html`.
  - Balanced HTML render check passed with headless Edge: `10/10` images loaded, `9` table rows, `5` cleaner rows, `3` current rows.
  - Main stable page after adding balanced link still passes: `19/19` images loaded, `9` strategy rows, `3` grid-picked rows, acceptance shown, ladder link, cleaner link, comparison link, and balanced link present.
  - Balanced selected sources:
    - `CF-1`: cleaner.
    - `CF-2`: cleaner.
    - `CF-3`: cleaner.
    - `CF-4`: cleaner.
    - `CF-5`: current.
    - `CF-6`: current.
    - `CF-7`: cleaner.
    - `CF-8`: current.
  - This is the current best automatic final display candidate. It remains display-only; formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

- Added a balanced final pick acceptance gate:
  - Script: `D:\MatlabProjects\Guanbing\scripts\validate_zhishan_cable_accel_balanced_display_pick.m`
  - Purpose: validate the automatic balanced final display pick without manually inspecting every file.
  - Output workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_acceptance.xlsx`
  - Output JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\CableAccelBalancedDisplay_acceptance.json`
  - Acceptance HTML: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\acceptance.html`
  - Acceptance screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_display_pick\acceptance_render.png`
  - Main stable entry now links to `balanced_display_pick/acceptance.html`.
  - Acceptance gates:
    - Formal config still uses `daily_median + [-100,100] m/s^2`.
    - Balanced policy scope is `display_only`.
    - Selection rule is recorded.
    - Manifest has all 8 points.
    - HTML, contact sheet, and review board exist.
    - All point checks pass: selected source valid, keep `>=92%`, image exists, policy point exists, and cleaner/current selection rule is satisfied.
  - Result: overall pass `1`; all global checks pass; all 8 point checks pass.
  - Acceptance HTML render check passed with headless Edge: `1/1` image loaded, `18` table rows, pass shown, `8` point `ok` rows.
  - Main stable page after adding balanced acceptance link still passes: `19/19` images loaded, `9` strategy rows, `3` grid-picked rows, acceptance shown, balanced link and balanced acceptance link present.

- Added a concise final display pack:
  - Script: `D:\MatlabProjects\Guanbing\scripts\publish_zhishan_cable_accel_final_display_pack.m`
  - Purpose: provide a short default user-facing entry that shows only the automatic balanced final pick and acceptance evidence, while the full review pack remains available separately.
  - Final entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
  - Final README: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\FINAL_README.md`
  - Final summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_summary.json`
  - Final rules workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.xlsx`
  - Final rules CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.csv`
  - Final render screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index_render.png`
  - Full review entry `index.html` now links to `final_index.html` as the recommended default entry.
  - Final rules table lists each `CF` point's selected source, absolute threshold, RMS30 top-percent segment removal, keep rate, RMS30 max, and acceptance pass flag.
  - Final entry render check passed with headless Edge: `2/2` images loaded, `9` strategy table rows, `5` cleaner rows, `3` current rows, balanced acceptance pass shown, rules link, full-pack link, and acceptance link present.
  - Main stable page after adding final link still passes: `19/19` images loaded, final link present, acceptance shown.
  - This is now the recommended first page to show the user. Use `index.html` only when reviewing the full search history and alternatives.

- Added final report-ready image export for the automatic balanced pick:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_final_display_images.m`
  - Purpose: copy the accepted balanced final pick into a report-facing folder with per-point images, compact contact sheet, review board, manifest, README, and HTML index.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\CableAccelFinalDisplay_manifest.xlsx`
  - Manifest CSV: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\CableAccelFinalDisplay_manifest.csv`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\CableAccelFinalDisplay_ContactSheet.jpg`
  - Review board: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\CableAccelFinalDisplay_ReviewBoard.jpg`
  - Per-point images: `CableAccelFinalDisplay_CF-1_20260301_20260331.jpg` through `CableAccelFinalDisplay_CF-8_20260301_20260331.jpg`
  - Render-check screenshot: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最终推荐展示\index_render.png`
  - Exported rule mix: `CF-1/2/3/4/7` use cleaner; `CF-5/6/8` use current.
  - Report image HTML file check passed: `10` image refs, `0` missing/unreadable, `9` table rows, `5` cleaner rows, `3` current rows.
  - Headless Edge screenshot check produced a readable `1600x1200` PNG.
  - `final_index.html`, `FINAL_README.md`, and `CableAccelFinalDisplay_summary.json` now link to this final report-image folder and manifest.
  - Final entry recheck after adding report-image links passed: `2/2` image refs, `0` missing images, `9` table rows, `5` cleaner rows, `3` current rows, `Balanced acceptance pass=1`, all required links present, and readable `1600x1000` render screenshot.

- Added a stricter visual fallback candidate after inspecting the final contact sheet:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_polished_min90_display_pick.m`
  - Purpose: keep the balanced final recommendation intact, but generate a more visually polished display-only alternative when the user still feels the final version is not clean enough.
  - Selection concept: keep rate target `>=90%`, then lower RMS30 max more aggressively than the balanced final pick.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\CableAccelPolishedMin90_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\CableAccelPolishedMin90_ContactSheet.jpg`
  - Render screenshot: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\polished_min90_display_pick\index_render.png`
  - Rules:
    - `CF-1`: `abs<=50 + drop top 5% RMS30`, keep `90.762%`, RMS30 max `27.154`, `8.96%` lower than balanced final.
    - `CF-2`: `abs<=75 + drop top 5% RMS30`, keep `92.496%`, same as balanced final.
    - `CF-3`: `abs<=5 + drop top 8% RMS30`, keep `90.307%`, RMS30 max `2.541`, `26.17%` lower than balanced final.
    - `CF-4`: `abs<=5 + drop top 8% RMS30`, keep `90.354%`, RMS30 max `2.513`, `27.28%` lower than balanced final.
    - `CF-5`: `abs<=50`, keep `90.396%`, RMS30 max `50.000`, `27.01%` lower than balanced final.
    - `CF-6`: `abs<=10 + drop top 8% RMS30`, keep `90.869%`, RMS30 max `5.804`, `13.15%` lower than balanced final.
    - `CF-7`: `abs<=50 + drop top 2% RMS30`, keep `90.868%`, RMS30 max `41.750`, `13.62%` lower than balanced final.
    - `CF-8`: `abs<=75 + drop top 5% RMS30`, keep `91.033%`, RMS30 max `40.013`, `6.18%` lower than balanced final.
  - Polished candidate acceptance pass: `1`; all 8 points keep at least `90%`.
  - Polished HTML/file check passed: `9` image refs, `0` missing images, `9` table rows, `8` pass rows, `0` fail rows, readable `1600x1200` render screenshot.
  - `final_index.html`, `README.md`, `FINAL_README.md`, `CableAccelFinalDisplay_summary.json`, and the full review `index.html` now link to `polished_min90_display_pick/index.html`.
  - Recheck after relinking passed: final entry has `2` image refs / `0` missing images / polished link present; full review entry has `19` image refs / `0` missing images / polished link present.

- Added a keep-rate ladder matrix so threshold selection no longer requires one-off manual retries:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_keep_ladder_review.m`
  - Purpose: build a visual candidate matrix for each `CF` point at keep-rate targets `95%`, `93%`, `92%`, `90%`, `88%`, and `85%`.
  - Method: reuse the existing threshold/RMS30 grid search, then recompute selected candidates on full data for each point/target.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review\CableAccelKeepLadder_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\keep_ladder_review\CableAccelKeepLadder_ContactSheet.jpg`
  - Per-point ladder images: `plots\CableAccelKeepLadder_CF-1.jpg` through `CF-8.jpg`.
  - Result: `48` full-data candidate rows (`8` points x `6` keep targets); each point has all `6` rows, and all rows pass the target keep rate.
  - HTML/file check passed: `9` image refs, `0` missing images, `49` table rows, `48` manifest rows.
  - `final_index.html`, `README.md`, `FINAL_README.md`, `CableAccelFinalDisplay_summary.json`, and the full review `index.html` now link to `keep_ladder_review/index.html`.
  - Recheck after relinking passed: final entry has `2` image refs / `0` missing images / polished link present / keep-ladder link present; full review entry has `19` image refs / `0` missing images / polished link present / keep-ladder link present.
  - The ladder shows the tradeoff explicitly: for example `CF-5` goes from `93%` keep with RMS30 max `68.5`, to `90%` keep with RMS30 max `50.0`, to `85%` keep with RMS30 max `32.8`; `CF-8` goes from `93%` keep with RMS30 max `42.6`, to `88%` keep with RMS30 max `35.2`, to `85%` keep with RMS30 max `29.5`.

- Added a keep/RMS tradeoff dashboard with automatic knee suggestions:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_tradeoff_dashboard.m`
  - Purpose: convert the keep-rate ladder into per-point tradeoff curves and recommend an automatic knee point without allowing the recommendation to be worse than the current balanced final pick.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard\index.html`
  - Suggestions workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard\CableAccelTradeoffDashboard_suggestions.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\tradeoff_dashboard\CableAccelTradeoffDashboard_ContactSheet.jpg`
  - Suggested automatic knee result:
    - Keep current balanced final for `CF-1`, `CF-2`, `CF-6`, `CF-7`, and `CF-8`.
    - Move `CF-3` to keep-target `92%`: keep `92.674%`, RMS30 max `2.862`, `16.86%` lower than current final while keeping slightly more data than current final.
    - Move `CF-4` to keep-target `90%`: keep `90.354%`, RMS30 max `2.513`, `27.28%` lower than current final with `1.67%` extra data loss.
    - Move `CF-5` to keep-target `90%`: keep `90.396%`, RMS30 max `50.000`, `27.01%` lower than current final with `3.11%` extra data loss.
  - HTML/file check passed: tradeoff dashboard `9` image refs / `0` missing images / `9` table rows.
  - `final_index.html`, `README.md`, `FINAL_README.md`, `CableAccelFinalDisplay_summary.json`, and the full review `index.html` now link to `tradeoff_dashboard/index.html`.
  - Recheck after relinking passed: final entry has `2` image refs / `0` missing images / tradeoff and keep-ladder links present; full review entry has `19` image refs / `0` missing images / tradeoff and keep-ladder links present.

- Added a complete auto-knee display candidate generated from the tradeoff suggestions:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_auto_knee_display_pick.m`
  - Purpose: produce a full 8-point visual candidate from the tradeoff-dashboard knee suggestions, so the suggestions are not only numbers/curves.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_ContactSheet.jpg`
  - Strategy:
    - Keep balanced final for `CF-1`, `CF-2`, `CF-6`, `CF-7`, and `CF-8`.
    - Use auto-knee stricter settings for `CF-3`, `CF-4`, and `CF-5`.
  - Auto-knee rules:
    - `CF-3`: `abs<=5 + drop top 5% RMS30`, keep `92.674%`, RMS30 max `2.862`, `16.86%` lower than balanced final.
    - `CF-4`: `abs<=5 + drop top 8% RMS30`, keep `90.354%`, RMS30 max `2.513`, `27.28%` lower than balanced final.
    - `CF-5`: `abs<=50`, keep `90.396%`, RMS30 max `50.000`, `27.01%` lower than balanced final.
  - Result: auto-knee pass `1`; all 8 point rows pass keep/RMS checks.
  - HTML/file check passed: auto-knee page `9` image refs / `0` missing images / `9` table rows / `3` auto-knee rows / `5` balanced-final rows / `8` manifest rows.
  - Visual contact sheet was inspected. Auto-knee currently looks like the best automated candidate to review first because it avoids over-filtering all points while improving the points with clear tradeoff gains.
  - `final_index.html`, `README.md`, `FINAL_README.md`, `CableAccelFinalDisplay_summary.json`, and full review `index.html` now link to `auto_knee_display_pick/index.html`.
  - Recheck after relinking passed: final entry has `2` image refs / `0` missing images / auto-knee and tradeoff links present; full review entry has `19` image refs / `0` missing images / auto-knee and tradeoff links present.

- Added report-ready image export for the auto-knee candidate:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_auto_knee_report_images.m`
  - Purpose: copy the auto-knee candidate into a report-facing folder after visual/numeric checks, so accepted charts can be used directly.
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示\CableAccelAutoKneeReport_manifest.xlsx`
  - Manifest CSV: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示\CableAccelAutoKneeReport_manifest.csv`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_auto_knee_推荐展示\CableAccelAutoKneeReport_ContactSheet.jpg`
  - Per-point report images: `CableAccelAutoKneeReport_CF-1_20260301_20260331.jpg` through `CableAccelAutoKneeReport_CF-8_20260301_20260331.jpg`
  - File check passed: auto-knee report page `9` image refs / `0` missing images / `9` table rows / `3` auto-knee rows / `5` balanced-final rows / `8` manifest rows.
  - `final_index.html`, `FINAL_README.md`, `CableAccelFinalDisplay_summary.json`, and full review `index.html` now link to this auto-knee report-ready folder and manifest.
  - Recheck after relinking passed: auto-knee report page, final entry, and full review entry all have `0` missing images; final entry and full review entry both expose auto-knee report links.

- Ran a single global `[-20,20] m/s^2` cable-acceleration threshold preview on 2026-05-29:
  - Command: `matlab -batch "addpath(genpath(pwd)); r = preview_zhishan_cable_accel_threshold(20); disp(r.output_folder);"`
  - Output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20\cable_accel_threshold_preview.xlsx`
  - Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20\cable_accel_threshold_preview_abs20_review_board.jpg`
  - Keep rates: `CF-1=66.157%`, `CF-2=54.897%`, `CF-3=99.821%`, `CF-4=99.821%`, `CF-5=77.167%`, `CF-6=99.916%`, `CF-7=52.315%`, `CF-8=66.741%`.
  - RMS30 max values: `CF-1=18.450`, `CF-2=17.860`, `CF-3=13.249`, `CF-4=13.335`, `CF-5=19.920`, `CF-6=13.800`, `CF-7=19.365`, `CF-8=16.201`.
  - Visual/numeric conclusion: not recommended as a single global rule. It over-filters `CF-1/2/7/8`, still leaves persistent high RMS on `CF-5`, and does not materially improve the points already clean under point-specific/auto-knee display rules.
  - This preview is display/diagnostic only; formal config remains `daily_median + [-100,100] m/s^2`.

- Added a balanced-final vs auto-knee side-by-side review on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_balanced_vs_auto_knee.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review\CableAccelBalancedVsAutoKnee_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\balanced_vs_auto_knee_review\CableAccelBalancedVsAutoKnee_ContactSheet.jpg`
  - The left side is balanced final; the right side is auto-knee.
  - Results: auto-knee changes only `CF-3/CF-4/CF-5`; the other five points stay the same as balanced final.
  - Numeric deltas versus balanced final: `CF-3` keeps `+0.652%` more data and lowers RMS30 max by `16.858%`; `CF-4` loses `1.668%` more data and lowers RMS30 max by `27.279%`; `CF-5` loses `3.109%` more data and lowers RMS30 max by `27.010%`.
  - File check passed: side-by-side page has `9` image refs, `0` missing images, `9` table rows, `3` auto-knee rows, and `5` balanced-final rows.
  - `final_index.html`, `README.md`, `CableAccelFinalDisplay_summary.json`, and `CableAccelDisplayRecommendation_review_summary.json` now link to the side-by-side review.
  - This remains display-only; formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

- Added an independent auto-knee acceptance gate on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\validate_zhishan_cable_accel_auto_knee_display_pick.m`
  - Acceptance page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\acceptance.html`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_acceptance.xlsx`
  - JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_knee_display_pick\CableAccelAutoKnee_acceptance.json`
  - Acceptance pass: `1`
  - Global checks all passed: formal config still `daily_median + [-100,100]`, manifest has 8 points, HTML/contact sheet/report output/side-by-side comparison exist, all point checks pass, `3` auto-knee rows and `5` balanced-final rows.
  - Point checks: `CF-3/CF-4/CF-5` are auto-knee rows with RMS30 max improvements of `16.858%`, `27.279%`, and `27.010%`; all points keep at least `90%` of finite data.
  - `final_index.html` now states that auto-knee is the current first-review candidate and links to auto-knee acceptance.
  - Full review `index.html`, `FINAL_README.md`, `README.md`, `CableAccelFinalDisplay_summary.json`, and `CableAccelDisplayRecommendation_review_summary.json` now expose the auto-knee acceptance result.
  - File checks passed: auto-knee acceptance page has `1` image ref and `0` missing images; final entry has `2` image refs and `0` missing images; full review entry has `19` image refs and `0` missing images.
  - This remains display-only; formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

- Published a current-best display pack on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\publish_zhishan_cable_accel_current_best_pack.m`
  - Entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_index.html`
  - Rules workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_rules.xlsx`
  - Rules CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_rules.csv`
  - Summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_summary.json`
  - README: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CURRENT_BEST_README.md`
  - Current-best policy: accepted auto-knee candidate.
  - The current-best rules table uses the auto-knee manifest directly: `CF-3/CF-4/CF-5` use auto-knee settings; `CF-1/CF-2/CF-6/CF-7/CF-8` keep balanced-final settings.
  - `final_index.html` and the full review `index.html` now link to `current_best_index.html`.
  - File checks passed: `current_best_index.html` has `2` image refs, `0` missing images, `9` table rows; `final_index.html` and full `index.html` have current-best links and no missing images.
  - `CableAccelCurrentBestDisplay_summary.json` reports `acceptance_pass=true` and `current_best_policy=Accepted auto-knee candidate`.
  - This remains display-only; formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

- Synchronized the default final rules with current-best on 2026-05-29:
  - `scripts/publish_zhishan_cable_accel_final_display_pack.m` now builds `CableAccelFinalDisplay_rules.xlsx/csv` from the auto-knee manifest rather than the older balanced manifest.
  - `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.csv` now has `CF-3/CF-4/CF-5` as `auto_knee` and `CF-1/CF-2/CF-6/CF-7/CF-8` as `balanced_final`.
  - `final_index.html` now labels the table as `Current-Best Strategy`.
  - `CableAccelFinalDisplay_summary.json` now records `acceptance_pass=true`, `auto_knee_acceptance_pass=true`, `balanced_acceptance_pass=true`, and `current_best_entry=current_best_index.html`.
  - Re-published `current_best_index.html`, `final_index.html`, and full `index.html`.
  - File checks passed: each page has `0` missing images; `final_index.html` and `current_best_index.html` each have `9` table rows; `git diff --check` passed for changed scripts/docs.
  - This remains display-only; formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

- Exported neutral current-best report images on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_current_best_report_images.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_当前最佳推荐展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_当前最佳推荐展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_当前最佳推荐展示\CableAccelCurrentBestReport_manifest.xlsx`
  - Manifest CSV: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_当前最佳推荐展示\CableAccelCurrentBestReport_manifest.csv`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_当前最佳推荐展示\CableAccelCurrentBestReport_ContactSheet.jpg`
  - Per-point images: `CableAccelCurrentBestReport_CF-1_20260301_20260331.jpg` through `CableAccelCurrentBestReport_CF-8_20260301_20260331.jpg`
  - `scripts/publish_zhishan_cable_accel_current_best_pack.m` now links current-best report-ready images to this neutral folder instead of the auto-knee-named folder.
  - Re-published current-best, final, and full review entries.
  - File checks passed: current-best report page has `9` image refs and `0` missing images; current-best/final/full-review entries have `0` missing images; manifest workbook, CSV, and contact sheet all exist.
  - Link checks passed: `current_best_index.html`, `final_index.html`, full review `index.html`, and the current-best report page have `0` missing local `href` targets.
  - This remains display-only; formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

- Added current-best whole-pack acceptance validation on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\validate_zhishan_cable_accel_current_best_pack.m`
  - Acceptance page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_acceptance.html`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_acceptance.xlsx`
  - JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_acceptance.json`
  - Markdown: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_acceptance.md`
  - Acceptance pass: `1`.
  - Global checks all passed: formal config still uses `daily_median + [-100,100]`, current-best summary is accepted, auto-knee acceptance is accepted, current-best/final/report manifests all have 8 points, rule mix is exactly `3` auto-knee rows and `5` balanced-final rows, all point checks pass, required files exist, and HTML image/link checks pass.
  - Point checks passed for `CF-1` through `CF-8`; `CF-3/CF-4/CF-5` are auto-knee rows and the other five rows are balanced-final rows.
  - Ran full refresh and validation with:
    - `matlab -batch "addpath(genpath(pwd)); e = export_zhishan_cable_accel_current_best_report_images(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); disp(v.html);"`
  - Post-update checks passed: required current-best files exist, `CableAccelCurrentBestDisplay_acceptance.json` reports `pass=true`, and `git diff --check` passed for the changed current-best scripts/docs.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2` unless the user explicitly approves changing formal config.

- Added stricter current-best alternatives on 2026-05-29:
  - Aggressive export command: `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); r = export_zhishan_cable_accel_ladder_tier_display('aggressive'); disp(r.html);"`
  - Aggressive output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\aggressive_display_export\index.html`
  - Aggressive manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\aggressive_display_export\CableAccelAggressiveDisplay_manifest.xlsx`
  - Added comparison script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_current_best_vs_aggressive.m`
  - Comparison page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_vs_aggressive_review\index.html`
  - Comparison manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_vs_aggressive_review\CableAccelCurrentBestVsAggressive_manifest.xlsx`
  - Aggressive result versus current-best:
    - `CF-1`: keep `87.189%`, RMS30 max improvement `20.279%`.
    - `CF-2`: keep `85.803%`, RMS30 max improvement `24.544%`.
    - `CF-3`: keep `87.304%`, RMS30 max improvement `41.527%`.
    - `CF-4`: keep `86.928%`, RMS30 max improvement `33.121%`.
    - `CF-5`: keep `85.384%`, RMS30 max improvement `32.777%`.
    - `CF-6`: keep `87.273%`, RMS30 max improvement `28.982%`.
    - `CF-7`: keep `85.377%`, RMS30 max improvement `25.423%`.
    - `CF-8`: keep `86.025%`, RMS30 max improvement `30.734%`.
  - Added target-keep export script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_target_keep_display.m`
  - Target80 output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target80_display_export\index.html`
  - Target80 manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target80_display_export\CableAccelTarget80Display_manifest.xlsx`
  - Target80 result versus current-best: `CF-1 29.593%`, `CF-2 31.540%`, `CF-3 17.075%`, `CF-4 6.411%`, `CF-5 44.362%`, `CF-6 47.200%`, `CF-7 33.178%`, `CF-8 46.472%` RMS30 max improvement. Most keep rates fall to about `80%~82%`, so this is an aggressive visual reference rather than the default recommendation.
  - Summary table: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_aggressive_target80_summary.csv`
  - Current recommendation after this pass: keep `current-best` as the default report candidate because it preserves at least `90%` of finite data and passes whole-pack validation. Use `aggressive` as the first stricter backup if the user wants cleaner charts. Use `target80` only when the visual requirement is stricter than the data-retention requirement.
  - Re-published `current_best_index.html`, `final_index.html`, and full review `index.html` with links to `current_best_vs_aggressive_review` and `target80_display_export`.
  - Re-ran `validate_zhishan_cable_accel_current_best_pack`; acceptance pass remained `1`, and HTML image/link checks remained passing.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added a three-level tradeoff review on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_three_level_review.m`
  - Purpose: put `current-best`, `aggressive`, and `target80` on one page, so the next review does not require opening three folders one by one.
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\three_level_tradeoff_review\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\three_level_tradeoff_review\CableAccelThreeLevelTradeoff_manifest.xlsx`
  - Review board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\three_level_tradeoff_review\CableAccelThreeLevelTradeoff_ReviewBoard.jpg`
  - Automatic next-review suggestions:
    - `CF-1`, `CF-2`, `CF-3`, `CF-4`, and `CF-7`: review `aggressive` first.
    - `CF-5`, `CF-6`, and `CF-8`: `target80` gives enough extra RMS30 reduction to be worth visual review, but it remains an aggressive reference rather than the default.
  - Re-published `current_best_index.html`, `final_index.html`, and full review `index.html` with the three-level tradeoff link.
  - Re-ran `validate_zhishan_cable_accel_current_best_pack`; acceptance pass remained `1`, and HTML image/link checks remained passing.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added a no-pick mixed visual-best candidate on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_visual_best_display.m`
  - Purpose: convert the three-level suggestions into one single chart package, so the user does not need to manually choose between `aggressive` and `target80` for each point.
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_best_display_export\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_best_display_export\CableAccelVisualBestDisplay_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_best_display_export\CableAccelVisualBestDisplay_ContactSheet.jpg`
  - Selected tiers:
    - `CF-1`, `CF-2`, `CF-3`, `CF-4`, `CF-7`: `aggressive`.
    - `CF-5`, `CF-6`, `CF-8`: `target80`.
  - RMS30 max improvement versus current-best:
    - `CF-1=20.279%`, `CF-2=24.544%`, `CF-3=41.527%`, `CF-4=33.121%`, `CF-5=44.362%`, `CF-6=47.200%`, `CF-7=25.423%`, `CF-8=46.472%`.
  - Re-published `current_best_index.html`, `final_index.html`, and full review `index.html` with links to `visual_best_display_export`.
  - Re-ran `validate_zhishan_cable_accel_current_best_pack`; acceptance pass remained `1`, and HTML image/link checks remained passing.
  - Current default remains `current-best` because it preserves at least `90%` finite data. `visual-best` is the stricter no-pick visual backup if the user prioritizes chart cleanliness.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added target75 and retention tradeoff summary on 2026-05-29:
  - Target75 command: `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); r = export_zhishan_cable_accel_target_keep_display(75); disp(r.html);"`
  - Target75 output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target75_display_export\index.html`
  - Target75 manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target75_display_export\CableAccelTarget75Display_manifest.xlsx`
  - Target75 result:
    - `CF-1`: keep `76.337%`, RMS30 max `17.553`.
    - `CF-2`: keep `76.191%`, RMS30 max `22.826`.
    - `CF-3`: keep `89.056%`, RMS30 max `2.373`.
    - `CF-4`: keep `88.970%`, RMS30 max `2.352`.
    - `CF-5`: keep `75.330%`, RMS30 max `17.365`.
    - `CF-6`: keep `80.930%`, RMS30 max `3.529`.
    - `CF-7`: keep `79.307%`, RMS30 max `31.515`.
    - `CF-8`: keep `76.770%`, RMS30 max `19.625`.
  - Added summary script: `D:\MatlabProjects\Guanbing\scripts\publish_zhishan_cable_accel_retention_tradeoff_summary.m`
  - Summary page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\retention_tradeoff_summary\index.html`
  - Summary workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\retention_tradeoff_summary\CableAccelRetentionTradeoff_summary.xlsx`
  - Summary decisions:
    - `CF-1`, `CF-2`, `CF-5`: `target75_review_only` because the extra RMS improvement is large, but keep rate is only about `75%~76%`.
    - `CF-3`, `CF-4`, `CF-6`, `CF-7`, `CF-8`: `visual_best_backup`.
  - Re-published `current_best_index.html`, `final_index.html`, and full review `index.html` with the retention-tradeoff link.
  - Re-ran `validate_zhishan_cable_accel_current_best_pack`; acceptance pass remained `1`, and HTML image/link checks remained passing.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added a cleaner-priority no-pick candidate on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_decisive_visual_display.m`
  - Purpose: make a single stricter chart package from the retention decision table, using `target75` only where it has large extra gain.
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\decisive_visual_display_export\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\decisive_visual_display_export\CableAccelDecisiveVisualDisplay_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\decisive_visual_display_export\CableAccelDecisiveVisualDisplay_ContactSheet.jpg`
  - Selected tiers:
    - `target75`: `CF-1`, `CF-2`, `CF-5`.
    - `visual_best`: `CF-3`, `CF-4`, `CF-6`, `CF-7`, `CF-8`.
  - RMS30 max improvement versus current-best:
    - `CF-1=41.152%`, `CF-2=40.544%`, `CF-3=41.527%`, `CF-4=33.121%`, `CF-5=65.270%`, `CF-6=47.200%`, `CF-7=25.423%`, `CF-8=46.472%`.
  - Tradeoff: `CF-1/CF-2/CF-5` use about `75%~76%` keep rates. This is the strictest no-pick review candidate, not the default.
  - Re-published `current_best_index.html`, `final_index.html`, and full review `index.html` with the decisive-visual link.
  - Re-ran `validate_zhishan_cable_accel_current_best_pack`; acceptance pass remained `1`, and HTML image/link checks remained passing.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Rechecked the user-requested `[-20,20] m/s^2` global cable-acceleration preview on 2026-05-29, then reran it after the user's latest request:
  - Latest output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_165624_abs20`
  - Latest review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_165624_abs20\cable_accel_threshold_preview_abs20_review_board.jpg`
  - Earlier output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_135130_abs20`
  - Keep rates: `CF-1=66.157%`, `CF-2=54.897%`, `CF-3=99.821%`, `CF-4=99.821%`, `CF-5=77.167%`, `CF-6=99.916%`, `CF-7=52.315%`, `CF-8=66.741%`.
  - Conclusion: do not use `[-20,20]` as a global formal rule. It is too destructive for `CF-1/CF-2/CF-7/CF-8` and still does not solve the display issue evenly across points.

- Exported cleaner-priority report-ready images on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_decisive_visual_report_images.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_更干净优先展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_更干净优先展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_更干净优先展示\CableAccelDecisiveVisualReport_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_更干净优先展示\CableAccelDecisiveVisualReport_ContactSheet.jpg`
  - Per-point images: `CableAccelDecisiveVisualReport_CF-1_20260301_20260331.jpg` through `CableAccelDecisiveVisualReport_CF-8_20260301_20260331.jpg`
  - Selected tiers: `CF-1/CF-2/CF-5=target75`; `CF-3/CF-4/CF-6/CF-7/CF-8=visual_best`.
  - Keep/RMS30 max summary: `CF-1 76.337% / 17.553`, `CF-2 76.191% / 22.826`, `CF-3 87.304% / 1.673`, `CF-4 86.928% / 1.681`, `CF-5 75.330% / 17.365`, `CF-6 80.930% / 3.529`, `CF-7 85.377% / 36.045`, `CF-8 80.635% / 22.828`.
  - Updated `current_best_index.html`, `final_index.html`, and full review `index.html` to link to this neutral cleaner-priority report folder.
  - Added validation script: `D:\MatlabProjects\Guanbing\scripts\validate_zhishan_cable_accel_visual_alternatives.m`
  - Validation page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_alternatives_validation.html`
  - Full refresh/validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); e = export_zhishan_cable_accel_decisive_visual_report_images(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
  - `validate_zhishan_cable_accel_current_best_pack` still passes, and `validate_zhishan_cable_accel_visual_alternatives` passes.
  - `git diff --check` passed for the touched scripts/docs.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added automatic cleanest-with-70%-keep-floor backup on 2026-05-29:
  - Target70 command: `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); r = export_zhishan_cable_accel_target_keep_display(70); disp(r.html);"`
  - Target70 output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target70_display_export\index.html`
  - Target70 result:
    - `CF-1`: keep `76.337%`, RMS30 max `17.553`.
    - `CF-2`: keep `71.233%`, RMS30 max `20.660`.
    - `CF-3`: keep `89.056%`, RMS30 max `2.373`.
    - `CF-4`: keep `88.970%`, RMS30 max `2.352`.
    - `CF-5`: keep `71.762%`, RMS30 max `13.794`.
    - `CF-6`: keep `80.930%`, RMS30 max `3.529`.
    - `CF-7`: keep `70.126%`, RMS30 max `27.524`.
    - `CF-8`: keep `73.594%`, RMS30 max `17.544`.
  - Added script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_cleanest70_display.m`
  - Rule: for each `CF-*`, choose the lowest `RMS30Max` candidate among generated display tiers with keep rate `>=70%`.
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\CableAccelCleanest70Display_manifest.xlsx`
  - Score matrix workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\CableAccelCleanest70Display_score_matrix.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest70_display_export\CableAccelCleanest70Display_ContactSheet.jpg`
  - Selected tiers:
    - `CF-1`: `target75`, keep `76.337%`, RMS30 max `17.553`, improvement vs current-best `41.152%`.
    - `CF-2`: `target70`, keep `71.233%`, RMS30 max `20.660`, improvement `46.186%`.
    - `CF-3`: `aggressive`, keep `87.304%`, RMS30 max `1.673`, improvement `41.527%`.
    - `CF-4`: `aggressive`, keep `86.928%`, RMS30 max `1.681`, improvement `33.121%`.
    - `CF-5`: `target70`, keep `71.762%`, RMS30 max `13.794`, improvement `72.412%`.
    - `CF-6`: `target80`, keep `80.930%`, RMS30 max `3.529`, improvement `47.200%`.
    - `CF-7`: `target70`, keep `70.126%`, RMS30 max `27.524`, improvement `43.053%`.
    - `CF-8`: `target70`, keep `73.594%`, RMS30 max `17.544`, improvement `58.861%`.
  - Updated `current_best_index.html`, `final_index.html`, full review `index.html`, and visual-alternative validation to include `target70` and `cleanest70`.
  - Full refresh/validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
  - `cleanest70` is the strictest automatic visual backup so far. It is likely the cleanest non-LLM result, but it keeps only about `70%~87%` depending on point, so it should not replace the default report candidate without user approval.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Exported cleanest70 neutral report-ready images on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_cleanest70_report_images.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最干净自动展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最干净自动展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最干净自动展示\CableAccelCleanest70Report_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_最干净自动展示\CableAccelCleanest70Report_ContactSheet.jpg`
  - Per-point images: `CableAccelCleanest70Report_CF-1_20260301_20260331.jpg` through `CableAccelCleanest70Report_CF-8_20260301_20260331.jpg`
  - Updated `current_best_index.html`, `final_index.html`, full review `index.html`, and visual-alternative validation to link/check this neutral cleanest70 folder.
  - Full refresh/validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
  - Visual-alternative validation now checks current-best report images, cleaner-priority report images, and cleanest70 report images. The latest pass had `0` missing/small cleanest70 report images and `8` manifest rows.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Exported satisfaction-auto neutral report-ready images on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_satisfaction_auto_report_images.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_满意度自动推荐展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_满意度自动推荐展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_满意度自动推荐展示\CableAccelSatisfactionAutoReport_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_满意度自动推荐展示\CableAccelSatisfactionAutoReport_ContactSheet.jpg`
  - Per-point images: `CableAccelSatisfactionAutoReport_CF-1_20260301_20260331.jpg` through `CableAccelSatisfactionAutoReport_CF-8_20260301_20260331.jpg`
  - Automatic selection from `satisfaction_review`:
    - `CF-1`: `cleaner_priority`, keep `76.337%`, RMS30 max `17.553`.
    - `CF-2`: `cleanest70`, keep `71.233%`, RMS30 max `20.660`.
    - `CF-3`: `cleaner_priority`, keep `87.304%`, RMS30 max `1.673`.
    - `CF-4`: `cleaner_priority`, keep `86.928%`, RMS30 max `1.681`.
    - `CF-5`: `cleanest70`, keep `71.762%`, RMS30 max `13.794`.
    - `CF-6`: `cleaner_priority`, keep `80.930%`, RMS30 max `3.528`.
    - `CF-7`: `cleanest70`, keep `70.126%`, RMS30 max `27.524`.
    - `CF-8`: `cleanest70`, keep `73.594%`, RMS30 max `17.544`.
  - Updated `current_best_index.html`, `final_index.html`, full review `index.html`, and visual-alternative validation to link/check this neutral satisfaction-auto folder.
  - Full refresh/validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = export_zhishan_cable_accel_satisfaction_auto_report_images(); s = compare_zhishan_cable_accel_satisfaction_review(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); r = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
  - Visual-alternative validation now checks satisfaction-auto manifest, contact sheet, review board, 8 per-point images, and linked HTML page. The latest pass had `0` missing/small satisfaction-auto report images and `8` manifest rows.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added lower-retention systematic review candidates on 2026-05-29:
  - Target60 output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target60_display_export\index.html`
  - Target50 output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\target50_display_export\index.html`
  - General script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_cleanest_keep_display.m`
  - Cleanest60 output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest60_display_export\index.html`
  - Cleanest50 output: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\cleanest50_display_export\index.html`
  - Low-keep comparison script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_low_keep_review.m`
  - Low-keep tradeoff page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_tradeoff_review\index.html`
  - Low-keep decision CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_tradeoff_review\CableAccelLowKeepTradeoff_decision.csv`
  - Next-review recommendations:
    - `CF-1`: `cleanest60`, keep `61.582%`, RMS30 max `12.484`; `cleanest50` is an extreme fallback at keep `50.337%`, RMS30 max `9.513`.
    - `CF-2`: `cleanest60`, keep `66.888%`, RMS30 max `17.786`; `cleanest50` is an extreme fallback at keep `50.988%`, RMS30 max `12.132`.
    - `CF-3`: keep `satisfaction_auto`, because `cleanest60/50` add no RMS gain.
    - `CF-4`: keep `satisfaction_auto`, because `cleanest60/50` add no RMS gain.
    - `CF-5`: `cleanest60`, keep `60.062%`, RMS30 max `9.258`; `cleanest50` adds no extra gain beyond that.
    - `CF-6`: keep `satisfaction_auto`, because `cleanest60/50` add no RMS gain.
    - `CF-7`: `cleanest60`, keep `67.679%`, RMS30 max `23.907`; `cleanest50` is an extreme fallback at keep `50.614%`, RMS30 max `15.453`.
    - `CF-8`: `cleanest60`, keep `62.968%`, RMS30 max `12.395`; `cleanest50` is an extreme fallback at keep `52.961%`, RMS30 max `9.364`.
  - Updated `current_best_index.html`, `final_index.html`, full review `index.html`, and visual-alternative validation to link/check the low-retention pages.
  - Full refresh/validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); r60 = export_zhishan_cable_accel_target_keep_display(60); r50 = export_zhishan_cable_accel_target_keep_display(50); c60 = export_zhishan_cable_accel_cleanest_keep_display(60); c50 = export_zhishan_cable_accel_cleanest_keep_display(50); lr = compare_zhishan_cable_accel_low_keep_review(); p = export_zhishan_cable_accel_satisfaction_auto_report_images(); s = compare_zhishan_cable_accel_satisfaction_review(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
  - Visual-alternative validation now also checks target60/50 manifests/images, cleanest60/50 manifests/score matrices/images, and low-keep tradeoff manifest/decision/board/index links.
  - Current judgment: `cleanest60` is the most useful next review tier if the satisfaction-auto image set is still too noisy. `cleanest50` is an extreme fallback only because several points drop to about 50% keep.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Exported low-keep automatic report-ready images on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_low_keep_auto_report_images.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\CableAccelLowKeepAutoReport_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\CableAccelLowKeepAutoReport_ContactSheet.jpg`
  - Review board: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_低保留率自动推荐展示\CableAccelLowKeepAutoReport_ReviewBoard.jpg`
  - Automatic selection from the low-keep tradeoff decision:
    - `CF-1`: `cleanest60`, keep `61.582%`, RMS30 max `12.484`, improvement vs satisfaction-auto `28.876%`.
    - `CF-2`: `cleanest60`, keep `66.888%`, RMS30 max `17.786`, improvement vs satisfaction-auto `13.909%`.
    - `CF-3`: `satisfaction_auto`, keep `87.304%`, RMS30 max `1.673`.
    - `CF-4`: `satisfaction_auto`, keep `86.928%`, RMS30 max `1.681`.
    - `CF-5`: `cleanest60`, keep `60.062%`, RMS30 max `9.258`, improvement vs satisfaction-auto `32.883%`.
    - `CF-6`: `satisfaction_auto`, keep `80.930%`, RMS30 max `3.528`.
    - `CF-7`: `cleanest60`, keep `67.679%`, RMS30 max `23.907`, improvement vs satisfaction-auto `13.142%`.
    - `CF-8`: `cleanest60`, keep `62.968%`, RMS30 max `12.395`, improvement vs satisfaction-auto `29.350%`.
  - The stable review pack now links/checks this output. Latest full refresh/validation passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); lp = export_zhishan_cable_accel_low_keep_auto_report_images(); lr = compare_zhishan_cable_accel_low_keep_review(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); v = validate_zhishan_cable_accel_current_best_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(v.pass); assert(a.pass);"`
  - Visual-alternative validation now checks the low-keep auto manifest, contact sheet, review board, eight per-point images, and HTML links/images.
  - Current judgment: this is the best next report-facing candidate if the user prioritizes cleaner cable-acceleration visuals over keeping roughly 70% or more of the display samples. `cleanest50` remains an extreme fallback, especially for `CF-1`, `CF-2`, `CF-7`, and `CF-8`.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Exported extreme fallback report-ready images on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_extreme_fallback_report_images.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示\CableAccelExtremeFallbackReport_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_极限干净备选展示\CableAccelExtremeFallbackReport_ContactSheet.jpg`
  - Rule: use `cleanest50` only where `low_keep_tradeoff_review` marked `cleanest50_extreme`; otherwise keep the low-keep recommendation.
  - Automatic selection:
    - `CF-1`: `cleanest50`, keep `50.337%`, RMS30 max `9.513`, improvement vs satisfaction-auto `45.805%`.
    - `CF-2`: `cleanest50`, keep `50.988%`, RMS30 max `12.132`, improvement vs satisfaction-auto `41.276%`.
    - `CF-3`: `satisfaction_auto`, keep `87.304%`, RMS30 max `1.673`.
    - `CF-4`: `satisfaction_auto`, keep `86.928%`, RMS30 max `1.681`.
    - `CF-5`: `cleanest60`, keep `60.062%`, RMS30 max `9.258`.
    - `CF-6`: `satisfaction_auto`, keep `80.930%`, RMS30 max `3.528`.
    - `CF-7`: `cleanest50`, keep `50.614%`, RMS30 max `15.453`, improvement vs satisfaction-auto `43.856%`.
    - `CF-8`: `cleanest50`, keep `52.961%`, RMS30 max `9.364`, improvement vs satisfaction-auto `46.625%`.
  - Full refresh/validation passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); ex = export_zhishan_cable_accel_extreme_fallback_report_images(); c = publish_zhishan_cable_accel_current_best_pack(); f = publish_zhishan_cable_accel_final_display_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(c.acceptance_pass); assert(f.acceptance_pass); assert(a.pass);"`
  - Visual-alternative validation now checks the extreme fallback manifest, contact sheet, review board, eight per-point images, and HTML links/images.
  - Current judgment: this is the cleanest generated report-facing fallback, but it is intentionally marked extreme because `CF-1`, `CF-2`, `CF-7`, and `CF-8` keep only about `50%~53%`. Use it only if visual cleanliness is more important than display sample retention.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added a low-keep-vs-extreme decision page on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_low_keep_vs_extreme_report.m`
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_vs_extreme_report\index.html`
  - Decision workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_vs_extreme_report\CableAccelLowKeepVsExtreme_decision.xlsx`
  - Side-by-side board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\low_keep_vs_extreme_report\CableAccelLowKeepVsExtreme_Board.jpg`
  - Decision summary:
    - `CF-1`: low-keep auto remains default; cleanest50 gives extra RMS30 gain `23.8%` for keep loss `11.2%`.
    - `CF-2`: review extreme tradeoff; cleanest50 gives extra RMS30 gain `31.8%` for keep loss `15.9%`.
    - `CF-3`: same as low-keep auto.
    - `CF-4`: same as low-keep auto.
    - `CF-5`: same as low-keep auto.
    - `CF-6`: same as low-keep auto.
    - `CF-7`: review extreme tradeoff; cleanest50 gives extra RMS30 gain `35.4%` for keep loss `17.1%`.
    - `CF-8`: low-keep auto remains default; cleanest50 gives extra RMS30 gain `24.5%` for keep loss `10.0%`.
  - Stable review pack now links this page, and visual-alternative validation checks the decision CSV, board, copied low-keep/extreme images, and HTML links/images.
  - Latest command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); cmp = compare_zhishan_cable_accel_low_keep_vs_extreme_report(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Current judgment: this is the quickest page for the user to decide whether the low-keep auto report images are good enough, or whether `CF-2` and `CF-7` should use the more destructive extreme fallback.

- Exported hybrid recommended report-ready images on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_hybrid_recommended_report_images.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示\index.html`
  - Manifest workbook: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示\CableAccelHybridRecommendedReport_manifest.xlsx`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合推荐展示\CableAccelHybridRecommendedReport_ContactSheet.jpg`
  - Selection rule: use low-keep auto by default; switch only `review_extreme_tradeoff` points from the low-keep-vs-extreme decision page to extreme fallback.
  - Selected packages:
    - `CF-1`: `low_keep_auto`, keep `61.582%`, RMS30 max `12.484`.
    - `CF-2`: `extreme_fallback`, keep `50.988%`, RMS30 max `12.132`.
    - `CF-3`: `low_keep_auto`, keep `87.304%`, RMS30 max `1.673`.
    - `CF-4`: `low_keep_auto`, keep `86.928%`, RMS30 max `1.681`.
    - `CF-5`: `low_keep_auto`, keep `60.062%`, RMS30 max `9.258`.
    - `CF-6`: `low_keep_auto`, keep `80.930%`, RMS30 max `3.528`.
    - `CF-7`: `extreme_fallback`, keep `50.614%`, RMS30 max `15.453`.
    - `CF-8`: `low_keep_auto`, keep `62.968%`, RMS30 max `12.395`.
  - Stable review pack links this folder, and visual-alternative validation checks its manifest, eight images, contact sheet, review board, and HTML page.
  - Latest command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); h = export_zhishan_cable_accel_hybrid_recommended_report_images(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Current judgment: this is now the most useful next candidate to show the user if they want a single no-pick folder that is cleaner than low-keep auto without pushing all optional points to the extreme 50% tier.
  - This remains display/report-only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Exported structured hybrid recommended parameter proposal on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_hybrid_recommended_parameters.m`
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\index.html`
  - XLSX: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\CableAccelHybridRecommended_parameters.xlsx`
  - CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\CableAccelHybridRecommended_parameters.csv`
  - JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\hybrid_recommended_parameters\CableAccelHybridRecommended_parameters.json`
  - Parsed display/review parameters:
    - `CF-1`: package `low_keep_auto`, source tier `target60`, `abs<=20`, drop top `10%` RMS30 segments, keep `61.582%`, RMS30 max `12.484`.
    - `CF-2`: package `extreme_fallback`, source tier `target50`, `abs<=20`, drop top `10%` RMS30 segments, keep `50.988%`, RMS30 max `12.132`.
    - `CF-3`: package `low_keep_auto`, source tier `visual_best`, `abs<=3`, drop top `10%` RMS30 segments, keep `87.304%`, RMS30 max `1.673`.
    - `CF-4`: package `low_keep_auto`, source tier `visual_best`, `abs<=3`, drop top `10%` RMS30 segments, keep `86.928%`, RMS30 max `1.681`.
    - `CF-5`: package `low_keep_auto`, source tier `target50`, `abs<=10`, drop top `10%` RMS30 segments, keep `60.062%`, RMS30 max `9.258`.
    - `CF-6`: package `low_keep_auto`, source tier `visual_best`, `abs<=5`, drop top `10%` RMS30 segments, keep `80.930%`, RMS30 max `3.528`.
    - `CF-7`: package `extreme_fallback`, source tier `target50`, `abs<=20`, drop top `10%` RMS30 segments, keep `50.614%`, RMS30 max `15.453`.
    - `CF-8`: package `low_keep_auto`, source tier `target60`, `abs<=20`, drop top `10%` RMS30 segments, keep `62.968%`, RMS30 max `12.395`.
  - Stable review pack links this parameter page, and visual-alternative validation checks the CSV row count, JSON, and HTML links.
  - Latest command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = build_zhishan_cable_accel_hybrid_recommended_parameters(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Current judgment: this is the reproducible parameter proposal for the current hybrid display candidate. It is still display/report-review only; do not write these into formal `zhishan_config.json` unless the user explicitly approves.
  - Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Exported refined55 report-ready images and parameters on 2026-05-29:
  - Scripts:
    - `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_refined55_report_images.m`
    - `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_refined55_parameters.m`
  - Output directory: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合55推荐展示`
  - HTML page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合55推荐展示\index.html`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_混合55推荐展示\CableAccelRefined55Report_ContactSheet.jpg`
  - Parameter page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\refined55_parameters\index.html`
  - Selection rule: start from hybrid recommended; switch only `CF-8` to the `cleanest55` candidate because it improves the display without dropping to the 50% tier.
  - Selected packages:
    - `CF-1`: `low_keep_auto`, `target60`, `abs<=20`, drop top `10%` RMS30 segments, keep `61.582%`, RMS30 max `12.484`.
    - `CF-2`: `extreme_fallback`, `target50`, `abs<=20`, drop top `10%` RMS30 segments, keep `50.988%`, RMS30 max `12.132`.
    - `CF-3`: `low_keep_auto`, `visual_best`, `abs<=3`, drop top `10%` RMS30 segments, keep `87.304%`, RMS30 max `1.673`.
    - `CF-4`: `low_keep_auto`, `visual_best`, `abs<=3`, drop top `10%` RMS30 segments, keep `86.928%`, RMS30 max `1.681`.
    - `CF-5`: `low_keep_auto`, `target50`, `abs<=10`, drop top `10%` RMS30 segments, keep `60.062%`, RMS30 max `9.258`.
    - `CF-6`: `low_keep_auto`, `visual_best`, `abs<=5`, drop top `10%` RMS30 segments, keep `80.930%`, RMS30 max `3.528`.
    - `CF-7`: `extreme_fallback`, `target50`, `abs<=20`, drop top `10%` RMS30 segments, keep `50.614%`, RMS30 max `15.453`.
    - `CF-8`: `cleanest55_refinement`, `target55`, `abs<=15`, drop top `2%` RMS30 segments, keep `55.826%`, RMS30 max `10.567`.
  - Stable review pack now links the refined55 image folder and parameter page. Visual-alternative validation checks the refined55 manifest, eight images, contact sheet, review board, parameter CSV/JSON, and HTML links/images.
  - Latest command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p55 = build_zhishan_cable_accel_refined55_parameters(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Current judgment: this is the best current single-folder candidate to show the user after the `[-20,20]` trial. A global `[-20,20]` threshold was too blunt for `CF-2`/`CF-7`; the refined55 mix keeps stricter handling only where it materially helps and uses a middle 55% option for `CF-8`.
  - This remains display/report-review only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added dense auto-visual cable acceleration search on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\optimize_zhishan_cable_accel_auto_visual_search.m`
  - Search page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_search\index.html`
  - Report-ready folder: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示`
  - Report-ready page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示\index.html`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示\CableAccelAutoVisualReport_ContactSheet.jpg`
  - Score matrix: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_search\CableAccelAutoVisualSearch_score_matrix.xlsx`
  - Method: dense non-LLM threshold search over `abs<=3, 5, 7.5, 10, 12.5, 15, 17.5, 20, 25, 30, 40, 50, 75, 100` and top-RMS30 segment deletion `0, 1, 2, 3, 5, 8, 10, 12, 15%`. It uses sampled grid search for speed, then recomputes a short candidate list on the full March data before final selection. The per-point minimum keep floor is chosen automatically from the `abs<=20 + drop top 10%` anchor.
  - Selected parameters:
    - `CF-1`: `moderate_noise`, min keep `55%`, `abs<=17.5`, drop top `12%`, keep `55.220%`, RMS30 max `10.651`.
    - `CF-2`: `severe_noise`, min keep `50%`, `abs<=20`, drop top `12%`, keep `50.032%`, RMS30 max `11.925`.
    - `CF-3`: `stable_signal`, min keep `80%`, `abs<=3`, drop top `15%`, keep `83.076%`, RMS30 max `1.448`.
    - `CF-4`: `stable_signal`, min keep `80%`, `abs<=3`, drop top `15%`, keep `82.967%`, RMS30 max `1.478`.
    - `CF-5`: `mixed_noise`, min keep `60%`, `abs<=10`, drop top `10%`, keep `60.062%`, RMS30 max `9.258`.
    - `CF-6`: `stable_signal`, min keep `80%`, `abs<=5`, drop top `10%`, keep `80.930%`, RMS30 max `3.528`.
    - `CF-7`: `severe_noise`, min keep `50%`, `abs<=20`, drop top `12%`, keep `50.004%`, RMS30 max `15.088`.
    - `CF-8`: `moderate_noise`, min keep `55%`, `abs<=17.5`, drop top `15%`, keep `55.990%`, RMS30 max `10.499`.
  - Fixed the auto-visual plot band renderer so percentile fill bands do not connect across missing intervals, and limited legends to the three intended entries.
  - Stable review pack now links the auto-visual search page and report-ready image folder. Visual-alternative validation checks the auto-visual manifest, short-list score matrix `91` rows, JSON, eight images, contact sheet, review board, and HTML links/images.
  - Latest command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Current judgment: this is the best current non-manual candidate. It is cleaner than `refined55` for `CF-1`, `CF-2`, `CF-3`, `CF-4`, `CF-7`, and `CF-8`, keeps `CF-5` at the proven `abs<=10 + drop top 10%` setting, and leaves `CF-2`/`CF-7` near the stricter 50% keep tier that the data appears to require.
  - This remains display/report-review only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added auto-visual comparison/diagnosis review page on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\compare_zhishan_cable_accel_auto_visual_review.m`
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\index.html`
  - Decision workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\CableAccelAutoVisualReview_decision.xlsx`
  - Decision CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\CableAccelAutoVisualReview_decision.csv`
  - Board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\CableAccelAutoVisualReview_Board.jpg`
  - Summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\auto_visual_review\CableAccelAutoVisualReview_summary.json`
  - The page compares the current `auto_visual` candidate against `refined55` and the latest isolated `[-20,20] m/s^2` preview, then checks the auto-visual score matrix for a lower-cost tighter alternative.
  - Diagnosis:
    - `CF-1`: `near_knee`; auto keep `55.220%`, RMS30 max `10.651`, `14.7%` RMS30 improvement vs refined55 and `42.3%` vs `±20`; no eligible score-row improvement remains.
    - `CF-2`: `data_limited_at_floor`; auto keep `50.032%`, RMS30 max `11.925`, only `1.7%` better than refined55 but `33.2%` better than `±20`; already at the adaptive 50% keep floor.
    - `CF-3`: `near_knee`; auto keep `83.076%`, RMS30 max `1.448`, `13.5%` better than refined55 and `89.1%` better than `±20`; no eligible score-row improvement remains.
    - `CF-4`: `near_knee`; auto keep `82.967%`, RMS30 max `1.478`, `12.0%` better than refined55 and `88.9%` better than `±20`; no eligible score-row improvement remains.
    - `CF-5`: `near_knee`; auto equals refined55 at keep `60.062%`, RMS30 max `9.258`, and is `53.5%` better than `±20`; no eligible score-row improvement remains.
    - `CF-6`: `near_knee`; auto equals refined55 at keep `80.930%`, RMS30 max `3.528`, and is `74.4%` better than `±20`; no eligible score-row improvement remains.
    - `CF-7`: `data_limited_at_floor`; auto keep `50.004%`, RMS30 max `15.088`, only `2.4%` better than refined55 but `22.1%` better than `±20`; already at the adaptive 50% keep floor.
    - `CF-8`: `near_knee`; auto keep `55.990%`, RMS30 max `10.499`, only `0.6%` better than refined55 and `35.2%` better than `±20`; best eligible row has only `1.3%` extra RMS30 gain, so it is not worth another rule change.
  - Stable review pack now links this page, and `validate_zhishan_cable_accel_visual_alternatives` checks its decision CSV, JSON, board, copied image sets, and HTML links/images.
  - Latest validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); c = compare_zhishan_cable_accel_auto_visual_review(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Current judgment: threshold-only global trials such as `±20` are inferior to the current auto-visual point-level threshold plus top-RMS30 segment deletion search. Further improvement for `CF-2/CF-7` would require going below the 50% keep floor, which should be a user decision rather than an automatic default.
  - This remains display/report-review only. Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Added ultra-clean below-50% review on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_ultra_clean_review.m`
  - Purpose: quantify the only remaining manual tradeoff after auto-visual review, namely whether `CF-2` and `CF-7` should go below the current 50% keep floor.
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\index.html`
  - Decision workbook: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanReview_decision.xlsx`
  - Decision CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanReview_decision.csv`
  - Package manifest: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanPackage_manifest.xlsx`
  - Comparison board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanReview_Board.jpg`
  - Optional package contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\ultra_clean_review\CableAccelUltraCleanPackage_ContactSheet.jpg`
  - Search policy: only `CF-2/CF-7`, thresholds `[7.5,10,12.5,15,17.5,20]`, top-RMS30 segment deletion `[12,15,18,20,25,30]%`, keep floors `[45,40,35]%`. This is display/review only.
  - Results:
    - `CF-2`: current auto visual `abs<=20 + drop top 12%`, keep `50.032%`, RMS30 max `11.925`. Ultra-clean candidate `abs<=17.5 + drop top 20%`, keep `41.778%`, RMS30 max `10.143`, RMS30 gain `14.9%`, keep loss `8.3%`, recommendation `review_destructive_tradeoff`.
    - `CF-7`: current auto visual `abs<=20 + drop top 12%`, keep `50.004%`, RMS30 max `15.088`. Ultra-clean candidate `abs<=17.5 + drop top 12%`, keep `45.131%`, RMS30 max `12.899`, RMS30 gain `14.5%`, keep loss `4.9%`, recommendation `review_destructive_tradeoff`.
  - Stable review pack now links this page, and `validate_zhishan_cable_accel_visual_alternatives` checks the package manifest, 2-row decision CSV, 72-row sample matrix, JSON, board, contact sheet, copied image sets, and HTML links/images.
  - Latest validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); u = build_zhishan_cable_accel_ultra_clean_review(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Current judgment: below-50% candidates improve `CF-2/CF-7` only moderately and visibly delete more data; keep `auto_visual` as default and use `ultra_clean_review` only if the user explicitly prioritizes cleaner figures over retention for those two points.
  - Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Promoted auto-visual candidate to the stable current-best/final entry on 2026-05-29:
  - Script: `D:\MatlabProjects\Guanbing\scripts\publish_zhishan_cable_accel_auto_visual_final_pack.m`
  - Current-best entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_index.html`
  - Final entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
  - Acceptance page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_acceptance.html`
  - Acceptance JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_acceptance.json`
  - Current-best rules: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelCurrentBestDisplay_rules.xlsx`
  - Final rules: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.xlsx`
  - These stable entries now point to `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_自动视觉推荐展示\index.html` as the default report-ready image package.
  - Older auto-knee/balanced/current-best report folders still exist as historical review candidates, but they are no longer the default recommendation.
  - Latest validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); f = publish_zhishan_cable_accel_auto_visual_final_pack(); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(f.acceptance_pass); assert(rv.acceptance_pass); assert(a.pass);"`
  - `validate_zhishan_cable_accel_visual_alternatives` now checks the 8-row current-best/final rules files plus current-best/final summary JSON and current-best acceptance JSON.
  - Current default recommendation for report display is `auto_visual`; `ultra_clean_review` remains an explicit destructive-tradeoff backup for only `CF-2/CF-7`.
  - Formal spectrum/force calculation still uses `daily_median + [-100,100] m/s^2`.

- Reran isolated `[-20,20] m/s^2` cable-acceleration threshold preview on 2026-05-29:
  - Command: `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); r = preview_zhishan_cable_accel_threshold(20); disp(r.output_folder); disp(r.markdown);"`
  - Output folder: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_224607_abs20`
  - Workbook: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_224607_abs20\cable_accel_threshold_preview.xlsx`
  - Markdown summary: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_224607_abs20\cable_accel_threshold_preview.md`
  - Review board: `D:\芝山大桥数据\2026年1-3月\run_logs\cable_accel_threshold_preview_20260529_224607_abs20\cable_accel_threshold_preview_abs20_review_board.jpg`
  - Keep/clip results:
    - `CF-1`: keep `66.157%`, clip `33.843%`, RMS30 max `18.450`.
    - `CF-2`: keep `54.897%`, clip `45.103%`, RMS30 max `17.860`.
    - `CF-3`: keep `99.821%`, clip `0.179%`, RMS30 max `13.249`.
    - `CF-4`: keep `99.821%`, clip `0.179%`, RMS30 max `13.335`.
    - `CF-5`: keep `77.167%`, clip `22.833%`, RMS30 max `19.920`.
    - `CF-6`: keep `99.916%`, clip `0.084%`, RMS30 max `13.800`.
    - `CF-7`: keep `52.315%`, clip `47.685%`, RMS30 max `19.365`.
    - `CF-8`: keep `66.741%`, clip `33.259%`, RMS30 max `16.201`.
  - Visual judgment: `±20` improves `CF-3/4/6` readability because these points barely need clipping, but it is still too blunt for `CF-1/2/5/7/8`; it removes a large fraction of data while the monthly waveform band remains dense. Do not promote this global threshold into formal config unless the user explicitly chooses data deletion over retention. The auto-visual candidate remains the better current display/report-review path.
  - Formal spectrum/force calculation was not changed; config still uses `daily_median + [-100,100] m/s^2`.

## 2026-05-29 Zhishan Cable Acceleration One-Command Pipeline

- Added `D:\MatlabProjects\Guanbing\scripts\run_zhishan_cable_accel_auto_display_pipeline.m`.
- Purpose: provide one repeatable entry for the current索力加速度展示/报告候选流程 instead of manually running several review and publication scripts.
- Modes:
  - `reuse`: reuse the existing dense auto-visual search result, then rebuild the auto-visual review, ultra-clean backup, stable final/current-best entries, stable review pack, and validation.
  - `full`: rerun the dense auto-visual search first, then run the same publication and validation sequence.
- Latest successful command:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); p = run_zhishan_cable_accel_auto_display_pipeline('reuse'); disp(p.final_index); disp(p.report_images); disp(p.validation_html);"`
- Latest output summary:
  - Final/default page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
  - Current-best page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_index.html`
  - Default report image package: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\index.html`
  - Stable validation page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_alternatives_validation.html`
  - Pipeline summary JSON: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelAutoDisplayPipeline_summary.json`
  - Pipeline readme: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\AUTO_DISPLAY_PIPELINE_README.md`
- Current stable final/current-best recommendation is now `strict_report_candidate`; `auto_visual` remains the conservative baseline and `ultra_clean_review` remains the evidence source for the stricter `CF-2/CF-7` choices.
- Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this pipeline is display/report-review only.

- Added stricter report-review candidate on 2026-05-30:
  - Script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_strict_report_candidate.m`
  - Output page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\index.html`
  - Decision CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\CableAccelStrictReport_decision.csv`
  - Manifest CSV: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\CableAccelStrictReport_manifest.csv`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\CableAccelStrictReport_ContactSheet.jpg`
  - Changed-point comparison board: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\strict_report_candidate\CableAccelStrictReport_CompareBoard.jpg`
  - Selection rule: promote stricter display-only candidates when RMS30 gain is at least `3%` with keep loss `<=5%`; allow the ultra-clean `CF-2/CF-7` options when RMS30 gain is at least `10%`, keep loss `<=10%`, and keep rate `>=40%`.
  - Selected changes vs `auto_visual`:
    - `CF-2`: `strict_ultra_clean`, `abs<=17.5`, drop top `20%`, keep `41.778%`, RMS30 max `10.143`, gain `14.945%`, keep loss `8.254%`.
    - `CF-5`: `strict_score_matrix`, `abs<=10`, drop top `12%`, keep `59.113%`, RMS30 max `8.870`, gain `4.192%`, keep loss `0.949%`.
    - `CF-7`: `strict_ultra_clean`, `abs<=17.5`, drop top `12%`, keep `45.131%`, RMS30 max `12.899`, gain `14.509%`, keep loss `4.872%`.
    - `CF-8`: `strict_score_matrix`, `abs<=15`, drop top `12%`, keep `52.152%`, RMS30 max `9.234`, gain `12.046%`, keep loss `3.838%`.
    - `CF-1/CF-3/CF-4/CF-6`: unchanged from `auto_visual`.
  - Current judgment: this is now the stable final/current-best display recommendation. It is stricter than `auto_visual`, intentionally accepting lower display-sample retention on `CF-2/CF-7/CF-8` for cleaner report figures.
  - Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`.

- Updated one-command pipeline on 2026-05-30:
  - `run_zhishan_cable_accel_auto_display_pipeline('reuse')` now rebuilds the strict report candidate before publishing the stable review pack and validation.
  - Latest pipeline run passed with `visual alternatives validation pass: 1`.
  - Validation now checks `strict_report_candidate` CSV row counts, 8 strict images, contact sheet, changed-point compare board, summary JSON, HTML links/images, and formal config policy.

- Promoted strict report candidate to final/current-best on 2026-05-30:
  - New script: `D:\MatlabProjects\Guanbing\scripts\publish_zhishan_cable_accel_strict_final_pack.m`
  - Current-best entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\current_best_index.html`
  - Final entry: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
  - Final rules: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\CableAccelFinalDisplay_rules.csv`
  - Final summary JSON now reports `default_display_candidate="strict_report_candidate"` and `report_images="../时程曲线_索力加速度_严格最终推荐展示/index.html"`.
  - Current final rule sources: `CF-1/3/4/6=auto_visual_default`, `CF-2/7=strict_ultra_clean`, `CF-5/8=strict_score_matrix`.
  - Validation now explicitly checks `current_best_rules_strict_candidate` and `final_display_rules_strict_candidate`; both passed with `strict_sources_ok=1 rows=8`.
  - Latest publishing/validation command passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this promotion affects display/report review only.

- Exported strict final report-ready images on 2026-05-30:
  - New script: `D:\MatlabProjects\Guanbing\scripts\export_zhishan_cable_accel_strict_final_report_images.m`
  - Report-ready image folder: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示`
  - Folder entry: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\index.html`
  - Manifest: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\CableAccelStrictFinalReport_manifest.csv`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\CableAccelStrictFinalReport_ContactSheet.jpg`
  - Review board: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\CableAccelStrictFinalReport_ReviewBoard.jpg`
  - `publish_zhishan_cable_accel_strict_final_pack` now exports this neutral report folder first, then points `final_index.html` and `current_best_index.html` to it.
  - `run_zhishan_cable_accel_auto_display_pipeline('reuse')` was rerun and passed end-to-end:
    - Final/default page: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\final_index.html`
    - Report images: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_严格最终推荐展示\index.html`
    - Validation: `D:\芝山大桥数据\2026年1-3月\report_cable_accel_display_recommendation\visual_alternatives_validation.html`
  - Validation now checks the strict final manifest, 8 copied point images, contact sheet, review board, summary JSON, index page, final/current-best strict rule sources, and all local HTML image/link references.
  - Manual visual check: opened `CableAccelStrictFinalReport_ContactSheet.jpg`; all 8 points render with the strict selected rules.
  - Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this folder is display/report-review only.

- Added a stricter visual-priority backup candidate on 2026-05-30:
  - New script: `D:\MatlabProjects\Guanbing\scripts\build_zhishan_cable_accel_visual_priority_report_candidate.m`
  - Output folder: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示`
  - Entry page: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\index.html`
  - Manifest: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_manifest.csv`
  - Decision CSV: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_decision.csv`
  - Contact sheet: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_ContactSheet.jpg`
  - Strict-vs-visual board: `D:\芝山大桥数据\2026年1-3月\时程曲线_索力加速度_视觉优先推荐展示\CableAccelVisualPriorityReport_CompareBoard.jpg`
  - Changed points versus strict final:
    - `CF-1`: `abs<=15`, drop top `3%`; keep `52.079%`; 5~95 band gain `13.15%`, but RMS30 max is `1.37%` worse than strict final.
    - `CF-2`: `abs<=15`, drop top `12%`; keep `39.441%`; RMS30 gain `11.68%`; 5~95 band gain `13.64%`.
    - `CF-7`: `abs<=15`, drop top `18%`; keep `38.509%`; RMS30 gain `20.02%`; 5~95 band gain `8.39%`.
    - Other points stay identical to strict final.
  - Current judgment: this candidate is visibly cleaner for `CF-2/CF-7`, but it drops those points below 40% keep. Keep `strict final` as the default report package; use `visual_priority` only if the user explicitly prefers cleaner images over retention for those points.
  - Stable review pack now links this candidate, and validation checks its 8-row manifest, 3-row decision CSV, 8 images, contact sheet, comparison board, summary JSON, index page, and local HTML references.
  - Latest validation passed:
    - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); rv = publish_zhishan_cable_accel_display_review_pack(); a = validate_zhishan_cable_accel_visual_alternatives(); assert(rv.acceptance_pass); assert(a.pass);"`
  - Formal spectrum/force calculation remains `daily_median + [-100,100] m/s^2`; this folder is display/report-review only.

## 2026-06-01 Zhishan March Final Config And Release Prep

- User requested release cleanup after the Zhishan March data-processing iterations.
- Current release target: `v1.7.5`.
- GUI versions updated:
  - MATLAB GUI `ui/run_gui.m`: `v1.7.5`.
  - Report GUI `reporting/report_gui.py`: `v1.7.5`.
- README updates:
  - Added `config/zhishan_config.json` to common config files.
  - Added MATLAB/report GUI `v1.7.5` release notes.
  - Added reporting README `v1.7.5` note.
- Latest Zhishan formal config state:
  - `strain`: SX-1~SX-10 level-2 alarm bounds `[-200, 400]`; March cleaning `[-200, 200]`; group plot warning lines enabled.
  - `bearing_displacement`: DX-1~DX-4 level-2 `[-80, 80]`, level-3 `[-100, 100]`; March cleaning `[-100, 100]`.
  - `cable_accel`: unit label `mm/s^2`; daily median offset correction; per-point March cleaning rules:
    - CF-1/CF-2/CF-7/CF-8: `[-300, 300]`.
    - CF-5: `[-100, 120]`.
    - CF-3/CF-4/CF-6: `[-100, 100]`.
  - `cable_accel` plot y-limits:
    - CF-1/CF-2/CF-7/CF-8: `[-500, 500]`.
    - CF-5: `[-150, 150]`.
    - CF group/default display: `[-300, 300]` where named group y-limits apply.
- Latest isolated recalculations completed successfully on 2026-06-01:
  - Strain group warning-line refresh: `D:\MatlabProjects\Guanbing\tmp\zhishan_strain_group_warn_recalc\matlab_strain_group_warn_recalc_20260601_121738.out.log`.
  - Cable acceleration y-limit refresh: `D:\MatlabProjects\Guanbing\tmp\zhishan_cable_accel_ylim_recalc\matlab_cable_accel_ylim_cf500_20260601_141934.out.log`.
- Latest self-checks:
  - Strain group `.fig` contains 10 SX curves and warning lines at `-200` and `400`.
  - Cable acceleration `.fig` y-limits checked: CF-1/CF-2/CF-7/CF-8 `[-500, 500]`, CF-5 `[-150, 150]`.
  - Cable acceleration stats updated at `D:\芝山大桥数据\2026年1-3月\stats\cable_accel_stats.xlsx`.
- Release action requested by user: commit, push, create tag, and include GUI version / README / state-document updates.

## Context-Compression Recovery Rule

If a Codex conversation stalls on automatic context compaction for more than 5 to 10 minutes, stop waiting. Terminate/restart Codex and open a new thread.

New thread startup prompt:

```text
Please read D:\MatlabProjects\Guanbing\docs\current_task_state.md, git status/diff, recent commits, and relevant output files, then continue the Zhishan Bridge data processing task.
```

Avoid uploading old screenshots/images into the continuation thread unless they are essential.
