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
$releaseNotesPath = Join-Path $repo ("docs\releases\{0}.md" -f $Version)
if (-not (Test-Path -LiteralPath $releaseNotesPath -PathType Leaf)) {
    throw "Release notes are missing: $releaseNotesPath"
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
if ($manifest.schema_version -lt 3 -or $manifest.file_inventory_count -ne $manifest.file_count_excluding_manifest) {
    throw "Workbench distribution has no closed file inventory"
}
if (-not $manifest.auto_threshold_preview_runner_smoke `
        -or -not $manifest.installed_profile_matrix_smoke `
        -or -not $manifest.task_history_smoke `
        -or $manifest.report_runtime -ne "embedded_headless_worker" `
        -or $manifest.standalone_report_builder_included `
        -or -not $manifest.includes_report_builder `
        -or -not $manifest.report_builder_context_smoke `
        -or -not $manifest.embedded_report_runtime_smoke `
        -or -not $manifest.embedded_report_job_smoke `
        -or -not $manifest.report_gate_contract_smoke `
        -or -not $manifest.report_visual_qc_smoke `
        -or -not $manifest.smoke.ok) {
    throw "Workbench distribution did not pass release smoke gates"
}

$forbiddenStandaloneReportFiles = @(Get-ChildItem -LiteralPath $distRoot -Recurse -File | Where-Object {
    $_.Name -ieq "BridgeReportBuilder.exe" -or
    $_.Name -ieq "MonthlyReportBuilder.exe" -or
    $_.FullName.Replace('\', '/') -match '/reporting/report_gui\.py$'
})
if ($forbiddenStandaloneReportFiles.Count -gt 0) {
    $paths = ($forbiddenStandaloneReportFiles | ForEach-Object FullName) -join "; "
    throw "Workbench distribution contains retired standalone report entrypoints: $paths"
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
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    $forbiddenArchiveEntries = @($archive.Entries | Where-Object {
        $normalizedEntryName = $_.FullName.Replace('\', '/')
        $normalizedEntryName -match '(^|/)BridgeReportBuilder\.exe$' -or
        $normalizedEntryName -match '(^|/)MonthlyReportBuilder\.exe$' -or
        $normalizedEntryName -match '(^|/)reporting/report_gui\.py$'
    })
    if ($forbiddenArchiveEntries.Count -gt 0) {
        $entryNames = ($forbiddenArchiveEntries | ForEach-Object FullName) -join "; "
        throw "Release archive contains retired standalone report entrypoints: $entryNames"
    }
}
finally {
    $archive.Dispose()
}
$archiveHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
"$archiveHash  $assetName" | Set-Content -LiteralPath $checksumPath -Encoding ASCII

$publication = [ordered]@{
    schema_version = 1
    repository = "zjkl19/GuanbingBridgeMonitoring"
    tag = $Version
    archive = $archivePath
    archive_sha256 = $archiveHash
    checksum = $checksumPath
    release_notes = $releaseNotesPath
    publish_command = "gh release create $Version `"$archivePath`" `"$checksumPath`" --verify-tag --title `"$Version`" --notes-file `"$releaseNotesPath`""
}
$publicationPath = Join-Path $resolvedOutput "publish_$Version.json"
$publication | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $publicationPath -Encoding UTF8

Write-Host "GitHub Release assets prepared:"
Write-Host "  $archivePath"
Write-Host "  $checksumPath"
Write-Host "Publication plan: $publicationPath"
