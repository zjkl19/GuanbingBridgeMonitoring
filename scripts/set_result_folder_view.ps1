param(
    [Parameter(Mandatory = $false)]
    [string]$RootDir,

    [Parameter(Mandatory = $false)]
    [string[]]$TargetFolders,

    [string[]]$Extensions = @('.jpg', '.emf', '.fig'),

    [int]$ViewMode = 1,
    [int]$IconSize = 96,
    [string]$GroupBy = 'prop:System.ItemTypeText',

    [switch]$CloseNewWindows
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    Write-Host "[folder-view] $Message"
}

function Test-SupportedWindows {
    $isWindowsHost = $true
    if (Get-Variable -Name IsWindows -Scope Global -ErrorAction SilentlyContinue) {
        $isWindowsHost = [bool]$Global:IsWindows
    } else {
        $isWindowsHost = ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT)
    }
    if (-not $isWindowsHost) {
        return $false
    }
    $version = [Environment]::OSVersion.Version
    return ($version.Major -ge 10)
}

function Normalize-PathText {
    param([string]$PathText)
    if ([string]::IsNullOrWhiteSpace($PathText)) {
        return $null
    }
    try {
        return [System.IO.Path]::GetFullPath($PathText.Trim())
    } catch {
        return $PathText.Trim()
    }
}

function Get-TargetFolderList {
    param(
        [string]$Root,
        [string[]]$Folders,
        [string[]]$Exts
    )

    $folderSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($folder in ($Folders | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $norm = Normalize-PathText $folder
        if ($norm -and (Test-Path -LiteralPath $norm -PathType Container)) {
            [void]$folderSet.Add($norm)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Root)) {
        $rootNorm = Normalize-PathText $Root
        if (-not (Test-Path -LiteralPath $rootNorm -PathType Container)) {
            throw "RootDir not found: $Root"
        }

        $extSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($ext in $Exts) {
            if ([string]::IsNullOrWhiteSpace($ext)) { continue }
            $trimmed = $ext.Trim()
            if (-not $trimmed.StartsWith('.')) {
                $trimmed = ".$trimmed"
            }
            [void]$extSet.Add($trimmed)
        }

        Get-ChildItem -LiteralPath $rootNorm -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $extSet.Contains($_.Extension) } |
            ForEach-Object {
                [void]$folderSet.Add($_.DirectoryName)
            }
    }

    return @($folderSet | Sort-Object)
}

function Get-ExplorerWindowForFolder {
    param(
        $ShellApp,
        [string]$FolderPath
    )

    foreach ($window in $ShellApp.Windows()) {
        try {
            $doc = $window.Document
            if ($null -eq $doc -or $null -eq $doc.Folder -or $null -eq $doc.Folder.Self) {
                continue
            }
            $winPath = Normalize-PathText $doc.Folder.Self.Path
            if ($winPath -and $winPath.Equals($FolderPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $window
            }
        } catch {
            continue
        }
    }
    return $null
}

function Wait-ExplorerWindow {
    param(
        $ShellApp,
        [string]$FolderPath,
        [int]$TimeoutMs = 5000
    )

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    do {
        $window = Get-ExplorerWindowForFolder -ShellApp $ShellApp -FolderPath $FolderPath
        if ($null -ne $window) {
            return $window
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Apply-FolderView {
    param(
        $Window,
        [int]$Mode,
        [int]$Size,
        [string]$GroupExpr
    )

    $doc = $Window.Document
    $doc.CurrentViewMode = [uint32]$Mode
    $doc.IconSize = $Size
    try {
        $doc.GroupBy = $GroupExpr
    } catch {
        if ($GroupExpr -ne 'System.ItemTypeText') {
            $doc.GroupBy = 'System.ItemTypeText'
        } else {
            throw
        }
    }
}

if (-not (Test-SupportedWindows)) {
    Write-Log 'Skipped: only supported on Windows 10/11.'
    exit 0
}

$folders = Get-TargetFolderList -Root $RootDir -Folders $TargetFolders -Exts $Extensions
if (-not $folders -or $folders.Count -eq 0) {
    Write-Log 'No folders containing target image files were found.'
    exit 0
}

$shell = New-Object -ComObject Shell.Application
$configured = 0

foreach ($folderPath in $folders) {
    try {
        $existingWindow = Get-ExplorerWindowForFolder -ShellApp $shell -FolderPath $folderPath
        $openedHere = $false
        $window = $existingWindow

        if ($null -eq $window) {
            $shell.Open($folderPath)
            $window = Wait-ExplorerWindow -ShellApp $shell -FolderPath $folderPath
            $openedHere = $true
        }

        if ($null -eq $window) {
            Write-Log "Skipped: failed to open Explorer window for $folderPath"
            continue
        }

        Apply-FolderView -Window $window -Mode $ViewMode -Size $IconSize -GroupExpr $GroupBy
        $configured += 1
        Write-Log "Configured: $folderPath"

        if ($openedHere -and $CloseNewWindows.IsPresent) {
            Start-Sleep -Milliseconds 300
            $window.Quit()
        }
    } catch {
        Write-Log ("Failed: {0} :: {1}" -f $folderPath, $_.Exception.Message)
    }
}

Write-Log "Done. Configured $configured folder(s)."
