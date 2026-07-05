# Current Remote State

Last updated: 2026-07-05 11:30 CST

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

- Status: completed and manually spot-checked by the user on 2026-07-05.
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

133 `F:\Guanbing` has the Hongtang Q2 source changes used for the accepted
report, but the worktree is not clean until the local `v1.7.14` release commit
is pulled or reset in through git.

- Remote HEAD before the `v1.7.14` release commit: `308dea7 Document Hongtang Q2 recovery`
- Remote `git status --short` at the last check showed the same Hongtang Q2
  modified files and new RMS/report-field-update test files as local.
- Report generator file `reporting/build_period_report.py` was synchronized to
  133 before the accepted Q2 report and then re-smoke-tested there.
- Remote focused tests passed:
  - `D:\Python310\python.exe -m unittest tests_py.test_build_period_report_word_update`
  - real Word COM smoke test on a copied DOCX returned `WORD_UPDATE_WARNINGS=[]`.
  - earlier focused MATLAB tests for lowfreq, GUI/config, gap mode and dynamic
    services passed on this recovery line.

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
