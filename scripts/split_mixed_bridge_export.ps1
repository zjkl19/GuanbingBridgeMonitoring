param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$ZhishanTargetRoot,

    [Parameter(Mandatory = $true)]
    [string]$HongtangTargetRoot,

    [string]$ZhishanConfigPath = "",

    [string[]]$ZhishanIds = @(),

    [string[]]$Months = @("2026-04", "2026-05", "2026-06"),

    [int]$MaxDaysPerMonth = 0,

    [ValidateSet("all", "zhishan", "hongtang")]
    [string]$BridgeFilter = "all",

    [switch]$DryRun,

    [switch]$Overwrite,

    [switch]$CopySidecarsToBoth = $true,

    [switch]$MonthSubfolders,

    [string]$SummaryPath = ""
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

function Read-ZhishanIdsFromConfig {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return @()
    }

    $text = [IO.File]::ReadAllText($Path)
    $matches = [regex]::Matches($text, '"file_id"\s*:\s*"([^"]+)"')
    $ids = New-Object System.Collections.Generic.List[string]
    foreach ($m in $matches) {
        $value = $m.Groups[1].Value.Trim()
        if ($value.Length -gt 0) {
            [void]$ids.Add($value)
        }
    }
    return @($ids | Sort-Object -Unique)
}

function Get-BridgeKeyFromName {
    param(
        [string]$Name,
        [hashtable]$ZhishanSet
    )
    $base = [IO.Path]::GetFileName($Name)
    if ([string]::IsNullOrWhiteSpace($base)) {
        return "sidecar"
    }
    $stem = [IO.Path]::GetFileNameWithoutExtension($base)
    $id = ($stem -split "_", 2)[0]
    if ($ZhishanSet.ContainsKey($id)) {
        return "zhishan"
    }
    return "hongtang"
}

function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Copy-OneFile {
    param(
        [string]$Source,
        [string]$Destination,
        [switch]$DryRun,
        [switch]$Overwrite
    )
    if ((Test-Path -LiteralPath $Destination) -and -not $Overwrite) {
        return "existing"
    }
    if ($DryRun) {
        return "would_copy"
    }
    Ensure-Dir -Path ([IO.Path]::GetDirectoryName($Destination))
    Copy-Item -LiteralPath $Source -Destination $Destination -Force:$Overwrite
    return "copied"
}

function Extract-ZipEntry {
    param(
        [System.IO.Compression.ZipArchiveEntry]$Entry,
        [string]$Destination,
        [switch]$DryRun,
        [switch]$Overwrite
    )
    if ((Test-Path -LiteralPath $Destination) -and -not $Overwrite) {
        return "existing"
    }
    if ($DryRun) {
        return "would_extract"
    }
    Ensure-Dir -Path ([IO.Path]::GetDirectoryName($Destination))
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Destination, $true)
    return "extracted"
}

function Add-StatusCount {
    param(
        [System.Collections.IDictionary]$Summary,
        [string]$Bridge,
        [string]$Status,
        [long]$Bytes
    )
    $key = "${Bridge}_${Status}"
    if (-not $Summary.Contains($key)) {
        $Summary[$key] = 0
    }
    $Summary[$key] = [int64]$Summary[$key] + 1

    $byteKey = "${Bridge}_bytes"
    if (-not $Summary.Contains($byteKey)) {
        $Summary[$byteKey] = 0
    }
    $Summary[$byteKey] = [int64]$Summary[$byteKey] + [int64]$Bytes
}

function Should-ProcessBridge {
    param([string]$Bridge)
    return $BridgeFilter -eq "all" -or $BridgeFilter -eq $Bridge
}

function Get-MonthFolderFromDay {
    param([string]$DayName)
    if ($DayName -match "^(\d{4})-(\d{2})-\d{2}$") {
        $monthNumber = [int]$Matches[2]
        return ("{0}{1}{2}{3}" -f $Matches[1], [char]0x5e74, $monthNumber, [char]0x6708)
    }
    return ""
}

function Resolve-TargetDir {
    param(
        [string]$Bridge,
        [string]$DayName,
        [string]$RelativeSubdir
    )
    $monthFolder = ""
    if ($MonthSubfolders) {
        $monthFolder = Get-MonthFolderFromDay -DayName $DayName
    }

    if ($Bridge -eq "zhishan") {
        $root = $ZhishanTargetRoot
        if (-not [string]::IsNullOrWhiteSpace($monthFolder)) {
            $root = Join-Path $root $monthFolder
        }
        return (Join-Path (Join-Path $root $DayName) $RelativeSubdir)
    }
    $root = $HongtangTargetRoot
    if (-not [string]::IsNullOrWhiteSpace($monthFolder)) {
        $root = Join-Path $root $monthFolder
    }
    return (Join-Path (Join-Path $root $DayName) $RelativeSubdir)
}

$idsFromConfig = @(Read-ZhishanIdsFromConfig -Path $ZhishanConfigPath)
$allIds = @(@($ZhishanIds) + @($idsFromConfig) | Where-Object { $_ } | Sort-Object -Unique)
if ($allIds.Count -eq 0) {
    throw "No Zhishan file ids were provided or found in config: $ZhishanConfigPath"
}

$expandedMonths = New-Object System.Collections.Generic.List[string]
foreach ($monthValue in @($Months)) {
    foreach ($part in ([string]$monthValue -split ",")) {
        $monthText = $part.Trim()
        if ($monthText.Length -gt 0) {
            [void]$expandedMonths.Add($monthText)
        }
    }
}
$Months = @($expandedMonths | Select-Object -Unique)

$zhishanSet = @{}
foreach ($id in $allIds) {
    $zhishanSet[$id] = $true
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$summary = [ordered]@{
    source_root = $SourceRoot
    zhishan_target_root = $ZhishanTargetRoot
    hongtang_target_root = $HongtangTargetRoot
    months = ($Months -join ",")
    max_days_per_month = $MaxDaysPerMonth
    bridge_filter = $BridgeFilter
    dry_run = [bool]$DryRun
    overwrite = [bool]$Overwrite
    month_subfolders = [bool]$MonthSubfolders
    zhishan_id_count = $allIds.Count
    day_count = 0
    zip_count = 0
    source_csv_count = 0
    sidecar_count = 0
    zhishan_copied = 0
    zhishan_extracted = 0
    zhishan_existing = 0
    zhishan_would_copy = 0
    zhishan_would_extract = 0
    zhishan_bytes = 0
    hongtang_copied = 0
    hongtang_extracted = 0
    hongtang_existing = 0
    hongtang_would_copy = 0
    hongtang_would_extract = 0
    hongtang_bytes = 0
    sidecar_copied = 0
    sidecar_existing = 0
    sidecar_would_copy = 0
    sidecar_bytes = 0
    filtered_out = 0
    errors = New-Object System.Collections.Generic.List[string]
}

foreach ($month in $Months) {
    $dayDirs = @(Get-ChildItem -LiteralPath $SourceRoot -Directory -ErrorAction Stop | Where-Object { $_.Name -like "$month-*" } | Sort-Object Name)
    if ($MaxDaysPerMonth -gt 0) {
        $dayDirs = @($dayDirs | Select-Object -First $MaxDaysPerMonth)
    }

    foreach ($day in $dayDirs) {
        $summary.day_count++
        $subDirs = @(Get-ChildItem -LiteralPath $day.FullName -Directory -Recurse -ErrorAction SilentlyContinue)
        if ($subDirs.Count -eq 0) {
            continue
        }

        foreach ($subDir in $subDirs) {
            $relativeSubdir = $subDir.FullName.Substring($day.FullName.Length).TrimStart("\")
            $csvFiles = @(Get-ChildItem -LiteralPath $subDir.FullName -File -Filter "*.csv" -ErrorAction SilentlyContinue)
            $zipFiles = @(Get-ChildItem -LiteralPath $subDir.FullName -File -Filter "*.zip" -ErrorAction SilentlyContinue)
            $sidecars = @(Get-ChildItem -LiteralPath $subDir.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -notin @(".csv", ".zip") })

            foreach ($csv in $csvFiles) {
                $summary.source_csv_count++
                $bridge = Get-BridgeKeyFromName -Name $csv.Name -ZhishanSet $zhishanSet
                if (-not (Should-ProcessBridge -Bridge $bridge)) {
                    $summary.filtered_out++
                    continue
                }
                $dstDir = Resolve-TargetDir -Bridge $bridge -DayName $day.Name -RelativeSubdir $relativeSubdir
                $dst = Join-Path $dstDir $csv.Name
                $status = Copy-OneFile -Source $csv.FullName -Destination $dst -DryRun:$DryRun -Overwrite:$Overwrite
                Add-StatusCount -Summary $summary -Bridge $bridge -Status $status -Bytes $csv.Length
            }

            if ($csvFiles.Count -eq 0) {
                foreach ($zip in $zipFiles) {
                    $summary.zip_count++
                    try {
                        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip.FullName)
                        try {
                            foreach ($entry in $archive.Entries) {
                                if ([string]::IsNullOrWhiteSpace($entry.Name)) {
                                    continue
                                }
                                if (-not $entry.Name.ToLowerInvariant().EndsWith(".csv")) {
                                    continue
                                }
                                $bridge = Get-BridgeKeyFromName -Name $entry.Name -ZhishanSet $zhishanSet
                                if (-not (Should-ProcessBridge -Bridge $bridge)) {
                                    $summary.filtered_out++
                                    continue
                                }
                                $dstDir = Resolve-TargetDir -Bridge $bridge -DayName $day.Name -RelativeSubdir $relativeSubdir
                                $dst = Join-Path $dstDir ([IO.Path]::GetFileName($entry.Name))
                                $status = Extract-ZipEntry -Entry $entry -Destination $dst -DryRun:$DryRun -Overwrite:$Overwrite
                                Add-StatusCount -Summary $summary -Bridge $bridge -Status $status -Bytes $entry.Length
                            }
                        } finally {
                            $archive.Dispose()
                        }
                    } catch {
                        [void]$summary.errors.Add("$($zip.FullName): $($_.Exception.Message)")
                    }
                }
            }

            foreach ($sidecar in $sidecars) {
                $summary.sidecar_count++
                if (-not $CopySidecarsToBoth) {
                    continue
                }
                $sidecarTargets = @("zhishan", "hongtang")
                if ($BridgeFilter -ne "all") {
                    $sidecarTargets = @($BridgeFilter)
                }
                foreach ($bridge in $sidecarTargets) {
                    $dstDir = Resolve-TargetDir -Bridge $bridge -DayName $day.Name -RelativeSubdir $relativeSubdir
                    $dst = Join-Path $dstDir $sidecar.Name
                    $status = Copy-OneFile -Source $sidecar.FullName -Destination $dst -DryRun:$DryRun -Overwrite:$Overwrite
                    Add-StatusCount -Summary $summary -Bridge "sidecar" -Status $status -Bytes $sidecar.Length
                }
            }
        }
    }
}

$json = ([pscustomobject]$summary | ConvertTo-Json -Depth 6)
if (-not [string]::IsNullOrWhiteSpace($SummaryPath)) {
    if (-not $DryRun) {
        Ensure-Dir -Path ([IO.Path]::GetDirectoryName($SummaryPath))
    }
    Set-Content -LiteralPath $SummaryPath -Value $json -Encoding UTF8
}
$json
