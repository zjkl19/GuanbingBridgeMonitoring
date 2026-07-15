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
