param(
    [switch]$SkipMatlab,
    [switch]$FullMatlab
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Body
    )
    Write-Host "[HEALTH] $Name" -ForegroundColor Cyan
    & $Body
}

Invoke-Step "Validate configs" {
    powershell -ExecutionPolicy Bypass -File .\scripts\validate_configs.ps1
}

Invoke-Step "Python report tests" {
    python -m unittest discover tests_py
}

Invoke-Step "Python compile reporting scripts" {
    $files = Get-ChildItem -Path .\reporting -Filter *.py -File
    if ($files.Count -gt 0) {
        python -m py_compile @($files.FullName)
    }
}

if (-not $SkipMatlab) {
    if ($FullMatlab) {
        Invoke-Step "MATLAB full tests" {
            matlab -batch "run_tests('all')"
        }
    } else {
        Invoke-Step "MATLAB default tests" {
            matlab -batch "run_tests('default')"
        }
    }
}

Write-Host "[HEALTH] Release health check passed." -ForegroundColor Green
