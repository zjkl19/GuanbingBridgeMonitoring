param(
    [string]$MatlabExe = "matlab",
    [string]$OutputDir = ".\bin\BridgeAnalysisRunner",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Convert-ToMatlabString($Value) {
    return ($Value -replace "'", "''")
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $outDir = $OutputDir
} else {
    $outDir = Join-Path $repo $OutputDir
}

if ($Clean -and (Test-Path -LiteralPath $outDir)) {
    Remove-Item -LiteralPath $outDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$repoM = Convert-ToMatlabString $repo
$outM = Convert-ToMatlabString $outDir
$code = @"
cd('$repoM');
addpath('$repoM','-begin');
addpath(fullfile('$repoM','ui'),'-begin');
addpath(fullfile('$repoM','config'),'-begin');
addpath(fullfile('$repoM','pipeline'),'-begin');
addpath(fullfile('$repoM','analysis'),'-begin');
addpath(fullfile('$repoM','scripts'),'-begin');
assert(exist('mcc','file') == 2, 'MATLAB Compiler mcc is not available in this MATLAB installation.');
mcc('-m','run_request_cli.m','-o','BridgeAnalysisRunner','-d','$outM','-a','+bms','-a','analysis','-a','config','-a','pipeline','-a','scripts','-a','ui');
"@
$code = ($code -split "`r?`n" | ForEach-Object { $_.Trim() }) -join " "

Write-Host "[build-runner] Output: $outDir" -ForegroundColor Cyan
& $MatlabExe -batch $code
if ($LASTEXITCODE -ne 0) {
    throw "MATLAB runner build failed with exit code $LASTEXITCODE"
}

$exePath = Join-Path $outDir "BridgeAnalysisRunner.exe"
if (!(Test-Path -LiteralPath $exePath)) {
    throw "Expected runner executable was not created: $exePath"
}
Write-Host "[build-runner] Created $exePath" -ForegroundColor Green
