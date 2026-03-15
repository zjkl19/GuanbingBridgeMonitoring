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
  --name MonthlyReportBuilder `
  --distpath reporting\dist `
  --workpath reporting\build `
  reporting\report_gui.py | Out-Host

Write-Host "GUI exe built at reporting\\dist\\MonthlyReportBuilder\\MonthlyReportBuilder.exe"
