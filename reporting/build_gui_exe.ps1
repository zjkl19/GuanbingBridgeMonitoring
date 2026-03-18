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

Copy-Item -Recurse -Force reports reporting\dist\MonthlyReportBuilder\reports
Copy-Item -Force reporting\README.md reporting\dist\MonthlyReportBuilder\README.md
Copy-Item -Force reporting\REPORTING_LOGIC.md reporting\dist\MonthlyReportBuilder\REPORTING_LOGIC.md

Write-Host "GUI exe built at reporting\\dist\\MonthlyReportBuilder\\MonthlyReportBuilder.exe"
