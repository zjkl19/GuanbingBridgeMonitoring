param(
    [switch]$SkipMatlabAll
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
    Write-Host "[CI-SMOKE] Python unit tests" -ForegroundColor Cyan
    python -m unittest discover tests_py
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "[CI-SMOKE] Python compile check" -ForegroundColor Cyan
    python -m py_compile reporting\analysis_manifest.py reporting\build_monthly_report.py reporting\build_period_report.py reporting\build_jlj_monthly_report.py reporting\build_guanbing_monthly_report.py
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    Write-Host "[CI-SMOKE] Config validation" -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File .\scripts\validate_configs.ps1
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (-not $SkipMatlabAll) {
        Write-Host "[CI-SMOKE] MATLAB tests" -ForegroundColor Cyan
        matlab -batch "run_tests('all')"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
finally {
    Pop-Location
}
