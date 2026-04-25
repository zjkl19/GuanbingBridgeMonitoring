param(
    [string]$PythonExe = "reporting\.venv\Scripts\python.exe",
    [string]$OutputDir = "archive",
    [switch]$AllowDirty,
    [switch]$SkipTests,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host "[PACKAGE] $Message" -ForegroundColor Cyan
}

function Assert-PathExists {
    param(
        [string]$Path,
        [string]$Message
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw $Message
    }
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

Assert-PathExists -Path $PythonExe -Message "Python executable not found: $PythonExe"

$dirty = (& git status --porcelain) -join "`n"
if ($dirty -and -not $AllowDirty) {
    throw "Git worktree is not clean. Commit/stash changes first, or rerun with -AllowDirty for a local test package."
}

$reportGui = Get-Content -LiteralPath "reporting\report_gui.py" -Raw -Encoding UTF8
if ($reportGui -notmatch 'APP_VERSION\s*=\s*"(?<version>v[^"]+)"') {
    throw "Unable to read APP_VERSION from reporting\report_gui.py"
}
$version = $Matches["version"]
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$builtAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$commit = (& git rev-parse --short HEAD).Trim()
$branch = (& git rev-parse --abbrev-ref HEAD).Trim()
$tags = @(& git tag --points-at HEAD) | Where-Object { $_ }
$tagText = if ($tags.Count -gt 0) { $tags -join ", " } else { "(none)" }

Write-Step "Version: $version"
Write-Step "Commit: $commit"
Write-Step "Branch: $branch"
Write-Step "Tags: $tagText"

if (-not $SkipTests) {
    Write-Step "Running Python unit tests..."
    & $PythonExe -m unittest discover -s tests_py -v
    if ($LASTEXITCODE -ne 0) {
        throw "Python unit tests failed."
    }

    Write-Step "Running report smoke precheck..."
    & $PythonExe "reporting\smoke_report_generation.py" --kind all
    if ($LASTEXITCODE -ne 0) {
        throw "Report smoke precheck failed."
    }
}

if (-not $SkipBuild) {
    Write-Step "Building BridgeReportBuilder..."
    & powershell -ExecutionPolicy Bypass -File "reporting\build_gui_exe.ps1" -PythonExe $PythonExe
    if ($LASTEXITCODE -ne 0) {
        throw "BridgeReportBuilder build failed."
    }
}

$distRoot = "reporting\dist\BridgeReportBuilder"
Assert-PathExists -Path $distRoot -Message "Dist directory not found: $distRoot"

$requiredPaths = @(
    "BridgeReportBuilder.exe",
    "_internal",
    "README.md",
    "REPORTING_LOGIC.md",
    "reports\README.md"
)

$trackedReportFiles = @(& git -c core.quotepath=false ls-files -- "reports/*.docx")
if ($trackedReportFiles.Count -lt 3) {
    throw "Expected at least 3 tracked report templates, found $($trackedReportFiles.Count)."
}

foreach ($rel in $trackedReportFiles) {
    $requiredPaths += ($rel -replace '/', '\')
}

foreach ($rel in $requiredPaths) {
    Assert-PathExists -Path (Join-Path $distRoot $rel) -Message "Package content missing: $rel"
}

$versionPath = Join-Path $distRoot "VERSION.txt"
$templateLines = @()
foreach ($rel in $trackedReportFiles) {
    $distTemplate = Join-Path $distRoot ($rel -replace '/', '\')
    $item = Get-Item -LiteralPath $distTemplate
    $templateLines += "- $rel ($($item.Length) bytes)"
}

$versionText = @"
BridgeReportBuilder Release
===========================
GUI version: $version
Git branch: $branch
Git commit: $commit
Git tags: $tagText
Built at: $builtAt
Builder: scripts\package_report_builder.ps1

Validation
----------
Python unit tests: $(if ($SkipTests) { "skipped" } else { "passed" })
Report smoke precheck: $(if ($SkipTests) { "skipped" } else { "passed" })
Exe build: $(if ($SkipBuild) { "skipped" } else { "passed" })

Included report templates
-------------------------
$($templateLines -join "`n")

Production update notes
-----------------------
1. Extract this package as a complete BridgeReportBuilder directory.
2. Keep BridgeReportBuilder.exe and _internal together.
3. Do not overwrite production config unless explicitly intended.
4. Data and generated reports remain under the data/result root.
5. Run Check Template/Directory before generating reports.
"@
Set-Content -LiteralPath $versionPath -Value $versionText -Encoding UTF8
Assert-PathExists -Path $versionPath -Message "VERSION.txt was not written."

$requiredPaths += "VERSION.txt"

$outputRoot = Resolve-Path $OutputDir
$zipPath = Join-Path $outputRoot "BridgeReportBuilder_${version}_${timestamp}.zip"
Write-Step "Writing package: $zipPath"
Compress-Archive -Path (Join-Path (Resolve-Path $distRoot) "*") -DestinationPath $zipPath -Force

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $zipPath))
try {
    $entries = @($zip.Entries | ForEach-Object { $_.FullName.Replace("/", "\").TrimEnd("\") })
    foreach ($rel in $requiredPaths) {
        $normalized = $rel.TrimEnd("\")
        $hasExactEntry = $entries -contains $normalized
        $hasChildEntry = (@($entries | Where-Object { $_ -like "$normalized\*" })).Count -gt 0
        if (-not ($hasExactEntry -or $hasChildEntry)) {
            throw "Zip content missing: $rel"
        }
    }
}
finally {
    $zip.Dispose()
}

$package = Get-Item -LiteralPath $zipPath
Write-Step "Package OK: $($package.FullName)"
Write-Step "Size: $($package.Length) bytes"
