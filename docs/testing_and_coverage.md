# Testing And Coverage Baseline

The project uses layered verification rather than treating a coverage
percentage as the release decision:

- MATLAB unit, contract, GUI, and integration tests under `tests/`;
- Python report/workbench/Qt tests under `tests_py/` plus the maintained Python
  smoke tests under `tests/`;
- compiled runner and packaged workbench smoke contracts;
- real bridge-data, report-field, and page-render validation for production
  candidates.

## Standard Python test entry point

Run every maintained Python test location with one command:

```powershell
reporting\.venv\Scripts\python.exe scripts\run_python_tests.py --verbosity 2
```

`scripts/run_ci_smoke.ps1` and `scripts/run_release_health_check.ps1` use the
same discovery entry point. This prevents the small report smoke tests under
`tests/` from being omitted while the main suite under `tests_py/` passes.

## Coverage baseline

Install the local test dependency once:

```powershell
reporting\.venv\Scripts\python.exe -m pip install -r reporting\requirements-test.txt
```

Run both language baselines:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_coverage_baseline.ps1
```

Faster instrumentation smoke:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_coverage_baseline.ps1 -MatlabTarget smoke
```

To validate only the coverage plumbing while unrelated work is in progress,
use a narrow Python discovery pattern as well:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_coverage_baseline.ps1 `
  -Only python -PythonPattern test_workbench_models.py
```

Individual language runs are available with `-Only python` and
`-Only matlab`. Generated files are under `outputs/coverage/` and are ignored
by Git:

- Python text, JSON, HTML, and Cobertura XML reports with branch measurement;
- MATLAB text/JSON summaries, test-result CSV, and Cobertura XML. MATLAB
  collects through condition level for the production roots `+bms/`,
  `analysis/`, `pipeline/`, `ui/`, `config/`, and `scripts/`; the interoperable
  Cobertura report exposes line and decision/branch totals. Root launch wrappers
  and `tests/` are intentionally not counted as production implementation.

The baseline is initially observational: it must not fail only because a
historical percentage is low. Test failures still fail the command. After the
baseline is stable, thresholds should be ratcheted by risk and changed code,
not imposed as one arbitrary percentage across numerical algorithms, Qt/Word
integration, and platform glue.

## Current measured snapshot

The full local baselines on 2026-07-15 passed 511/511 Python tests and 648/648
MATLAB tests. The measured production-source totals were:

| Scope | Line coverage | Branch coverage | Combined coverage.py result |
| --- | ---: | ---: | ---: |
| `workbench/` | 77.46% (6,904/8,913) | 63.71% (1,794/2,816) | 74.16% |
| `reporting/` | 57.39% (8,168/14,232) | 44.88% (2,527/5,630) | 53.85% |
| Python total | 65.12% (15,072/23,145) | 51.16% (4,321/8,446) | 61.39% |
| MATLAB production roots | 46.44% (20,570/44,297) | 47.91% (7,554/15,766) | n/a |

The MATLAB run collected through condition level and exported its interoperable
line/decision totals to Cobertura. The table intentionally reports the Python
and MATLAB baselines separately because the two coverage engines instrument
different languages and production roots; combining them into one percentage
would be misleading.

The final three Python tests exercise the PowerShell 360 transfer wrapper with
a fake CLI: no API-key literal is allowed, a single direct mode remains an
array under strict PowerShell semantics, and automatic download selects its
proxy fallback and hashes the result. No Python production source changed after
the coverage snapshot, so the production-code percentages above are unchanged.

The low aggregate MATLAB percentage is materially affected by operational
scripts that are difficult to exercise safely in a unit runner. Excluding
`scripts/`, MATLAB statement/decision coverage is about `73.69%` / `58.81%`;
for the `+bms/` analysis kernel it is about `78.90%` / `62.84%`. High-risk
modules now have stronger direct coverage, including cache prebuild
`89.42%` / `72.73%`, archive extraction `85.93%` / `72.73%`, plot option
resolution `93.00%` / `81.03%`, RMS-only refresh `86.60%` / `73.08%`,
workbench analysis lifecycle `96.60%` / `82.35%`, report-task lifecycle
`91.34%` / `78.57%`, and strict report-job orchestration `92.12%` / `80.65%`.

This snapshot is evidence that branch collection works, not evidence that all
behavior is sufficiently tested. In particular, platform-bound Word export,
large report-builder alternatives, error recovery, and production data runs
still need integration and rendered-output checks. Re-run the baseline after
feature work changes the discovered test count; never copy these numbers into
a release note without regenerating the artifacts.

For compound safety decisions, branch coverage alone is insufficient. Use
decision-table boundary tests and selectively review condition or MC/DC
coverage for cleaning thresholds, configuration precedence, date windows,
archive safety, cache transactions, and report acceptance gates.

## Verified source-CSV cleanup test boundary

The optional archive-backed source cleanup is destructive and must be reviewed
as its own high-risk subsystem. Do not infer its coverage from the older cache
prebuild or archive-extraction percentages above, and do not publish a new
percentage until the complete coverage artifacts have been regenerated after
the feature lands.

Its decision table must cover at least:

- default-off retention and the exact confirmation token/timestamp contract;
- strict boolean/policy parsing, dedicated-preprocessing module selection and
  rejection of unsupported data layouts;
- eligible configured CSV versus retained ZIP, WIM, Excel, unconfigured CSV and
  non-CSV files;
- closed MAT/metadata `pair_id` and `mat_bytes`, independent cache loading and
  zero-write reuse after the CSV is absent;
- missing, changed or path-conflicting source ZIP/extraction evidence;
- receipt path/config/cache/archive binding, truncated or tampered receipts and
  a new same-day source appearing after a committed receipt;
- one-natural-day streaming, stop-before-analysis behavior and multi-day
  partial failure;
- interruption after preparation/rename and during deletion, rollback results,
  partial receipt continuation and idempotent rerun;
- capacity/lock boundaries and proof that cache workers never delete sources.

Unit and branch evidence is still not sufficient for release. A packaged-runner
smoke must exercise the real task JSON contract, and isolated production-data
acceptance must verify daily receipts, retained ZIP hashes, removed/retained
file inventories, MAT-only readability, free-space change and a subsequent
ordinary `auto` analysis. Stable production deployment remains blocked until
those artifacts close.

Latest non-coverage release regression on 2026-07-16 passed `624/624` Python
tests in `reporting\.venv` in `151.40 s` and `724/724` MATLAB tests. The focused
rc5 recovery, provenance and compiled-manifest contracts passed `28/28` Python
tests; the focused manifest/OOM-classification gate passed `45/45` MATLAB
tests. These counts are regression evidence only and do not replace the
measured coverage snapshot above. The formal build exited `0`; native Windows
foreground/focus, DPI, font and icon acceptance passed. The compiled Runner
release gate additionally exercises default-off retention, unsafe-policy
rejection, a committed one-day verified cleanup transaction, a valid
`2,771,558`-byte manifest containing `1,200` warnings and a deterministic valid
failed-manifest fallback. The release inventory closes `385` files /
`227,271,383` bytes by per-file size and SHA-256; its ZIP contains the same 385
members plus the release manifest (`386` entries total), and all inventory
hashes close against the archive.
