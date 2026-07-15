param(
    [string]$Version = "",
    [string]$OutputDir = "release\workbench",
    [switch]$SkipBuild,
    [switch]$AllowDevelopmentVersion
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Bytes)
        return (-join ($hash | ForEach-Object { $_.ToString("x2") }))
    }
    finally {
        $sha.Dispose()
    }
}

function Get-StreamSha256([System.IO.Stream]$Stream) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($Stream)
        return (-join ($hash | ForEach-Object { $_.ToString("x2") }))
    }
    finally {
        $sha.Dispose()
    }
}

function Get-StrictString($Value, [string]$Name, [bool]$AllowEmpty = $false) {
    if ($Value -isnot [string]) {
        throw "$Name must be a string"
    }
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value)) {
        throw "$Name must not be empty"
    }
    return $Value
}

function ConvertTo-SafeRelativePath($Value) {
    $Value = Get-StrictString $Value "Relative package path"
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Unsafe relative package path: $Value"
    }
    $normalized = $Value.Replace('\', '/')
    $segments = @($normalized -split '/')
    if ([string]::IsNullOrWhiteSpace($normalized) `
            -or [System.IO.Path]::IsPathRooted($normalized) `
            -or $segments -contains '..' `
            -or $segments -contains '.' `
            -or $segments -contains '' `
            -or $normalized -match '[:\x00-\x1f]') {
        throw "Unsafe relative package path: $Value"
    }
    foreach ($segment in $segments) {
        if ($segment.TrimEnd([char[]]@(' ', '.')) -ne $segment) {
            throw "Unsafe relative package path: $Value"
        }
    }
    return $normalized
}

function Test-IsIntegerValue($Value) {
    return ($Value -is [byte] `
        -or $Value -is [sbyte] `
        -or $Value -is [int16] `
        -or $Value -is [uint16] `
        -or $Value -is [int32] `
        -or $Value -is [uint32] `
        -or $Value -is [int64] `
        -or $Value -is [uint64])
}

function Get-StrictInt64($Value, [string]$Name, [int64]$Minimum = 0) {
    if (-not (Test-IsIntegerValue $Value)) {
        throw "$Name must be an integer"
    }
    try {
        $converted = [int64]$Value
    }
    catch {
        throw "$Name is outside the supported integer range"
    }
    if ($converted -lt $Minimum) {
        throw "$Name must be at least $Minimum"
    }
    return $converted
}

function Assert-ExactBoolean($Value, [bool]$Expected, [string]$Name) {
    if ($Value -isnot [bool] -or $Value -ne $Expected) {
        throw "$Name must be the Boolean value $Expected"
    }
}

function Assert-OperatorGuideContract([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Operator guide not found: $Path"
    }
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $requiredFragments = @(
        (-join (39044, 29983, 25104, 20998, 26512, 32531, 23384 | ForEach-Object { [char]$_ })),
        (-join (25171, 24320, 26354, 32447, 39044, 35272, 24182, 25302, 32447, 35774, 32622 | ForEach-Object { [char]$_ })),
        (-join (25302, 32447, 35774, 32622, 19978, 19979, 38480 | ForEach-Object { [char]$_ })),
        (-join (19979, 20391, 26694, 36873, 21462, 26694, 20013, 23454, 38469, 26377, 38480, 26679, 26412, 30340, 26368, 39640, 20540 | ForEach-Object { [char]$_ })),
        (-join (19978, 20391, 26694, 36873, 21462, 26694, 20013, 23454, 38469, 26377, 38480, 26679, 26412, 30340, 26368, 20302, 20540 | ForEach-Object { [char]$_ })),
        (-join (21024, 38500, 20005, 26684, 20302, 20110, 35813, 20540, 30340, 25968, 25454 | ForEach-Object { [char]$_ })),
        (-join (21024, 38500, 20005, 26684, 39640, 20110, 35813, 20540, 30340, 25968, 25454 | ForEach-Object { [char]$_ })),
        (-join (31561, 20110, 20505, 36873, 38408, 20540, 30340, 28857, 20445, 30041 | ForEach-Object { [char]$_ }))
    )
    foreach ($fragment in $requiredFragments) {
        if (-not $content.Contains($fragment)) {
            throw "Operator guide is missing required user workflow text: $Path"
        }
    }
}

function Get-NormalizedSha256($Value, [string]$Name) {
    $Value = Get-StrictString $Value $Name
    if ($Value -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "$Name must be a SHA-256 digest"
    }
    return $Value.ToLowerInvariant()
}

function Assert-NoReparsePointInExistingPath([string]$Path, [string]$Name) {
    $current = [System.IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Name contains a reparse point: $current"
            }
        }
        $parent = [System.IO.Directory]::GetParent($current)
        if ($null -eq $parent -or $parent.FullName -eq $current) {
            break
        }
        $current = $parent.FullName
    }
}

function Assert-NoUnsafeFilesystemPathSegments([string]$Path, [string]$Name) {
    foreach ($segment in @($Path -split '[\\/]')) {
        if ([string]::IsNullOrEmpty($segment)) {
            continue
        }
        if ($segment.TrimEnd([char[]]@(' ', '.')) -ne $segment) {
            throw "$Name contains a segment ending in a space or dot: $segment"
        }
    }
}

function Assert-OutputOutsideDistribution([string]$OutputPath, [string]$DistributionPath) {
    $outputCanonical = [System.IO.Path]::GetFullPath($OutputPath).TrimEnd([char[]]@('\', '/'))
    $distCanonical = [System.IO.Path]::GetFullPath($DistributionPath).TrimEnd([char[]]@('\', '/'))
    $distPrefix = $distCanonical + [System.IO.Path]::DirectorySeparatorChar
    if ($outputCanonical.Equals($distCanonical, [System.StringComparison]::OrdinalIgnoreCase) `
            -or $outputCanonical.StartsWith(
                $distPrefix,
                [System.StringComparison]::OrdinalIgnoreCase
            )) {
        throw "Release output directory must be outside the workbench distribution"
    }
}

function Publish-VerifiedFileSet([object[]]$Items) {
    $records = @()
    foreach ($item in $Items) {
        if (-not (Test-Path -LiteralPath $item.temporary -PathType Leaf)) {
            throw "Verified temporary publication file is missing: $($item.temporary)"
        }
        if (Test-Path -LiteralPath $item.destination) {
            $destinationItem = Get-Item -LiteralPath $item.destination -Force
            if ($destinationItem.PSIsContainer) {
                throw "Publication destination is a directory: $($item.destination)"
            }
            if (($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Publication destination is a reparse point: $($item.destination)"
            }
        }
        $destinationExists = Test-Path -LiteralPath $item.destination -PathType Leaf
        $records += [pscustomobject]@{
            temporary = [string]$item.temporary
            destination = [string]$item.destination
            existed = [bool]$destinationExists
            backup = if ($destinationExists) {
                "$($item.destination).__previous_$([guid]::NewGuid().ToString('N'))"
            }
            else {
                $null
            }
            published = $false
        }
    }

    $publicationSucceeded = $false
    $rollbackSucceeded = $true
    try {
        foreach ($record in $records) {
            if ($record.existed) {
                [System.IO.File]::Replace(
                    $record.temporary,
                    $record.destination,
                    $record.backup,
                    $true
                )
            }
            else {
                [System.IO.File]::Move($record.temporary, $record.destination)
            }
            $record.published = $true
        }
        $publicationSucceeded = $true
    }
    catch {
        for ($index = $records.Count - 1; $index -ge 0; $index -= 1) {
            $record = $records[$index]
            if (-not $record.published) {
                continue
            }
            try {
                if ($record.existed -and (Test-Path -LiteralPath $record.backup -PathType Leaf)) {
                    if (Test-Path -LiteralPath $record.destination -PathType Leaf) {
                        $failedPublicationBackup = `
                            "$($record.destination).__failed_$([guid]::NewGuid().ToString('N'))"
                        [System.IO.File]::Replace(
                            $record.backup,
                            $record.destination,
                            $failedPublicationBackup,
                            $true
                        )
                        if (Test-Path -LiteralPath $failedPublicationBackup) {
                            Remove-Item -LiteralPath $failedPublicationBackup -Force `
                                -ErrorAction SilentlyContinue
                        }
                    }
                    else {
                        [System.IO.File]::Move($record.backup, $record.destination)
                    }
                }
                elseif (-not $record.existed -and (Test-Path -LiteralPath $record.destination)) {
                    Remove-Item -LiteralPath $record.destination -Force
                }
            }
            catch {
                $rollbackSucceeded = $false
                Write-Warning "Failed to roll back publication file $($record.destination): $($_.Exception.Message)"
            }
        }
        throw
    }
    finally {
        if ($publicationSucceeded -or $rollbackSucceeded) {
            foreach ($record in $records) {
                if ($record.backup -and (Test-Path -LiteralPath $record.backup)) {
                    Remove-Item -LiteralPath $record.backup -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repo

if (-not $Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $repo "VERSION") -Raw -Encoding UTF8).Trim()
}
if ($Version -notmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$') {
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
Assert-NoReparsePointInExistingPath $distRoot "Workbench distribution path"
$operatorGuideName = (-join (20351, 29992, 35828, 26126 | ForEach-Object { [char]$_ })) + ".md"
Assert-OperatorGuideContract -Path (Join-Path $distRoot $operatorGuideName)
$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$manifestHash = Get-BytesSha256 $manifestBytes
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
$manifestText = $strictUtf8.GetString($manifestBytes)
if ($manifestText.Length -gt 0 -and [int][char]$manifestText[0] -eq 0xFEFF) {
    $manifestText = $manifestText.Substring(1)
}
$manifest = $manifestText | ConvertFrom-Json
if ((Get-StrictInt64 $manifest.schema_version "manifest.schema_version") -ne 3) {
    throw "Workbench release manifest schema must be exactly 3"
}
if ((Get-StrictString $manifest.version "manifest.version") -cne $Version) {
    throw "VERSION and release manifest differ: $Version vs $($manifest.version)"
}

$requiredTrueManifestFields = @(
    "auto_threshold_preview_runner_smoke",
    "analysis_runner_failure_exit_smoke",
    "installed_profile_matrix_smoke",
    "invalid_cli_smoke",
    "task_history_smoke",
    "native_screenshot_smoke",
    "native_focus_smoke",
    "native_dpi_smoke",
    "native_font_smoke",
    "native_icon_smoke",
    "operator_feature_contract_smoke",
    "includes_analysis_runner",
    "includes_report_builder",
    "report_builder_context_smoke",
    "embedded_report_runtime_smoke",
    "embedded_report_job_smoke",
    "report_gate_contract_smoke",
    "report_visual_qc_smoke"
)
foreach ($fieldName in $requiredTrueManifestFields) {
    $property = $manifest.PSObject.Properties[$fieldName]
    if ($null -eq $property) {
        throw "Workbench release manifest is missing $fieldName"
    }
    Assert-ExactBoolean $property.Value $true "manifest.$fieldName"
}
Assert-ExactBoolean $manifest.standalone_report_builder_included $false `
    "manifest.standalone_report_builder_included"
if ((Get-StrictString $manifest.screenshot_mode "manifest.screenshot_mode") `
        -cne "native_windows" `
        -or (Get-StrictString $manifest.report_runtime "manifest.report_runtime") `
        -cne "embedded_headless_worker") {
    throw "Workbench distribution did not pass its native screenshot/report runtime gates"
}
$nativeGui = $manifest.native_gui_acceptance
if ($null -eq $nativeGui) {
    throw "Workbench release manifest is missing native_gui_acceptance evidence"
}
foreach ($fieldName in @(
        "foreground_window_matches",
        "focus_owned_by_process",
        "native_window_icon"
    )) {
    $property = $nativeGui.PSObject.Properties[$fieldName]
    if ($null -eq $property) {
        throw "Native GUI acceptance evidence is missing $fieldName"
    }
    Assert-ExactBoolean $property.Value $true "manifest.native_gui_acceptance.$fieldName"
}
if ((Get-StrictInt64 $nativeGui.dpi_awareness_code `
        "manifest.native_gui_acceptance.dpi_awareness_code") -ne 2 `
        -or (Get-StrictInt64 $nativeGui.window_dpi `
            "manifest.native_gui_acceptance.window_dpi") -lt 96 `
        -or (Get-StrictInt64 $nativeGui.physical_width `
            "manifest.native_gui_acceptance.physical_width") -lt 1000 `
        -or (Get-StrictInt64 $nativeGui.physical_height `
            "manifest.native_gui_acceptance.physical_height") -lt 700) {
    throw "Workbench native GUI acceptance evidence is incomplete"
}
if ((Get-StrictInt64 $manifest.operator_feature_contract_version `
        "manifest.operator_feature_contract_version" 1) -lt 2) {
    throw "Workbench operator feature contract is missing"
}

$manifestInventoryCount = Get-StrictInt64 $manifest.file_inventory_count `
    "manifest.file_inventory_count"
$manifestFileCount = Get-StrictInt64 $manifest.file_count_excluding_manifest `
    "manifest.file_count_excluding_manifest"
$manifestTotalBytes = Get-StrictInt64 $manifest.total_bytes_excluding_manifest `
    "manifest.total_bytes_excluding_manifest"
if ($manifestInventoryCount -ne $manifestFileCount) {
    throw "Workbench distribution has no closed file inventory"
}
$distVersionPath = Join-Path $distRoot "VERSION"
$smokePath = Join-Path $distRoot "workbench_smoke.json"
if (-not (Test-Path -LiteralPath $distVersionPath -PathType Leaf) `
        -or -not (Test-Path -LiteralPath $smokePath -PathType Leaf)) {
    throw "Workbench distribution is missing its VERSION or smoke result"
}
$distVersion = (Get-Content -LiteralPath $distVersionPath -Raw -Encoding UTF8).Trim()
$smokeResult = Get-Content -LiteralPath $smokePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($distVersion -ne $Version `
        -or (Get-StrictString $manifest.smoke.version "manifest.smoke.version") -ne $Version `
        -or (Get-StrictString $smokeResult.version "smoke.version") -ne $Version) {
    throw "Workbench distribution contains inconsistent version records"
}
$manifestSmokeJson = $manifest.smoke | ConvertTo-Json -Depth 100 -Compress
$standaloneSmokeJson = $smokeResult | ConvertTo-Json -Depth 100 -Compress
if ($manifestSmokeJson -cne $standaloneSmokeJson) {
    throw "Embedded manifest smoke result differs from workbench_smoke.json"
}
foreach ($fieldName in @(
        "ok",
        "manual_threshold_controls_available",
        "threshold_band_control_available",
        "lower_box_threshold_control_available",
        "upper_box_threshold_control_available",
        "offset_effective_range_seconds_available",
        "unzip_settings_available"
    )) {
    $property = $smokeResult.PSObject.Properties[$fieldName]
    if ($null -eq $property) {
        throw "Workbench smoke result is missing $fieldName"
    }
    Assert-ExactBoolean $property.Value $true "smoke.$fieldName"
}
if ((Get-StrictInt64 $smokeResult.config_tab_count "smoke.config_tab_count") -ne 9 `
        -or (Get-StrictInt64 $smokeResult.gap_override_column_count `
            "smoke.gap_override_column_count") -ne 6) {
    throw "Workbench smoke result has an invalid operator feature shape"
}

# Recompute the complete dist inventory immediately before compression. This
# prevents a file changed after build from being packaged under stale hashes.
$expectedInventory = @($manifest.file_inventory)
if ($expectedInventory.Count -ne $manifestInventoryCount) {
    throw "Workbench manifest inventory count does not match its entries"
}
$expectedByPath = @{}
$expectedTotalBytes = [int64]0
foreach ($entry in $expectedInventory) {
    $relative = ConvertTo-SafeRelativePath $entry.path
    if ($relative -ieq "release_manifest.json" `
            -or $expectedByPath.ContainsKey($relative)) {
        throw "Workbench manifest contains an unsafe or duplicate path: $relative"
    }
    $expectedBytes = Get-StrictInt64 $entry.bytes "inventory[$relative].bytes"
    $expectedHash = Get-NormalizedSha256 $entry.sha256 `
        "inventory[$relative].sha256"
    $path = Join-Path $distRoot ($relative.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Workbench manifest file is missing before packaging: $relative"
    }
    $item = Get-Item -LiteralPath $path
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Workbench manifest file is a reparse point: $relative"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ([int64]$item.Length -ne $expectedBytes `
            -or $actualHash -ne $expectedHash) {
        throw "Workbench manifest file changed before packaging: $relative"
    }
    $expectedByPath[$relative] = [pscustomobject]@{
        path = $path
        bytes = $expectedBytes
        sha256 = $expectedHash
    }
    $expectedTotalBytes += [int64]$item.Length
}
$allDistItems = @(Get-ChildItem -LiteralPath $distRoot -Recurse -Force)
$reparseItems = @($allDistItems | Where-Object {
    ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
})
if ($reparseItems.Count -gt 0) {
    $paths = ($reparseItems | ForEach-Object FullName) -join "; "
    throw "Workbench distribution contains reparse points: $paths"
}
$actualFiles = @($allDistItems | Where-Object {
    -not $_.PSIsContainer `
        -and -not $_.FullName.Equals($manifestPath, [System.StringComparison]::OrdinalIgnoreCase)
})
$actualPaths = @($actualFiles | ForEach-Object {
    ConvertTo-SafeRelativePath `
        ($_.FullName.Substring($distRoot.Length).TrimStart([char[]]'\/').Replace('\', '/'))
})
$extraPaths = @($actualPaths | Where-Object { -not $expectedByPath.ContainsKey($_) })
if ($actualFiles.Count -ne $manifestFileCount `
        -or $extraPaths.Count -gt 0 `
        -or $expectedTotalBytes -ne $manifestTotalBytes) {
    throw "Workbench dist inventory is not closed immediately before packaging"
}
$executableRelative = ConvertTo-SafeRelativePath $manifest.executable
if (-not $expectedByPath.ContainsKey($executableRelative)) {
    throw "Workbench executable is not bound by the manifest inventory"
}
$manifestExeHash = Get-NormalizedSha256 $manifest.executable_sha256 `
    "manifest.executable_sha256"
$executableInventory = $expectedByPath[$executableRelative]
if ($executableInventory.sha256 -ne $manifestExeHash) {
    throw "Workbench executable hash differs between manifest fields"
}
$exePath = $executableInventory.path
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Verified workbench executable is missing: $exePath"
}

$forbiddenStandaloneReportFiles = @($actualFiles | Where-Object {
    $_.Name -ieq "BridgeReportBuilder.exe" -or
    $_.Name -ieq "MonthlyReportBuilder.exe" -or
    $_.FullName.Replace('\', '/') -match '/reporting/report_gui\.py$'
})
if ($forbiddenStandaloneReportFiles.Count -gt 0) {
    $paths = ($forbiddenStandaloneReportFiles | ForEach-Object FullName) -join "; "
    throw "Workbench distribution contains retired standalone report entrypoints: $paths"
}

$outputCandidate = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $OutputDir
}
else {
    Join-Path $repo $OutputDir
}
Assert-NoUnsafeFilesystemPathSegments $outputCandidate "Release output path"
$resolvedOutput = [System.IO.Path]::GetFullPath($outputCandidate)
Assert-OutputOutsideDistribution $resolvedOutput $distRoot
if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
    throw "Release output path is a file, not a directory: $resolvedOutput"
}
Assert-NoReparsePointInExistingPath $resolvedOutput "Release output path"
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
Assert-NoReparsePointInExistingPath $resolvedOutput "Release output path"
$resolvedOutput = (Get-Item -LiteralPath $resolvedOutput -Force).FullName
Assert-OutputOutsideDistribution $resolvedOutput $distRoot
$assetName = "BridgeMonitoringWorkbench-$Version-win-x64.zip"
$archivePath = Join-Path $resolvedOutput $assetName
$checksumPath = "$archivePath.sha256"
$publicationPath = Join-Path $resolvedOutput "publish_$Version.json"
$operationId = [guid]::NewGuid().ToString("N")
$temporaryArchivePath = Join-Path $resolvedOutput ".$assetName.$operationId.tmp"
$temporaryChecksumPath = Join-Path $resolvedOutput ".$assetName.sha256.$operationId.tmp"
$temporaryPublicationPath = Join-Path $resolvedOutput ".publish_$Version.$operationId.tmp"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$packageLockPath = Join-Path $resolvedOutput ".workbench_release_package.lock"
if (Test-Path -LiteralPath $packageLockPath) {
    $lockItem = Get-Item -LiteralPath $packageLockPath -Force
    if ($lockItem.PSIsContainer `
            -or ($lockItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Release package lock path is not a regular file: $packageLockPath"
    }
}
try {
    $packageLockStream = [System.IO.File]::Open(
        $packageLockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
}
catch {
    throw "Another workbench release packaging process is using $resolvedOutput"
}
try {
    $expectedArchiveByPath = @{}
    $archiveStream = [System.IO.File]::Open(
        $temporaryArchivePath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    try {
        $zip = [System.IO.Compression.ZipArchive]::new(
            $archiveStream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $true,
            [System.Text.Encoding]::UTF8
        )
        try {
            foreach ($pair in @($expectedByPath.GetEnumerator() | Sort-Object Name)) {
                $relative = [string]$pair.Key
                $archiveEntryPath = "BridgeMonitoringWorkbench/$relative"
                $source = $pair.Value
                $entry = $zip.CreateEntry(
                    $archiveEntryPath,
                    [System.IO.Compression.CompressionLevel]::Optimal
                )
                $sourceStream = [System.IO.File]::Open(
                    $source.path,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::Read
                )
                try {
                    $entryStream = $entry.Open()
                    try {
                        $sourceStream.CopyTo($entryStream)
                    }
                    finally {
                        $entryStream.Dispose()
                    }
                }
                finally {
                    $sourceStream.Dispose()
                }
                $expectedArchiveByPath[$archiveEntryPath] = [pscustomobject]@{
                    bytes = [int64]$source.bytes
                    sha256 = [string]$source.sha256
                }
            }

            $manifestEntryPath = "BridgeMonitoringWorkbench/release_manifest.json"
            $manifestEntry = $zip.CreateEntry(
                $manifestEntryPath,
                [System.IO.Compression.CompressionLevel]::Optimal
            )
            $manifestEntryStream = $manifestEntry.Open()
            try {
                $manifestEntryStream.Write($manifestBytes, 0, $manifestBytes.Length)
            }
            finally {
                $manifestEntryStream.Dispose()
            }
            $expectedArchiveByPath[$manifestEntryPath] = [pscustomobject]@{
                bytes = [int64]$manifestBytes.Length
                sha256 = $manifestHash
            }
        }
        finally {
            $zip.Dispose()
        }
    }
    finally {
        $archiveStream.Dispose()
    }

    $verificationStream = [System.IO.File]::Open(
        $temporaryArchivePath,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read
    )
    try {
        $archive = [System.IO.Compression.ZipArchive]::new(
            $verificationStream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $true,
            [System.Text.Encoding]::UTF8
        )
        try {
            $seenArchivePaths = @{}
            foreach ($entry in $archive.Entries) {
                if ([string]::IsNullOrEmpty($entry.Name)) {
                    throw "Release archive contains an unexpected directory entry: $($entry.FullName)"
                }
                $normalizedEntryName = ConvertTo-SafeRelativePath `
                    ($entry.FullName.Replace('\', '/'))
                if ($seenArchivePaths.ContainsKey($normalizedEntryName)) {
                    throw "Release archive contains duplicate entries: $normalizedEntryName"
                }
                if (-not $expectedArchiveByPath.ContainsKey($normalizedEntryName)) {
                    throw "Release archive contains an unexpected file: $normalizedEntryName"
                }
                $seenArchivePaths[$normalizedEntryName] = $true
                $expectedEntry = $expectedArchiveByPath[$normalizedEntryName]
                $entryStream = $entry.Open()
                try {
                    $entryHash = Get-StreamSha256 $entryStream
                }
                finally {
                    $entryStream.Dispose()
                }
                if ([int64]$entry.Length -ne [int64]$expectedEntry.bytes `
                        -or $entryHash -ne [string]$expectedEntry.sha256) {
                    throw "Release archive entry failed size/SHA verification: $normalizedEntryName"
                }
            }
            $missingArchivePaths = @($expectedArchiveByPath.Keys | Where-Object {
                -not $seenArchivePaths.ContainsKey($_)
            })
            if ($seenArchivePaths.Count -ne $expectedArchiveByPath.Count `
                    -or $missingArchivePaths.Count -gt 0) {
                throw "Release archive file inventory is incomplete"
            }
        }
        finally {
            $archive.Dispose()
        }
        $verificationStream.Position = 0
        $archiveHash = Get-StreamSha256 $verificationStream
    }
    finally {
        $verificationStream.Dispose()
    }

    $ascii = New-Object System.Text.ASCIIEncoding
    [System.IO.File]::WriteAllText(
        $temporaryChecksumPath,
        "$archiveHash  $assetName`r`n",
        $ascii
    )

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
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText(
        $temporaryPublicationPath,
        ($publication | ConvertTo-Json -Depth 5),
        $utf8NoBom
    )

    # Nothing is published until the archive itself, its full contents, the
    # checksum and publication plan have all been created successfully.
    Publish-VerifiedFileSet @(
        [pscustomobject]@{ temporary = $temporaryArchivePath; destination = $archivePath },
        [pscustomobject]@{ temporary = $temporaryChecksumPath; destination = $checksumPath },
        [pscustomobject]@{ temporary = $temporaryPublicationPath; destination = $publicationPath }
    )
}
finally {
    foreach ($temporaryPath in @(
            $temporaryArchivePath,
            $temporaryChecksumPath,
            $temporaryPublicationPath
        )) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    $packageLockStream.Dispose()
    Remove-Item -LiteralPath $packageLockPath -Force -ErrorAction SilentlyContinue
}

Write-Host "GitHub Release assets prepared:"
Write-Host "  $archivePath"
Write-Host "  $checksumPath"
Write-Host "Publication plan: $publicationPath"
