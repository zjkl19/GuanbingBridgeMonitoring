param(
    [string]$OutputDir = ".\release",
    [string]$Version = "",
    [switch]$IncludeReportBuilderDist
)

$ErrorActionPreference = "Stop"

function Write-Step($Message) {
    Write-Host "[package] $Message" -ForegroundColor Cyan
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $stamp
}

$outRoot = Join-Path $repo $OutputDir
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$stage = Join-Path $outRoot "BridgeMonitoringRuntime_$Version"
if (Test-Path $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$includeDirs = @(
    "+bms",
    "analysis",
    "config",
    "pipeline",
    "scripts",
    "ui",
    "reports",
    "reporting"
)

$excludeDirNames = @(
    ".git",
    ".venv",
    "__pycache__",
    "build",
    "tmp",
    "outputs",
    "release"
)
if (!$IncludeReportBuilderDist) {
    $excludeDirNames += "dist"
}

function Copy-FilteredDir($RelativePath) {
    $src = Join-Path $repo $RelativePath
    if (!(Test-Path $src -PathType Container)) {
        return
    }
    $dst = Join-Path $stage $RelativePath
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    Get-ChildItem -LiteralPath $src -Recurse -Force | ForEach-Object {
        $relative = $_.FullName.Substring($src.Length).TrimStart("\", "/")
        $parts = $relative -split "[\\/]"
        if ($parts | Where-Object { $excludeDirNames -contains $_ }) {
            return
        }
        $target = Join-Path $dst $relative
        if ($_.PSIsContainer) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
        } else {
            if ($_.Name -match "(_backup_|backup_\d|\.spec$|\.pyc$|~$)") {
                return
            }
            New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }
}

foreach ($dir in $includeDirs) {
    Copy-FilteredDir $dir
}

$rootFiles = @(
    "README.md",
    "start_gui.m",
    "run_all.m",
    "load_config.m",
    "save_config.m",
    "validate_config.m",
    "displayFig.m",
    "displayHiddenFig.m",
    "建科院标志PNG-01.png"
)
foreach ($file in $rootFiles) {
    $src = Join-Path $repo $file
    if (Test-Path $src -PathType Leaf) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $stage $file) -Force
    }
}

$manifest = [ordered]@{
    package_version = $Version
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    repo = $repo
    include_report_builder_dist = [bool]$IncludeReportBuilderDist
    note = "Data directories are excluded. Copy this package over source code only."
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stage "package_manifest.json") -Encoding UTF8

$zip = Join-Path $outRoot "BridgeMonitoringRuntime_$Version.zip"
if (Test-Path $zip) {
    Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force
Write-Step "Created $zip"
Write-Step "Stage directory: $stage"
