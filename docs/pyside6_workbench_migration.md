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
`alarm_bounds` editor. It still does not write to production machines.

## Packaged local milestone

- Build with `scripts/build_workbench_exe.ps1`.
- Run `dist/BridgeMonitoringWorkbench/BridgeMonitoringWorkbench.exe`.
- The onedir release includes the compiled MATLAB analysis runner, all profile
  configs/templates, and a freshly packaged report builder.
- The build blocks unless the workbench EXE smoke contract, two native Qt
  screenshots, and the packaged report builder `--job-context` smoke test pass.
- `release_manifest.json` records SHA-256, version, file count/byte size
  excluding the manifest itself, and smoke results. Generated `build/` and
  `dist/` content is intentionally local.

The new configuration page edits only explicit `defaults/per_point`
`alarm_bounds`. It validates level names and finite ordered bounds, rejects a
save if the source file changed after loading, automatically backs up an
overwritten config, preserves unrelated JSON fields, and invalidates any old
job approval after the selected config is changed. Cleaning thresholds,
post-filter thresholds, offsets, and plot overrides remain in the MATLAB GUI.

The packaged shell also includes a stable-channel GitHub Release updater. It
checks no more than once per day, supports a manual check, requires a newer
semantic version and a runnable Windows x64 ZIP, verifies the archive SHA256
and internal EXE SHA256, stages outside the installation, preserves configs,
backs up the current installation, and replaces files only after user
confirmation and process exit. See `docs/workbench_github_updates.md`.

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

- Cleaning-threshold editor parity (alarm-bound editing is now migrated).
- Automatic-cleaning preview parity.
- Post-filter cleanup and offset-correction parity.
- Group-plot, plot-common, and spectrum override parity.
- Embedded report build progress and final Word/PDF QC.
- Installed-runtime comparison across every bridge profile.
