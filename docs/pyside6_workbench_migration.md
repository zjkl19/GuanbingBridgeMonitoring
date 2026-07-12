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

This round does not migrate advanced MATLAB configuration editors and does not
write to production machines.

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

- Threshold editor parity.
- Automatic-cleaning preview parity.
- Post-filter cleanup and offset-correction parity.
- Group-plot, plot-common, and spectrum override parity.
- Embedded report build progress and final Word/PDF QC.
- Packaging and end-to-end comparison across every bridge profile.
