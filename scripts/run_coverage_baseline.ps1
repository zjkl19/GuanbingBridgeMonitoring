param(
    [ValidateSet("all", "python", "matlab")]
    [string]$Only = "all",
    [ValidateSet("all", "smoke")]
    [string]$MatlabTarget = "all",
    [string]$PythonPattern = "test_*.py",
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $repo "outputs\coverage"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
    $OutputRoot = Join-Path $repo $OutputRoot
}
$OutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$python = Join-Path $repo "reporting\.venv\Scripts\python.exe"
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
    $python = (Get-Command python -ErrorAction Stop).Source
}

Push-Location $repo
$previousCoverageFile = $env:COVERAGE_FILE
try {
    if ($Only -in @("all", "python")) {
        $env:COVERAGE_FILE = Join-Path $OutputRoot ".coverage"
        & $python -m coverage --version *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Python coverage is not installed. Run: $python -m pip install -r reporting\requirements-test.txt"
        }

        & $python -m coverage erase --rcfile .coveragerc
        if ($LASTEXITCODE -ne 0) { throw "coverage erase failed" }
        & $python -m coverage run --rcfile .coveragerc scripts\run_python_tests.py --verbosity 1 --pattern $PythonPattern
        if ($LASTEXITCODE -ne 0) { throw "Python tests under coverage failed" }

        $reportLines = & $python -m coverage report --rcfile .coveragerc
        $reportExit = $LASTEXITCODE
        $reportLines | Set-Content -LiteralPath (Join-Path $OutputRoot "python-coverage-summary.txt") -Encoding UTF8
        $reportLines | Write-Host
        if ($reportExit -ne 0) { throw "Python coverage report failed" }

        & $python -m coverage xml --rcfile .coveragerc -o (Join-Path $OutputRoot "python-cobertura.xml")
        if ($LASTEXITCODE -ne 0) { throw "Python Cobertura export failed" }
        & $python -m coverage json --rcfile .coveragerc --pretty-print -o (Join-Path $OutputRoot "python-coverage.json")
        if ($LASTEXITCODE -ne 0) { throw "Python JSON coverage export failed" }
        & $python -m coverage html --rcfile .coveragerc -d (Join-Path $OutputRoot "python-html")
        if ($LASTEXITCODE -ne 0) { throw "Python HTML coverage export failed" }
    }

    if ($Only -in @("all", "matlab")) {
        $quotedOutput = $OutputRoot.Replace("'", "''")
        $quotedTarget = $MatlabTarget.Replace("'", "''")
        & matlab -batch "addpath('scripts','-begin'); run_matlab_coverage('$quotedOutput','$quotedTarget');"
        if ($LASTEXITCODE -ne 0) { throw "MATLAB coverage run failed" }
    }
}
finally {
    $env:COVERAGE_FILE = $previousCoverageFile
    Pop-Location
}

Write-Host "Coverage artifacts: $OutputRoot" -ForegroundColor Green
