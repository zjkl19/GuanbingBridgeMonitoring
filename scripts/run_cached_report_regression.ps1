param(
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$GuanbingRoot = 'F:\管柄大桥数据\2026年3月',
    [string]$HongtangRoot = 'E:\洪塘大桥数据\2026年1-3月',
    [string]$JiulongjiangRoot = 'E:\九龙江数据\2026年3月',
    [switch]$IncludeJiulongjiang,
    [switch]$KeepOutput
)

$ErrorActionPreference = 'Stop'

function Resolve-Python {
    param([string]$Root)
    $venvPython = Join-Path $Root 'reporting\.venv\Scripts\python.exe'
    if (Test-Path -LiteralPath $venvPython) {
        return $venvPython
    }
    return 'python'
}

Set-Location $RepoRoot
$python = Resolve-Python -Root $RepoRoot
$common = @(
    'reporting\smoke_report_generation.py',
    '--generate',
    '--report-date', (Get-Date -Format 'yyyy年MM月dd日')
)
if ($KeepOutput) {
    $common += '--keep-output'
}

Write-Host '[cached-regression] Python:' $python
Write-Host '[cached-regression] Output root:' (Join-Path $RepoRoot 'tmp\cached_report_regression')

Write-Host '[cached-regression] Guanbing monthly from existing stats/images...'
& $python @common --kind guanbing --output-root (Join-Path $RepoRoot 'tmp\cached_report_regression\guanbing') --guanbing-result-root $GuanbingRoot
if ($LASTEXITCODE -ne 0) { throw 'Guanbing cached report regression failed.' }

Write-Host '[cached-regression] Hongtang period from existing stats/images/WIM...'
& $python @common --kind hongtang --output-root (Join-Path $RepoRoot 'tmp\cached_report_regression\hongtang') --hongtang-result-root $HongtangRoot --hongtang-wim-root (Join-Path $HongtangRoot 'WIM\results\hongtang')
if ($LASTEXITCODE -ne 0) { throw 'Hongtang cached report regression failed.' }

if ($IncludeJiulongjiang) {
    Write-Host '[cached-regression] Jiulongjiang monthly from existing stats/images...'
    & $python @common --kind jlj --output-root (Join-Path $RepoRoot 'tmp\cached_report_regression\jlj') --jlj-result-root $JiulongjiangRoot
    if ($LASTEXITCODE -ne 0) { throw 'Jiulongjiang cached report regression failed.' }
}

Write-Host '[cached-regression] Done.'
