param(
    [string]$PythonExe = "reporting\.venv\Scripts\python.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $PythonExe)) {
    throw "Python executable not found: $PythonExe"
}

& $PythonExe -m pip install pyinstaller | Out-Host
& $PythonExe -m pip install -r reporting\requirements.txt | Out-Host

& $PythonExe -m PyInstaller `
  --noconfirm `
  --clean `
  --noconsole `
  --name BridgeReportBuilder `
  --distpath reporting\dist `
  --workpath reporting\build `
  reporting\report_gui.py | Out-Host

$distRoot = "reporting\dist\BridgeReportBuilder"
$distReports = Join-Path $distRoot "reports"
if (Test-Path $distReports) {
    Remove-Item -Recurse -Force $distReports
}
New-Item -ItemType Directory -Force $distReports | Out-Null

$copyReportsScript = @'
from pathlib import Path
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
except Exception:
    report_files = list((repo / "reports").glob("*.docx")) + [repo / "reports" / "README.md"]

for rel in report_files:
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

Copy-Item -Force reporting\README.md reporting\dist\BridgeReportBuilder\README.md
Copy-Item -Force reporting\REPORTING_LOGIC.md reporting\dist\BridgeReportBuilder\REPORTING_LOGIC.md

Write-Host "GUI exe built at reporting\dist\BridgeReportBuilder\BridgeReportBuilder.exe"
