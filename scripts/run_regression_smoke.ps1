param(
    [string]$GuanbingRoot = "F:\管柄大桥数据\2026年3月",
    [string]$HongtangRoot = "E:\洪塘大桥数据\2026年1-3月",
    [string]$JiulongjiangRoot = "E:\九龙江数据\2026年3月",
    [switch]$SkipPythonTests,
    [switch]$SkipReports
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$tmp = Join-Path $repo ("tmp\regression_smoke_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Write-Step($Message) {
    Write-Host "[regression] $Message" -ForegroundColor Cyan
}

function Invoke-Optional($Description, [scriptblock]$Block) {
    Write-Step $Description
    try {
        & $Block
    } catch {
        Write-Host "[regression][FAIL] $Description" -ForegroundColor Red
        throw
    }
}

Push-Location $repo
try {
    if (!$SkipPythonTests) {
        Invoke-Optional "python unit tests" {
            python -m unittest discover tests_py
        }
        Invoke-Optional "reporting py_compile" {
            python -m py_compile (Get-ChildItem reporting -Filter *.py -File | ForEach-Object { $_.FullName })
        }
    }

    if (!$SkipReports) {
        $reportOut = Join-Path $tmp "reports"
        New-Item -ItemType Directory -Force -Path $reportOut | Out-Null

        $guanbingTemplate = Join-Path $repo "reports\G104线管柄大桥监测月报模板-自动报告.docx"
        $guanbingCfg = Join-Path $repo "config\default_config.json"
        if ((Test-Path $GuanbingRoot) -and (Test-Path $guanbingTemplate) -and (Test-Path $guanbingCfg)) {
            Invoke-Optional "Guanbing report smoke" {
                python reporting\build_guanbing_monthly_report.py `
                    --template $guanbingTemplate `
                    --config $guanbingCfg `
                    --data-root $GuanbingRoot `
                    --output-dir (Join-Path $reportOut "guanbing") `
                    --report-month "2026年03月" `
                    --start-date "2026-02-26" `
                    --end-date "2026-03-25"
            }
        } else {
            Write-Host "[regression][SKIP] Guanbing report smoke: missing data/template/config"
        }

        $hongtangTemplate = Join-Path $repo "reports\洪塘大桥健康监测周期报模板-自动报告.docx"
        $hongtangCfg = Join-Path $repo "config\hongtang_config.json"
        if ((Test-Path $HongtangRoot) -and (Test-Path $hongtangTemplate) -and (Test-Path $hongtangCfg)) {
            Invoke-Optional "Hongtang period report smoke" {
                python reporting\build_period_report.py `
                    --template $hongtangTemplate `
                    --config $hongtangCfg `
                    --data-root $HongtangRoot `
                    --output-dir (Join-Path $reportOut "hongtang") `
                    --wim-results-dir (Join-Path $HongtangRoot "WIM\results\hongtang") `
                    --report-period "2026年1-3月" `
                    --monitoring-time "2026年01月01日~2026年03月31日" `
                    --start-date "2026-01-01" `
                    --end-date "2026-03-31" `
                    --report-date "2026年04月15日"
            }
        } else {
            Write-Host "[regression][SKIP] Hongtang report smoke: missing data/template/config"
        }

        $jljTemplate = Join-Path $repo "reports\九龙江大桥健康监测2026年3月份月报_0506.docx"
        $jljCfg = Join-Path $repo "config\jiulongjiang_config.json"
        if ((Test-Path $JiulongjiangRoot) -and (Test-Path $jljTemplate) -and (Test-Path $jljCfg)) {
            Invoke-Optional "Jiulongjiang report smoke" {
                python reporting\build_jlj_monthly_report.py `
                    --template $jljTemplate `
                    --config $jljCfg `
                    --data-root $JiulongjiangRoot `
                    --output-dir (Join-Path $reportOut "jiulongjiang") `
                    --report-month "2026年3月份" `
                    --start-date "2026-03-23" `
                    --end-date "2026-03-31"
            }
        } else {
            Write-Host "[regression][SKIP] Jiulongjiang report smoke: missing data/template/config"
        }
    }

    Write-Step "Done. Output: $tmp"
} finally {
    Pop-Location
}
