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

Copy-Item -Recurse -Force reports reporting\dist\BridgeReportBuilder\reports
Copy-Item -Force reporting\README.md reporting\dist\BridgeReportBuilder\README.md
Copy-Item -Force reporting\REPORTING_LOGIC.md reporting\dist\BridgeReportBuilder\REPORTING_LOGIC.md

$period0318 = "reporting\\dist\\BridgeReportBuilder\\reports\\洪塘大桥健康监测周期报模板0318.docx"
$periodAlias = "reporting\\dist\\BridgeReportBuilder\\reports\\洪塘大桥健康监测周期报模板.docx"
if (Test-Path -LiteralPath $period0318) {
    Copy-Item -LiteralPath $period0318 -Destination $periodAlias -Force
}

Write-Host "GUI exe built at reporting\\dist\\BridgeReportBuilder\\BridgeReportBuilder.exe"
