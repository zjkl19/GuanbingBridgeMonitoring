param(
    [string]$PythonExe = "reporting\.venv\Scripts\python.exe",
    [switch]$SkipReportBuilder,
    [switch]$SkipAnalysisRunner
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repo

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw "Python executable not found: $PythonExe"
}

& $PythonExe -c "import PySide6, PyInstaller" | Out-Host

$distParent = Join-Path $repo "dist"
$buildRoot = Join-Path $repo "build\workbench"
& $PythonExe -m PyInstaller `
    --noconfirm `
    --clean `
    --noconsole `
    --icon "reporting\assets\BridgeReportBuilder.ico" `
    --name "BridgeMonitoringWorkbench" `
    --distpath $distParent `
    --workpath $buildRoot `
    "start_workbench.py" | Out-Host

$distRoot = Join-Path $distParent "BridgeMonitoringWorkbench"
$exePath = Join-Path $distRoot "BridgeMonitoringWorkbench.exe"
if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
    throw "Workbench executable was not produced: $exePath"
}

Copy-Item -LiteralPath (Join-Path $repo "VERSION") -Destination (Join-Path $distRoot "VERSION") -Force
Copy-Item -LiteralPath (Join-Path $repo "README.md") -Destination (Join-Path $distRoot "README.md") -Force

$copyAssets = @'
from __future__ import annotations

import json
import shutil
from pathlib import Path

repo = Path.cwd()
dest = repo / "dist" / "BridgeMonitoringWorkbench"
profile_path = repo / "config" / "bridge_profiles.json"
payload = json.loads(profile_path.read_text(encoding="utf-8-sig"))
relative_files = {
    Path("config") / "bridge_profiles.json",
    Path("config") / "workbench_update.json",
}
for profile in payload.get("profiles", []):
    for key in ("default_config", "report_template"):
        value = str(profile.get(key) or "").strip()
        if value:
            candidate = Path(value)
            if not candidate.is_absolute():
                relative_files.add(candidate)
    machine_pattern = str(profile.get("machine_config_pattern") or "").strip()
    if machine_pattern and "<COMPUTERNAME>" not in machine_pattern:
        candidate = Path(machine_pattern)
        if not candidate.is_absolute():
            relative_files.add(candidate)

for relative in sorted(relative_files, key=lambda item: str(item).casefold()):
    source = repo / relative
    if not source.is_file():
        continue
    target = dest / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)

icon_source = repo / "workbench" / "assets" / "module_icons"
icon_target = dest / "workbench" / "assets" / "module_icons"
if icon_target.exists():
    shutil.rmtree(icon_target)
shutil.copytree(icon_source, icon_target)
'@
$copyScript = Join-Path $buildRoot "copy_workbench_assets.py"
Set-Content -LiteralPath $copyScript -Value $copyAssets -Encoding UTF8
& $PythonExe $copyScript | Out-Host

if (-not $SkipAnalysisRunner) {
    $runnerSource = Join-Path $repo "bin\BridgeAnalysisRunner"
    $runnerExe = Join-Path $runnerSource "BridgeAnalysisRunner.exe"
    $runnerInputs = @(
        Get-Item -LiteralPath (Join-Path $repo "run_request_cli.m")
        Get-ChildItem -LiteralPath (Join-Path $repo "+bms") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "analysis") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "pipeline") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "scripts") -Recurse -File -Filter "*.m"
        Get-ChildItem -LiteralPath (Join-Path $repo "ui") -Recurse -File -Filter "*.m"
    )
    $latestRunnerInput = ($runnerInputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    if (-not (Test-Path -LiteralPath $runnerExe -PathType Leaf) `
            -or (Get-Item -LiteralPath $runnerExe).LastWriteTimeUtc -lt $latestRunnerInput) {
        Write-Host "Analysis runner is stale; rebuilding before workbench packaging."
        & (Join-Path $repo "scripts\build_analysis_runner.ps1")
    }
    if (-not (Test-Path -LiteralPath (Join-Path $runnerSource "BridgeAnalysisRunner.exe") -PathType Leaf)) {
        throw "Analysis runner is missing: $runnerSource"
    }
    $previewSmokeRoot = Join-Path $buildRoot "auto_threshold_preview_smoke"
    & $PythonExe (Join-Path $repo "scripts\validate_auto_threshold_preview_runner.py") `
        --project-root $repo --output-root $previewSmokeRoot --replace | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "Compiled automatic-cleaning preview contract smoke failed with exit code $LASTEXITCODE"
    }
    $runnerTarget = Join-Path $distRoot "bin\BridgeAnalysisRunner"
    if (Test-Path -LiteralPath $runnerTarget) {
        Remove-Item -LiteralPath $runnerTarget -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path $runnerTarget) -Force | Out-Null
    Copy-Item -LiteralPath $runnerSource -Destination $runnerTarget -Recurse -Force
}

if (-not $SkipReportBuilder) {
    $reportSource = Join-Path $repo "reporting\dist\BridgeReportBuilder"
    $reportExe = Join-Path $reportSource "BridgeReportBuilder.exe"
    $reportInputs = @(
        Get-ChildItem -LiteralPath (Join-Path $repo "reporting") -File -Filter "*.py"
        Get-Item -LiteralPath (Join-Path $repo "reporting\requirements.txt")
        Get-Item -LiteralPath (Join-Path $repo "config\bridge_profiles.json")
    )
    $latestReportInput = ($reportInputs | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1).LastWriteTimeUtc
    if (-not (Test-Path -LiteralPath $reportExe -PathType Leaf) `
            -or (Get-Item -LiteralPath $reportExe).LastWriteTimeUtc -lt $latestReportInput) {
        Write-Host "Report builder is stale; rebuilding before workbench packaging."
        & (Join-Path $repo "reporting\build_gui_exe.ps1") -PythonExe $PythonExe
    }
    if (-not (Test-Path -LiteralPath $reportExe -PathType Leaf)) {
        throw "Packaged report builder is missing after rebuild: $reportExe"
    }
    $reportTarget = Join-Path $distRoot "reporting\dist\BridgeReportBuilder"
    if (Test-Path -LiteralPath $reportTarget) {
        Remove-Item -LiteralPath $reportTarget -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Split-Path $reportTarget) -Force | Out-Null
    Copy-Item -LiteralPath $reportSource -Destination $reportTarget -Recurse -Force

    $reportSmokeContext = Join-Path $buildRoot "report_builder_smoke_context.json"
    $reportSmokePayload = [ordered]@{
        schema_version = 1
        bridge_id = "guanbing"
        project_root = $distRoot
        data_root = $distRoot
        config_path = (Join-Path $distRoot "config\default_config.json")
        start_date = "2026-01-01"
        end_date = "2026-01-01"
        period_label = "EXE smoke"
        monitoring_range = "EXE smoke"
        report_date = "2026-01-01"
        analysis = @{}
        report = [ordered]@{
            plots_approved = $false
            output_dir = (Join-Path $distRoot "output\doc")
        }
    }
    $reportSmokePayload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportSmokeContext -Encoding UTF8
    $packagedReportExe = Join-Path $reportTarget "BridgeReportBuilder.exe"
    $reportSmokeProcess = Start-Process `
        -FilePath $packagedReportExe `
        -ArgumentList @("--job-context", $reportSmokeContext, "--job-context-smoke-test") `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($reportSmokeProcess.ExitCode -ne 0) {
        throw "Packaged report builder context smoke test failed with exit code $($reportSmokeProcess.ExitCode)"
    }
    $reportJobSmokeProcess = Start-Process `
        -FilePath $packagedReportExe `
        -ArgumentList @("--report-job-contract-smoke-test") `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($reportJobSmokeProcess.ExitCode -ne 0) {
        throw "Packaged embedded report-job smoke test failed with exit code $($reportJobSmokeProcess.ExitCode)"
    }
    $reportGateSmokeProcess = Start-Process `
        -FilePath $packagedReportExe `
        -ArgumentList @("--report-gate-contract-smoke-test") `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($reportGateSmokeProcess.ExitCode -ne 0) {
        throw "Packaged report gate contract smoke test failed with exit code $($reportGateSmokeProcess.ExitCode)"
    }
    $visualQcSmokeProcess = Start-Process `
        -FilePath $packagedReportExe `
        -ArgumentList @("--visual-qc-contract-smoke-test") `
        -WindowStyle Hidden `
        -Wait `
        -PassThru
    if ($visualQcSmokeProcess.ExitCode -ne 0) {
        throw "Packaged report visual-QC smoke test failed with exit code $($visualQcSmokeProcess.ExitCode)"
    }
}

$smokeOutput = Join-Path $distRoot "workbench_smoke.json"
$smokeProcess = Start-Process `
    -FilePath $exePath `
    -ArgumentList @("--smoke-test", "--smoke-output", $smokeOutput) `
    -WindowStyle Hidden `
    -Wait `
    -PassThru
if ($smokeProcess.ExitCode -ne 0) {
    throw "Workbench EXE smoke test failed with exit code $($smokeProcess.ExitCode)"
}
$smoke = Get-Content -LiteralPath $smokeOutput -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $smoke.ok -or $smoke.profile_count -ne 6 -or $smoke.tab_count -ne 4 `
        -or $smoke.config_tab_count -lt 8 -or $smoke.module_count -lt 20 `
        -or $smoke.auto_threshold_module_count -lt 10 `
        -or -not $smoke.auto_threshold_preview_enabled `
        -or -not $smoke.update_backup_management_enabled `
        -or -not $smoke.profile_matrix_review_enabled `
        -or $smoke.group_plot_module_count -lt 1 `
        -or $smoke.cleaning_threshold_row_count -lt 1 `
        -or $smoke.plot_common_field_count -ne 14 `
        -or $smoke.spectrum_module_count -ne 2 `
        -or $smoke.provenance_column_count -ne 7 `
        -or $smoke.report_qc_column_count -ne 5) {
    throw "Workbench EXE smoke contract failed: $($smoke | ConvertTo-Json -Compress)"
}

$profileMatrixOutput = Join-Path $distRoot "workbench_profile_matrix.json"
& $PythonExe (Join-Path $repo "scripts\validate_workbench_installed_profiles.py") `
    --package-root $distRoot --output $profileMatrixOutput `
    --evidence-root (Join-Path $buildRoot "profile_matrix_evidence") | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw "Frozen six-profile matrix failed with exit code $LASTEXITCODE"
}
$profileMatrix = Get-Content -LiteralPath $profileMatrixOutput -Raw -Encoding UTF8 | ConvertFrom-Json
if ($profileMatrix.status -ne "passed" -or $profileMatrix.profile_count -ne 6 `
        -or $profileMatrix.report_capable_count -ne 5 -or $profileMatrix.analysis_only_count -ne 1 `
        -or -not $profileMatrix.assets_unchanged) {
    throw "Frozen six-profile matrix contract failed: $($profileMatrix | ConvertTo-Json -Compress -Depth 4)"
}

$screenshotOutput = Join-Path $distRoot "workbench_startup.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $screenshotOutput -ProfileId "guanbing" -TabIndex 0
$configScreenshotOutput = Join-Path $distRoot "workbench_alarm_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $configScreenshotOutput -ProfileId "hongtang" -TabIndex 1
$cleaningScreenshotOutput = Join-Path $distRoot "workbench_cleaning_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $cleaningScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -ConfigTabIndex 1
$postFilterScreenshotOutput = Join-Path $distRoot "workbench_post_filter_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $postFilterScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 2
$autoThresholdScreenshotOutput = Join-Path $distRoot "workbench_auto_threshold.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $autoThresholdScreenshotOutput -ProfileId "guanbing" -TabIndex 1 -ConfigTabIndex 3 -DemoAutoThresholdPreview
$offsetScreenshotOutput = Join-Path $distRoot "workbench_offset_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $offsetScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 4
$groupScreenshotOutput = Join-Path $distRoot "workbench_group_plot_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $groupScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 5
$plotCommonScreenshotOutput = Join-Path $distRoot "workbench_plot_common_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $plotCommonScreenshotOutput -ProfileId "hongtang" -TabIndex 1 -ConfigTabIndex 6
$spectrumScreenshotOutput = Join-Path $distRoot "workbench_spectrum_editor.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $spectrumScreenshotOutput -ProfileId "zhishan" -TabIndex 1 -ConfigTabIndex 7
$reportTaskScreenshotOutput = Join-Path $distRoot "workbench_report_task.png"
& (Join-Path $repo "scripts\capture_workbench_window.ps1") -ExePath $exePath -OutputPath $reportTaskScreenshotOutput -ProfileId "hongtang" -TabIndex 3

$files = Get-ChildItem -LiteralPath $distRoot -Recurse -File | Where-Object {
    $_.FullName -ne (Join-Path $distRoot "release_manifest.json")
}
$fileInventory = @($files | ForEach-Object {
    $relative = $_.FullName.Substring($distRoot.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
    [ordered]@{
        path = $relative
        bytes = [long]$_.Length
        sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
})
$updatePolicy = Get-Content -LiteralPath (Join-Path $distRoot "config\workbench_update.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$releaseManifest = [ordered]@{
    schema_version = 2
    built_at = (Get-Date).ToString("o")
    version = (Get-Content -LiteralPath (Join-Path $distRoot "VERSION") -Raw -Encoding UTF8).Trim()
    executable = "BridgeMonitoringWorkbench.exe"
    executable_sha256 = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
    update_repository = $updatePolicy.repository
    update_channel = $updatePolicy.channel
    includes_analysis_runner = -not $SkipAnalysisRunner
    includes_report_builder = -not $SkipReportBuilder
    report_builder_context_smoke = -not $SkipReportBuilder
    embedded_report_job_smoke = -not $SkipReportBuilder
    report_gate_contract_smoke = -not $SkipReportBuilder
    report_visual_qc_smoke = -not $SkipReportBuilder
    auto_threshold_preview_runner_smoke = -not $SkipAnalysisRunner
    installed_profile_matrix_smoke = $true
    installed_profile_matrix = [ordered]@{
        profile_count = $profileMatrix.profile_count
        report_capable_count = $profileMatrix.report_capable_count
        analysis_only_count = $profileMatrix.analysis_only_count
        asset_count = $profileMatrix.asset_count
        assets_unchanged = $profileMatrix.assets_unchanged
    }
    file_count_excluding_manifest = $files.Count
    total_bytes_excluding_manifest = [long](($files | Measure-Object Length -Sum).Sum)
    file_inventory_count = $fileInventory.Count
    file_inventory = $fileInventory
    screenshots = @(
        "workbench_startup.png",
        "workbench_alarm_editor.png",
        "workbench_cleaning_editor.png",
        "workbench_post_filter_editor.png",
        "workbench_auto_threshold.png",
        "workbench_offset_editor.png",
        "workbench_group_plot_editor.png",
        "workbench_plot_common_editor.png",
        "workbench_spectrum_editor.png",
        "workbench_report_task.png"
    )
    smoke = $smoke
}
$manifestPath = Join-Path $distRoot "release_manifest.json"
$releaseManifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

Write-Host "Workbench EXE built and verified: $exePath"
Write-Host "Release manifest: $manifestPath"
