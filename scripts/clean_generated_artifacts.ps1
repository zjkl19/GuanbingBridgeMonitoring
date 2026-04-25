param(
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

$targets = @(
    "output",
    "tmp",
    "run_logs",
    "reports\__tmp_period_clean"
)

$patterns = @(
    "config\*_backup_*.json",
    "reports\*_自动生成_*.docx",
    "reports\*_backup_*.xlsx",
    "reports\period_template*_auto_clean.docx",
    "reporting\__pycache__",
    "reporting\*.pyc"
)

function Remove-IfRequested {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if (-not $resolved.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean outside repo: $resolved"
    }
    if ($Apply) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
        Write-Host "[removed] $resolved"
    } else {
        Write-Host "[would remove] $resolved"
    }
}

function Get-RelativePath {
    param([string]$BasePath, [string]$FullPath)
    $baseUri = [System.Uri](([System.IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'))
    $fullUri = [System.Uri]([System.IO.Path]::GetFullPath($FullPath))
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString()).Replace('/', '\')
}

foreach ($target in $targets) {
    Remove-IfRequested (Join-Path $RepoRoot $target)
}

foreach ($pattern in $patterns) {
    Get-ChildItem -Path $RepoRoot -Filter (Split-Path $pattern -Leaf) -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.FullName.StartsWith((Join-Path $RepoRoot "reporting\.venv"), [System.StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
            if ($_.FullName.StartsWith((Join-Path $RepoRoot ".git"), [System.StringComparison]::OrdinalIgnoreCase)) {
                return $false
            }
            $relative = Get-RelativePath $RepoRoot $_.FullName
            $relative -like $pattern
        } |
        ForEach-Object { Remove-IfRequested $_.FullName }
}

if (-not $Apply) {
    Write-Host "Dry run only. Re-run with -Apply to remove these generated artifacts."
}
