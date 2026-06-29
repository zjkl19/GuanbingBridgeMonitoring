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
  --icon reporting\assets\BridgeReportBuilder.ico `
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
        machine_config = str(profile.get("machine_config_pattern") or "").strip()
        if machine_config and "<COMPUTERNAME>" not in machine_config:
            rel_machine_cfg = Path(machine_config)
            if not rel_machine_cfg.is_absolute():
                src_machine_cfg = repo / rel_machine_cfg
                if src_machine_cfg.exists() and rel_machine_cfg not in config_files:
                    config_files.append(rel_machine_cfg)
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
    shutil.copytree(asset_root, dst_asset_root)

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

Copy-Item -Force reporting\README.md reporting\dist\BridgeReportBuilder\README.md
Copy-Item -Force reporting\REPORTING_LOGIC.md reporting\dist\BridgeReportBuilder\REPORTING_LOGIC.md

Write-Host "GUI exe built at reporting\dist\BridgeReportBuilder\BridgeReportBuilder.exe"
