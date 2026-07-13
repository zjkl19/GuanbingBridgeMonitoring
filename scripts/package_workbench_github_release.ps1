param(
    [string]$Version = "",
    [string]$OutputDir = "release\workbench",
    [switch]$SkipBuild,
    [switch]$AllowDevelopmentVersion
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repo

if (-not $Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $repo "VERSION") -Raw -Encoding UTF8).Trim()
}
if ($Version -notmatch '^v\d+\.\d+\.\d+([+-].+)?$') {
    throw "Invalid version: $Version"
}
if (-not $AllowDevelopmentVersion -and $Version -match '-') {
    throw "Development versions cannot be published as stable updates: $Version"
}

if (-not $SkipBuild) {
    & (Join-Path $repo "scripts\build_workbench_exe.ps1")
}

$distRoot = Join-Path $repo "dist\BridgeMonitoringWorkbench"
$manifestPath = Join-Path $distRoot "release_manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Verified workbench distribution is missing: $distRoot"
}
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$exePath = Join-Path $distRoot ([string]$manifest.executable)
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Verified workbench executable is missing: $exePath"
}
if ($manifest.version -ne $Version) {
    throw "VERSION and release manifest differ: $Version vs $($manifest.version)"
}
$actualExeHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualExeHash -ne ([string]$manifest.executable_sha256).ToLowerInvariant()) {
    throw "Workbench EXE hash differs from release manifest"
}
if ($manifest.schema_version -lt 2 -or $manifest.file_inventory_count -ne $manifest.file_count_excluding_manifest) {
    throw "Workbench distribution has no closed file inventory"
}
if (-not $manifest.auto_threshold_preview_runner_smoke `
        -or -not $manifest.installed_profile_matrix_smoke `
        -or -not $manifest.task_history_smoke `
        -or -not $manifest.report_builder_context_smoke `
        -or -not $manifest.embedded_report_job_smoke `
        -or -not $manifest.report_gate_contract_smoke `
        -or -not $manifest.report_visual_qc_smoke `
        -or -not $manifest.smoke.ok) {
    throw "Workbench distribution did not pass release smoke gates"
}

$resolvedOutput = Join-Path $repo $OutputDir
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
$assetName = "BridgeMonitoringWorkbench-$Version-win-x64.zip"
$archivePath = Join-Path $resolvedOutput $assetName
$checksumPath = "$archivePath.sha256"
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}
Compress-Archive -LiteralPath $distRoot -DestinationPath $archivePath -CompressionLevel Optimal
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
"$archiveHash  $assetName" | Set-Content -LiteralPath $checksumPath -Encoding ASCII

$publication = [ordered]@{
    schema_version = 1
    repository = "zjkl19/GuanbingBridgeMonitoring"
    tag = $Version
    archive = $archivePath
    archive_sha256 = $archiveHash
    checksum = $checksumPath
    publish_command = "gh release create $Version `"$archivePath`" `"$checksumPath`" --verify-tag --title `"$Version`" --notes-file RELEASE_NOTES.md"
}
$publicationPath = Join-Path $resolvedOutput "publish_$Version.json"
$publication | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $publicationPath -Encoding UTF8

Write-Host "GitHub Release assets prepared:"
Write-Host "  $archivePath"
Write-Host "  $checksumPath"
Write-Host "Publication plan: $publicationPath"
