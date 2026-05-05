param(
    [switch]$Apply,
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$plan = New-Object System.Collections.Generic.List[object]

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
    $plan.Add([pscustomobject]@{
        path = $resolved
        action = if ($Apply) { "removed" } else { "would_remove" }
    }) | Out-Null
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

if (-not [System.String]::IsNullOrWhiteSpace($ReportPath)) {
    if ([System.IO.Path]::IsPathRooted($ReportPath)) {
        $reportFullPath = [System.IO.Path]::GetFullPath($ReportPath)
    } else {
        $reportFullPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $ReportPath))
    }
    if (-not $reportFullPath.StartsWith($RepoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write cleanup report outside repo: $reportFullPath"
    }
    $reportDir = Split-Path -Parent $reportFullPath
    if (-not [System.String]::IsNullOrWhiteSpace($reportDir)) {
        New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
    }
    [pscustomobject]@{
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        repo_root = $RepoRoot
        apply = [bool]$Apply
        item_count = $plan.Count
        items = $plan
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportFullPath -Encoding UTF8
    Write-Host "Cleanup report written: $reportFullPath"
}
