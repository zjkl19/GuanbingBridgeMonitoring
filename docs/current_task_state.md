# Current Task State

Last updated: 2026-07-15

## Purpose

This file is the handoff point for long Codex sessions. New conversations should read this file first, then read `git status`, `git diff`, recent commits, and relevant output files before continuing.

## 2026-07-15 v1.8.1-rc3 Isolated Deployment And Jiulongjiang Acceptance

- The reviewed rc3 package is now deployed only under the isolated
  `F:\Guanbing_v1.8.1-rc1\app` candidate tree on machine 133. The stable
  `F:\Guanbing` installation and `F:\九龙江数据\2026年5月` source tree remain
  untouched. The retained rollback tree is
  `F:\Guanbing_v1.8.1-rc1\app_before_rc3_20260715_231823`, and the deployment
  receipt is
  `F:\Guanbing_v1.8.1-rc1\deployment_receipt_rc3_20260715_231823.json`.
- The deployed ZIP SHA-256 remains
  `60358c2f643b82d144580bba4562f7ca5fd7ee642c98d5a1398e6c6246f4e650`;
  the workbench and Runner hashes remain the reviewed rc3 hashes below.
- The first four-worker cache build completed with `eligible=5325`,
  `created=3764`, `reused=1561`, `failed=0`. A pre-repeat inventory closes
  5,325 MAT files and 5,325 metadata files. The immediate
  `force_rebuild=false` reuse task is currently running; zero-write reuse has
  not yet been accepted and must not be recorded as complete.
- Source review found Guanbing `GB-*` strain/crack groups and G05/G06 y-limits
  accidentally retained in `jiulongjiang_config.json`. The working-tree fix
  removes those foreign groups and y-limits without inventing a Jiulongjiang
  grouping: all 50 explicit strain points and 22 explicit crack points remain.
  `ConfigLinter` now reports no `group_point_reference` issue for this config.
- Post-fix source regression passes Python `592 passed, 1 skipped` plus
  `180 subtests`, and MATLAB `676/676`.
- This configuration correction was made after the immutable rc3 ZIP was built.
  The current Jiulongjiang analysis must use the reviewed task-specific fixed
  configuration snapshot. A later candidate rebuild is required before claiming
  that the packaged default configuration contains this correction.
- Remaining acceptance gates are: finish and validate the zero-write reuse run,
  run all 15 applicable modules from MAT cache, validate statistics/figures and
  their source records, generate the May report, then update fields and export
  the authoritative PDF with Microsoft Word and inspect every page.

## 2026-07-15 Curve Threshold Interaction Correction

- The cleaning editor no longer presents the two one-sided actions as drag-line
  buttons. The legacy MATLAB interaction is restored as one two-line dialog:
  lower and upper horizontal lines share one required time window, default to
  the loaded preview extent, support endpoint dragging and exact numeric entry,
  and produce one reviewed two-sided rule for the selected point.
- Two separate box actions implement the user-confirmed semantics. Lower-side
  selection takes the highest finite sample actually hit by the rectangle and
  updates only `min`; upper-side selection takes the lowest and updates only
  `max`. Strict comparisons preserve samples equal to the bound. The other bound,
  existing rule time window, zero handling and outlier settings are preserved.
- Box selection displays the actual selected preview count, candidate value and
  sampled deletion estimate. A tiny/empty/non-finite selection cannot be
  accepted; cancel and close do not mutate the table, confirmation remains an
  in-memory edit, and the existing explicit save/automatic-backup boundary is
  unchanged.
- Preview loading is fixed to the selected module/point identity and, when the
  editor has a loaded configuration and task context, must match its dependency
  SHA-256, bridge, data root and start/end dates. Missing or mismatched context
  fails closed. The UI states that preview counts may be sampled and full-cache
  recomputation remains authoritative.
- Final local regression after the interaction and context-binding changes:
  Python `597/597` executed successfully (`1` conditional permission skip),
  MATLAB `675/675`, focused automatic-preview contract `4/4`, and focused
  cleaning-threshold contract `5/5`.

## 2026-07-15 Local Machine-Profile And Cross-Bridge Cache Capability

- The implementation changes in this batch were local-only. A separate
  read-only status check inspected machine 133, but no task was stopped, no
  runtime was upgraded and no remote file was written. No cleaning, filtering,
  statistics or report calculation rule changed.
- The shared storage-location catalog no longer exposes the retired empty
  `office_pc` / “办公室电脑” entry. The shared choices remain the development
  machine, 133 analysis machine and 126 data machine. Future or one-off machines
  continue to use `config/path_profiles.local.json` or the GUI custom path; the
  host-name/environment/path auto-selection priority is unchanged.
- `bridge_profiles.json` now distinguishes default modules from optional
  capabilities. All six installed bridge profiles advertise
  `cache_prebuild` as available but do not select it by default, so an ordinary
  analysis request is unchanged until the operator explicitly enables it.
- Cache generation now routes through `bms.data.CachePrebuildService`:
  - `jlj_daily_export` keeps the existing multi-channel `jlj_csv_v2` builder;
  - `dated_folders` and `hongtang_period` use the existing two-column
    `csv_timeseries_v2` parser/metadata contract with capacity checks, whole-run
    and per-target leases, transactional replacement and reusable-cache checks.
- The standard backend discovers only CSV files reached from configured
  analysis modules and point mappings. It includes both wind speed/direction
  sources and enabled crack-temperature companion sources. WIM, Hongtang
  low-frequency Excel, ZIP archives, unconfigured CSV and non-CSV sources are
  explicitly excluded.
- Focused regressions pass: Python `37/37`; MATLAB `73/73`. The MATLAB set
  exercises real cache creation and loading for `dated_folders`,
  `hongtang_period` and `jlj_daily_export`, plus reuse, source-change rebuild,
  wind direction and crack-temperature coverage. The complete Python suite ran
  `597` tests successfully (`596` passed and `1` was conditionally skipped),
  including the updated release-packaging fixtures.

## 2026-07-15 Local v1.8.1-rc3 Release Review

- The review began with CLI, MATLAB batch and Qt-offscreen execution while the
  desktop was in active office use. After explicit authorization, the final
  release gate briefly launched the native Windows GUI for focus/DPI/icon
  checks. No Computer Use, Word/WPS automation or machine-133 write was used.
- Release review fixed terminal analysis/report status races, strict report
  artifact acceptance without SHA-256, and RMS-only refresh overwriting raw
  grouped plots with zero-valued support lines.
- Analysis and report launches now use launch-specific immutable request
  snapshots and same-directory atomic status/result publication. Process
  ownership binds the job, launch, PID, creation time and executable; canonical
  task/data-root and report-output locks prevent duplicate or cross-task writes.
  Moved task files use their actual directory and the current runtime root.
- A report can only adopt the exact manifest created or modified by its current
  build and matching the returned DOCX path/hash. Analysis-manifest selection
  atomically binds path, SHA-256 and state while invalidating an older approval;
  stale windows, persistence failures and cleanup-pending processes keep the
  GUI report gate closed.
- Archive extraction now revalidates the ZIP snapshot after capacity planning,
  binds the exact path/size/CRC entry set to the opened archive, rechecks before
  publication, and uses a host/PID/UUID directory lease. Live same-host tasks
  cannot be reclaimed by age and old cleanup tokens cannot delete a new lock.
- The build has an explicit Qt-offscreen audit mode. Its manifest is marked
  non-native and the formal package script rejects it. A subsequent native
  Windows probe passed foreground and keyboard-focus ownership, native icon,
  120 DPI, per-monitor awareness and a 2018 x 1122 physical window. The final
  rebuilt rc3 package reproduced the same evidence in its release manifest.
- Packaging now rehashes the complete frozen distribution immediately before
  compression and requires root/dist/manifest/smoke version records to agree.
- The final Python regression ran `597` tests successfully (`596` passed and
  `1` was conditionally skipped). The final MATLAB regression passed `675/675`
  with no failure or incomplete test. Earlier coverage artifacts remain
  diagnostic rather than substitutes for these release gates.
- The analysis Runner and unified workbench were rebuilt locally. Runner SHA-256
  is `902dcd79956e9d091227d004cef47be6003a72325ee115f7b418d6ad31eb8531`;
  workbench EXE SHA-256 is
  `8be37fcd576547a77d72b1d04135fe716bc56ac862a69ab32157640b636d8af9`.
  The candidate manifest closes `384/384` files and all `16/16` native Windows
  screenshots, six installed bridge profiles, embedded-report contracts,
  compiled failure-exit and automatic-threshold-preview smoke tests. The
  release ZIP SHA-256 is
  `60358c2f643b82d144580bba4562f7ca5fd7ee642c98d5a1398e6c6246f4e650`.
- The first offscreen audit correctly exposed a false-negative screenshot gate:
  dense CJK fallback boxes on a valid table page exceeded the old 5% dark-pixel
  limit. The offscreen-only detector now permits 20% while retaining its bright
  frame requirement; native PrintWindow thresholds remain strict and separate.
  The build-script regression is `20/20` and the complete package rerun passed.
- rc3 remains a development-branch candidate and is now deployed only to the
  isolated 133 candidate tree. It has not replaced stable `F:\Guanbing`.
  Jiulongjiang full-period analysis/report acceptance remains incomplete. The
  final rebuilt package, inventory, native Windows screenshots and
  focus/DPI/icon evidence have passed locally.

## 2026-07-15 Jiulongjiang May W4 Cache Completion

- Machine 133 completed
  `Guanbing_v181rc1_Jiulongjiang_May_CachePrebuild_W4_20260715` inside the
  isolated `F:\Guanbing_v1.8.1-rc1` tree. Stable production and the source ZIP
  tree remained untouched.
- Final summary: `created=3764`, `reused=1561`, `eligible=5325`, `failed=0`,
  elapsed `6h50m27s`; cache size `57.50 GiB`, F: free space `539.33 GiB`.
- A pre-repeat inventory found 5,325 MAT/metadata pairs. The immediate
  `force_rebuild=false` reuse rerun is in progress; its summary and the
  byte-for-byte zero-write comparison remain pending. The 15-module analysis
  and May report/Word-PDF review have not started.

## 2026-07-15 360 Cloud Transfer Pilot And V2Ray Diagnosis

- At this checkpoint the local P0 hardening batch was complete but had not yet
  been committed; the later rc3 release review recorded above supersedes that
  publication state. The Codex monitor automation remains paused. The isolated Jiulongjiang W4 cache task
  on 133 has completed; its downstream acceptance steps remain pending.
- The official `360disk` CLI `0.8.37` was validated in both directions using
  new random payloads and end-to-end SHA256 checks. A portable Node/CLI runtime
  and the credential-safe wrapper now exist only under the 133 RC tree; stable
  production was not modified.
- V2Ray is not in TUN mode and the CLI normally connects directly. Explicitly
  forcing V2Ray did not explain the slow uploads: direct 8 MiB runs varied from
  `0.066` to `0.319 MiB/s`, while forced-proxy runs were `0.123` and
  `0.197 MiB/s`. The actual fault boundary is severe 360 endpoint jitter,
  intermittent `fetch`/connect failures, and weak CLI retry behavior.
- 360-to-133 download reached `3.148 MiB/s`; 133 upload reached `0.285 MiB/s`.
  Local download required retry/proxy fallback and verified at `0.169` to
  `0.558 MiB/s`. All accepted payloads had matching SHA256.
- `scripts/invoke_360disk_transfer.ps1` now applies asymmetric direct/proxy
  fallback, outer retries, raw-output suppression and SHA256 reporting without
  storing credentials. Full instructions and evidence are in
  `docs/ops/360disk_transfer.md`.
- Three wrapper regressions were added and the complete Python suite now passes
  `511/511`. They cover credential-literal rejection, the single-mode array
  defect found by real upload smoke, and automatic proxy-first download hashing.
- Do not select 360 as the default multi-gigabyte route from these small-file
  measurements alone. After Jiulongjiang cache work ends, repeat with a 1-2 GiB
  random artifact and compare against SSH/SMB and the official desktop client.

## 2026-07-15 Local P0 Test Hardening After rc2 Build

- The Codex monitor automation was paused at the user's request so the local
  machine can be used interactively. This did **not** stop or modify the
  isolated Jiulongjiang cache task on machine 133. That four-worker build later
  completed successfully; before the remaining acceptance work, the next
  session must still begin with a read-only process/task and disk check rather
  than assuming no residual worker exists.
- Targeted failure-path tests found and fixed concrete defects in four safety
  areas:
  - Jiulongjiang cache prebuild now has whole-run and per-target locks, can
    reclaim a same-host dead-PID lock, and recovers MAT/meta half-pairs and
    interrupted transaction directories. A metadata-only half-pair is now
    correctly counted as `rebuilt`, not `created`.
  - `refresh_dynamic_rms_only` now discovers MAT-only alias caches through the
    same loader as the main analysis path. A zero-point refresh fails before
    replacing statistics or group figures unless an explicit legacy
    `allow_empty_output=true` override is supplied.
  - Strict report generation now rechecks every pinned artifact's byte count
    and SHA256, performs template preflight for all supported bridge report
    types, and rejects missing or outside-output stale builder results before
    Word/PDF processing.
  - Workbench analysis/report launch failures and unexpectedly exited child
    processes now leave a durable `launch_failed` state. Stop requests cannot
    regress to a stale `running` heartbeat; report termination verifies process
    exit before atomically publishing `stopped`. Stale stop flags are removed
    before relaunch, transient status-read failures keep live tasks
    non-restartable, and packaged-runner/MATLAB selection, stopping, and native
    offscreen Qt button flows have direct lifecycle tests. MATLAB status JSON
    and Python task contexts now use same-directory atomic publication.
- Final local source regressions pass: Python `511/511`; MATLAB `648/648`.
  Regenerated coverage is Python statement/branch `65.12%` / `51.16%` and
  MATLAB production-root statement/decision `46.44%` / `47.91%`. Excluding
  orchestration scripts, MATLAB statement/decision coverage is approximately
  `73.69%` / `58.81%`; the `+bms/` kernel is approximately `78.90%` / `62.84%`.
  Detailed artifacts are under `outputs/coverage`.
- The last compiled rc2 EXE and ZIP predate these P0 source fixes and therefore
  are no longer release-equivalent to the working tree. Before any publish or
  deployment, rebuild the internal Runner and workbench and repeat CLI, native
  GUI, embedded-report, failure-exit and closed-package-inventory smoke tests.
- At this checkpoint these local changes had not yet been committed, pushed,
  deployed to 133 or merged to `main`. The later rc3 release review recorded
  above supersedes that publication state; deployment and `main` merge remain
  separate decisions.

## 2026-07-15 Local v1.8.1-rc2 Operator Controls And Coverage Gate

- Interactive development is local-only on branch
  `codex/jiulongjiang-cache-prebuild`. The running isolated Jiulongjiang rc1
  production workflow on machine 133 was not inspected, modified, restarted or
  redeployed during this work. The Codex monitor automation is currently paused
  for interactive local development; the remote Windows task itself was not
  stopped. Resume with a read-only check before continuing remote acceptance.
- Future ZIP extraction requests now support `auto`, 1, 2, 4 or a bounded custom
  worker count. The service records requested/resolved/effective concurrency and
  any deterministic serial fallback. Archive immutability, staging publication,
  lock handling and disk-capacity gates are unchanged. This setting is not
  retroactively applied to a running production request.
- The cleaning editor now has two explicit one-sided actions: set a lower bound
  and remove values below it, or set an upper bound and remove values above it.
  The native frozen GUI was tested with a selected Guanbing point, draggable line,
  exact `-275.5` entry and cancel; the table/configuration remained unchanged.
- Zero-offset correction accepts an optional second-precision effective start
  and end. Legacy date-only end values still include the full day; explicit
  midnight remains an exact boundary. Gap rendering now supports field-wise
  global/module/point inheritance without changing analytical samples or stats.
- Final local test baselines pass: Python `475/475`; MATLAB `634/634`. Python
  statement/branch/combined coverage is `64.32%` / `50.63%` / `60.65%`.
  MATLAB production-root statement coverage is `46.02%` and decision/branch
  coverage is `47.52%`, with condition-level metrics collected. Artifacts are
  under `outputs/coverage`.
- The rc2 compiled workbench passes CLI, frozen GUI, all-profile, embedded
  report, internal Runner, screenshot and operator-feature package gates. The
  Chinese-named EXE is
  `dist/BridgeMonitoringWorkbench/桥梁健康监测工作台.exe`, SHA256
  `3AE1C6175B9BDC35C68D269266A388A6D481895515F6CBF335759431EBD9EFAD`.
  Its manifest closes at 383 files and 226,791,562 bytes excluding the manifest.
- A local-only release archive was prepared at
  `release/workbench_rc2_local/BridgeMonitoringWorkbench-v1.8.1-rc2-win-x64.zip`,
  117,398,190 bytes, SHA256
  `E59E9E1513382F50489788D8B48B84556ACD0560365294C287E181DE88313B3A`.
  It has not been uploaded, installed on 133, tagged, committed or pushed.
- Architecture assessment: retain the MATLAB numerical kernel and PySide6
  orchestration split. Do not perform a big-bang rewrite. Next low-risk steps are
  a shared module catalog, one path/profile model, extracted capacity/parallel
  planning services and mechanical splits of oversized editors with compatibility
  re-exports. Production/report acceptance remains the release decision, not a
  coverage percentage alone.

## 2026-07-15 v1.8.1-rc1 Jiulongjiang May ZIP/Cache/Report Regression

- Work continues on branch `codex/jiulongjiang-cache-prebuild` from stable
  baseline `dcab406`. Production `F:\Guanbing` and the source ZIP tree
  `F:\九龙江数据\2026年5月` are read-only; all remote writes are isolated under
  `F:\Guanbing_v1.8.1-rc1`.
- The candidate adds verified ZIP64 streaming extraction, source/output-root
  isolation, disk/lock gates, raw MAT cache prebuilding, transactional MAT/meta
  publication and the Jiulongjiang monthly-report period/WIM/patrol fixes.
  Verified extraction reuse ignores derived cache files but continues to check
  every ZIP-declared path and byte count.
- Final local gates pass: MATLAB `612/612`, Python `441/441`, compiled Runner,
  embedded report runtime, native GUI, all-profile matrix, screenshots and the
  closed 382-file package inventory. The compiled failure-exit smoke used an
  empty Jiulongjiang root with only `doUnzip=true`; it returned exit code `249`,
  left `analysis_status.status=failed`, retained a readable failed manifest and
  recorded the `unzip` module as `fail`. The release manifest therefore records
  `analysis_runner_failure_exit_smoke=true`.
- The final local package was built at `2026-07-15 03:35:59 +08:00` and is
  `release/workbench/BridgeMonitoringWorkbench-v1.8.1-rc1-win-x64.zip`,
  117,198,340 bytes, SHA256
  `BA2ED5DCA711F69B2932B3B067DD7B0E2EC5EC19FBBB1A918D6CEECB4F114B23`.
  Its 125,024-byte `release_manifest.json` has SHA256
  `D90742F86AA26ACA7A1CD4F399DD3FA571571535E7225D5E87499F47218A10B9`;
  the inventory closes at 382 files and 226,583,174 bytes excluding that
  manifest. The 6,577,771-byte workbench EXE SHA256 is
  `0C409E93EA11D8A83E4DBA8F47567F52B0557C4E648AF35CA30914FED4117CE0`;
  the 2,779,220-byte internal Runner SHA256 is
  `EA0F3B7998ED67FCD45EFA61F461B08FC8834809AAEE69F489903779D88946FC`.
- The same final package is deployed only in the isolated 133 candidate tree.
  Receipt:
  `F:\Guanbing_v1.8.1-rc1\deployment_receipt_summary_runner_exitfix_20260715_034040.json`;
  rollback copy:
  `F:\Guanbing_v1.8.1-rc1\app_before_summary_runner_exitfix_20260715_034040`.
- The isolated May 1 extraction/reuse-v3 and two-worker cache transaction plus
  idempotency repeat have completed on 133. The source inventory remains 31
  ZIPs and 61,754,011,511 compressed bytes. The full 31-day extraction later
  completed with source-ZIP immutability checks, and the four-worker cache run
  completed with `created=3764`, `reused=1561`, `eligible=5325`, `failed=0`
  in `6h50m27s`. Cache size was `57.50 GiB` and F: free space was
  `539.33 GiB`. Strict pair acceptance, the zero-write reuse rerun, all 15
  applicable `mat_only` modules and the pinned-manifest May report with
  Microsoft Word PDF/every-page QA remain incomplete. Do not describe the RC
  as accepted until those remaining gates finish.

## 2026-07-14 v1.8.0 Production Cutover On gb-133

- The rollback-safe production switch is complete. `F:\Guanbing` is now the
  frozen v1.8.0 packaged installation, not a git checkout. Its 381-file
  schema-v3 inventory, Chinese-named workbench EXE and internal MATLAB runner
  match the stable release hashes recorded below. Future production upgrades
  must use a verified formal release/update transaction rather than `git pull`
  in this directory.
- The former clean v1.7.39 checkout is retained intact at
  `F:\Guanbing_legacy_pre_v1.8.0_20260714_2252`. Retain it through both a
  14-day observation window and two successful real production report cycles;
  use whichever completes later. The switch evidence, 43 exported
  scheduled-task XML files, shortcut backup and state snapshots are under
  `F:\Guanbing_v1.8.0_stable_stage_20260714\production_switch_backup\switch_20260714_224954`.
- All historical `Guanbing*`/`Codex_Hongtang*` scheduled tasks inspected for
  the switch are disabled and none is running. Sixteen completed orphaned
  old-root launcher processes were audited and removed; the final read-only
  check found no MATLAB, analysis-runner, workbench or report-builder process.
  Do not re-enable the historical one-shot tasks wholesale.
- The desktop entry is now
  `C:\Users\dell\Desktop\桥梁健康监测工作台.lnk`, targeting
  `F:\Guanbing\桥梁健康监测工作台.exe` with `F:\Guanbing` as its working
  directory. The retired standalone report shortcut was backed up and removed;
  report generation remains embedded in the unified workbench.
- Production-root CLI/GUI smokes passed for Guanbing, Hongtang, Jiulongjiang,
  Shuixianhua, Chongyangxi and Zhishan. The embedded headless report worker,
  invalid-CLI handling and native Hongtang report-page screenshot also passed;
  configuration paths resolve through the `prod_133` machine profile.
- The final Guanbing cache validation used only the source actually present on
  133, `2026-05-26` through `2026-05-28`; it is not a full June acceptance
  run. It completed all 10 requested modules, produced 10 readable statistics
  workbooks and 149 decodable figures, and closed all eight formal acceleration
  plot count records. The 988-file source inventory was unchanged. The missing
  `2026-05-29` adjacent rolling file is disclosed, so the May 28 tail was not
  fabricated.

## 2026-07-14 v1.8.0 Stable Release Gate

- The `dev/pyside6-workbench` tree has completed the stable-release gate. The
  full health run is
  `outputs/health_checks/release_health_check_20260714_203651.json`: Python
  `425/425` plus `109` subtests, MATLAB `576/576`, MSSQL-backed coverage
  included, and the compiled
  MATLAB GUI smoke passed with 13 tabs, 16 tables and all 6 configured machine
  path profiles. Native PySide6 screenshots for all 15 migrated pages were
  inspected; the warning editor contains 156 explicit two-sided bounds, the
  application icon and organization logo are present, and no clipping,
  mojibake or blank configuration page remains.
- The stable schema-v3 package closes at 381 inventoried files. The user EXE is
  `dist/BridgeMonitoringWorkbench/桥梁健康监测工作台.exe`, SHA-256
  `7A6B3DBACC32BA382A9B2B5CEB595AA6B9A25783D9B4179544F742141C7766BC`.
  The internal MATLAB runner SHA-256 is
  `0BA58452CF91E730FD1EE24A6FC36DCEC181B23E0672AE52BC3C9E0C0EC7CC55`.
  The 117,166,819-byte archive is
  `release/workbench/BridgeMonitoringWorkbench-v1.8.0-win-x64.zip`, SHA-256
  `87C6F0E08D25383E316F9E5F7953BAE74707AE4E07C4F363FB222A4E26A3C6ED`.
  Its schema-v3 inventory closes at `381` files and `226,537,794` bytes
  excluding the manifest itself.
- A real-ZIP install, update and fault-injected rollback cycle passed at
  `tmp/workbench_update_cycle/v180_stable_package_gate_20260714_204604/update_cycle_result.json`.
  It preserved operator configuration and unmanaged files, removed retired
  managed runtime files, started the installed Chinese-named EXE, and restored
  the exact injected previous installation on rollback.
- Jiulongjiang and Shuixianhua monthly reports now reject stale-template media
  and period mismatches rather than emitting a report with the requested month
  in its filename but old-month figures or narrative. Jiulongjiang additionally
  preserves the final section properties, period-filters the wind summary,
  binds selected image hashes, prunes unused template media and fails closed on
  report QC. Shuixianhua QC likewise writes a structured failure manifest and
  raises on either a QC exception or any non-`ok` result.
- Formal report PDFs now have one explicit authority boundary. Shuixianhua uses
  the Word PDF emitted by its builder; the other embedded report types export
  through an isolated `Word.Application` instance that refreshes fields and
  atomically replaces the PDF. LibreOffice output is recorded only as a layout
  preview. When Word export is unavailable the task remains reviewable but is
  marked `warning`, the GUI states that no authoritative PDF was generated,
  and a preview is never promoted to the formal `pdf_path`.
- Shuixianhua wind summaries are resolved uniquely by monitoring point plus
  report start/end dates, preferring the analysis/derived manifest bound to the
  task. A missing, wrong-period, duplicate same-period or point-mismatched
  summary now fails closed instead of silently reusing another month's wind
  result.
- The machine-133 production replacement described above has completed using
  the verified stable archive and a retained timestamped rollback tree. The
  available Guanbing validation scope is explicitly the May 26-28 cache sample,
  not a full June run; a later full-period production run remains a separate
  data/report acceptance activity.

## 2026-07-14 Shuixianhua May Report Period Repair

- The May analysis outputs were correct; the stale March x-axes came from the
  report builder copying the March template without replacing its embedded
  result figures. The repaired builder now resolves and embeds 47 exact
  May-period figures, rejects an image whose filename/date does not close on
  `2026-05-01` through `2026-05-31`, and verifies every selected source-image
  hash is present in the generated DOCX.
- The same repair removes two stale March statements claiming that nine
  temperature points had no data. The temperature result table now expands
  from its single template row to all 10 current statistics rows, and a
  post-build check requires the report PointID list to match the statistics
  source exactly.
- The strict candidate is
  `output/doc/manual_review_20260714/shuixianhua_may_fixed/水仙花大桥健康监测2026年5月月报_报告生成器_20260714_174016.docx`
  (SHA-256
  `FDF930F8055EBF6D9B969D2EC659278A44F9E0694B667179F9E828174D1CF7D8`).
  Its Microsoft Word PDF has 48 pages and SHA-256
  `E991B3A35D18AE9C562BB75E252E7A60EE0E73D368045C32F833ACCC227D9DC4`.
  The report manifest is `shuixianhua_report_build_manifest_20260714_174016.json`
  with status `ok`, zero missing items and zero warnings. All 47 selected May
  figures are embedded; no March period/x-axis token or broken caption
  reference remains. Page 2 is the template's intentional blank cover verso.
- Visual QA now rasterizes a builder-provided Microsoft Word PDF when one is
  available. LibreOffice remains a fallback only: it mis-evaluates this
  template's `STYLEREF`/`SEQ` caption fields and can invent extra blank pages,
  so it must not replace the Word PDF for caption or pagination acceptance.
  PDF QC also rejects Chinese or English broken-reference results.
- Focused report tests pass `38/38`; the full Python regression passes
  `402/402`. This candidate is ready for user review but is not yet a signed
  client deliverable.

## 2026-07-14 v1.8.0-rc3 Unified Workbench Candidate

- Ordinary workbench analysis requests now use time-series source mode `auto`.
  Valid CSV remains the first choice; when CSV is absent, the loader may use a
  valid compatible MAT cache. A user whose archived data directory contains
  only MAT files does not need to select `mat_only`. Explicit `mat_only` remains
  an isolation/verification option and is not the ordinary GUI default.
- `DataIndex` has been corrected so explicit `mat_only` never falls back to CSV
  while inventorying source files. Keep this boundary in future index changes:
  `auto` may select CSV first and MAT second, whereas `mat_only` may select MAT
  only.
- Jiulongjiang and Shuixianhua daily-export loading now supports their existing
  `jlj_csv_v2` MAT caches (`ts`, `valx`, `valy`, `valz`, internal `meta` plus
  matching external cache metadata). In `auto`, CSV behavior remains unchanged
  when a CSV exists; a valid MAT cache is used only when the CSV is absent.
  The focused Jiulongjiang/Shuixianhua adapter suite passes `24/24`, and a
  read-only real Shuixianhua May cache smoke loaded `1,782,849` finite samples
  through ordinary `load_timeseries_range` discovery without restoring CSV.
- Zhishan and Shuixianhua cable-acceleration raw time-history plots use automatic
  y-limits. This change applies only to the raw time-history figure; RMS figures
  retain their existing configured/default y-limit behavior and statistical
  meaning.
- Report-generation code is now embedded in the workbench application and is
  invoked as a background worker from the same executable runtime. The unified
  package no longer copies or pops up a separate `BridgeReportBuilder.exe`.
  The final package contains exactly two executables: the user-facing
  `桥梁健康监测工作台.exe` and its internal MATLAB analysis runner. Installed
  CLI, native-GUI, embedded-report, invalid-CLI and all-profile matrix smokes
  pass; no retired report-builder/report-GUI executable is present.
- Read-only inspection of machine 126 established the following source facts:
  the first real temperature/humidity timestamp is
  `2026-06-08 09:00:02.057`, first visible in the June 9 export. Point `33` is
  temperature; `33-2` is highly likely to be relative humidity. Within the
  inspected export range, no independent `WS-H` channel was observed. Preserve
  the timestamp as an inspected-range result, retain the `33-2` identity caveat,
  and do not synthesize a channel or claim an earlier start time without new
  source evidence.
- Local production-data validation order is fixed as Hongtang, Guanbing,
  Zhishan, then Shuixianhua. Hongtang's accepted RC2 analysis/report baseline
  has passed and was not repeated. RC3 validation then completed a Guanbing
  three-day source sample, Zhishan April source analysis and Shuixianhua May
  source analysis in that order. These latter three are analysis-layer
  evidence, not a claim that full-period reports have been generated or
  approved. In particular, the available Guanbing source covers only part of
  May 26-28 and is not a June monthly acceptance run.
- Known source and engineering-parameter limits must be disclosed:
  Zhishan has no `2026-04-02` partition, lacks CF-7 on `2026-04-01`, and lacks
  the adjacent `2026-05-01` rolling source needed for the April tail.
  Shuixianhua cable-acceleration data are absent for `2026-05-02` through
  `2026-05-05`. No authoritative mapping of effective free length `L` and
  linear density `rho` was found for the 34 Shuixianhua cable points, so cable
  acceleration, RMS and frequency results remain usable, but cable-force kN
  conversion, force plots and force conclusions must stay blocked until the
  engineering table is supplied. None of these limits permits fabricated
  samples or inferred structural parameters.
- Validation evidence is stratified as follows:
  - Hongtang: accepted full Q2 analysis/report baseline at
    `E:\GuanbingLocalValidation\v1.8.0-rc2_20260713_2118\hongtang_q2_complete_0628_0630_20260713_2225`.
  - Guanbing: RC3 source-sample manifests
    `analysis_manifest_20260714_051527.json` and
    `analysis_manifest_20260714_052106.json` under
    `E:\GuanbingLocalValidation\v1.8.0-rc3_20260714_045654\guanbing\run_logs`.
  - Zhishan: April manifest `analysis_manifest_20260714_055424.json` under
    `E:\GuanbingLocalValidation\v1.8.0-rc3_20260714_045654\zhishan\run_logs`;
    all 14 formal plot records close their counts.
  - Shuixianhua: May manifest `analysis_manifest_20260714_091235.json` under
    `E:\GuanbingLocalValidation\v1.8.0-rc3_20260714_045654\shuixianhua\run_logs`;
    65/65 formal plot records close their counts and all eight statistics
    workbooks are readable. The final wind-only compiled rerun is
    `analysis_manifest_20260714_100143.json`; it removed the false cache-only
    0/2 preflight warning without changing any wind statistic or JPG hash.
- Final full health evidence is
  `outputs/health_checks/release_health_check_20260714_095626.json`: Python
  `388/388`, MATLAB `574/574`, MSSQL-backed tests included, plus compiled GUI
  smoke. After the last user-facing `wind_direction` -> `风向` display fix, the
  focused Qt suite passes `19/19`, and the rebuilt native screenshot has been
  visually approved.
- The schema-v3 release tree closes at 381/381 inventoried files and
  226,562,280 bytes. Workbench SHA-256 is
  `66368A15E0AAEDA4B5F67B629E8329DFFAAF509823F90EF1525A90D8F1F78440`;
  runner SHA-256 is
  `635B6886CE66252C13FB1EAD30761605BE1058190F646B9082B5C3F968005D2B`.
  The 117,190,491-byte RC ZIP is
  `release\workbench\BridgeMonitoringWorkbench-v1.8.0-rc3-win-x64.zip`,
  SHA-256
  `888E71154982891CA4C351FE9A505DD5F8E525D201D2AE35732F775590C372BF`.
  Disposable install/update/rollback validation passed at
  `tmp\workbench_update_cycle\rc3_final_20260714\update_cycle_result.json`.
  This is a dev-branch release candidate; it is not authorization to merge
  `main`, replace the legacy production installation, or invent missing source
  data/engineering parameters.

## 2026-07-14 Hongtang Q2 Supplement Recalculation (June 28-30)

- The previously omitted `2026-06-28` through `2026-06-30` Hongtang folders
  were added under the local read-only source
  `E:\洪塘大桥数据\2026年4-6月`. Recalculation used an isolated `mat_only`
  candidate tree at
  `E:\GuanbingLocalValidation\v1.8.0-rc2_20260713_2118\hongtang_q2_complete_0628_0630_20260713_2225`;
  no CSV extraction, resampling, preprocessing or WIM rerun was enabled.
- The 9-module analysis completed in 7,090.16 seconds. The signed analysis
  manifest is `run_logs\analysis_manifest_20260714_002903.json` with SHA-256
  `1E1694A6CE60E717E1348A845A88053EE34376FFF2BA9A99CF6C51EC1A070A41`.
  All 47 formal plot records close their source/input/finite/plotted counts:
  8 wind, 3 earthquake, 12 structural acceleration and 24 cable acceleration.
  Nine statistics workbooks contain 43 readable sheets with no formula errors.
- The immutable coverage audit is `run_logs\data_coverage_audit.json` with
  SHA-256
  `CD60E3D70B87A6D3D0BBF0BC331F57E1F33FC2BE4DF6C9E2C97D03536A471587`.
  W1/W2 each contain 4,021,058 samples for June 28-30, with an actual gap on
  June 29 from `08:46:26.532` to `09:48:30.684` (3,724.152 seconds). Because
  the July 1 adjacent rolling export is absent, June 30 is available only to
  about 09:00 and must not be described as a complete day.
- Against the earlier partial-period result, only the quarter mean wind speeds
  changed: W1 `2.75 -> 2.74 m/s`, W2 `1.37 -> 1.36 m/s`. Maximum 10-minute
  means remain W1 `6.892408934 m/s` at `2026-05-28 15:35` and W2
  `6.508341430 m/s` at `2026-04-23 11:35`.
- The maximum cable-acceleration 10-minute RMS is CS8 `2.468 m/s2` at
  `2026-06-22 10:05`, above the stated first-level threshold of
  `1000 mm/s2 (1.000 m/s2)`. The report generator now compares measured RMS
  values with the threshold instead of emitting a fixed “below threshold”
  sentence, and directs the operator to review the original time history and
  alarm record. Structural acceleration remains below its threshold: maximum
  10-minute RMS `0.035 m/s2` versus `315 mm/s2`.
- The original analysis manifest omitted twelve cable-force report JPGs because
  the producer collector did not recognize `索力时程图` and
  `索力时程图_组图`. The current report binds those exact files plus the
  coverage audit through
  `run_logs\derived_report_inputs_20260714_0050.json`, SHA-256
  `02BD4BF6D35DADFCFC322831AA60371B35C454B7CA100AA08D248E475C47FAA6`.
  Future runs collect the corrected directories directly.
- Strict report generation now pins the analysis manifest, the derived
  sidecar, all selected artifact sizes/hashes and the result root; it rejects
  filesystem fallback, unlisted coverage audits, missing/warning manifests,
  or synthesized legacy manifests. The full Python regression passes
  `340/340`; the final ten-file MATLAB batch, including the hidden legacy GUI
  smoke, passes `99/99`.
- The rebuilt `v1.8.0-rc2` workbench package validates its complete 605-file,
  392,272,449-byte inventory. The workbench EXE SHA-256 is
  `8A803627746C743F70E31629AC99734356AF70EEFB7B3DBA19AFF430F358C546`,
  the report builder SHA-256 is
  `270C30D051A44E77472BD16DF80F575D64DE289A84AA7CA43F620E1BE070E027`,
  and the rebuilt analysis runner SHA-256 is
  `10A93329971C43FDFE948B95BBE16C41091E5F68B6220059ACA512CB55453E0E`.
  Compiled analysis/report protocol, strict report conditions, all-profile
  configuration, invalid CLI, automatic-cleaning preview and fifteen native
  GUI screenshots pass.
- The final report is
  `E:\GuanbingLocalValidation\v1.8.0-rc2_20260713_2118\hongtang_q2_complete_0628_0630_20260713_2225\自动报告\洪塘大桥健康监测2026年第二季度周期报_20260714_041653.docx`,
  SHA-256
  `4F6663ADBBDFDB44D766DDEC49CB40CC089E80FEDCC47029C66EF27D33894181`.
  Its Microsoft Word authoritative PDF is beside it with the same stem,
  SHA-256
  `9E6FA907339ED92AE13D5DDF75A74E707D078A0C526F0052A556FE2C684FC603`.
  The end-to-end report manifest is
  `period_report_manifest_20260714_041653.json`, SHA-256
  `1F551AB315C769BF2896FDFF866CCCC25B76281C7E89BE597B22A19D10C2F316`;
  it records `front_matter_pages=3`, `status=ok`, zero missing/warning items
  and all 186 bound report images.
  Word renders 81 physical pages: page 2 is the intentional blank cover verso,
  and the 78-page numbered body runs from `第 1 页 共 78 页` through
  `第 78 页 共 78 页`. This exposed and fixed the prior off-by-one
  `{ = NUMPAGES - 4 }` formula; the template and generator now use the actual
  three unnumbered front-matter pages. All pages render without edge clipping
  or broken cross-references, and the final `图 4-15 地震动时程图` is correct.
  The authoritative Word-PDF audit is
  `run_logs\workbench\hongtang_q2_complete_rc2_20260713_2225\word_qc_final_pagefix_e2e_20260714_0420\authoritative_word_pdf_qc.json`,
  SHA-256
  `380A6116C81359D98C5EB349F10FC5DF7EFA98BC070E6F27E4F0CF46C9E5F300`.
- The durable delivery record is
  `run_logs\final_delivery_qc_20260714_0425.json`, SHA-256
  `28F7C6D9293881F14F3213B464A2B69414A1BA905AABE690E0FF0CF5FB64FF5D`.
  The schema-v2 task context is closed as `completed/passed` and points to the
  Word-authoritative PDF rather than the LibreOffice compatibility preview;
  its SHA-256 is
  `6CB2CD9C1EC02863E48A8BE3327C0CC88369FFA1C9D9F62F661CD040719A4BF8`.

## 2026-07-13 v1.8.0-rc1 All-Profile Workbench Candidate

Historical prerelease snapshot; superseded by the stable v1.8.0 production
cutover recorded at the top of this file.

- The workbench/profile/release gates no longer assume six bridges or a fixed
  5+1 report-capability split. The installed matrix is derived from
  `config/bridge_profiles.json`, requires exactly the catalog identities and
  dynamically computed report/analysis-only counts, and fails when a newly
  added bridge has not been checked by the frozen EXE.
- User-facing “六桥自检” wording is replaced by “所有桥梁自检”. The frozen
  native GUI shows `所有桥梁 6/6` for the current catalog, without embedding 6
  in the code or test contract.
- Version is `v1.8.0-rc1`. SemVer prerelease precedence is now implemented so a
  future stable `v1.8.0` is newer than this RC; numeric prerelease identifiers
  such as `rc.10` also sort correctly.
- Python regression passes `297/297`. MATLAB's dynamic catalog contract passes
  `2/2`; the legacy GUI smoke passes `4/4`.
- The packaged Chinese EXE SHA256 is
  `37d4c52afb8bad8d4436cf4c1e3f7ff1e714ec74e597231fa97bff279b2ffad9`.
  Its schema-v2 release manifest closes at 599 files. All current profiles,
  14 native screenshots, compiled proposal preview, embedded report, visual
  quality and invalid-CLI gates pass.
- The 210,241,987-byte RC ZIP SHA256 is
  `0e92ed58d79448e30ee5678b92dca7e9cfbff0fa9e0494e25a3a30a445b58903`.
  A disposable install/update cycle passed config and unmanaged-file
  preservation, stale-runtime/legacy-EXE removal, native screenshot, backup
  creation and exact fault-injected rollback in 37.8 seconds.
- Real Windows UI automation opened the frozen EXE, found the
  “所有桥梁自检” control, and verified the modal summary: current catalog 6/6,
  report-capable 5, analysis-only 1, 12 assets unchanged.
- Deployment plan: publish GitHub prerelease `v1.8.0-rc1`, install on 133 under
  isolated `F:\Guanbing_v1.8.0-rc1`, leave `F:\Guanbing` untouched, and validate
  Hongtang Q2 analysis/report plus Guanbing analysis with independent task/log
  and output paths.
- Commit `e237a51` is pushed on `dev/pyside6-workbench`; draft PR #1 targets
  `main`, and tag/Pre-release `v1.8.0-rc1` is published with the verified ZIP
  and checksum assets. The PR remains unmerged.
- Read-only 133 preflight confirmed `DESKTOP-21RTG63\\dell`, a clean old
  `F:\Guanbing` production checkout at `f2531f5`, no MATLAB process, the
  expected Hongtang/Guanbing data roots, and about 1.78 TB / 845 GB free on
  E/F. The old production tree was not modified.
- The RC is installed only at `F:\Guanbing_v1.8.0-rc1`. All 599 packaged files
  and the Chinese EXE hash were revalidated on 133; all catalog profiles passed
  frozen-EXE smoke with zero configuration-load errors, packaged assets stayed
  unchanged, and the remote native screenshot was visually reviewed.
- Production-data comparison uses `mat_only` validation configurations. Dated
  cache folders are exposed through candidate-only junction views; generated
  stats, figures, logs and reports remain under the RC tree. No unzip,
  resampling, header editing or raw-CSV processing is selected. Hongtang Q2 is
  the current first long run; Guanbing follows after Hongtang analysis/report
  validation so the two high-memory analyses do not overlap.

## 2026-07-13 Hongtang Q2 Spectrum And Report-Template Calibration

- The Hongtang structural-acceleration spectrum search uses three inclusive
  `target_frequency +/- 0.15 Hz` bands. The default targets are
  `0.898/1.460/2.737 Hz`; A5, A9-X, A9-Y, A10-X and A10-Y retain their
  documented per-point overrides. A Python regression now protects every
  resulting interval, and the existing MATLAB spectrum tests protect the
  inclusive-band and per-point-override behavior.
- The user-supplied Q2 proofreading report was audited for tracked changes and
  comments. Accepted wording/numbering corrections were transferred to
  `reports/洪塘大桥健康监测周期报模板-自动报告.docx` through the repeatable
  `reporting/calibrate_hongtang_period_template.py` tool.
- Period-report headers no longer contain duplicated floating page text or a
  hard-coded total. `reporting/docx_header_fields.py` writes exactly one Word
  `PAGE` field and one `NUMPAGES` field, widens the report-number cell so the
  identifier stays on one line, and audits the saved DOCX package. The report
  builder refuses a generated report that fails this field contract.
- Monthly/period report wording now distinguishes instantaneous maximum wind
  speed from maximum 10-minute mean wind speed, uses the same vibration
  statistics source for overview and body, fixes the accepted figure/table
  references and grammar, and distinguishes axle-load equality from a strict
  exceedance.
- A 2026-07-13 read-only check on 133 confirmed a clean remote `main` at
  `f2531f5` and copied the current Q2 `accel_stats.xlsx` and
  `accel_spec_stats.xlsx` for local audit without modifying the server. The
  current maximum structural-acceleration 10-minute RMS is `0.107 m/s2`
  (A10-Y), so generated text must round to `0.11 m/s2`; no fixed sample value
  may remain in either the overview or body.
- The current Python suite passes `296/296`; the focused MATLAB spectrum and
  workbench-contract batch passes `24/24`. Word field update and rendered-page
  checks show a single `第 PAGE 页 共 NUMPAGES 页` header and an unwrapped report
  number.
- Native GUI review of the frozen Hongtang spectrum page exposed binary-float
  tails such as `1.6859999999999999`. The editor now displays concise,
  round-trippable values such as `1.686` without changing the stored or MATLAB
  calculation value; a Qt regression protects the A10-Y row.

## 2026-07-12 PySide6 Unified Workbench Migration (historical dev phase)

Historical migration state, superseded by the v1.8.0 merge, release and 133
production cutover recorded above:

- The recurring `pyside6` high-saturation refactor automation is paused at the
  user's request because this computer is currently needed for frequent manual
  use. Do not resume it until the user explicitly asks.
- Development was isolated on branch `dev/pyside6-workbench`, based on tagged
  production release `v1.7.39`. The completed branch was merged to `main` and
  released as v1.8.0. On 133 the unified Chinese-named workbench is now the
  production entry; the legacy MATLAB GUI exists only in the retained rollback
  checkout during the observation window.
- `workbench/` now provides a four-page PySide6 workbench for project/analysis,
  explicit pre-warning-value configuration, manifest/plot review, and report
  handoff. `start_workbench.py` is the source entry; the packaged local entry is
  `dist/BridgeMonitoringWorkbench/桥梁健康监测工作台.exe`.
- The workbench reads every bridge profile in the shared project catalog and its Python module
  option contract is regression-checked against
  `bms.module.ModuleRegistry`. It writes a versioned `job_context.json` and a
  MATLAB-compatible `run_request.json`.
- Local analysis uses the existing execution boundary: prefer
  `BridgeAnalysisRunner.exe`, otherwise use `matlab -batch`. Status polling,
  progress fraction/current module/ETA, stdout/stderr logs, cooperative stop
  files, task restoration, and terminal manifest loading are implemented.
- Report execution is now embedded as a separate background process. The
  existing report GUI and embedded task share one dispatcher; the latter writes
  stage/status/result JSON and returns DOCX/PDF/report-manifest QC directly to
  the workbench. The old `--job-context` prefill remains available as a fallback.
- Formal-report enablement requires a successful manifest, no failed module
  records, complete coverage of all selected modules, and an explicit plot
  approval. Config, manifest, and report-template SHA-256 values are pinned and
  rechecked before MATLAB launch/report handoff.
- Explicit historical-manifest binding rejects bridge, data-root, start-date,
  or end-date mismatches. Starting a new job clears the previous manifest and
  plot approval. These fixes prevent approval leakage across projects/months.
- The current Python suite passes `296/296`. The current joint MATLAB
  workbench/runner/config/plot batch baseline remains `147/147`; the latest
  report/config/update-focused MATLAB batch passes `70/70`. The earlier focused alarm-editor,
  plot-settings GUI, main-GUI smoke, and run-request group passes `24/24`.
  A direct MATLAB JSON-contract run completed and
  produced an `ok` manifest. A second end-to-end run through the Python
  `AnalysisLauncher` selected the compiled runner, completed in about 22.5
  seconds wall time, wrote logs/status, and produced a context-matched manifest
  with pinned SHA-256.
- Native Windows visual checks passed for the project/analysis page, the
  real-manifest review page, and the Hongtang 156-row alarm editor.
- The packaged user-facing executable is now named
  `桥梁健康监测工作台.exe`; the English distribution folder and GitHub ZIP
  asset prefix remain stable for tooling. The transactional updater accepts a
  legacy installation containing `BridgeMonitoringWorkbench.exe`, removes the
  old executable as managed runtime, installs/restarts the Chinese executable,
  and requires the Chinese name in every new release inventory.
- The default UI font is raised from 9 pt to 10 pt. The title bar exposes a
  persisted “自动检查更新” checkbox, initially enabled from policy and
  independently switchable by the user, plus “立即检查更新”. Source and
  development builds still never auto-install an update.
- User-facing report-review wording no longer exposes `manifest`,
  `provenance`, `门禁` or `QC`. The UI now says “分析结果清单”, “图件数据完整性检查”,
  “报告生成条件” and “质量检查”; internal JSON keys and file protocols are
  unchanged. A widget-level wording regression prevents those original terms
  from returning to the primary workflow.
  The focused warning/profile/provenance MATLAB contract batch passes `12/12`.
- The 25 processing/analysis checkboxes now carry packaged-safe custom SVG
  line icons that depict each module's real meaning. In particular, the
  Geokon low-frequency synchronization module uses a data-acquisition
  instrument with waveform display, ports, and synchronization arrow. No
  `FFT`/`HP`/`LP` text fallback is used. Font-based color Emoji were rejected
  after frozen rendering proved unstable.
- GitHub Release update support is implemented. Packaged stable builds check at
  most once per 24 hours and expose a manual check button. The updater requires
  a newer stable tag, the expected Windows x64 ZIP, a GitHub asset digest or
  `.sha256` asset, and an internal EXE SHA256 match. Installation is explicit,
  runs after process exit, backs up the old install, and preserves existing
  configs. `scripts/package_workbench_github_release.ps1` prepares the two
  required assets but never publishes externally. GitHub currently has no
  Releases, so no update is offered until the first reviewed stable Release is
  deliberately published.
- The updater now uses a schema-v2 release manifest with an exact inventory of
  all 595 packaged files (relative path, bytes and SHA256), not only ZIP/EXE
  hashes. Staging rejects traversal, absolute, duplicate-case and symbolic-link
  members, validates every inventory file and every required smoke gate, and
  automatically falls back to a short system-temporary root when a ZIP member
  would approach the Windows path limit.
- The old copy-in-place PowerShell installation path has been replaced in the
  UI by the verified staged EXE's transaction mode. It builds and validates a
  candidate directory, preserves existing configs and unmanaged operator files,
  removes stale managed runtime files, then atomically swaps the live directory
  to a timestamped backup. Faults both before activation and after activation
  restore the exact original tree.
- A real 200.0 MB development Release ZIP passed the complete disposable update
  cycle in 34.3 seconds: archive/checksum/inventory verification, frozen-EXE
  install, config and unmanaged-file preservation, stale-runtime removal,
  installed all-profile/8-config-tab smoke, native Chinese screenshot, backup
  creation, and fault-injected exact rollback. The run also exposed and fixed a
  262-character extraction failure, an offscreen screenshot false alarm and a
  native screen-grab repaint race. The final widget-rendered screenshot is
  `2000x1075` with a `0.0` black-region ratio. Evidence is under
  `tmp/workbench_update_cycle/validation_final2`.
- `scripts/build_workbench_exe.ps1` produces an onedir release with the compiled
  MATLAB Runner, six project configs/templates, and the report builder. The
  build blocks on the workbench smoke contract, fourteen native screenshots,
  packaged report `--job-context` smoke and embedded report-job protocol smoke.
  `release_manifest.json` records the
  EXE SHA-256, file count, total bytes, and smoke result.
- Explicit `defaults/per_point` `alarm_bounds` editing is migrated with strict
  level/bounds validation, save-as, automatic backup, source-SHA drift refusal,
  unrelated-field preservation, and old task-approval invalidation. Cleaning
  thresholds are now also migrated in a separate configuration subtab. It
  supports scalar/array/empty representations, one-sided and timed rules,
  `zero_to_nan`, moving-window outlier parameters, and explicit dated
  `exclude_ranges` with a readable reason. The GUI no longer exposes inverted
  thresholds as an all-data suppression mechanism. No-op round trips across every currently configured bridge preserve the
  loaded payload exactly; source overwrites use the same SHA-drift refusal and
  backup gate. The packaged build records a third native screenshot for this
  editor.
- The previously narrow warning page no longer equates “no explicit
  `alarm_bounds`” with “no warning configuration”. Its default subtab now
  inventories `alarm_bounds`, `force_alarm_bounds`, `alarm_levels`,
  `warn_lines`, `rms_warn_lines`, and `group_warn_lines` without converting
  between their different semantics. Every row shows scope, module,
  point/group, level or label, value, unit, runtime purpose, validity state and
  exact JSON path; source/status filters and free-text search remain responsive
  for Hongtang's 222-row inventory. Empty configured fields and malformed
  values stay visible. The second subtab retains the guarded explicit
  `alarm_bounds` editor.
- Guanbing now shows 12 inventory rows: 3 wind alarm levels, 8 configured
  deflection/tilt plot lines and one explicitly empty bearing-displacement
  line field; 11 are configured and none are malformed. The packaged
  all-profile gate closes at Guanbing 12, Hongtang 222, Jiulongjiang 14,
  Shuixianhua 111, Chongyangxi 46 and Zhishan 40 rows, with zero invalid rows
  and exact no-op payload preservation for every catalog config. A MATLAB contract
  verifies that Guanbing's displayed wind/deflection/tilt values match the
  existing runtime resolvers. The focused MATLAB warning batch passes `17/17`.
- A malformed direct frozen-EXE smoke command exposed a pre-existing
  PyInstaller `--noconsole` failure path: `argparse` tried to write usage to a
  `None` stderr and displayed a `NoneType.write` exception dialog. The parser
  now exits with code 2 and appends the real diagnostic to
  `%TEMP%\BridgeMonitoringWorkbench_cli_error.log`; the package build has a
  mandatory invalid-CLI smoke so this dialog cannot regress silently.
- The project page now includes a local task center rather than relying only
  on a file picker. It indexes only direct task children under the selected
  data root's `run_logs/workbench` plus contexts explicitly opened in the
  current process, merges newer analysis status plus separate report
  status/result JSON, and checks bridge
  identity, data-root availability, config SHA drift, completed Manifest and
  report outputs before enabling restore. Warning contexts remain visible and
  recoverable; unknown bridges and unreadable JSON are visible but blocked.
  Search/status filters, direct directory opening and a return-to-config path
  are embedded without adding a fifth top-level workflow tab.
- The task-center contract is shared through
  `tests/fixtures/workbench_task_history_contract.json`; Python index/widget/
  main-window tests pass, and the focused MATLAB task/context/request batch
  passes `14/14`. Full Python regression passes `292/292`. The frozen
  catalog-driven all-profile gate now additionally
  requires an enabled 8-column task center, and the release/update gate records
  `task_history_smoke=true`.
- This milestone also fixed a pre-existing transactional-update cleanup gap:
  the generated install script omitted the managed
  `workbench_warning_overview.png`, so an old overview image could survive an
  update. Both it and the new task-center image are now removed/replaced as
  managed evidence while unrelated operator files remain preserved.
- A fresh `v1.7.39-dev` 210,047,646-byte ZIP passed the full disposable update
  cycle in 35.3 seconds. The frozen EXE preserved the operator config and
  unmanaged note, removed stale runtime, replaced both old managed screenshots,
  returned the 8-column task-center smoke, rendered a native `2000x1075`
  screenshot with zero black-region ratio, created a backup, and restored the
  exact old tree after an injected post-rename failure. Evidence is under
  `tmp/workbench_task_history_update_cycle`.
- The later Chinese-EXE/UI milestone produced a 210,204,728-byte development
  ZIP and passed the same frozen update cycle in 38.7 seconds. The starting
  installation contained only the legacy English EXE; the final candidate
  contained `桥梁健康监测工作台.exe`, removed the English EXE, preserved the
  operator config/unmanaged note, replaced all managed visual evidence,
  reported 10 pt font and auto-update enabled, rendered at `2000x1075` with
  zero black-region ratio, and restored the exact legacy tree under injected
  failure. Evidence is under `tmp/workbench_chinese_exe_update_cycle_final`.
- The rebuilt workbench EXE SHA256 is
  `8f7b04baebca53739faa57859bdc41720c128e8f8fa8b622b906b8300753a93f`.
  Its schema-v2 release inventory closes at `599` files, includes both the
  Guanbing warning-overview and Hongtang explicit-bound screenshots, and pins
  all fourteen native screenshot hashes including the empty-bounds explanation,
  operator-friendly review wording and task center. The
  all-profile matrix, invalid-CLI/task-history smokes, report gates and
  compiled preview smoke all pass.
- Post-filter cleanup is migrated as a third configuration subtab. It edits
  only `post_filter_thresholds`, supports scalar/array/empty and one-sided
  timed rules, preserves unrelated cleaning/offset/alarm fields, and passes
  no-op round trips across every currently configured bridge. The packaged Zhishan visual
  gate exercises the real one-sided low-pass rules.
- Automatic-cleaning proposals are migrated as a fourth configuration subtab
  without reimplementing the algorithm in Python. `run_request_cli` now
  dispatches `auto_threshold_proposal` requests to the existing MATLAB
  `AutoThresholdProposalService`; the same rebuilt
  `BridgeAnalysisRunner.exe` used for analysis writes deterministic
  request/status/result artifacts. PySide6 provides module/algorithm options,
  polling, editable human-review rows, explicit selection, termination, and a
  guarded apply step. Only selected `range/window_range` rows are appended;
  `apply_key` and safe point identity come from MATLAB, the generation-time
  config SHA256 is checked by the Runner before data loading and again before
  applying selected rows, duplicate rows are refused, and the source is backed
  up before replacement. A real compiled-runner smoke completed
  with exit code 0 and closed request/status/result/config-SHA provenance.
- Automatic-cleaning curve-preview parity is now complete. The Runner retains
  the existing MATLAB extrema-preserving sampler, writes preview series to a
  separate JSON artifact, and pins its SHA256 into the proposal result. PySide6
  validates artifact/request/config identity, sample-count closure, duplicate
  point keys and the 50000-point safety ceiling before showing the curve.
  Selecting or editing a proposal redraws the blue source series, red proposed
  bounds and yellow local time window; the same view can be opened in a larger
  dialog. A deterministic packaged screenshot exercises the real view. The
  rebuilt compiled Runner produced one proposal and one 30-point preview while
  preserving the 100.0 source maximum under a 32-point cap. Focused MATLAB
  proposal/Runner tests pass `14/14`. The final packaged EXE SHA256 is
  `cdaf1bad1620d8d8b45095fd019089bae77f1de55e6e72cb42320248f07653cf`;
  its schema-v2 release inventory closes at `595` files and records the new
  compiled-preview smoke as passed.
- Update-backup retention is now explicit in the packaged workbench. The new
  “更新备份” action inventories only direct sibling transaction backups,
  displays the original and target versions, and permits deletion only after a
  second confirmation. Cleanup always keeps the latest two identity-closed
  backups; malformed manifests, missing EXEs, symlinks and unrelated/manual
  directories are excluded. A disposable regression proves that the oldest
  eligible backup is removed while two current and all anomalous directories
  remain.
- Local installed-runtime comparison now covers every configured profile, not only
  representative screenshots. The frozen EXE is launched independently for
  Guanbing, Hongtang, Jiulongjiang, Shuixianhua, Chongyangxi and Zhishan and
  must return the exact bridge identity, layout, default dates, enabled-module
  set, config/template path and SHA256, report capability and 8-tab editor
  shape. Five profiles close against the five packaged report job types and
  Chongyangxi remains explicitly analysis-only. Hashes for the profile catalog,
  six configs and five templates (`12` assets) are identical before and after
  the matrix. MATLAB's `BridgeProfileRegistry` independently passes the same
  all-profile/module/report contract (`2/2`). Evidence is packaged as
  `workbench_profile_matrix.json` and is now a mandatory Release gate.
  Packaged operators can review it from the “所有桥梁自检” title-bar action; the
  reader refuses incomplete checks or a matrix whose byte size/SHA256 no
  longer matches the unique release-inventory record.
- Native screenshot QA exposed an intermittent `PrintWindow` partial-frame
  acceptance weakness: the old gate counted bright samples but did not cap
  black samples. Capture now waits longer, retries up to 15 times, rejects
  frames with more than 10% near-black coarse-grid samples, and independently
  caps a dense whole-frame sample at 3%. Five repeated startup captures and the
  rebuilt eleven-screenshot set pass both gates; the title-bar “所有桥梁自检”
  action is visible in the native evidence.
- Offset correction and grouped plots are migrated as the fifth and sixth
  configuration subtabs. Offset editing covers scalar, fixed, first-day,
  daily/hourly mean or median and segmented date-window rules; overlapping
  segments are rejected before save. Group editing exposes the actual group
  container key, explicitly separates `strain` and `strain_timeseries`, keeps
  point order, validates known points and group keys, and preserves legacy list
  representation when unchanged. Both services pass exact no-op round trips
  across every currently configured bridge and share a MATLAB/Python JSON fixture.
- This milestone fixed a pre-existing MATLAB group-editor alias bug:
  `readGroups(cfg,'strain')` preferred `groups.strain_timeseries`, while the old
  save path always wrote `groups.strain`. Saving now writes the resolved source
  key and synchronizes the canonical key only when both were identical before
  editing; intentionally divergent statistical/time-series groups are left
  separate.
- Plot-common and spectrum settings are migrated as the seventh and eighth
  configuration subtabs. The common editor covers the complete 14-field union
  used by the current bridge catalog, including full/capped high-frequency
  sampling, line/dense-band rendering, gap behavior and line widths. It
  preserves unknown fields, keeps MATLAB defaults implicit, and refuses the
  misleading explicit `full + dense_band` pair because MATLAB forces full
  sampling to line rendering.
- The spectrum editor manages explicit or inherited point coverage for both
  `accel_spectrum` and `cable_accel_spectrum`, and default/per-point find-peak
  orders. All active bridge configurations now use `peak_orders`; older external
  target/tolerance/theoretical-frequency arrays remain importable through a
  compatibility path and are normalized on edit. `fs`, automatic sample-rate
  detection, thresholds and unrelated fields are retained. Invalid table edits
  block module switching without discarding the draft.
- A shared Python/MATLAB fixture and regression suite verifies both schemas;
  all currently configured bridges pass exact no-op round trips. The rebuilt packaged
  EXE passes an 8-config-tab smoke contract (`14` common fields, `2` spectrum
  modules), packaged report-context smoke, and ten native `2020x1120` visual
  captures. The Hongtang common-plot and Zhishan spectrum pages were inspected
  at native resolution.
- Report generation and plot-provenance review are embedded as the next
  workflow milestone. All analysis-manifest `.plot.json` artifacts are listed
  with module, series/source/plotted counts and disclosed incomplete dates.
  Approval is disabled for capped/reduced series, missing source provenance,
  source/input or finite/plotted mismatch, or incoherent day coverage.
- The report child process supports all five report-capable profiles and
  records `loading/preflight/building/qc/completed` progress. It rechecks pinned
  config/template/analysis-manifest hashes, then returns DOCX ZIP/main-part/
  media/hash QC, available PDF pages and report-manifest missing/warning counts.
  The legacy report GUI was refactored to the same dispatcher. A shared
  MATLAB/Python provenance fixture closes the output contract.
- Frozen testing found and fixed a stale-report-EXE packaging bug: the
  workbench packager previously rebuilt the MATLAB runner when stale but only
  copied any existing report EXE. It now rebuilds `BridgeReportBuilder.exe`
  whenever report Python/config inputs are newer, and the release manifest
  records a successful embedded-report protocol smoke.
- Page-level report QC is now part of the shared report task. It uses
  LibreOffice and Poppler to produce a PDF, every page PNG, a contact sheet and
  `visual_qc.json`, with automatic blank-page and raster-edge warnings. A
  reusable sample-matrix CLI rendered five existing local reports (371 pages):
  Guanbing 40, Hongtang 109, Jiulongjiang 107 and Zhishan 47 passed; the
  Shuixianhua 68-page historical sample warned on confirmed blank pages 3 and
  10. All five DOCX packages were structurally valid.
- The first matrix run exposed and fixed another explicit bug: repeating long
  Chinese DOCX names in the QC/profile path made LibreOffice return code 0
  without a PDF. QC now uses short SHA-derived directories and a disposable
  system-temporary LibreOffice profile. The packaged report builder has a
  dedicated visual-QC contract smoke in addition to the report-job smoke.
- The frozen report EXE independently rendered the 40-page Guanbing sample in
  25.6 seconds with the same zero blank/edge-warning result as source mode.
  The report page now exposes an “打开逐页渲染 QC” action bound to the pinned
  contact-sheet directory.
- The report approval gate is now revalidated inside the report child process,
  not only in the PySide6 page. The child refuses missing/unpinned or changed
  config/template/manifest files, bridge/data-root/date mismatches, unsuccessful
  or incomplete module records, absent formal plot provenance, and any
  source/input/finite/plotted closure failure. The UI also refuses approval when
  a manifest contains zero formal provenance records. A frozen-EXE contract
  smoke proves both a valid context and rejection of a provenance-free context.
- A reusable five-profile audit/comparison CLI is available at
  `scripts/validate_fresh_report_profiles.py`. The local audit found zero
  production-eligible historical contexts: Guanbing's configured F: result root
  is absent; Jiulongjiang, Shuixianhua and local Zhishan March manifests predate
  `.plot.json`; the copied Hongtang/remote Zhishan manifests reference result
  provenance not present on this machine. No gate was bypassed or fabricated.
- Isolated generator-only fallback builds were nevertheless completed for the
  four locally available result roots and compared with accepted samples.
  Hongtang/Jiulongjiang/Zhishan rendered 108/104/46 pages without blank or edge
  warnings; Shuixianhua rendered 67 pages and warned on blank pages 10 and 42.
  All four report manifests remained warnings: Hongtang reported 10 missing/WIM
  items, Jiulongjiang 11 missing items, Zhishan lacked anchors 2-5/2-6, and
  Shuixianhua still relies on a synthesized legacy manifest. Page/media deltas
  therefore remain diagnostic evidence, not production parity acceptance.
- The Python suite now passes `292/292`; the report/config-related MATLAB batch
  passes `70/70`. The workbench and report builder were rebuilt, all fourteen native
  screenshots passed visual inspection, and the release manifest records the
  packaged report-gate contract smoke in addition to report-job and visual-QC
  smokes.
- The workbench packager now rebuilds the compiled analysis runner whenever
  included MATLAB sources are newer than the runner executable. This prevents
  a visually current PySide6 package from silently carrying an obsolete core
  runner.
- Compiled-runner testing exposed UTF-8 BOM incompatibility in request JSON.
  Python now writes request JSON as BOM-free UTF-8, and the shared MATLAB
  `bms.io.JsonFile` reader accepts either form. Analysis and automatic-proposal
  dispatch both use the shared reader; BOM-specific regression coverage is in
  place.
- Cross-language contract testing exposed and fixed a pre-existing MATLAB bug:
  default and per-point cleaning thresholds with different optional struct
  fields could not be concatenated. `CleaningPipeline` now normalizes the four
  supported threshold fields before merging. This is a schema-compatibility
  fix only; threshold comparisons and statistics remain unchanged.
- A long-standing bracket error in `config/sample_config.json` was fixed. A
  regression now parses all runtime configs and profile catalogs. Missing
  report test/runtime dependencies (`matplotlib`, `numpy`, `pypdf`) are pinned.

Remaining bridge/period acceptance work after the application cutover:

- make locally available (or deliberately stage from an approved production
  bundle) complete context-matched analysis manifests and every referenced
  formal `.plot.json`, then generate through the embedded task for all five
  profiles and resolve the recorded report-manifest/page/media differences;
- complete the outstanding context-matched, full-period bridge/report
  comparisons before citing those periods as accepted deliverables. Application
  deployment and the ordinary legacy-GUI retirement are complete, but the
  May 26-28 Guanbing sample must not be generalized to a full June or all-bridge
  report acceptance.

## 2026-07-12 Hongtang Typhoon Bavi Template Report

Current completed and verified state:

- The Q2 wind correction, W1/W2 diagnostic, and v1.7.38 locked final report are
  unchanged. The typhoon report uses that accepted Q2 report only as the formal
  mother template; it does not rerun or overwrite the Q2 deliverable.
- The 2026-07-12 Donghua export was verified on 126 before copying directly to
  133. Its waveform and feature ZIP files each contain 139 entries including
  W1/W2. Their SHA256 values are respectively
  `EDB8AD130724E1DE124060676E9CF7D939DA225BE354834D0103EC8A7B1E42EA`
  and `D17AF98F8D229E1FF3C6F928BC011C2467BCA8ECBC53184494B90D6924A4F589`.
- The formal analysis window is the 24 hours before Typhoon Bavi's confirmed
  2026-07-11 23:20 landfall through the latest actual export sample:
  2026-07-10 23:20 to 2026-07-12 09:00. No later data are interpolated or
  inferred. W1/W2 each have all 202 expected complete 10-minute bins.
- W1/W2 raw maximum wind speeds are 14.74/17.42 m/s at 2026-07-11
  16:09:29/17:02:49. Their maximum 10-minute mean wind speeds are 5.21/7.60 m/s
  at 14:10/16:00 and do not reach the 25 m/s level-1 10-minute threshold. Both
  maxima occurred before landfall. The report keeps raw gust peaks separate
  from threshold-comparable 10-minute means.
- Main-girder, tower, south-cable, and north-cable post/pre envelope-median
  ratios are 1.03, 1.04, 0.85, and 0.88. No sustained multi-point synchronous
  amplification is claimed; the report retains the operational caveat that
  weather warnings, traffic controls, and site inspection remain controlling.
- The final Q2-template report is under
  `output/doc/hongtang_typhoon_template_final_20260712_v2`. Manifest status is
  `ok`, missing-entry count is zero, and 80 source-entry audits are recorded.
  Final DOCX SHA256 is
  `4E04BCFD083F99E745EC28A15FAABA9FC86107EC04C252C70655BA7E779D0D6C`.
  Word fields and the TOC were updated. LibreOffice rendered 23 pages; every
  page was inspected, including the corrected chapter break and 4.1-4.5 TOC
  numbering. The previous blank page is absent.
- Production evidence is under
  `F:\Guanbing\run_logs\remote_tasks\hongtang_typhoon_template_20260712\final_20260712_layoutfix`.
  The earlier three-page lightweight brief remains only as a superseded staged
  artifact and must not be presented as the final owner deliverable.

## 2026-07-11 Zhishan May/June Full Recovery And Final Reports (v1.7.28-v1.7.32)

Current completed and verified state:

- Zhishan May and June were recomputed on 133 with the corrected natural-day
  rolling-export loader, `dynamic_raw_sampling_mode=full`, `gap_mode=connect`,
  and `dynamic_raw_line_width=1.0`. Both runs passed strict manifest,
  statistics-workbook, image-dimension, and source/input/finite/plotted
  provenance closure checks. May CF-5 used `53,511,660` source/input samples
  and `53,160,712` finite samples; the former month-end break is absent.
- The June full run completed in `3946.6` seconds. Its only verified source
  omissions are the missing `2026-06-19` dated partition and missing
  `2026-07-01` adjacent rolling file. Formal provenance identifies affected
  dates `2026-06-18`, `2026-06-19`, and `2026-06-30`; the June 30 tail is
  incomplete and was not synthesized.
- v1.7.29 stopped applying static absolute strain bounds before high/low-pass
  filtering. v1.7.30 removed the obsolete April-June SX-5 low-pass `+/-100`
  post-filter, retaining the genuine seasonal response. The targeted May/June
  dynamic-strain rerun completed in `2120.36` seconds; SX-5 high/low-pass counts
  were `52,325,754/52,251,615` for May and
  `48,253,898/48,091,016` for June. All four statistics workbooks and all 64
  regenerated dynamic-strain figures passed QA.
- v1.7.31 added an audited source-quality disclosure parameter. v1.7.32 makes
  the report compare low-pass strain extrema against configured alarm bounds
  instead of emitting the contradictory old “no abnormality” wording. May and
  June SX-5 both contain a real `1000.0 microstrain` maximum above the configured
  `+405.0 microstrain` level-2 boundary. Reports explicitly require raw-data,
  sensor-state, and site-inspection review and do not directly label this as a
  structural abnormality.
- Final locked-media reports on 133 use nine manifest bindings with
  `require_source_provenance=true` and v1.7.28 full acceleration/cable plots:
  - May: `F:\芝山大桥数据\2026年5月\自动报告\芝山大桥健康监测2026年5月份月报_完整数据锁定媒体_v1.7.32_20260711_164940.docx`
    (`SHA256 bf8668a7d4c1cfe627bc9d3522f5f94751e5338de5aab03cf3c6f5f75b018338`).
  - June: `F:\芝山大桥数据\2026年6月\自动报告\芝山大桥健康监测2026年6月份月报_完整数据锁定媒体_v1.7.32_20260711_165035.docx`
    (`SHA256 c18437ec7b912e89e1ba66692f14228ab213a886e4cf3dc1b1e565fefd6394bc`).
- Final local DOCX copies are under
  `output/doc/zhishan_may_v1732_20260711` and
  `output/doc/zhishan_june_v1732_20260711`. QA-only frozen-field copies rendered
  to 47 and 48 pages respectively; every page was checked. No reference-error,
  missing-bookmark, placeholder, layout, or wrong-image defect was found. QA
  PDFs are under the matching `output/pdf` directories.
- Publication validation: MATLAB `497` passed, `0` failed, one expected SQL
  assumption skip; report tests reached `144/144`; GUI smoke tests passed
  `4/4`. Local, origin, and 133 are clean at `9ccf3c5`, exact tag `v1.7.32`.
  The final scheduled task is disabled with result `0`, and no MATLAB process
  is running on 133.

## 2026-07-11 Hongtang Report Point-Token Fix (v1.7.27)

Current verified implementation state:

- The v1.7.26 Zhishan April and Hongtang Q2 full analyses completed on 133 and
  passed strict plot/statistics validation. Zhishan has 14 formal full plots;
  Hongtang has 43 formal time-history plots, including 36 acceleration/cable
  plots with source/input/plotted count closure.
- Full contact-sheet and selected-original visual QA found no recurrence of
  the rolling-export daily truncation/sparse-plot defect. Hongtang A1 becomes
  nearly flat after May 28 and A9-X remains low amplitude, but direct reads of
  the source MAT caches reproduce both behaviors; they are source sensor data,
  not filtering or plotting loss.
- Current-stat report candidates exposed a separate manifest lookup defect:
  the Hongtang `CS1` report slot selected the newer `CS12` image, and `CX1`
  selected `CX12`, because manifest token lookup used substring matching before
  the existing strict filesystem-token check.
- v1.7.27 makes manifest-backed point-image selection enforce exact token
  boundaries. It retains the defensive filesystem collision check and adds a
  regression test where newer `CS12` must not replace `CS1`.
- Validation completed before publication: all `142` Python report tests pass;
  report-GUI Zhishan source self-test reports `ok=true`, `version=v1.7.27`;
  MATLAB main-GUI and plot-settings smoke tests pass `8/8`; Python compileall
  and `git diff --check` pass.
- Historical pre-publication note: report regeneration was pending at this
  point. It was subsequently completed and superseded by later validated
  releases and the stable cutover. Future final reports must still use locked
  media bindings and be rendered and checked page by page.

## 2026-07-10 Guanbing G05-006 Dynamic-Strain Boxplot Restore

Current completed run state:

- Scope: only the high-pass dynamic-strain boxplot/statistics affected by
  `GB-RSG-G05-001-06` under `gb-133:F:\管柄数据\2026年6月`; the monitoring
  range is `2026-05-26` through `2026-05-28`.
- Root cause: `config/default_config.json` contained a permanent per-point
  post-filter range `40..52` for `GB-RSG-G05-001-06`, while the normal
  dynamic-strain range also applied. The two sequential filters removed every
  finite value, so G05-006 disappeared from the high-pass boxplot.
- Fix: remove that obsolete point override and add a regression test requiring
  `resolve_post_filter_thresholds` to return no G05-006 override. Local and
  `gb-133:F:\Guanbing` currently contain the same uncommitted patch on `main`
  at `7834efe`.
- Focused MATLAB validation passed locally and on 133:
  `tests/test_post_filter_thresholds.m` and
  `tests/test_dynamic_strain_boxplot_service.m` (`19` tests total).
- Remote task root:
  `F:\Guanbing\run_logs\remote_tasks\guanbing_g05_006_highpass_20260710_101710`.
  The previous G05 outputs and high-pass statistics workbook were backed up
  there before the targeted rerun.
- Recalculated G05-006 high-pass statistics: `Count=56936`,
  `Min=-1.95610223`, `Q1=-0.45329783`, `Median=-0.18528674`,
  `Q3=-0.01269816`, `Max=10.58718275`, `Mean=0.00038905`, and
  `Std=0.90190458` microstrain.
- Final report on 133:
  `F:\管柄数据\2026年6月\自动报告\G104线管柄大桥监测月报_2026年06月_自动生成_20260710_101948.docx`.
  Figure 19 now contains all six G05 boxes; its text reports maximum tensile
  strain `10.59με` and maximum compressive strain `3.01με` for span 2.
- Local QA bundle:
  `D:\MatlabProjects\Guanbing\output\doc\guanbing_g05_006_20260710_101948`.
  The final DOCX rendered to `40` pages with no reference-error text or missing
  figure blocks. The source M21 template's existing page-total fields and
  manual-highlight content were preserved. Report QC still flags the inherited
  `m/s2` superscript-format risk; the manifest also records legacy anchor
  lookup/pre-extracted-CSV warnings, but the template images were preserved and
  the G05 high-pass image was explicitly replaced.

## 2026-07-10 Zhishan/Hongtang Rolling-Export Full-Plot Recovery (v1.7.26)

Current verified implementation state; supersedes the July 9 plot-sampling
acceptance notes below:

- User acceptance baselines are the local Zhishan March CF-1 and Hongtang Q1
  CS1 raw time-history figures. Both are ordinary blue lines on a `1000x469`
  MATLAB figure, exported as `1563x733`, with `LineWidth=1.0` and connected gaps.
- Root cause: export folder `D` spans approximately `D-1 09:00` through
  `D 09:00`. Commit `292d38a` introduced day-by-day loading but read only folder
  `D` before clipping to calendar day `D`, retaining roughly `00:00-09:00` and
  silently discarding the `09:00-24:00` samples stored under `D+1`.
- The `full` mode added later plotted every sample only after this truncation;
  old full provenance therefore did not prove complete source ingestion.
- v1.7.26 reconstructs each rolling-export natural day from D and D+1, clips to
  `[D,D+1)`, deduplicates files and exact timestamps, then applies cleaning once.
  Month/quarter boundaries can resolve a strict exact-date folder under a
  same-family sibling partition. Missing or ambiguous required sources remain
  explicit instead of being guessed.
- Source provenance now includes required/found contribution, actual source
  roots/files, sample counts, duplicate/conflict counts, coverage endpoints,
  incomplete calendar days, and the scope
  `required_export_contribution`; it also states that internal gap coverage is
  not automatically assessed. Individual and raw group plot sidecars carry the
  point identity and source provenance.
- Formal Zhishan/Hongtang settings are `dynamic_raw_sampling_mode=full`,
  `gap_mode=connect`, and `dynamic_raw_line_width=1.0`. Explicit empty
  `groups.cable_accel` settings prevent raw cable-acceleration group fallback
  from reloading very large full-month/quarter waveforms; cable-force spectrum
  group calculations remain enabled.
- UTF-16LE/CRLF physical header counting is fixed for new parses. Existing v2
  caches are not globally invalidated because Hongtang Q2 has MAT-only dates.
  Historical affected Zhishan caches omit three leading rows per CSV (about
  `0.00017%` of April CF-1), which is unrelated to the daily-gap regression.
- Real local Zhishan April CF-1 validation:
  - corrected calendar input `49,895,490`; finite after cleaning `49,891,939`;
  - old production finite count `18,746,161`; algorithm had discarded
    `31,145,778` finite samples (`62.43%`);
  - April 30 correctly reads `D:\芝山大桥数据\2026年4月\2026-04-30`
    plus `D:\芝山大桥数据\2026年5月\2026-05-01`, producing `1,727,997`
    points through `23:59:59.959`;
  - export folder `2026-04-02` is genuinely missing, so April 1/2 are marked
    incomplete and the approximately 24-hour source gap is not fabricated.
- Corrected local sample:
  `run_logs/diagnostics/source_vs_algorithm_20260710/samples/zhishan/CF-1_20260401_20260430.jpg`.
  It was generated from all `49,895,490` cleaned-series entries in about 39 s,
  is `1563x733`, visually matches the accepted dense baseline, and passes the
  locked-media `require_source_provenance` gate.
- Remote 133 pre-publish state was clean at `3f1c435`, no MATLAB process was
  running, and both old full-rerun tasks are now disabled. The Zhishan April
  task had still been enabled/Ready and was explicitly disabled on July 10.
- Remote source boundary check: Hongtang Q2 and Zhishan June do not currently
  contain or have a recognized sibling containing `2026-07-01`; their June 30
  final approximately 15 hours must remain incomplete unless raw data is later
  recovered.
- Validation completed before release publication:
  - full MATLAB suite: `493` total, `492` passed, `0` failed, and one expected
    assumption-filtered SQL Server integration test because `MSSQLSERVER` was
    stopped;
  - focused rolling-export/config tests: `83/83` passed;
  - MATLAB main-GUI/plot-settings smoke: `8/8` passed with GUI `v1.7.26`;
  - Python locked-media tests: `32/32` passed;
  - report GUI Zhishan source self-test returned `ok=true`, `version=v1.7.26`;
  - Python compileall and `git diff --check` passed.
- Next production order: publish/pull v1.7.26; generate and visually inspect one
  Hongtang Q2 full sample on 133; only after both bridge samples pass, run the
  full Zhishan April and Hongtang Q2 analyses. Generate reports last using
  strict locked-media replacement with `require_source_provenance=true`, then
  render and inspect every page. No corrected report has been generated yet.

Detailed evidence: `docs/dynamic_plot_source_vs_algorithm_20260710.md`.

## 2026-07-09 Hongtang/Zhishan High-Sample Raw Line Plot Final Refresh

Current accepted run state:

- Scope: `gb-133` production rerun for:
  - Hongtang Q2: `E:\洪塘大桥数据\2026年4-6月`
  - Zhishan April/May/June: `F:\芝山大桥数据\2026年4月`,
    `F:\芝山大桥数据\2026年5月`, `F:\芝山大桥数据\2026年6月`
- Code state: local, `origin/main`, and `gb-133:F:\Guanbing` are on `main` at
  `8e95106 Use high-sample raw line plots for reports` for the accepted run.
- Final report-facing raw dynamic plot policy for Hongtang and Zhishan:
  `plot_common.dynamic_raw_render_mode=line`,
  `plot_common.dynamic_raw_fig_max_points=1200000`,
  `plot_common.dynamic_raw_min_points_per_day=12000`, and
  `plot_common.dynamic_raw_line_width=1.2`. Ordinary plot limits remain
  separate. This supersedes both the earlier `dense_band` attempts and the
  earlier lower-cap high-density line run.
- Production task root on 133:
  `F:\Guanbing\run_logs\remote_tasks\dense_band_final_20260709`.
- Completed analysis logs for the accepted final line-mode run:
  - `E:\洪塘大桥数据\2026年4-6月\run_logs\run_log_20260709_165250.txt`
  - `F:\芝山大桥数据\2026年4月\run_logs\run_log_20260709_163941.txt`
  - `F:\芝山大桥数据\2026年5月\run_logs\run_log_20260709_172801.txt`
  - `F:\芝山大桥数据\2026年6月\run_logs\run_log_20260709_173553.txt`
- Regenerated reports on 133:
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260709_174239.docx`
  - `F:\芝山大桥数据\2026年4月\自动报告\芝山大桥健康监测2026年4月份月报_自动生成_20260709_174338.docx`
  - `F:\芝山大桥数据\2026年5月\自动报告\芝山大桥健康监测2026年5月份月报_自动生成_20260709_174350.docx`
  - `F:\芝山大桥数据\2026年6月\自动报告\芝山大桥健康监测2026年6月份月报_自动生成_20260709_174402.docx`
- Report generation runtimes were normal: Hongtang about `84` seconds;
  Zhishan monthly reports about `11` to `12` seconds each.
- Local QA bundle:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\dense_band_final_20260709`.
  Final copied bundle:
  `reports_bundle_dense_band_20260709_174412_final`; rendered pages:
  `rendered_174412_final`.
- QA result:
  - all four report manifests were `status=ok`; missing-image entries were
    `0`. Hongtang warning entries are repeated copies of the same preflight
    warning (`earthquake has points but no file_patterns.earthquake`) and are
    not missing figures;
  - DOCX internal XML/text scan found no `引用源未找到`, `错误！`,
    `未定义书签`, placeholder braces, or `MERGEFIELD`;
  - media counts were Hongtang `183` and Zhishan `58` per month;
  - LibreOffice rendered Hongtang to `110` PDF pages and each Zhishan report
    to `47` PDF pages. Selected high-frequency pages were rendered and checked:
    Hongtang `p057`, `p061`, `p076`, `p088`, `p098`; Zhishan monthly `p031`,
    `p041`, `p042`, `p043`;
  - final visual policy is high-sample ordinary line plotting. Dense-band
    vertical bars and filled-envelope patches were rejected during QA because
    they either looked striped or introduced geometric filled blocks. The
    accepted line-mode figures preserve the original waveform look where source
    samples exist; true long source gaps remain connected by `gap_mode=connect`
    and should not be mistaken for downsampling gaps.
- Operational note: remote `[folder-view] Failed` messages at the end of
  MATLAB runs are Explorer-open failures in the SSH session, not analysis or
  report failures.
- This supersedes the `dense_plot_refresh_20260709`, `dense_band`, and
  `highfreq_plot_sampling_20260709` runs below.

## 2026-07-09 Hongtang/Zhishan High-Density Raw Plot Rerun

Superseded by the dense raw plot final refresh above; kept as run history:

- Scope: `gb-133` production rerun for:
  - Hongtang Q2: `E:\洪塘大桥数据\2026年4-6月`
  - Zhishan April/May/June: `F:\芝山大桥数据\2026年4月`,
    `F:\芝山大桥数据\2026年5月`, `F:\芝山大桥数据\2026年6月`
- Code state: local and `gb-133:F:\Guanbing` are on `main` at
  `caffd0e Improve high-frequency report plot sampling`.
- Main change from the earlier v1.7.23 pass: report-facing raw dynamic plots
  now use dedicated high-density extrema-preserving sampling via
  `plot_common.dynamic_raw_fig_max_points=900000` and
  `plot_common.dynamic_raw_min_points_per_day=10000` for Hongtang and Zhishan.
  Ordinary/common plot limits remain separate.
- Production task root on 133:
  `F:\Guanbing\run_logs\remote_tasks\highfreq_plot_sampling_20260709`.
- Completed analysis manifests:
  - `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260709_065456.json`
  - `F:\芝山大桥数据\2026年4月\run_logs\analysis_manifest_20260709_070041.json`
  - `F:\芝山大桥数据\2026年5月\run_logs\analysis_manifest_20260709_070659.json`
  - `F:\芝山大桥数据\2026年6月\run_logs\analysis_manifest_20260709_071257.json`
- Regenerated reports on 133:
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260709_071654.docx`
  - `F:\芝山大桥数据\2026年4月\自动报告\芝山大桥健康监测2026年4月份月报_自动生成_20260709_071824.docx`
  - `F:\芝山大桥数据\2026年5月\自动报告\芝山大桥健康监测2026年5月份月报_自动生成_20260709_071837.docx`
  - `F:\芝山大桥数据\2026年6月\自动报告\芝山大桥健康监测2026年6月份月报_自动生成_20260709_071849.docx`
- Report generation runtimes were normal: Hongtang about `121` seconds;
  Zhishan monthly reports about `12` to `14` seconds each.
- Local QA bundle:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\highfreq_plot_sampling_20260709_reports`.
  It contains copied DOCX reports, manifests, report images, PDFs, rendered
  PNG pages, and contact sheets.
- QA result:
  - all four report manifests were `status=ok`, `missing_count=0`,
    `warnings=0`;
  - DOCX internal text/XML scan found no `引用源未找到`, `错误`, `未定义书签`,
    `Error!`, placeholder tokens, or common mojibake;
  - LibreOffice/Poppler rendered Hongtang to `110` page PNGs and each
    Zhishan month to `47` page PNGs for visual contact-sheet review;
  - Word COM PDF export on the local workstation hung on the large Hongtang
    DOCX and was stopped. LibreOffice can falsely re-evaluate Word fields
    such as `STYLEREF/SEQ`; use DOCX XML visible field results as the final
    cross-reference check when LibreOffice shows `引用源未找到`.
- Visual judgment: Hongtang and Zhishan high-frequency time-history figures now
  use dense extrema-preserving raw samples and no longer show the stale sparse
  uniform-sampling look. Remaining blank/low-coverage intervals should be
  treated as source-data coverage gaps unless raw dated folders prove
  otherwise.

## 2026-07-09 Hongtang Q2 High-Frequency Plot Refresh

Current accepted run state:

- Scope: `gb-133` production data root
  `E:\洪塘大桥数据\2026年4-6月`.
- Code state: no source-code change was needed for this pass. The remote and
  local worktrees were already on `main` at `bf6956a` / `v1.7.23`, where
  `pipeline/prepare_plot_series.m` and
  `bms.analyzer.DynamicSeriesService.limitSeriesPoints` already use
  bucketed extrema-preserving sampling. This same generic plotting fix now
  covers Hongtang Q2 high-frequency time histories as well as Zhishan.
- Production task directories on 133:
  - `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1723_resample_20260709_012334`
  - `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1723_dynamic_restore_20260709_020817`
  - `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1723_report_20260709_0240`
- Reprocessed modules:
  `wind`, `earthquake`, `acceleration`, and `cable_accel`. The first pass
  produced new `20260401_20260630` figures. A later RMS-only refresh was
  rejected for acceptance because, in the Hongtang MAT-only direct-wave state,
  it refreshed `0` points and overwrote dynamic stats with header-only files.
  The accepted state was restored by rerunning the main `acceleration` and
  `cable_accel` analyzers.
- Accepted analysis manifest:
  `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260709_023826.json`.
- Final report generated on 133:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260709_024212.docx`.
  It was copied locally to
  `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260709_024212.docx`.
- Report manifest/QC:
  `period_report_manifest_20260709_024212.json`,
  `report_qc_hongtang_period_20260709_024212.json`, and
  `report_qc_hongtang_period_20260709_024212.txt` under the remote
  `自动报告` directory. QC status was `ok`, `missing_count=0`,
  `issue_count=0`, and `output_docx_image_count=179`.
- Stats QA after the restore:
  - `accel_stats.xlsx`: `12` data rows;
  - `cable_accel_stats.xlsx`: `24` data rows;
  - `wind_stats.xlsx`: `2` data rows;
  - `eq_stats.xlsx`: `3` data rows.
- Local QA bundle:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_v1723_resample_20260709_024212`.
  The DOCX rendered through LibreOffice/Poppler to `110` page PNGs for visual
  review. Contact-sheet review of the high-frequency page ranges and the
  copied key images found no obvious blank pages, missing figures, or stale
  sparse uniform-sampling appearance. DOCX internal text scan found no
  reference-error/place-holder hits.
- Important output-folder note: old `20260627` image files can still coexist
  in the result directories, but the accepted report manifest had `0` image
  references to `20260627` and thousands of `20260630` image references.

## 2026-07-08 Zhishan Q2 Tight Cleaning And Plot Sampling

Current accepted code/report state:

- Scope: `gb-133` production data roots
  `F:\芝山大桥数据\2026年4月`, `F:\芝山大桥数据\2026年5月`, and
  `F:\芝山大桥数据\2026年6月`.
- Cleaning/profile changes:
  - bearing displacement `DX-1` to `DX-4` Q2 cleaning is now `[-35, 35]`
    mm for both raw and filtered statistics/plots;
  - static strain `SX-1` to `SX-10` Q2 cleaning is now `[-100, 100]`
    microstrain;
  - dynamic-strain highpass and lowpass post-filter cleaning also uses
    `[-100, 100]` microstrain for Q2, while the March lowpass special
    `max=20` rule is preserved;
  - structural acceleration Q2 default cleaning is now `[-0.3, 0.3]`
    m/s^2; raw acceleration time-history plot styles explicitly keep
    `warn_lines=[]` and `group_warn_lines=[]`, while RMS warning lines are
    retained;
  - cable acceleration cleaning/offset rules remain the accepted April-June
    rules from the previous Zhishan refinement.
- Plotting change:
  - `pipeline/prepare_plot_series.m` and
    `bms.analyzer.DynamicSeriesService.limitSeriesPoints` now use
    bucketed extrema-preserving sampling instead of uniform point sampling.
    Each time bucket keeps its local min/max/absolute-extreme and endpoints,
    so dense high-frequency time histories keep a continuous-looking envelope
    when the plotted series is capped by `fig_max_points`.

Validation and production run:

- Local MATLAB validation passed with a clean explicit path:
  `tests/test_prepare_plot_series_gap_mode.m`,
  `tests/test_dynamic_series_service.m`, `tests/test_zhishan_config.m`,
  `tests/test_cleaning_pipeline.m`, `tests/test_load_timeseries_range.m`,
  `tests/test_bms_services.m`, and `tests/test_post_filter_thresholds.m`.
- 133 focused validation passed:
  `tests/test_prepare_plot_series_gap_mode.m`,
  `tests/test_dynamic_series_service.m`, and `tests/test_zhishan_config.m`.
- 133 production task directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_q2_tight_clean_20260708_224403`.
- 133 reran the affected modules for April, May, and June:
  `bearing_displacement`, `strain`, `dynamic_strain_highpass`,
  `dynamic_strain_lowpass`, `acceleration`, `accel_spectrum`, and
  `cable_accel`.
- Stats QA passed on 133:
  - bearing displacement raw/filtered min/max within `[-35, 35]`;
  - static strain and dynamic-strain high/lowpass min/max within
    `[-100, 100]`;
  - structural acceleration min/max within `[-0.3, 0.3]`.
- Source-data notes:
  `F:\芝山大桥数据\2026年4月` has no `2026-04-02` source folder in the
  current listing, and the earlier accepted June note still applies:
  `F:\芝山大桥数据\2026年6月` has no `2026-06-19` source folder.
- Reports regenerated on 133:
  - `F:\芝山大桥数据\2026年4月\自动报告\芝山大桥健康监测2026年4月份月报_自动生成_20260709_005850.docx`
  - `F:\芝山大桥数据\2026年5月\自动报告\芝山大桥健康监测2026年5月份月报_自动生成_20260709_005903.docx`
  - `F:\芝山大桥数据\2026年6月\自动报告\芝山大桥健康监测2026年6月份月报_自动生成_20260709_005916.docx`
- Report generation elapsed times were about `13` seconds each, well below
  the 10 minute anomaly threshold.
- Report manifests for all three reports returned `warnings=[]` and
  `output_docx_image_count=58`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_q2_tight_clean_20260709`.
  The three reports rendered to `47` PNG pages each. Contact-sheet review and
  key-image review found no large blank areas, missing-image pages, obvious
  layout breaks, stale sparse high-frequency sampling, or raw acceleration
  `±1` warning lines. Key image contact sheet:
  `...\rendered\key_image_contact_sheet.jpg`.

## 2026-07-08 Zhishan May/June Monthly Report Refinement

Current accepted code/report state:

- Scope: `gb-133` production data roots
  `F:\芝山大桥数据\2026年5月` and `F:\芝山大桥数据\2026年6月`.
- Cleaning/profile change:
  - the April validated Zhishan cleaning windows in
    `config/zhishan_config.json` now run from `2026-04-01` through
    `2026-06-30`, covering May and June with the same engineering rules;
  - bearing displacement `DX-1` to `DX-4` keeps level-2 cleaning bounds
    `[-80, 80]` mm;
  - static strain and dynamic-strain post-filtering keep the grouped level-2
    bounds, with `SX-5`, `SX-6`, and `SX-8` capped at `200` microstrain;
  - cable acceleration thresholds are
    `CF-1/2/3/4/5/7/8 = [-500, 500]`, `CF-6 = [-3000, 3000]`;
  - cable fixed-offset corrections now cover `2026-04-01` to `2026-06-30`:
    `CF-1=-2000`, `CF-2=-2000`, `CF-3=29600`, `CF-4=29600`,
    `CF-5=29800`, `CF-6=-200`, `CF-7=-1500`, `CF-8=2000`.
- Test hardening:
  - `tests/test_zhishan_config.m` now asserts the May/June window endpoints
    for strain, lowpass dynamic-strain, bearing displacement, and cable
    acceleration offsets/thresholds.
  - Avoid `addpath(genpath(projectRoot))` for validation or production runs
    because old release archives under the workspace can shadow current
    `pipeline` functions. Use explicit project paths with `-begin`.

Validation and production run:

- Local focused validation passed with clean MATLAB path:
  `tests/test_zhishan_config.m`, `tests/test_post_filter_thresholds.m`,
  `tests/test_dynamic_strain_boxplot_service.m`,
  `tests/test_time_series_loader.m`, plus Python report-manifest tests
  `tests_py.test_manifest_image_lookup` and
  `tests_py.test_report_manifest_artifacts`.
- 133 focused validation passed with clean MATLAB path:
  `tests/test_zhishan_config.m`, `tests/test_post_filter_thresholds.m`,
  and `tests/test_time_series_loader.m`.
- 133 full/refinement task directory:
  `F:\Guanbing\run_logs\remote_tasks\zhishan_202605_202606_run_20260708_182426`.
  - May run directory: `...\202605`; completed successfully.
  - June run directory: `...\202606`; completed successfully.
- Source-data note:
  `F:\芝山大桥数据\2026年6月` does not contain a `2026-06-19` dated
  source folder. Treat this as a source-data coverage gap, not a processing
  failure.
- Stats QA passed on 133 with `0` threshold violations:
  - bearing `DX-1` to `DX-4` original and filtered ranges within `[-80, 80]`;
  - static strain and dynamic-strain high/lowpass ranges within the configured
    group bounds;
  - cable acceleration ranges within the configured CF thresholds;
  - cable spectrum sheets contain `31` daily rows for May and `30` daily rows
    for June.
- Important observed data condition:
  June `SX-5` dynamic-strain valid sample count is much lower than the other
  strain points after cleaning (`117226` highpass and `118445` lowpass rows).
  This should be considered when interpreting the June report.
- Reports regenerated on 133:
  - `F:\芝山大桥数据\2026年5月\自动报告\芝山大桥健康监测2026年5月份月报_自动生成_20260708_195300.docx`
  - `F:\芝山大桥数据\2026年6月\自动报告\芝山大桥健康监测2026年6月份月报_自动生成_20260708_195312.docx`
- Report manifests:
  - `F:\芝山大桥数据\2026年5月\自动报告\zhishan_report_build_manifest_20260708_195300.json`
  - `F:\芝山大桥数据\2026年6月\自动报告\zhishan_report_build_manifest_20260708_195312.json`
  Both manifests returned `status=ok`, `warnings=[]`, `missing_count=0`,
  and `output_docx_image_count=58`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_202605_202606_20260708_195312`.
  Both DOCX files rendered to `47` PNG pages; text QA found no `错误`,
  `引用源未找到`, `未定义书签`, `Error! Reference source not found`, `${`,
  `{{`, `TODO`, or stale `2026年3月` / `2026年4月`. Visual spot checks
  confirmed updated bearing displacement, strain/dynamic-strain, cable
  acceleration, and cable-spectrum pages.

## 2026-07-08 Zhishan April Report Refinement

Current accepted code/report state:

- Scope: `gb-133` production data root `F:\芝山大桥数据\2026年4月`.
- Cleaning/profile changes:
  - bearing displacement `DX-1` to `DX-4` keeps the April level-2 cleaning
    bounds `[-80, 80]` mm;
  - static strain `SX-5`, `SX-6`, and `SX-8` now remove values `> 200`;
  - dynamic strain highpass/lowpass post-filtering also caps `SX-5`,
    `SX-6`, and `SX-8` at `200`;
  - cable acceleration April rules are:
    `CF-1/2/3/4/5/7/8 = [-500, 500]`, `CF-6 = [-3000, 3000]`;
  - cable fixed offsets are:
    `CF-1=-2000`, `CF-2=-2000`, `CF-3=29600`, `CF-4=29600`,
    `CF-5=29800`, `CF-6=-200`, `CF-7=-1500`, `CF-8=2000`.
- Dynamic strain performance changes:
  - highpass filtering supports chunked processing with overlap;
  - lowpass filtering supports downsample-before-lowpass for long-period
    trends and is enabled for Zhishan April with 60 second bins.
- Raw CSV cache hardening:
  - `CacheManager.sourcesMatch` now accepts a raw cache when the exact source
    path was stored with mojibake but the source filename, bytes, and mtime
    fingerprint still match. This fixed the CF-5 `2026-04-30` cache miss that
    caused MATLAB to hang while falling back to a 131 MB CSV read.
- Report generator:
  - `reporting/build_zhishan_monthly_report.py` now reads the bearing
    displacement figures from split raw/filter group directories for
    `图 2-5` and `图 2-6`, so stale combined-directory images are not reused.

Validation and production run:

- Local tests passed:
  `tests/test_time_series_loader.m`, `tests/test_zhishan_config.m`,
  `tests/test_post_filter_thresholds.m`,
  `tests/test_dynamic_strain_boxplot_service.m`,
  and `tests/test_zhishan_report_assets.py`.
- 133 focused tests passed:
  `tests/test_time_series_loader.m`, `tests/test_zhishan_config.m`,
  and `tests/test_zhishan_report_assets.py`.
- 133 full/refinement runs:
  - full module run directory:
    `F:\Guanbing\run_logs\remote_tasks\zhishan_202604_refine_20260708_1500`;
  - cable resume run directory:
    `F:\Guanbing\run_logs\remote_tasks\zhishan_202604_cable_resume_20260708_1615`;
  - cable resume completed with `status=ok`, offset rows `8`, and wrote:
    `F:\芝山大桥数据\2026年4月\stats\cable_accel_stats.xlsx`,
    `F:\芝山大桥数据\2026年4月\stats\cable_accel_spec_stats.xlsx`.
- Stats QA passed on 133:
  - bearing `DX-1` to `DX-4` within `[-80, 80]`;
  - `SX-5`, `SX-6`, `SX-8` static and dynamic strain caps satisfied;
  - CF cable acceleration ranges satisfy the configured April thresholds.
- Report regenerated on 133:
  `F:\芝山大桥数据\2026年4月\自动报告\芝山大桥健康监测2026年4月份月报_自动生成_20260708_162640.docx`.
- Report manifest:
  `F:\芝山大桥数据\2026年4月\自动报告\zhishan_report_build_manifest_20260708_162640.json`.
  Manifest result: `status=ok`, `warnings=[]`, `missing_count=0`,
  `output_docx_image_count=58`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_202604_refine_20260708`.
  Rendered to 47 PNG pages; text QA found no `错误`, `引用源未找到`,
  `未定义书签`, `Error! Reference source not found`, `${`, `{{`, `TODO`,
  or stale `2026年3月`. Visual spot-checks confirmed the updated bearing
  displacement and cable acceleration pages are using the new images.

## 2026-07-07 Hongtang Q2 SL-8 Negative Strain Cleaning

Current accepted code/report state:

- This is a post-`v1.7.22` Hongtang Q2 data-cleaning adjustment; GUI/report
  version remains `v1.7.22`.
- `config/hongtang_config.json` now applies a point-specific Q2 static-strain
  threshold for `SL-8`: remove values `< 0` or `> 150`.
- The existing `SL-8` `offset_correction = 100`, alarm bounds, and other
  tower strain point thresholds were not changed.
- Regression coverage: `tests/test_config_integration_regression.m` asserts
  `SL_8.thresholds.min == 0` and `max == 150`.

Validation and production run:

- Local MATLAB tests passed:
  `tests/test_config_integration_regression.m`,
  `tests/test_hongtang_lowfreq_loader.m`,
  `tests/test_cleaning_pipeline.m`,
  `tests/test_post_filter_thresholds.m`.
- 133 ran the same focused MATLAB tests successfully after applying the
  validation patch.
- 133 strain rerun:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_sl8_negative_clean_20260707_172058`
  - MATLAB run status: `ok`.
  - MATLAB elapsed inside run: `352.20` seconds.
  - Analysis manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260707_172811.json`.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\strain_stats.xlsx`.
  - Stats check: `SL-8` row has `Min=0.378`, `Max=127.25`,
    `Mean=75.545`.
- 133 report regenerated:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260707_173019.docx`.
- Report manifest:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260707_173019.json`.
- Manifest result: `status=ok`, `missing_count=0`,
  `report_qc_status=ok`, `report_number=BG02FQJC2600002-J2`.
- Final local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_sl8_negative_clean_20260707_173019`.
  - DOCX OOXML/text checks found no saved `引用源未找到`,
    `错误！未定义书签`, `Error!`, `${`, or `{{` tokens.
  - DOCX contains `187` media files and `185` drawing elements.
  - LibreOffice rendered PDF is available for fallback inspection, but it is
    not an acceptance render for this template because it mis-renders Word
    cross-reference fields as `引用源未找到` and paginates to `110` pages while
    the document fields still show `共 82 页`.
  - Local Word COM automation failed even on a small smoke document in this
    session; 133 Word COM direct PDF export also failed to open this document.
    Treat Word/WPS manual render as the remaining layout check before external
    release if strict Word-rendered PDF evidence is required.

## 2026-07-07 Hongtang Q2 v1.7.22 Period Template Hardening

Current accepted code/report state:

- GUI/report version bumped to `v1.7.22`.
- Release commit: `60e37ca` plus follow-up sync-status documentation commit.
- Release tag: `v1.7.22`.
- Scope:
  - add the official Hongtang period-report auto template:
    `reports/洪塘大桥健康监测周期报模板-自动报告.docx`;
  - default Hongtang period-report profiles to the 2026 Q2 data root,
    monitoring range, report date, and auto template;
  - derive the quarterly report number automatically, with an explicit
    `--report-number` override for CLI recovery runs;
  - generalize WIM caption/table anchors so static captions are located by
    content rather than one fixed table title;
  - validate copied WIM continuation tables before reuse, and fall back to a
    standard table if the template table is not addressable by the required
    row/column layout;
  - remove stale picture/short-label blocks before target captions when a
    manually checked report is reused as the next generator template.

133 production verification:

- 133 source path during validation: `F:\Guanbing`, patched on top of
  `f1c9b21` / `v1.7.21`.
- After publish, 133 `F:\Guanbing` was fast-forwarded to `origin/main` /
  `v1.7.22` and left with a clean worktree. The pre-publish validation patch
  was retained as `stash@{0}: pre_v1722_validation_backup`.
- Focused Python report tests passed on both local and 133:
  `tests_py.test_docx_image_blocks`,
  `tests_py.test_wim_auto_captions`,
  `tests_py.test_build_period_report_word_update`,
  `tests_py.test_hongtang_period_followups`,
  `tests_py.test_bridge_profiles`.
- Compile checks passed for `reporting` and `tests_py` on both local and 133.
- Hongtang Q2 period report regenerated on 133 in `110.38` seconds:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260707_150151.docx`.
- Report manifest:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260707_150151.json`.
- Manifest result: `status=ok`, `missing_count=0`, `warnings_count=0`,
  `report_qc_status=ok`, `report_number=BG02FQJC2600002-J2`.
- The generated report contains `183` media files and `189` drawings. An
  earlier validation build exposed duplicated template figures with `314`
  drawings and a `127` page render; `remove_nearby_picture_block_before`
  corrected this to the accepted page count.

Final local QA copy:

- `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_template_report_20260707_150151`.
- Word COM exported an `82` page PDF and all `82` pages rendered to PNG.
- Low-content rendered pages: only page `2`, consistent with the intentional
  blank/separator page.
- PDF text checks found no `引用源未找到`, `错误!`, `错误！未定义书签`,
  `Error!`, `${`, or `{{`.
- Cover shows report number `BG02FQJC2600002-J2` and date `2026年07月10日`.
- Earthquake summary text and rendered figures are aligned: horizontal peak
  `0.018m/s²`, vertical peak `0.019m/s²`, and `EQ-X/Y/Z` figure markers extend
  through `2026-06-30`.
- Wind section check: bridge-deck 10-minute average maximum is `5.46m/s`, and
  wind/earthquake captions/tables render in the expected section.
- Checked PDF copied back to 133:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_template_report_20260707_150151_word_checked.pdf`.

## 2026-07-06 Hongtang Q2 v1.7.21 Plot Extrema Consistency

Current accepted code/report state:

- GUI/report version bumped to `v1.7.21`.
- Release tag planned: `v1.7.21`.
- Scope:
  - preserve finite min, max, and absolute-peak samples when time-series plots
    are downsampled for display;
  - preserve the same extrema when lightweight `.fig` files simplify line data;
  - keep static-strain boxplot sampling from dropping critical extrema;
  - make earthquake stats carry both `Peak` and `PeakSigned`;
  - place earthquake plot markers/text at the full-resolution absolute peak
    sample instead of the largest positive plotted sample.
- Coverage applies through shared plotting paths to deflection, bearing
  displacement, tilt, crack, temperature, humidity, rainfall, GNSS, static
  strain, dynamic strain, acceleration, cable acceleration, wind, earthquake,
  frequency-time-history, and cable-force time-history outputs.
- Audit note:
  `docs/hongtang_q2_extrema_plot_audit.md`.
- Local focused MATLAB tests passed:
  `tests/test_prepare_plot_series_gap_mode.m`,
  `tests/test_dynamic_series_service.m`,
  `tests/test_earthquake_series_service.m`,
  `tests/test_earthquake_analysis_pipeline.m`,
  `tests/test_structural_time_series_plot_service.m`,
  `tests/test_strain_analysis_pipeline.m`,
  `tests/test_wind_analysis_pipeline.m`,
  `tests/test_bms_services.m`,
  `tests/test_writer_plot_manifest_services.m`,
  `tests/test_dynamic_strain_boxplot_service.m`.

Remote 133 production verification:

- `F:\Guanbing` has the same working-tree patch applied on top of `e2f32e6`
  / `v1.7.20` for production verification.
- Hongtang Q2 earthquake module reran successfully in `91.56` seconds.
- Regenerated stats:
  `E:\洪塘大桥数据\2026年4-6月\stats\eq_stats.xlsx`.
- Regenerated analysis manifest:
  `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260706_211605.json`.
- Remote `.fig` validation passed for `EQ-X`, `EQ-Y`, and `EQ-Z`: each
  `eq_stats.xlsx` row matched the plotted curve point, red marker, and text
  label within exported display precision (3 decimal places and whole seconds).
- Hongtang Q2 period report regenerated on 133 in `87.27` seconds:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_213107.docx`.
- Report manifest:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_213107.json`.
- Checked PDF copied back to 133:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_period_v1721_20260706_213107_word_checked.pdf`.

Final local QA copy:

- `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_v1721_20260706_213107`.
- Manifest: `status=ok`, `missing_count=0`, `warnings=0`,
  `report_qc_status=ok`.
- Independent report QC passed with `0` issues, `29` tables, and `181` images.
- Word COM exported an `81` page PDF and all `81` pages rendered to PNG.
- PDF/DOCX text checks found no `引用源未找到`, `错误!`, `错误！未定义书签`,
  `Error!`, `${`, or `{{`.
- Earthquake summary text in the rendered PDF states horizontal peak
  `0.018m/s²` and vertical peak `0.019m/s²`; local `eq_stats_v1721.xlsx`
  rows are `EQ-X 0.005`, `EQ-Y 0.018`, and `EQ-Z 0.019`.
- Low-content rendered pages were page `2` and page `81`, consistent with the
  report's blank/separator and final-signoff pages.

## 2026-07-06 Hongtang Q2 v1.7.20 Report Follow-up Correction

Current accepted code/report state:

- GUI/report version bumped to `v1.7.20`.
- Implementation commit: `6519192` (`Fix Hongtang Q2 report follow-ups`).
- Scope:
  - update Hongtang Q2 table 1-2 maintenance log to the actual Q2 records only;
  - fix period-report earthquake peak mapping from `eq_stats.xlsx` rows shaped as
    `PointID=EQ, Component=X/Y/Z` so the summary uses `EQ-X/EQ-Y/EQ-Z`;
  - clean all Hongtang bearing-displacement values outside each point's level-2
    alarm bounds `[-240, 240]` before rerun/reporting.

Code/config changes:

- `reporting/build_period_report.py` now regenerates table 1-2 from the Q2
  maintenance log when the report period intersects 2026-04-01 to 2026-06-30.
- `reporting/build_monthly_report.py` normalizes earthquake stats keys so
  `EQ + X/Y/Z` rows contribute to the horizontal/vertical peak summary.
- `config/hongtang_config.json` now sets `per_point.bearing_displacement.*.thresholds`
  equal to each point's level-2 bounds, while preserving `Z11_2` offset correction.
- `ui/run_gui.m` and `reporting/report_gui.py` report `v1.7.20`.

Validation:

- Local Python tests passed:
  `tests_py.test_hongtang_period_followups`,
  `tests_py.test_artifact_lookup`,
  `tests_py.test_build_period_report_word_update`.
- Local MATLAB tests passed:
  `tests/test_main_gui_smoke.m`,
  `tests/test_hongtang_lowfreq_loader.m`,
  `tests/test_cleaning_pipeline.m`,
  `tests/test_structural_time_series_plot_service.m`,
  `tests/test_post_filter_thresholds.m`.
- 133 pulled `6519192`; the same focused Python tests passed, JSON threshold
  assertion passed (`10` bearing points), and the same focused MATLAB tests passed.

133 production rerun:

- Bearing-displacement task:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1720_bearing_20260706_174310`
  - MATLAB elapsed inside run: `135.18` seconds; task status elapsed `142.25`
    seconds.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\bearing_displacement_stats.xlsx`.
  - Analysis manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260706_174539.json`.
  - Stats check: `10` rows, `0` `OrigMin_mm`/`OrigMax_mm`/`FiltMin_mm`/
    `FiltMax_mm` violations outside `[-240, 240]`.
- Report generation task:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1720_report_20260706_174646`
  - Runtime: `105.84` seconds.
  - Output DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_174718.docx`.
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_174718.json`.
  - Checked PDF copied back to 133:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_174718_word_checked.pdf`.

Final local QA copy:

- `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_v1720_20260706_174718`
  - Manifest check: `missing=0`, `warnings=0`.
  - Word COM exported an `81` page PDF and all `81` pages rendered to PNG.
  - Low-content pages were `2`, `5`, and `81`, consistent with separator/blank
    and final-signoff pages.
  - DOCX/PDF checks found no `引用源未找到`, `错误!`, `错误！未定义书签`,
    `Error!`, `${`, or `{{`.
  - Table 1-2 renders as Q2-only `15` maintenance rows.
  - Report text now states bearing displacement range `-60.3mm~173.0mm`.
  - Earthquake summary now states horizontal peak `0.018m/s²` and vertical peak
    `0.019m/s²`; rendered EQ-X/Y/Z figures reach 2026-06-30.

## 2026-07-06 Hongtang Q2 Strain Cleaning Threshold Update

Current accepted code state:

- Latest commit: `43c2b99` (`Tighten Hongtang Q2 strain cleaning thresholds`).
- This is a post-`v1.7.19` Hongtang Q2 report data-cleaning adjustment; GUI version remains `v1.7.19`.

Config change:

- `config/hongtang_config.json` now applies uniform Q2 static-strain cleaning thresholds:
  - main girder strain groups `B/C/D/E/F/G/H`: remove values `< -200` or `> 200`;
  - tower strain groups `K/L`: remove values `< -150` or `> 150`.
- The thresholds are stored in each `per_point.strain.*.thresholds` object with empty `t_range_start` / `t_range_end`, meaning the rule applies to the selected Q2 run period.
- Existing offset corrections and alarm bounds were not changed.

Validation and production run:

- Local MATLAB tests passed:
  `tests/test_hongtang_lowfreq_loader.m`, `tests/test_cleaning_pipeline.m`, `tests/test_post_filter_thresholds.m`.
- 133 pulled `43c2b99`; remote JSON and threshold checks passed, and the same MATLAB tests passed.
- 133 strain rerun:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_strain_thresholds_20260706_163317`
  - MATLAB run status: `ok`.
  - MATLAB elapsed inside run: `146.42` seconds.
  - Analysis manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260706_163554.json`
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\strain_stats.xlsx`
  - Stats check: 64 strain rows; main girder rows have no values outside `[-200, 200]`; tower rows have no values outside `[-150, 150]`.
  - Representative stats after cleaning: `SG-6` min/max `-34.649/53.027`; `SL-8` min/max `-148.929/127.25`.
- 133 report regeneration:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_report_strain_thresholds_20260706_163656`
  - Runtime: `88.98` seconds.
  - Output DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_163731.docx`
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_163731.json`
  - Checked PDF copied back to 133:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_163731_checked.pdf`
- Final local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_strain_thresholds_20260706_163731`
  - Word COM exported an 82-page PDF.
  - All 82 pages rendered to PNG; only page 2 was low-content, consistent with the template blank/separator page.
  - PDF text checks found no `引用源未找到`, `错误!`, `错误！未定义书签`, `Error!`, `${`, or `{{`.
  - Report text now states main girder strain range `-60.3με~152.3με` and tower strain range `-148.9με~127.2με`.

## 2026-07-06 Hongtang Q2 v1.7.19 Final Closure

Current repository release target:

- MATLAB GUI version in `ui/run_gui.m`: `v1.7.19`
- Report GUI version in `reporting/report_gui.py`: `v1.7.19`
- Latest accepted code state: `bf43de2` (`Preserve caption bookmarks during auto-number conversion`), clean on local `main` and 133 `F:\Guanbing`.

Final fixes after the earlier v1.7.18 report correction:

- `SG-6` and `SL-8` no longer use the legacy inverted-threshold all-data suppression workaround for Q2. They are restored to normal transitional cleaning bounds `[-1000, 1000]` because the points show usable Q2 data again.
- Hongtang low-frequency `abs_max_valid` is sensor-specific, and strain skips that raw absolute-value guard. This prevents raw `SG-6` values around 1200 from being removed before `offset_correction = -1220` brings them back into range.
- Hongtang low-frequency cache is raw-only:
  - cache files use `__raw_v3.mat`;
  - cache metadata hashes only raw parse settings, not filtering thresholds;
  - cleaning/filtering is applied after reading cache so changing thresholds does not require regenerating raw cache.
- The report generator now accepts bearing-displacement raw image names ending in both `*_Orig.jpg` and `*_Orig_*.jpg`, matching the Q2 production filenames.
- Static period-report figure/table captions are converted to Word auto-number fields while preserving caption bookmarks. This prevents template cross-references such as the bridge-tower strain paragraph from becoming `错误！未定义书签` after Word field updates.

133 final production state:

- 133 code was fast-forwarded to `bf43de2`, and focused report tests passed:
  `D:\Python310\python.exe -m unittest tests_py.test_wim_auto_captions tests_py.test_artifact_lookup tests_py.test_build_period_report_word_update`
- Final report generation task:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1719_report_final_20260706_155715`
  - Runtime: `89.31` seconds.
  - Output DOCX:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_155749.docx`
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_155749.json`
  - Manifest check: `missing_entries=0`, bearing-displacement missing paths `0`.
  - DOCX check: `_Ref4508` and `_Ref4616` are present; `SEQ 图` count `37`, `SEQ 表` count `21`.
- Final local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\hongtang_q2_v1719_final_20260706_155749`
  - Word COM exported an 82-page PDF:
    `hongtang_q2_report.pdf`.
  - Rendered all 82 pages to PNG; only page 2 was low-content, consistent with the template blank/separator page.
  - PDF text checks found no `引用源未找到`, `错误!`, `错误！未定义书签`, `Error!`, `${`, or `{{`.
  - Page 37 bridge-tower strain text now reads correctly: `如图 4-6 所示，箱线图如图 4-7 所示。`

## 2026-07-06 Hongtang Q2 Report Correction Snapshot

Current repository release target:

- MATLAB GUI version in `ui/run_gui.m`: `v1.7.18`
- Report GUI version in `reporting/report_gui.py`: `v1.7.18`
- This release follows `v1.7.17` and keeps the wind/earthquake timestamp
  fallback and MAT-only source behavior from the previous release line.

Code/report changes in this release:

- `config/hongtang_config.json` applies the user-specified Q2 zero-point
  corrections:
  - `SG-6` strain `offset_correction = -1220`
  - `Z11-2` bearing displacement `offset_correction = 250`
- Bearing-displacement output is now split by source variant in the shared
  structural pipeline:
  - single raw: `时程曲线_支座位移_原始`
  - single filtered: `时程曲线_支座位移_滤波`
  - group raw: `时程曲线_支座位移_组图_原始`
  - group filtered: `时程曲线_支座位移_组图_滤波`
- The Hongtang period-report bearing section now reads report figures from the
  raw bearing-displacement output folder, matching the accepted first-quarter
  report's raw time-history-with-warning-lines presentation.
- WIM period-report table/figure captions are generated with Word field codes:
  `STYLEREF 1` + `SEQ 表/图`; continuation table captions use `SEQ 表 \c`.
- WIM table 4-1 now describes the last column as explicit overload counts for
  `1.5/2.0` times thresholds, e.g. `总重1.5/2.0倍：34/0`.
- `reporting/build_period_report.py` accepts per-point file-pattern lists when
  collecting high-frequency missing-data evidence, fixing a report-generator
  crash found during local smoke testing.

Local validation before 133 sync:

- JSON validation passed:
  `python -m json.tool config/hongtang_config.json`
- Python compile passed:
  `C:\Users\eamdf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe -m compileall -q reporting tests_py`
- Python unit smoke passed:
  `C:\Users\eamdf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe -m unittest tests_py.test_wim_auto_captions`
- MATLAB focused tests passed:
  `matlab -batch "addpath(genpath(pwd)); results = runtests({'tests/test_structural_time_series_plot_service.m','tests/test_jlj_adapter.m','tests/test_offset_correction.m'}); assertSuccess(results);"`
- Q1 report-generator smoke passed with `BMS_NO_WORD=1` using
  `E:\洪塘大桥数据\2026年1-3月`; it intentionally reported missing bearing
  figures because the old Q1 result folder does not have the new `_原始`
  bearing-displacement directories.
- Latest Q1 smoke output checked:
  `tmp\report_smoke_wim_autocaption\洪塘大桥健康监测2026年1-3月周期报_20260706_121351.docx`
  contains WIM `SEQ 表/图` fields and a clean table 4-1 overload-count header.

Accepted 133 production state:

- 133 `F:\Guanbing` was fast-forwarded to `82fa278` / `v1.7.18`, clean against
  `origin/main`.
- Remote focused tests passed with 133 runtimes:
  - `D:\Python310\python.exe -m unittest tests_py.test_wim_auto_captions tests_py.test_build_period_report_word_update`
  - MATLAB focused tests for structural plotting, offset correction, and GUI
    version smoke.
- Affected Hongtang Q2 low-frequency modules were rerun on 133:
  `strain` and `bearing_displacement`.
  - Run directory:
    `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_v1718_strain_bearing_20260706_123551`
  - MATLAB exit code: `0`
  - Runtime: about `171.49` seconds inside MATLAB.
  - Updated stats:
    `E:\洪塘大桥数据\2026年4-6月\stats\strain_stats.xlsx` and
    `E:\洪塘大桥数据\2026年4-6月\stats\bearing_displacement_stats.xlsx`.
  - Offset report:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\offset_correction_applied_20260706_123706.xlsx`
    confirmed `Z11-2 = 250` on `2184` rows and `SG-6 = -1220` on `6552`
    rows.
  - New single-point bearing-displacement output folders each contain `10`
    JPG and `10` EMF files:
    `时程曲线_支座位移_原始` and `时程曲线_支座位移_滤波`.
    Hongtang has no bearing-displacement groups configured, so group folders
    are not generated for this bridge.
- Final 133 Q2 report:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\洪塘大桥健康监测2026年4-6月周期报_20260706_124340.docx`
- Report manifest:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\period_report_manifest_20260706_124340.json`
  with `status=ok`, `missing_count=0`, `warnings=[]`, and report QC `ok`.
- Report build runtime: `104.32` seconds, below the 10-minute failure threshold.
- Local QA copied the report bundle to
  `D:\MatlabProjects\Guanbing\run_logs\remote_tasks\hongtang_q2_v1718_report_20260706_1242\bundle_from_133`.
  Word COM rendered an 82-page PDF:
  `D:\MatlabProjects\Guanbing\run_logs\remote_tasks\hongtang_q2_v1718_report_20260706_1242\word_render_timeout\hongtang_q2_report_20260706_124340_word_full.pdf`.
  Text and visual checks found no `错误`, `引用源未找到`, stale Q1 date text, or
  missing placeholders. Table 4-1, bearing displacement raw plots, wind, wind
  rose, and earthquake pages were visually spot-checked.
- The checked PDF was copied back to 133:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_124340_word_checked.pdf`.

## 2026-07-06 Hongtang Q2 Late-June Patch Snapshot

Current repository release target:

- MATLAB GUI version in `ui/run_gui.m`: `v1.7.17`
- Report GUI version in `reporting/report_gui.py`: `v1.7.17`
- This release follows `v1.7.15` and keeps the MAT-only time-series source
  behavior from that release.

Accepted 133 production state:

- Only Hongtang Q2 dates `2026-06-28` to `2026-06-30` were supplemented from
  the recovered Donghua exports.
- Source patch manifest:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_donghua_patch_20260706_061724\patch_manifest.json`
- High-frequency refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_patch_refresh_20260706_063728`
  with main manifest
  `E:\洪塘大桥数据\2026年4-6月\run_logs\analysis_manifest_20260706_082618.json`.
- RMS refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_patch_rms_refresh_20260706_083341`
  with acceleration `12/12`, cable acceleration `24/24`, and no skipped
  points.
- Final checked report:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_090831_checked.docx`
- Final checked Word-exported PDF:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_090831_checked.pdf`
- Report build runtime: `146.629` seconds, below the 10-minute failure
  threshold.
- Local render QA copied the report bundle to
  `D:\MatlabProjects\Guanbing\tmp\docs\hongtang_q2_patch_report_20260706_090700`,
  rendered the Word-exported PDF to `79` PNG pages, and found no `错误`,
  `引用源未找到`, stale Q1 date text, old `共 63 页` header text, or mojibake
  error/reference text.

Report generator fix in this release:

- `reporting/build_period_report.py` now parses the page count emitted by Word
  COM, updates header/footer shape fields, and patches hard-coded total-page
  text in header/footer XML when the Word template stores the total page count
  in a text box.
- Remote 133 unit smoke passed with `D:\Python310\python.exe -m unittest
  tests_py.test_build_period_report_word_update`.
- Local Python smoke passed:
  `C:\Users\eamdf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe -m unittest tests_py.test_build_period_report_word_update tests_py.test_report_qc tests_py.test_analysis_manifest`.

MAT-only follow-up for the supplemented dates:

- Canonical MAT caches were added for wind speed/direction and earthquake
  channels that were not produced by the original timestamp-cache path:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_patch_canonical_cache_20260706_092000`.
- MAT-only smoke passed before and after deleting direct wave CSV files for
  `W1`, `W2`, `EQ-X`, `EQ-Y`, `EQ-Z`, `A1`, `CS1`, and `CX3`.
- Deleted only direct `波形\*.csv` files for `2026-06-28` to `2026-06-30`:
  `417` files / `37,572,244,652` bytes. Feature CSV files were retained.
- 126 automatic Donghua export check after the point-name fix:
  `H:\DHtest\定时导出\2026-07-06` had one wave zip and one eigen zip at
  2026-07-06 09:32 CST, both readable, both with `139` entries, and both
  including `CX3` plus wind speed/direction entries.
- MATLAB GUI smoke passed after the version bump:
  `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); results = runtests({'tests/test_main_gui_smoke.m'}); assertSuccess(results);"`

Follow-up correction on 2026-07-06:

- User review found that the report's wind and earthquake figures still ended
  around 2026-06-27 even though the recovered late-June source data existed.
- Root cause: the recovered Donghua waveform CSVs for wind and earthquake used
  timestamp names such as `风速_20260705224253038.csv`,
  `塔顶风速_20260705224400015.csv`, and `X_20260705224156737.csv`. Hongtang
  config only matched exact IDs such as `风速_162.csv` and `X_144.csv`, so the
  06:42-06:44 wind/earthquake plots were generated before the canonical MAT
  aliases existed.
- `config/hongtang_config.json` now keeps exact `{file_id}.csv` matching first
  and adds per-point timestamp fallback patterns for W1/W2 wind speed/direction
  and EQ-X/Y/Z.
- `tests/test_time_series_loader.m` covers the timestamp fallback for tower wind
  speed and EQ-X.
- 133 wind/earthquake refresh:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_wind_eq_refresh_20260706_0945`
  refreshed wind in `151.37` seconds and earthquake in `68.04` seconds.
- New figure-axis check showed W1/W2 speed/direction end at
  `2026-06-30 09:00:02`, W1/W2 10-minute wind figures end at
  `2026-06-30 23:55`, and EQ-X/Y/Z end at `2026-06-30 09:00:05`.
- Corrected checked report:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_105133_wind_eq_checked.docx`
- Corrected checked PDF:
  `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260706_105133_wind_eq_checked.pdf`
- Local render QA bundle:
  `D:\MatlabProjects\Guanbing\tmp\docs\hongtang_q2_report_wind_eq_fix_20260706_1050`.
  DOCX QC passed; PDF text check found no `错误`, `引用源未找到`, old `共 63 页`,
  or stale Q1 date text. Visual check of rendered pages 76-80 confirmed wind
  and earthquake plots now reach 2026-06-30.

## 2026-07-05 MAT-only Time-series Source Snapshot

Current working release target after the Hongtang Q2 recovery line:

- MATLAB GUI version in `ui/run_gui.m`: `v1.7.15`
- Report GUI version in `reporting/report_gui.py`: unchanged at `v1.7.14`

Accepted design for large high-frequency datasets:

- `bms.data.TimeSeriesLoader` now supports automatic time-series source
  selection:
  - `auto`: use CSV plus validated MAT cache when CSV exists; if the CSV has
    been archived, fall back to a matching `cache\*.mat`.
  - `csv_cache`: legacy CSV-only discovery.
  - `prefer_mat`: MAT first, CSV fallback.
  - `mat_only`: MAT-only discovery.
- `config/hongtang_config.json` sets
  `data_adapter.time_series.source_mode=auto`.
- Hongtang Q1 has older MAT caches without `*.meta.json`, so Hongtang currently
  sets `data_adapter.time_series.require_metadata=false`. New caches still
  write metadata and should keep the metadata files.
- File fallback matching now uses point-name boundaries, avoiding mistakes such
  as matching `A1` to `A10` or `CS1` to `CS10`.
- `bms.data.DataIndex` can discover MAT cache sources, including Hongtang
  dated folders under period roots.
- Durable operating note: `docs/mat_only_timeseries_source.md`.

Latest local and remote validation:

- `git diff --check`: passed with only line-ending warnings.
- MATLAB:
  `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); results = runtests({'tests/test_time_series_loader.m','tests/test_load_timeseries_range.m','tests/test_run_preflight.m'}); assertSuccess(results);"`
  -> passed.
- MATLAB:
  `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); results = runtests({'tests/test_dynamic_series_service.m','tests/test_bms_services.m'}); assertSuccess(results);"`
  -> passed.
- Real Hongtang Q1 smoke on local data:
  `E:\洪塘大桥数据\2026年1-3月\2026-01-01\波形\cache\CS1_148.mat`
  was read through `load_timeseries_range`, and
  `bms.analyzer.DynamicSeriesService.collectRecord` produced valid RMS output.
- 133 validation ran after fast-forwarding to code commit `c77ba32` and fetching
  tag `v1.7.15`.
- 133 focused MATLAB test passed:
  `tests/test_time_series_loader.m`.
- 133 real Hongtang Q1 MAT-only smoke passed for:
  `E:\洪塘大桥数据\2026年1-3月\2026-01-01\波形\cache\CS1_148.mat`.
- 133 real Hongtang Q2 CSV + cache smoke passed for:
  `E:\洪塘大桥数据\2026年4-6月\2026-04-01\波形\CS1_148.csv`.
- After a stricter MAT-only validation on 133, Hongtang Q2 active dated
  waveform folders were converted to MAT-only operation:
  - run directory:
    `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_mat_only_delete_20260705_133553`
  - direct raw CSV files deleted:
    `E:\洪塘大桥数据\2026年4-6月\20??-??-??\波形\*.csv`
    -> `9,675` files / `853,816,533,340` bytes.
  - final direct wave CSV count: `0`.
  - remaining dated wave MAT caches: `3,662` files / `37,899,893,177` bytes.
  - validation before deletion: configured non-empty CSV-backed sources
    `3,662`, MAT ok `3,662`, missing MAT `0`, bad MAT `0`; `36` configured
    source CSVs were 2-byte empty placeholders.
  - post-delete MAT-only smoke passed for `CS1`, `A1`, and `W1`.

## 2026-07-05 Latest Engineering Snapshot

This is the current release point for the Hongtang Q2 recovery and report
generation hardening work.

Current repository:

- Root: `D:\MatlabProjects\Guanbing`
- Branch: `main`
- Latest baseline before this snapshot: `308dea7 Document Hongtang Q2 recovery`
- MATLAB GUI version in `ui/run_gui.m`: `v1.7.14`
- Report GUI version in `reporting/report_gui.py`: `v1.7.14`

Accepted local changes in this snapshot:

- Fixed Hongtang Q2 dated-folder high-frequency loading so period roots such as
  `E:\洪塘大桥数据\2026年4-6月\<YYYY-MM-DD>\波形` are preferred over stale or
  misleading wrapper folders.
- Tightened time-series cache matching and removed the bad CS8 offset rule in
  `config/hongtang_config.json`.
- Propagated `plot_common.gap_mode=connect` through the common plot services and
  module plotters. Explicit `break` remains supported; `connect` only connects
  existing finite points and does not synthesize missing raw dates.
- Reduced high-frequency memory pressure by collecting acceleration,
  cable-acceleration, earthquake and wind records by day, downsampling plot
  series, and aggregating RMS/10-minute wind curves by time bin.
- Added `scripts/refresh_dynamic_rms_only.m` for targeted RMS refreshes after
  loader/RMS fixes without rerunning the whole production pipeline.
- Hardened Hongtang period-report generation:
  - `reporting/build_period_report.py` now falls back from missing Python COM
    (`pythoncom/win32com`) to PowerShell Word COM for field/TOC/cross-reference
    updates.
  - field-update failures are returned as manifest warnings instead of being
    silently ignored.
  - final acceptance should include a rendered/exported report check, not only
    raw DOCX QC.
- Added focused tests for dated-folder loading, gap-mode propagation, dynamic
  RMS aggregation, analysis-manifest warnings, and report-field update fallback.
- Added `docs/hongtang_q2_2026_recovery.md` as the durable runbook for this
  recovery.

Remote Hongtang Q2 verification on `192.168.100.133`:

- Data root: `E:\洪塘大桥数据\2026年4-6月`
- Full run directory:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_full_20260705_022000`
- RMS refresh run directory:
  `F:\Guanbing\run_logs\remote_tasks\hongtang_q2_rms_refresh_20260705_102937`
- RMS refresh result: `acceleration 12/12`, `cable_accel 24/24`, no skipped
  points.
- Report generator runtime for the final Q2 build was about `80` seconds.
- Final checked report copied back to 133:
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260705_105401_checked.docx`
  - `E:\洪塘大桥数据\2026年4-6月\自动报告\hongtang_q2_report_20260705_105401_checked.pdf`
- Local render QA produced `110` PNG pages and found no
  `错误` / `引用源未找到` / stale Q1 date / old `共 63 页` text in the rendered
  report.

Latest validation before release:

- Python:
  `C:\Users\eamdf\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe -m unittest tests_py.test_build_period_report_word_update tests_py.test_report_qc tests_py.test_analysis_manifest`
  -> `10` tests passed.
- MATLAB:
  `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); issues = checkcode('scripts/refresh_dynamic_rms_only.m'); disp(numel(issues)); results = runtests({'tests/test_dynamic_series_service.m','tests/test_bms_services.m'}); assertSuccess(results);"`
  -> `checkcode=0`, focused tests passed.
- 133:
  `D:\Python310\python.exe -m unittest tests_py.test_build_period_report_word_update`
  -> passed, and a real Word COM smoke test returned `WORD_UPDATE_WARNINGS=[]`.

Known residual data caveat:

- Some late-June and individual high-frequency source gaps remain real raw-data
  availability issues. The plotting fixes prevent false gaps and stale-cache
  mistakes, but they do not invent absent source files.

## 2026-07-04 Engineering Snapshot

This is the current recovery point for the Donghua export compatibility,
Hongtang Q2 recovery, GUI/path-profile visibility, and remote production-state
cleanup work.

Current repository:

- Root: `D:\MatlabProjects\Guanbing`
- Branch: `main`
- Latest baseline before this snapshot: `ede75d6 Document 133 code sync status`
- MATLAB GUI version in `ui/run_gui.m`: `v1.7.13`
- Report GUI version in `reporting/report_gui.py`: unchanged from the previous report-generator release.

Accepted local changes in this snapshot:

- Added Hongtang Q2 low-frequency sync support:
  - `+bms/+data/JikangClient.m`
  - `+bms/+data/HongtangLowFreqSyncService.m`
  - module key `lowfreq_sync`, GUI option `doLowfreqSync`, preset field
    `lowfreq_sync`
  - output remains the single workbook `lowfreq\data.xlsx`; credentials must
    come from environment variables or ignored `config/jikang_credentials.local.json`.
  - WIM/称重 remains on the existing SQL pipeline; do not SQL-ify lowfreq.
- Set shared plotting default `plot_common.gap_mode` to `connect`; explicit
  `break` remains supported when a config requests it.
- Hongtang profile now defaults the low-frequency sync module on.
- Hongtang lowfreq sync was hardened after live testing:
  - fixed Jikang parameter selection to prefer physical `paraType=1` over
    frequency/electrical channels;
  - fixed request-error sanitization so credential query values are masked;
  - pinned Hongtang Jikang device IDs in config to avoid an extra project-device
    list call.
- Added `+bms/+data/DonghuaExportNormalizer.m`.
  - Supports Donghua's older direct `日期\波形\*.csv` layout and the newer
    nested `日期\波形\GUID\*.csv` / `日期\特征值\GUID\*.csv` layout.
  - Moves missing nested CSV files up to the legacy direct folder before the
    existing preprocessing scripts run, so only one raw CSV copy is kept.
  - Canonicalizes `_原始数据...` and known mojibake variants; identical nested
    duplicates are deleted and different-content conflicts are left for review.
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
- `tests/test_hongtang_lowfreq_sync_service.m`

Latest local test evidence before committing this snapshot:

- `git diff --check`: passed, only line-ending warnings.
- Focused Hongtang/GUI/config tests passed on 2026-07-04:
  `tests/test_hongtang_lowfreq_sync_service.m`,
  `tests/test_step_factory_split.m`, `tests/test_main_gui_smoke.m`,
  `tests/test_config_migrator.m` plus script
  `tests/test_prepare_plot_series_gap_mode.m`.
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

Remote Hongtang Q2 layout normalization on `192.168.100.133`:

- Data root: `E:\洪塘大桥数据\2026年4-6月`
- Moved misleading wrapper layout `波形\<YYYY-MM-DD>\波形` up to standard
  `<YYYY-MM-DD>\波形` in place, without duplicating raw CSV data.
- Move run directory:
  `E:\洪塘大桥数据\2026年4-6月\run_logs\layout_move_20260704_175616`
- Verification: moved `89` date folders; CSV total stayed `9675` before/after;
  wrapper `波形` folder no longer exists. Source data is still incomplete for
  `2026-04-02`, `2026-06-19`, and late June has reduced CSV counts.
- Lowfreq workbook generated on 133:
  `E:\洪塘大桥数据\2026年4-6月\lowfreq\data.xlsx`
  - Manifest:
    `E:\洪塘大桥数据\2026年4-6月\run_logs\hongtang_lowfreq_sync_20260704_183004.json`
  - Q2 rows: `2184`; columns: `79`; mapped lowfreq columns: `78`.
  - Filled Q2 value cells: `90033`; missing Q2 value cells: `80319`.
  - Jikang samples fetched: `140214`; duplicate samples dropped: `11039`.
  - Workbook time range after template+append: `2022-07-28 12:00:00` to
    `2026-06-30 23:00:00`.

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

## 2026-07-08 Zhishan April Cleanup And Report Regeneration

- Target production machine/data root:
  `133:F:\芝山大桥数据\2026年4月`.
- Final generated report on 133:
  `F:\芝山大桥数据\2026年4月\自动报告\芝山大桥健康监测2026年4月份月报_自动生成_20260708_133148.docx`.
- Local QA copy:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_report_20260708_133148\zhishan_202604_report_20260708_133148.docx`.
- Local render QA output:
  `D:\MatlabProjects\Guanbing\run_logs\remote_artifacts\zhishan_report_20260708_133148\rendered`.
- Source-data note: the April data root has no `2026-04-02` dated source
  folder. Cable force spectrum sheets therefore show that date blank; this is
  a source-data gap, not a cleaning/report bug.
- April-specific cleaning policy now in `config/zhishan_config.json`:
  - `bearing_displacement / DX-1~DX-4`: clean outside `[-80, 80]` mm for
    `2026-04-01` to `2026-04-30`, preserving March `[-100, 100]`.
  - `strain / SX-1~SX-10`: clean outside the confirmed level-2 groups:
    `SX-1/2/9/10=[-283,414]`, `SX-3/4/7/8=[-218,298]`,
    `SX-5/6=[-252,405]`.
  - `dynamic_strain` and `dynamic_strain_lowpass`: added April
    `post_filter_thresholds` with the same level-2 bounds so high/low-pass
    derived report figures and stats are also cleaned.
  - `cable_accel / CF-1~CF-8`: April fixed offsets
    `CF-1=-2000`, `CF-2=-2000`, `CF-3=29000`, `CF-4=29000`, `CF-5=29000`,
    `CF-6=-200`, `CF-7=-1500`, `CF-8=2000`, then clean outside
    `[-3000, 3000]`.
  - `cable_accel` plot style now uses auto y-limits for all CF points.
- Code fixes made during this run:
  - `+bms/+data/CleaningPipeline.m`: supports date-scoped fixed
    `offset_correction` rules.
  - `pipeline/resolve_post_filter_thresholds.m`: accepts JSON-loaded
    cell-of-struct post-filter rules and normalizes missing `min/max` fields.
  - `reporting/build_zhishan_monthly_report.py`: normalizes visible
    `图/表 n-m` captions to plain text to remove stale Word REF fields that
    render as `错误：引用源未找到`.
- Remote rerun evidence:
  - Main April cleanup run:
    `F:\Guanbing\run_logs\remote_tasks\zhishan_202604_april_clean_20260708_121250`.
  - Dynamic strain high/low-pass refresh:
    `F:\Guanbing\run_logs\remote_tasks\zhishan_dynamic_20260708_131627`,
    final status `complete/ok`.
- Remote validation:
  - `bearing_displacement_stats.xlsx`: all original/filter min/max within
    `[-80,80]`.
  - `strain_stats.xlsx`: all SX min/max within their level-2 groups.
  - `dynamic_strain_highpass_stats.xlsx` and
    `dynamic_strain_lowpass_stats.xlsx`: all sheets/groups within their
    level-2 groups; low-pass `SX-5/SX-6` max now caps at `405.0/398.0`.
  - `cable_accel_stats.xlsx`: all CF min/max within `[-3000,3000]`.
  - CF offset report:
    `F:\芝山大桥数据\2026年4月\run_logs\offset_correction_applied_20260708_121344.xlsx`.
- Report QA:
  - Report builder runtime about `14` seconds for the final build.
  - Manifest `status=ok`, `missing_count=0`, `warnings=[]`.
  - DOCX text QA found no `引用源未找到`, `错误`, `未定义书签`, `Error!`,
    leftover template tokens, or common mojibake.
  - Rendered `47` PNG pages locally; spot-checked DX, dynamic strain
    high/low-pass, and CF pages. The earlier stale caption-field error was
    fixed in the final render.
- Local/remote tests passed:
  - `matlab -batch "cd('D:\MatlabProjects\Guanbing'); addpath(genpath(pwd)); results = runtests({'tests/test_cleaning_pipeline.m','tests/test_post_filter_thresholds.m','tests/test_zhishan_config.m'}); assertSuccess(results);"`
  - `python tests\test_zhishan_report_assets.py`
  - Same focused MATLAB config/post-filter tests passed on 133.

## Context-Compression Recovery Rule

If a Codex conversation stalls on automatic context compaction for more than 5 to 10 minutes, stop waiting. Terminate/restart Codex and open a new thread.

New thread startup prompt:

```text
Please read D:\MatlabProjects\Guanbing\docs\current_task_state.md, git status/diff, recent commits, and relevant output files, then continue the Zhishan Bridge data processing task.
```

Avoid uploading old screenshots/images into the continuation thread unless they are essential.

## 2026-07-16 v1.8.1-rc4 Archive-Backed Cache Cleanup Batch

- Branch: `codex/jiulongjiang-cache-prebuild`; do not merge `main` yet.
- Candidate feature: optional verified deletion of extracted CSV after daily
  cache prebuild for `jlj_daily_export` (Jiulongjiang and Shuixianhua). It is
  default-off, requires `DELETE_VERIFIED_EXTRACTED_CSV`, and only runs in a
  dedicated preprocessing task.
- Transaction boundary is one natural day: extract, build/reuse every active
  configured cache source, independently load/validate MAT+meta, prove recovery
  from the unchanged ZIP and extraction manifest including CRC, write a durable
  receipt, then same-volume stage/delete only eligible CSVs. ZIP, WIM, Excel,
  unconfigured CSV, cache and evidence are retained.
- Source request discovery is shared by cache prebuild and cleanup. Split wind
  speed/direction files and crack-temperature companions are therefore both
  covered, and nonstandard contains-fallback filenames remain reusable after a
  committed cleanup.
- Local release gates passed: focused MATLAB `70/70`, full MATLAB `711/711`,
  full Python `608/608`, compiled Runner default-off/unsafe/enabled cleanup
  scenarios, native Windows icon/font/DPI/focus screenshots and package gate.
- Candidate ZIP:
  `release\workbench\BridgeMonitoringWorkbench-v1.8.1-rc4-win-x64.zip`,
  SHA256 `721BE6B6512805B83D7FEB23358BE8E7980BC6188E55FE8D36AF2A952254714D`.
- 133 remains isolated: stable `F:\Guanbing` and E-drive source ZIPs are
  read-only; candidate writes are limited to `F:\Guanbing_v1.8.1-rc1`.
- Current remote job is Jiulongjiang May rc3 MAT-only analysis. At 03:23 it was
  on module 13/15 `cable_accel`, SLCGQ-08/15, stderr empty; estimated remaining
  time was 35–55 minutes. Some cable-acceleration rolling exports for May 1–8
  report incomplete source coverage and must be disclosed after provenance
  verification.
- Next order: validate/report Jiulongjiang May; deploy rc4 only to the isolated
  candidate tree and clean May extracted CSVs; process Shuixianhua June with
  daily extract/cache/proof/cleanup then separate 13-module MAT-only analysis
  and report; process Jiulongjiang June only after all 30 ZIPs are stable and
  openable.
- Shuixianhua June source preflight: 30/30 ZIPs openable; June 14/15/16 have
  materially shorter coverage and must be disclosed.
- Jiulongjiang June is blocked by source state: only June 1–18 exist, June 18
  lacks a valid EOCD, and June 19–30 are absent. Do not start until the 30/30
  two-poll stability and ZIP-openability gate passes.
