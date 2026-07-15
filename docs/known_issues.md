# Known Issues And Follow-Up Items

Last updated: 2026-07-15

This file tracks recoverable technical risks that are too important to leave in
chat history but not always urgent enough to fix immediately.

## v1.8.1-rc1 Daily ZIP Extraction And Cache-Prebuild Boundaries

Status: implementation and local regression are complete. The full
Jiulongjiang May W4 cache run on 133 completed with `created=3764`,
`reused=1561`, `eligible=5325`, `failed=0` in `6h50m27s`; cache size was
`57.50 GiB` and F: free space was `539.33 GiB`. Strict pair acceptance, the
zero-write reuse repeat, 15-module analysis and May report review remain open,
so this result does not authorize a stable production upgrade by itself.

- “预生成分析缓存” is an optional capability for all installed bridge
  profiles and remains unchecked by default. `jlj_daily_export` uses the
  dedicated multi-channel `jlj_csv_v2` backend; `dated_folders` and
  `hongtang_period` use the standard two-column `csv_timeseries_v2` backend.
  Do not bypass the layout dispatcher or treat one cache schema as the other.
- The standard backend is configuration-scoped, not a recursive CSV converter:
  it caches only files resolved from configured analysis modules/points,
  including both wind channels and an enabled crack-temperature companion.
  WIM, Hongtang low-frequency Excel, ZIP, unconfigured CSV and non-CSV sources
  remain excluded. A newly introduced sensor family with extra companion files
  must add an explicit discovery contract and regression before it can claim
  complete pre-generation coverage.
- ZIP archives are read-only inputs. Automatic deletion is forbidden, and an
  existing output directory without a matching verified extraction manifest
  cannot be overwritten by the safe default. Production trials should use a
  separate output root.
- The extraction and cache-prebuild space checks are startup budgets, not a
  substitute for monitoring free space during long runs. Do not lower the
  configured reserve merely to force a run through.
- A verified daily extraction remains reusable after derived `cache` files are
  created. Reuse still checks every ZIP-declared relative path and byte count;
  any missing or changed archive entry fails closed.
- `preprocessing.unzip.summary_file` is a path, not only a filename. An
  absolute value is used unchanged; a relative value is resolved under the
  extraction `output_root`. Rejoining an absolute summary path to the output
  root is a fixed regression and must remain covered by tests.
- In the `jlj_daily_export` backend, only files explicitly classified as
  DTCZ/WIM may be skipped. Unknown or damaged time-series CSV files are errors,
  and an all-WIM/no-eligible input must not report success. The standard backend
  does not inspect unconfigured files at all; a configured CSV that cannot
  produce a valid two-column MAT/meta pair fails that cache run.
- New MAT and metadata files form one transaction: both carry the same
  `pair_id`, metadata records the exact `mat_bytes`, and a failed publish rolls
  the previous pair back. Older pairless `jlj_csv_v2` caches remain readable
  for compatibility, but they cannot count as proof that the new transaction
  protocol was exercised.
- A transaction validation run should use `force_rebuild=true`; its immediate
  repeat must use `force_rebuild=false` and reuse every eligible cache without
  writing another pair.
- Cache prebuild now uses a whole-run lock, per-target locks and target-level
  transaction directories. Same-host locks whose recorded PID is no longer
  alive are recoverable, and MAT-only/meta-only half-pairs are repaired on the
  next run. Continue to test hard interruption at the boundary between MAT and
  metadata publication; do not delete locks or transaction directories by hand
  while a recorded process is still alive.
- This is a prerelease candidate. Stable clients do not automatically update to
  it, and `F:\Guanbing` must remain untouched until the isolated full-period
  analysis and report regression are accepted.

## v1.8.1-rc2 Local Operator-Control And Coverage Boundary

Status: rc3 now supersedes the earlier rc2 candidate and has passed complete
source regression, compiled-package and native-GUI checks. It remains
intentionally undeployed to machine 133 while the isolated Jiulongjiang
acceptance sequence is incomplete.

- Configurable extraction concurrency is available only for future runs. A
  running extraction/cache task keeps the worker count captured in its request;
  never mutate or restart it merely to adopt the new setting.
- `auto` resolves conservatively and records the requested, resolved and
  effective worker counts plus any serial fallback reason. Parallel speed-up is
  workload and storage dependent; the safety and disk gates remain authoritative.
- One-sided manual threshold editing changes exactly one bound for the selected
  module and point. Preview and drag interaction are advisory until the operator
  confirms; cancel and window close must leave the configuration unchanged.
- Zero-offset effective ranges have second precision. A legacy date-only end
  includes that whole day, while an explicit `00:00:00` end means midnight
  exactly. Keep both interpretations covered by boundary tests.
- Gap rendering inherits by field from point to module to compatible legacy
  settings and finally the global default. It affects plotting continuity only;
  it must not change samples, cleaning, statistics or report conclusions.
- Coverage is now measured at line/statement, branch/decision and condition
  levels, but remains one layer of evidence. Word automation, native GUI behavior,
  real bridge data and rendered reports still require their own acceptance gates.
- The last compiled rc2 package predates the cache recovery, MAT-only RMS guard,
  strict report artifact/template/output checks and GUI child-process lifecycle
  fixes. Treat that ZIP/EXE as stale until a new build passes the complete
  package and native-GUI smoke matrix.
- A failed analysis/report spawn or an unexpectedly exited child must leave a
  durable `launch_failed` status; it must not inherit an old success/result
  file. Strict report jobs must recheck pinned artifact bytes/SHA256, preflight
  the selected template and reject missing or outside-output builder results.
- Stop requests and status polling are now a tested state machine: an analysis
  stays `stopping` while its worker is alive and converges to `stopped` after
  exit; a report is only labelled stopped after its exact recorded root process
  is confirmed gone. MATLAB status JSON, Python job contexts and report terminal
  files use atomic same-directory replacement so a polling GUI cannot observe a
  half document and enable a duplicate start. Preserve these stop-then-poll and
  transient-read regressions in future GUI refactors.
- Avoid a large one-time architecture rewrite. Continue extracting shared module
  catalogs, path/profile models and safety planners in small contract-preserving
  steps after the Jiulongjiang rc1 production validation is closed.

## v1.8.1-rc3 Local Review Boundary

Status: confirmed source defects are fixed. The complete Python suite ran `582`
tests successfully (`581` passed, `1` conditionally skipped), and MATLAB passed
`673/673` with no failure or incomplete test. The final rebuilt rc3 workbench
passed native foreground, keyboard focus and icon ownership at 120 DPI with
per-monitor awareness and a 2018 x 1122 physical window. The `384/384` file
inventory and formal release archive gate passed; rc3 is not deployed to
machine 133.

- ZIP safety now assumes an immutable snapshot from planning through atomic
  publication and verifies that assumption. Keep the same-path/same-length
  replacement regression; never weaken it to path and uncompressed bytes only.
- Extraction lock recovery is opt-in. Same-host live PIDs must never be
  reclaimed by age, malformed/foreign owners remain protected until the stale
  threshold, and cleanup only removes a matching UUID token.
- Qt-offscreen screenshots remain useful for an occupied desktop but cannot
  replace native evidence. The final rebuilt EXE has passed native foreground,
  focus, icon and per-monitor DPI checks, and its own evidence is embedded in
  the release manifest; an older EXE's evidence still cannot certify a new
  archive.
- Packaging recomputes every inventoried file hash before compression. Do not
  add a fast path that trusts an earlier manifest after files may have changed.
- Strict report provenance requires both byte count and SHA-256. Missing hashes
  are an error, not a compatibility warning, for formally pinned artifacts.
- Report stop currently guarantees only that the exact recorded report worker
  root process exits. It does not prove that Word, LibreOffice or COM descendants
  have all exited. Before reusing an affected output/data root, inspect known
  descendant PIDs/identities read-only; do not fall back to PID-unsafe
  `taskkill /T`. A true tree-level guarantee requires a Windows Job Object or
  cooperative child-process supervision in a later architecture change.

## Hongtang Q2 Supplement Coverage And Review Items

Status: June 28-30 supplement recalculated and disclosed; two data-quality
items still require engineering review.

- W1/W2 have an actual June 29 gap from `08:46:26.532` to `09:48:30.684`
  (3,724.152 seconds). The adjacent July 1 rolling export is also absent, so
  the June 30 high-frequency tail after about 09:00 cannot be reconstructed.
  Reports must disclose both facts and must not present June 30 as a complete
  natural day.
- The maximum cable-acceleration 10-minute RMS is CS8 `2.468 m/s2` at
  `2026-06-22 10:05`. This exceeds the stated `1000 mm/s2 (1.000 m/s2)`
  first-level threshold. The software no longer labels this result “below
  threshold” or infers that no alarm occurred; the original time history and
  system alarm record require operator review.
- CS10 contains one isolated `-15.268 m/s2` sample at
  `2026-05-27 19:01:55.786` among 145,474,555 samples. Current CS10 cleaning
  is intentionally empty, so the value remains in formal statistics. Do not
  silently remove it; confirm whether it is a physical transient or an
  acquisition outlier before changing the cleaning contract.
- The accepted low-frequency source still has missing rows for Z12-2, Z14-2
  and Z15-1. The supplement run freezes the existing low-frequency and WIM
  results rather than fabricating replacements.
- The signed analysis manifest from this one completed run predates the
  corrected cable-force directory collector, so twelve exact cable-force JPGs
  are bound through a signed derived sidecar. This is an audited compatibility
  bridge, not permission for ordinary filesystem fallback. Future analysis
  manifests should carry those images directly.

## v1.8.0 Stable Source And Validation Boundaries

Status: stable package gates and the rollback-safe 133 production switch are
complete. The bridge-specific source, engineering and report-acceptance limits
below remain in force.

- Ordinary GUI runs should remain on source mode `auto`: CSV has priority and a
  valid MAT cache is used when CSV is absent. Do not instruct ordinary users to
  select `mat_only` simply because an archived period contains only MAT files.
  Explicit `mat_only` is reserved for isolated verification and must never
  fall back to CSV. `DataIndex` now enforces the same rule; a future index
  refactor must not reintroduce CSV fallback in `mat_only`.
- Jiulongjiang/Shuixianhua cache-only operation requires a valid
  `jlj_csv_v2` MAT payload and matching metadata. A malformed, stale or
  metadata-less cache fails closed; it must not be accepted merely because the
  `.mat` filename matches a point. When both valid CSV and MAT are present in
  `auto`, CSV remains authoritative.
- Automatic y-limits for Zhishan and Shuixianhua cable acceleration apply only
  to raw time-history figures. Do not infer that the RMS figure axis, RMS
  aggregation or alarm/statistical threshold changed.
- The unified-workbench report implementation is embedded in the workbench
  application as a background worker for the same EXE runtime. v1.8.0 must not
  ship or open a second `BridgeReportBuilder.exe`. The final 381-file package,
  native GUI, embedded-report worker, CLI and disposable update/rollback cycle
  pass; the inventory contains only the workbench and internal analysis-runner
  executables.
- Read-only inspection of 126 found the first real temperature/humidity sample
  at `2026-06-08 09:00:02.057`, first included by the June 9 export. Point `33`
  is temperature and `33-2` is highly likely humidity. Within the inspected
  export range, no independent `WS-H` channel was observed. This remains a
  source-identification caveat until authoritative channel documentation is
  obtained and must not be generalized to uninspected historical partitions.
- Local validation order is Hongtang -> Guanbing -> Zhishan -> Shuixianhua.
  Hongtang has an accepted RC2 analysis/report baseline. Guanbing's local RC3
  source sample plus the final 133 v1.8.0 validation and Zhishan April RC3
  source analysis are complete but do not constitute full-period report
  acceptance; Guanbing covers only May 26-28 and lacks the May 29 adjacent
  rolling file needed to close the final day. A fresh Shuixianhua May candidate
  report has now been generated
  with 47/47 locked May figures and a complete 10-point temperature table, but
  it remains pending user review and must not be described as a signed client
  deliverable.
- Zhishan source gaps: all of `2026-04-02`, CF-7 on `2026-04-01`, and the
  adjacent `2026-05-01` rolling source required for the April tail are absent.
  Shuixianhua cable-acceleration source is absent from `2026-05-02` through
  `2026-05-05`. Reports and validation summaries must disclose these gaps and
  must not fabricate continuity.
- Shuixianhua temperature point `WD-04-11-15#横梁` reports a May range of
  `-200.0 C` to `149.3 C`, unlike the other temperature points. The value is
  retained and disclosed in the candidate report; it requires source/sensor
  quality review and must not be silently cleaned or interpreted as a physical
  bridge-temperature excursion without evidence.
- Shuixianhua captions use Word `STYLEREF` plus `SEQ` fields. Microsoft Word
  renders and numbers them correctly, while the current LibreOffice fallback
  may show broken-reference text and extra blank pages. Formal acceptance must
  use either the builder-provided Word PDF (Shuixianhua) or the PDF created by
  the unified isolated Word exporter (other embedded report types). The QC path
  rejects broken-reference text. If Word export is unavailable, LibreOffice is
  a layout preview only: the task is a warning and no formal `pdf_path` may be
  reported.
- The repository and inspected source contain no authoritative Shuixianhua
  34-point mapping for cable effective free length `L` and linear density
  `rho`. Cable acceleration, RMS and identified frequencies can be reviewed;
  cable-force kN conversion, force figures and force conclusions must remain
  unavailable. Do not copy nominal section data or another bridge's parameters.
  Required evidence is an approved table mapping point -> physical cable ->
  cable type -> effective `L` -> `rho` -> baseline force, with drawing/version
  and date.
- Shuixianhua's final compiled wind-only rerun closes 8/8 source records and
  reproduces the prior wind workbook and all eight JPG hashes exactly. The
  corrected preflight no longer reports a false “0/2 points found” warning for
  a valid cache-only source. Preserve this regression when changing cache
  discovery.

## PySide6 Workbench Production Migration Boundaries

Status: staged rollback-safe production switch completed on 2026-07-14. The
legacy tree is retained for rollback and must not yet be deleted.

- The mutable `F:\Guanbing_v1.8.0-rc1` candidate has a report-builder hash that
  no longer matches its original release manifest and must never be promoted
  as the stable installation. It remains historical candidate evidence only.
  The immutable v1.8.0 archive was instead verified and installed at
  `F:\Guanbing`.
- The former clean v1.7.39 checkout is retained at
  `F:\Guanbing_legacy_pre_v1.8.0_20260714_2252`. Forty-three historical task
  definitions were exported before cutover; all inspected
  `Guanbing*`/`Codex_Hongtang*` tasks remain disabled and no related process was
  running after final smoke. Retain the rollback tree through both a 14-day
  observation window and two successful real report cycles, using whichever
  completes later; do not re-enable historical one-shot tasks wholesale.
- Candidate production-data validation must keep task names, logs and outputs
  separate. Hongtang Q2 analysis/report and Guanbing analysis may not overwrite
  the accepted old-version statistics, figures or reports during comparison.

- Hongtang period-report pagination is now generated from Word `PAGE` and
  `NUMPAGES` fields and no longer patches a hard-coded total. Any future
  template replacement must retain the one-header/one-PAGE/one-NUMPAGES
  contract or the report builder will reject the output. Rendering the bare
  template is not an acceptance test for caption cross-references; acceptance
  remains a fully populated report followed by Word field update and complete
  page rendering.
  The current template has three unnumbered physical pages before the body
  (cover, blank verso and approval page), so the adjusted total is
  `{ = NUMPAGES - 3 }`. The earlier `- 4` value rendered the final page as
  `第 78 页 共 77 页`; Word PDF QA on 2026-07-14 caught and fixed that
  off-by-one error. Revalidate the offset against an authoritative Word PDF if
  the front matter is ever changed.

- The PySide6 shell currently covers project/date/module selection, local
  analysis launch, status/manifest review, task restoration, and guarded report
  handoff. The warning page now inventories `alarm_bounds`,
  `force_alarm_bounds`, `alarm_levels`, `warn_lines`, `rms_warn_lines`, and
  `group_warn_lines` with source provenance, while explicit `alarm_bounds` and
  data-cleaning threshold editing retain backup/hash gates. The inventory
  intentionally does not convert plot lines or one-sided levels into two-sided
  bounds. Compiled-runner-backed automatic-cleaning
  proposals and curve previews, post-filter cleaning, offsets, grouped plots,
  common plotting and spectrum overrides are also migrated.
  The unified PySide6 workbench is now the production entry on 133. Keep the
  retained MATLAB-GUI checkout only as the bounded rollback path during the
  observation window; do not operate both interfaces against the same live
  output tree concurrently.
- The Python module key/option mapping mirrors MATLAB and is protected by a
  source-contract test against `bms.module.ModuleRegistry`; future module
  additions must update both sides or the test will fail.
- Historical RC packages included a separate rebuilt report generator. RC3
  instead embeds report execution in the workbench runtime and must not copy or
  launch `BridgeReportBuilder.exe`. The rebuilt unified package has completed
  installed-runtime verification, but the bridge-by-bridge evidence is still
  stratified: only Hongtang has an accepted full analysis/report baseline;
  Guanbing, Zhishan and Shuixianhua currently have the source-analysis evidence
  described above. The retained legacy tree is an emergency rollback copy, not
  the ordinary production entry and not evidence of full-period report parity.
- The frozen shell itself now passes a catalog-driven all-profile matrix: every
  configured project loads, each report/analysis-only capability matches the
  shared catalog, and all packaged catalog/config/template assets retain
  identical SHA256 values
  after every profile switch. This closes installed-resource/runtime parity but
  does not substitute for production-data report comparison. The packaged
  “所有桥梁自检” action exposes this result and refuses a matrix that is
  incomplete, has a hard-coded/stale project count, or no longer matches its
  release-inventory size/SHA256 record.
- The report gate verifies manifest success, selected-module coverage,
  context identity, pinned hashes, and every manifest-declared full-plot
  provenance record. Explicit visual approval remains mandatory.
- Remote task submission/monitoring is not exposed as a general workbench
  feature. The user explicitly authorized one isolated 133 RC comparison under
  `F:\Guanbing_v1.8.0-rc1`; it used independent task names, cache-only views,
  logs and outputs and did not change the then-current production checkout.
  That RC comparison is superseded by the stable cutover. The one-off
  validation does not expand the GUI's supported scheduling scope.
- The local task center is intentionally a bounded recovery index, not a
  filesystem-wide scheduler database. It scans only direct job directories
  under the currently selected data root and contexts explicitly opened in the
  running process; it does not recurse through large raw-data or backup trees,
  discover other drives automatically, or poll 133. A missing data root or
  changed configuration is shown as a warning for operator review, while an
  unknown bridge or unreadable context is blocked. Restoring a warning does not
  waive the ordinary launch/report validation gates.
- GitHub auto-update code is present. Stable `v1.8.0` is published as a formal
  GitHub Release; stable clients deliberately ignore prereleases and tags
  without an eligible release asset. The real-ZIP disposable update-cycle
  validator and native screenshot/JSON evidence passed before publication and
  production cutover. The 2026-07-13 development ZIP
  passed frozen installation, replacement of the warning/task-history managed
  screenshots, migration from the legacy English EXE to the Chinese EXE, and
  exact fault-injected rollback. Existing configs
  are deliberately preserved, so future config-schema changes still need an
  explicit migration rather than relying on package replacement.
- The warning inventory covers values resident in bridge JSON configuration.
  It does not scrape threshold numbers embedded directly in legacy report
  prose or generator code. Those constants must be centralized only after
  their engineering/statistical meaning is reviewed; the overview must not
  imply that a plotting reference line is an alarm-engine threshold.
- Guanbing has valid wind grading values and deflection/tilt plot reference
  lines but no explicit two-sided lower/upper rules. This is intentional, not a
  load failure. The editor now hides the empty table and explains the
  distinction; it offers explicit add actions but never converts one-sided
  grades or plot lines automatically. Any new two-sided rule still requires
  confirmation against the formal project warning standard before saving.

## Workbench Update Backup Retention

Status: explicit operator-controlled retention implemented and initial 133
production cutover completed; rollback retention window is active.

Successful updates retain a timestamped sibling backup of the full previous
installation so rollback remains possible after restart. The packaged
workbench now inventories these backups and offers an explicit cleanup action
that always keeps the newest two identity-closed backups. There is deliberately
no unattended deletion. A directory is eligible only when it is a direct,
non-symlink sibling with the transaction naming pattern, a workbench EXE and a
readable semantic-version release manifest. Malformed, incomplete and manual
directories are displayed as retained or ignored and are never removed by the
cleanup function. Failed transactions still restore the exact old tree and
delete their pending candidate. This behavior passed the stable-package
disposable update/rollback gate. The manually retained pre-v1.8.0 production
tree on 133 remains outside automatic cleanup until the stated observation
window closes.

## Embedded Report QC Boundary

Status: embedded report runtime is deployed and its production-root smoke
passes. Full-period bridge-specific report acceptance remains stratified and is
not implied by the application cutover.

The workbench now runs the same report dispatch service used by the legacy
report GUI in a background process and records stage/status/result JSON. QC
checks DOCX ZIP integrity, the main document part, media count, output hash and
size; it records available PDF size/page count and report-manifest
missing/warning counts. It also renders every page, creates a contact sheet and
flags blank pages or raster-boundary contact. Five historical samples totaling
371 pages were rendered; four passed automatically. The Shuixianhua sample has
two genuinely blank pages (3 and 10), retained as a warning rather than silently
accepted. Contact-sheet/manual page review remains the acceptance step; newly
generated embedded reports still need profile-by-profile comparison before a
specific bridge/period is accepted as a deliverable.

Installed-runtime visual execution was verified on the 40-page Guanbing sample:
the embedded report worker completed in 25.6 seconds and matched source mode
with no blank-page or edge warnings. Production-root smoke now also verifies
the embedded worker in the unified EXE; this still does not replace fresh,
full-period report comparison for each bridge.

Do not treat an old successful analysis manifest as report-ready merely because
its module status is `ok`. The child process now requires non-empty formal
`.plot.json` provenance and independently repeats identity, hash, module and
count-closure checks. The 2026-07-13 local audit intentionally found zero
eligible five-profile contexts: the local historical manifests predate formal
provenance or reference result files that exist only in the production bundle.
Generator-only fallback builds are explicitly labelled and are not an approval
substitute. Their current deltas are: Hongtang 108 pages/182 media (10 missing,
4 warnings), Jiulongjiang 104/147 (11 missing, 1 warning), Shuixianhua 67/85
(blank pages 10 and 42, synthesized legacy manifest), and Zhishan 46/57
(missing figure anchors 2-5 and 2-6). These historical samples must be resolved
against complete context-matched results before they can be cited as current
bridge-specific acceptance; they do not block the completed v1.8.0 application
deployment.

Historical RC1/RC2 packaging rebuilt `BridgeReportBuilder.exe` whenever report
Python/config inputs were newer; that guard prevented a stale copied report EXE
from opening the old GUI. RC3 supersedes this layout by freezing the report
modules into the workbench executable and launching an internal background
worker. Keep the historical note for diagnosis, but do not restore the separate
EXE to the unified package.

The first five-profile render also exposed a Windows long-path defect: the QC
folder repeated the full Chinese DOCX name and LibreOffice returned success
without producing a PDF. Visual QC now uses short SHA-derived output folders
and an isolated system-temporary LibreOffice profile. This avoids both the
conversion failure and undeletable deep profile trees.

## Plot And Spectrum Editor Compatibility Rules

Status: migrated locally on `dev/pyside6-workbench`; six-bridge no-op and
cross-language contracts covered.

- MATLAB deliberately forces high-frequency `dynamic_raw_sampling_mode=full`
  to line rendering. The PySide6 editor therefore refuses an explicit
  `full + dense_band` pair instead of saving a value MATLAB would silently
  override. This is a configuration truthfulness guard, not an algorithm or
  plot-statistics change.
- All active bridge configurations have been migrated to `peak_orders`. Older
  external `target_freqs`, `tolerance` and `theor_freqs` files remain readable
  through an import-compatibility path; saving an edited spectrum module
  normalizes its managed frequency fields to `peak_orders`, matching MATLAB
  `SpectrumPeakOrderEditorService`. `fs`, auto-detection, thresholds and
  unrelated fields remain unchanged.
- Spectrum point coverage may be explicit under `points.<spectrum_module>` or
  inherited from the corresponding acceleration/cable/group points. The UI
  displays the effective inherited list but only writes an explicit list when
  the user selects that mode.

## Strain Group Editor Alias Read/Write Mismatch

Status: fixed locally on `dev/pyside6-workbench`; MATLAB and Python contracts covered.

The legacy group editor read `strain` through `ModuleConfigResolver`, whose
compatibility order prefers `groups.strain_timeseries`, but saved through the
canonical key `groups.strain`. Configs containing both keys could therefore
show a successful save while the next reload still displayed the unchanged
timeseries groups. The MATLAB service now writes the same resolved group key it
read. When the resolved and canonical containers were identical before the
edit, both are kept synchronized; when they were intentionally different, the
canonical statistical groups remain untouched. The PySide6 editor exposes the
two JSON keys separately and shares labels safely through `plot_styles.strain`.

## Compiled Runner Request JSON Encoding

Status: fixed locally on `dev/pyside6-workbench`; real compiled EXE verified.

MATLAB `jsondecode(fileread(...))` rejected UTF-8 JSON files beginning with a
BOM. The first compiled automatic-proposal smoke therefore fell through to the
legacy analysis dispatcher and exited before writing a result. Workbench
request writers now use BOM-free UTF-8, while `bms.io.JsonFile` strips a BOM
when one is supplied by an external tool. `RunRequest`, automatic-proposal
dispatch and the CLI dispatcher share this reader. The same utility hashes the
pinned configuration, and the compiled proposal Runner refuses configuration
drift before reading analysis data. The rebuilt runner completed an actual
request with exit code 0 and matching config SHA256.

The preview path now has its own contract rather than embedding potentially
large series inside the proposal result. The Runner writes a separate JSON,
pins its SHA256, and reports its series count. PySide6 refuses changed files,
request/config identity mismatches, duplicate module/point keys, non-closing
time/value/sample counts, or a series above the 50000-point safety limit. The
packager runs a real compiled preview smoke on every analysis-runner build and
checks that extrema-preserving sampling retains a known source maximum. This
adds review evidence only; MATLAB still owns all proposal calculations.

This encoding rule applies to JSON contracts only. Generated Windows
PowerShell 5.1 launchers containing Chinese paths should continue to use UTF-8
with BOM as documented below.

## Compiled Runner Failure Exit Semantics

Status: fixed and covered by a real compiled-Runner release gate.

A module-level failure can be a valid completed orchestration result with a
failed analysis manifest, so waiting for the process alone is not proof of
success. `RunRequestRunner` now writes the final async `failed` status together
with its valid `manifest_path` first, then raises
`BMS:RunRequestRunner:AnalysisFailed`; the compiled Runner consequently exits
non-zero while preserving the diagnostic manifest and module records. The
release build runs an empty-root Jiulongjiang `doUnzip` failure request and
requires a non-zero process exit, failed status, retained failed manifest and
`unzip=fail`. Only after that check does the package manifest set
`analysis_runner_failure_exit_smoke=true`; GitHub Release packaging blocks old
or unverified manifests without this field.

## MATLAB Path Pollution From Archived Runtime Copies

Status: test harness guarded; repository archives remain untouched.

Blind `addpath(genpath(projectRoot))` can put MATLAB files below
`ops_local/release_archives` or `release_packages` ahead of the current
`pipeline`. During this milestone it selected a v1.7.8
`resolve_post_filter_thresholds.m` instead of the dev-branch implementation.
Focused workbench tests now explicitly place the current root, pipeline,
analysis, config and UI paths at the beginning. Do not delete or edit archived
deliverables to solve path order; production launchers and compiled builds must
add only the intended current source directories.

## Cleaning Threshold Struct Field Compatibility

Status: fixed locally on `dev/pyside6-workbench`; regression covered.

MATLAB struct concatenation fails when a default cleaning threshold contains
`min/max/t_range_start/t_range_end` but a per-point threshold omits one or more
optional fields. This is valid in current production configs—for example,
one-sided wind/temperature rules—and previously could fail inside
`CleaningPipeline.applyRuleBlock`. Known invalid date intervals now use the
separate `exclude_ranges` contract instead of inverted thresholds.

The pipeline now normalizes each threshold to the four supported fields before
default/per-point merging. Missing min/max remain empty, so one-sided filtering
semantics are unchanged. The Python editor and MATLAB pipeline share
`tests/fixtures/workbench_cleaning_threshold_contract.json`; focused MATLAB
coverage verifies default/point merging and one-sided filtering. This fix does
not change any configured bound, comparison rule, or statistical definition.

## High-Frequency Report Plot Sampling

Status: superseded by the v1.7.26 rolling-export fix; keep only as history and a report QA rule.

The previous extrema-preserving cap fixed dropped extrema, but some monthly or
quarterly raw high-frequency time-history figures still looked visually sparse
when they used the ordinary common cap or when dense-band rendering was used
too aggressively. The later source-vs-algorithm audit proved that the dominant
daily blank bands were not a plot-density problem: the v1.7.14 per-day loader
kept only about 38% of each calendar day. Hongtang Q2 and Zhishan now use:

- `plot_common.dynamic_raw_render_mode=line`
- `plot_common.dynamic_raw_sampling_mode=full`
- `plot_common.dynamic_raw_line_width=1.0`
- `plot_common.gap_mode=connect`

The corrected path deliberately avoids both sparse low-cap line plots and
filled-envelope `dense_band` output. During the 2026-07-09 report refresh, the
dense-band variants were rejected because vertical min/max bars looked striped
and filled patches introduced geometric blocks across long source gaps. The
high-sample line mode is slower than low-cap plotting but closer to the
original full-resolution waveform. The 2026-07-10 fix reconstructs each natural
day from export folders D and D+1 before cleaning and plotting; see
`docs/dynamic_plot_source_vs_algorithm_20260710.md`.

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

## Rolling-Export Boundary Sources And Legacy UTF-16 Caches

Status: explicitly disclosed residuals after v1.7.26; do not hide them with plot changes.

- Zhishan April lacks export folder `2026-04-02`. It creates one real source
  gap of roughly 24 hours and marks calendar days April 1 and April 2 incomplete.
- Hongtang Q2 and Zhishan June currently have no `2026-07-01` export folder in
  their current or recognized adjacent partition roots. June 30 after about
  09:00 therefore remains unavailable until a later raw archive is recovered.
  Zhishan June also lacks the `2026-06-19` dated partition. v1.7.28 formal
  provenance therefore marks June 18, June 19, and June 30 incomplete. The
  v1.7.32 June report discloses all three affected dates and does not interpolate
  or fabricate the missing periods.
- The UTF-16LE/CRLF parser now counts physical header lines correctly. Existing
  `csv_timeseries_v2` MAT caches are deliberately not invalidated, so historical
  Zhishan caches still omit the first three data rows of each affected CSV. The
  measured impact on April CF-1 is about `0.00017%` and does not explain visual
  gaps or change extrema. Rebuild only from available raw CSV if literal
  point-for-point completeness is required; do not invalidate Hongtang MAT-only
  caches whose source CSV was already archived or removed.

New dynamic `.plot.json` files record required export contribution, incomplete
calendar days, missing export dates, sample counts, and the fact that internal
gap coverage is not automatically assessed. Locked report bindings should set
`require_source_provenance: true` for these high-frequency images.

## Zhishan SX-5 Low-Pass Strain Excursions

Status: retained and disclosed after v1.7.30; requires engineering/sensor review.

The old April-June SX-5 post-filter forced low-pass strain into `[-100, 100]`
microstrain and silently discarded the seasonal baseline and large positive
excursions. v1.7.30 removes that obsolete point-specific filter. The May and
June recomputations retain more than 40 million finite SX-5 low-pass samples
per month and show a `1000.0 microstrain` maximum, above the configured
`+405.0 microstrain` level-2 boundary.

This is not a plot-density artifact and must not be hidden by reinstating the
old threshold. It is also not, by itself, proof of a structural abnormality.
The v1.7.32 reports require cross-checking the raw sample, sensor operating
state, acquisition saturation/limits, and site inspection before drawing an
engineering conclusion.

## MAT-Only Dynamic RMS Refresh

Status: fixed locally; keep the fail-closed regression in the release gate.

During the 2026-07-09 Hongtang Q2 high-frequency plot refresh, the direct-wave
CSV copies had already been removed and the run depended on the formal MAT
data-source mode. A manual `refresh_dynamic_rms_only` pass refreshed `0`
points and overwrote `accel_stats.xlsx` / `cable_accel_stats.xlsx` with
header-only files. The accepted state was restored by rerunning the main
`acceleration` and `cable_accel` analyzers, which correctly read the MAT data
and rebuilt both plots and stats.

Fixed behavior:

- `refresh_dynamic_rms_only` now uses the same vendor-aware calendar-day and
  MAT alias/source-discovery path as the main dynamic analyzers;
- a refreshed point count of `0` raises
  `refresh_dynamic_rms_only:NoPointsRefreshed` before group plots or the stats
  workbook are written; the legacy empty-output behavior requires the explicit
  `allow_empty_output=true` option;
- `tests/test_refresh_dynamic_rms_only.m` covers a Hongtang-style MAT-only
  alias fixture, byte-for-byte preservation of an existing workbook on a
  zero-point refresh, and the explicit empty-output override.

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

On 2026-07-10, Guanbing `GB-RSG-G05-001-06` exposed the same class of hidden
suppression without an inverted range: a permanent `40..52` per-point
post-filter ran after the normal dynamic-strain bounds and therefore removed
all finite high-pass values. The obsolete override was removed. When a boxplot
point is unexpectedly empty, inspect both the common filter and resolved
per-point post-filter before treating it as missing source data.

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

Native `PrintWindow` evidence also needs a completeness gate. A 2026-07-13
capture rendered only part of the frame during the repaint race, while the old
"at least 150 bright samples" rule could still accept it. The capture helper
now combines the bright requirement with a maximum 10% near-black sample ratio,
waits one second before the first capture, and retries up to 15 times. The final
ten packaged screenshots and five repeated startup captures contain no dark
grid samples. Keep this gate when changing DPI or window-launch behavior.

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
