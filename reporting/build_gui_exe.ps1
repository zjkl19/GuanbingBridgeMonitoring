param(
    [string]$PythonExe = "reporting\.venv\Scripts\python.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $PythonExe)) {
    throw "Python executable not found: $PythonExe"
}

function Invoke-NativeBuildStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepName,
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Executable @Arguments | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$StepName failed with exit code $exitCode."
    }
}

# The mutex name is derived from the absolute output paths, so any two processes
# targeting the same reporting/dist and reporting/build trees share one lock,
# including builds launched from different Windows sessions.
$distPathForLock = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path "reporting\dist"))
$buildPathForLock = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path "reporting\build"))
$lockIdentity = ($distPathForLock + "|" + $buildPathForLock).ToUpperInvariant()
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $lockDigest = [System.BitConverter]::ToString(
        $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($lockIdentity))
    ).Replace("-", "").Substring(0, 24)
}
finally {
    $sha256.Dispose()
}

$mutexName = "Global\Guanbing_BridgeReportBuilder_Build_$lockDigest"
$buildMutex = $null
$buildMutexAcquired = $false

try {
    $buildMutex = [System.Threading.Mutex]::new($false, $mutexName)
    try {
        $buildMutexAcquired = $buildMutex.WaitOne(0)
    }
    catch [System.Threading.AbandonedMutexException] {
        # The owning process terminated without releasing the mutex. Windows
        # transfers ownership to this process, so it is safe to continue.
        $buildMutexAcquired = $true
    }

    if (-not $buildMutexAcquired) {
        throw "Another report-builder build is already writing reporting/dist or reporting/build (mutex: $mutexName)."
    }

Invoke-NativeBuildStep `
    -StepName "Installing PyInstaller" `
    -Executable $PythonExe `
    -Arguments @("-m", "pip", "install", "pyinstaller")

Invoke-NativeBuildStep `
    -StepName "Installing report-builder requirements" `
    -Executable $PythonExe `
    -Arguments @("-m", "pip", "install", "-r", "reporting\requirements.txt")

Invoke-NativeBuildStep `
    -StepName "Building BridgeReportBuilder with PyInstaller" `
    -Executable $PythonExe `
    -Arguments @(
        "-m", "PyInstaller",
        "--noconfirm",
        "--clean",
        "--noconsole",
        "--icon", "reporting\assets\BridgeReportBuilder.ico",
        "--name", "BridgeReportBuilder",
        "--distpath", "reporting\dist",
        "--workpath", "reporting\build",
        "reporting\report_gui.py"
    )

$distRoot = "reporting\dist\BridgeReportBuilder"
$distReports = Join-Path $distRoot "reports"
if (Test-Path $distReports) {
    Remove-Item -Recurse -Force $distReports
}
New-Item -ItemType Directory -Force $distReports | Out-Null

$copyReportsScript = @'
from pathlib import Path
import json
import shutil
import subprocess

repo = Path.cwd()
dest_root = repo / "reporting" / "dist" / "BridgeReportBuilder"
try:
    output = subprocess.check_output(
        ["git", "-c", "core.quotepath=false", "ls-files", "--", "reports/*.docx", "reports/README.md"],
        cwd=repo,
        text=True,
        encoding="utf-8",
    )
    report_files = [Path(line.strip()) for line in output.splitlines() if line.strip()]
    other_output = subprocess.check_output(
        ["git", "-c", "core.quotepath=false", "ls-files", "--others", "--exclude-standard", "--", "reports/*.docx"],
        cwd=repo,
        text=True,
        encoding="utf-8",
    )
    for path in [Path(line.strip()) for line in other_output.splitlines() if line.strip()]:
        if path.exists() and path not in report_files:
            report_files.append(path)
except Exception:
    report_files = list((repo / "reports").glob("*.docx")) + [repo / "reports" / "README.md"]

profile_path = repo / "config" / "bridge_profiles.json"
config_files = []
if profile_path.exists():
    data = json.loads(profile_path.read_text(encoding="utf-8"))
    config_files.append(Path("config") / "bridge_profiles.json")
    for profile in data.get("profiles", []):
        default_config = str(profile.get("default_config") or "").strip()
        if default_config:
            rel_cfg = Path(default_config)
            if not rel_cfg.is_absolute():
                src_cfg = repo / rel_cfg
                if src_cfg.exists() and rel_cfg not in config_files:
                    config_files.append(rel_cfg)
        template = str(profile.get("report_template") or "").strip()
        if not template:
            continue
        rel = Path(template)
        if rel.is_absolute():
            continue
        src = repo / rel
        if src.exists() and rel not in report_files:
            report_files.append(rel)

for rel in report_files:
    src = repo / rel
    if not src.exists():
        continue
    dst = dest_root / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

asset_root = repo / "reports" / "assets"
if asset_root.exists():
    dst_asset_root = dest_root / "reports" / "assets"
    if dst_asset_root.exists():
        shutil.rmtree(dst_asset_root)
    shutil.copytree(asset_root, dst_asset_root, dirs_exist_ok=True)

for rel in config_files:
    src = repo / rel
    if not src.exists():
        continue
    dst = dest_root / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
'@
$copyReportsScriptPath = "reporting\build\copy_report_templates.py"
Set-Content -LiteralPath $copyReportsScriptPath -Value $copyReportsScript -Encoding UTF8
& $PythonExe $copyReportsScriptPath | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy report templates/assets into the packaged report builder."
}

Copy-Item -Force reporting\README.md reporting\dist\BridgeReportBuilder\README.md
Copy-Item -Force reporting\REPORTING_LOGIC.md reporting\dist\BridgeReportBuilder\REPORTING_LOGIC.md

Write-Host "GUI exe built at reporting\dist\BridgeReportBuilder\BridgeReportBuilder.exe"
}
finally {
    if ($buildMutexAcquired -and $null -ne $buildMutex) {
        $buildMutex.ReleaseMutex()
    }
    if ($null -ne $buildMutex) {
        $buildMutex.Dispose()
    }
}
