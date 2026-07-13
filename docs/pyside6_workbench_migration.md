# PySide6 Workbench Migration

## Objective

Replace the user-facing MATLAB GUI with one PySide6 workbench while retaining
the validated MATLAB analysis engine. The migration is additive: the legacy
MATLAB GUI remains available until configuration parity and production report
cycles prove the new shell.

## First-round scope (10-hour budget)

- Define a versioned `job_context.json` contract.
- Read the existing bridge profile catalog.
- Build MATLAB-compatible `run_request.json` payloads.
- Launch either `BridgeAnalysisRunner.exe` or `matlab -batch` locally.
- Monitor the existing status JSON and stop-file protocol.
- Read an analysis manifest and present module results.
- Enforce an explicit plot-review gate before report generation.
- Pass the approved context into the existing PySide6 report generator.
- Add unit, contract, manifest, and offscreen GUI smoke tests.

The second local milestone adds a packaged EXE and migrates the explicit
`alarm_bounds` editor. The third local milestone adds data-cleaning threshold
parity. The fourth adds post-filter cleanup plus compiled-runner-backed
automatic-cleaning proposals. The fifth migrates offset correction and grouped
plot configuration. The sixth migrates common plot parameters and
acceleration/cable-acceleration spectrum coverage plus peak-order overrides.
The seventh embeds report execution/QC and complete plot-provenance review.
None of these milestones writes to production machines.

## Packaged local milestone

- Build with `scripts/build_workbench_exe.ps1`.
- Run `dist/BridgeMonitoringWorkbench/桥梁健康监测工作台.exe`.
- The onedir release includes the compiled MATLAB analysis runner, all profile
  configs/templates, and a freshly packaged report builder.
- The build blocks unless the workbench EXE smoke contract, fourteen native Qt
  screenshots, packaged report `--job-context` smoke, and the embedded
  report-job protocol smoke pass.
- The frozen EXE is launched once for each of the six bridge profiles. The
  resulting `workbench_profile_matrix.json` closes selected identity, config
  and template SHA256, default dates, module coverage, five report-capable
  profiles, one analysis-only profile, editor shape and before/after hashes for
  all twelve catalog/config/template assets.
- The packaged title bar exposes this evidence through “六桥自检”. The reader
  accepts only a six-row all-true matrix with the 5+1 capability split and also
  rechecks the matrix byte size and SHA256 against its unique release-inventory
  record.
- `release_manifest.json` records SHA-256, version, file count/byte size
  excluding the manifest itself, and smoke results. Generated `build/` and
  `dist/` content is intentionally local.

The configuration page has separate editors for explicit `defaults/per_point`
`alarm_bounds` and data-cleaning `thresholds` / `zero_to_nan` / `outlier`.
The alarm editor validates level names and finite ordered bounds. The cleaning
editor preserves the production schema variants used by all six bridge
configs, including scalar/array/empty threshold containers, one-sided rules,
optional time windows, and the legacy `1000/-1000` suppression sentinel. Both
reject a save if the source file changed after loading, automatically back up an
overwritten config, preserves unrelated JSON fields, and invalidates any old
job approval after the selected config is changed.

Post-filter `post_filter_thresholds` uses a separate editor with the same
representation and save guards. Automatic-cleaning proposal generation remains
numerically owned by MATLAB: `BridgeAnalysisRunner.exe` dispatches a versioned
proposal request to `AutoThresholdProposalService`, while PySide6 owns options,
status polling, the human-review table and explicit application. Applying
requires the generation-time config SHA256 both before MATLAB data loading and
before selected rows are written, carries MATLAB-provided
`apply_key`/safe point identity, skips review-only rows, backs up the source,
and invalidates the old job context.

The compiled Runner now writes sampled preview series to a separate hash-pinned
artifact instead of inflating the proposal result. The PySide6 table selection
and editable bounds drive a dependency-free Qt curve view with threshold lines,
local-window shading and a pop-out view. The source service's existing
extrema-preserving sampler remains authoritative; Python does not recompute a
threshold or cleaning decision. Artifact type/version, request/config identity,
SHA256, duplicate point keys and sample-count closure are validated before a
curve is shown. A real compiled-runner contract smoke creates one proposal and
one 30-point preview while preserving the 100.0 source maximum under a 32-point
cap.

Offset correction and grouped plots are separate guarded editors. Offset rows
cover scalar values and the MATLAB `fixed`, first-day, daily, hourly and
non-overlapping segmented modes without changing `vals = vals + correction`
semantics. Group editing operates on the actual `groups.<key>` containers,
distinguishes `strain` from `strain_timeseries`, preserves historical list
containers on no-op edits, and updates the corresponding `group_labels` while
preserving unrelated plot settings. All six bridge configs pass exact no-op
round trips through both services.

The plot-common editor covers the complete 14-field union present across the
six production bridge configs and preserves unknown future fields. It keeps
MATLAB defaults implicit when a checkbox is cleared and refuses an explicit
`full + dense_band` combination because the MATLAB runtime forces full raw
sampling to line rendering. The spectrum editor manages explicit/fallback
coverage for `accel_spectrum` and `cable_accel_spectrum`, together with default
and per-point peak orders. Existing `fs`, `auto_detect_fs`, thresholds and
unrelated fields remain untouched. Legacy `target_freqs`/`tolerance`/
`theor_freqs` fields round-trip exactly until the corresponding module is
actually edited, at which point they are deliberately normalized to the
MATLAB-supported `peak_orders` contract.

Report generation now runs as a separate non-GUI child process from the
workbench. Source and frozen runtimes share a versioned status/result JSON
contract, and the legacy report window calls the same dispatch service so the
two entries cannot drift. The workbench displays preflight, building, QC and
terminal states; pins and rechecks config/template/analysis-manifest hashes;
and summarizes DOCX package integrity/media, available PDF pages, and
report-manifest missing/warning counts. Five report-capable profiles are
mapped; Chongyangxi remains intentionally analysis-only.

Final report QC also renders every DOCX page through LibreOffice and Poppler,
writes page PNGs plus a contact sheet, and flags blank pages or content touching
the raster boundary. Output folders use short source hashes rather than long
Chinese report names. A five-profile local matrix rendered 371 pages: Guanbing,
Hongtang, Jiulongjiang and Zhishan passed without automatic page warnings;
Shuixianhua retained two truly blank historical pages (3 and 10) as an explicit
warning for manual review.

The review page enumerates every manifest-declared `.plot.json`. It requires
full sampling, no reduction, finite/plotted equality, source/input and finite
source/input equality, coherent requested/complete/incomplete day counts, and
explicit missing-source/incomplete-day disclosure. Failed closure locks plot
approval. Disclosed source gaps remain visible but admissible; no data are
invented.

The packaged shell also includes a stable-channel GitHub Release updater. It
checks no more than once per day, supports a manual check, requires a newer
semantic version and a runnable Windows x64 ZIP, verifies the archive SHA256
and schema-v2 whole-package inventory, stages outside the installation,
preserves configs and unmanaged operator files, validates a complete candidate,
then atomically swaps the old installation to a backup only after user
confirmation and process exit. Fault-injected pre/post-activation rollback and
the frozen installed runtime are covered by the real-ZIP disposable validator.
Backup retention is operator-triggered rather than automatic: the workbench
lists recognized sibling backups and, after a second confirmation, can remove
older identity-closed copies while always retaining the newest two. Unreadable,
misnamed, symlinked or incomplete backups are never selected for cleanup.
See `docs/workbench_github_updates.md`.

## Process boundary

The workbench owns user interaction and job state. MATLAB owns numerical
analysis. Python report builders own DOCX/PDF production. They communicate only
through versioned JSON, manifests, logs, and file paths. PySide6 is not embedded
inside MATLAB, and the MATLAB engine is not rewritten in Python.

## Safety gates

1. Validate project, data root, config, dates, and selected modules.
2. Run analysis in a separate process.
3. Require a successful analysis manifest with no failed modules.
4. Require explicit plot approval tied to that job context.
5. Only then enable the formal report entry.

## Later migration work

- Generate fresh reports through the embedded task for each report-capable
  profile and compare them with the accepted historical samples.
