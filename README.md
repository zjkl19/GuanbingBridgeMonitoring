# Guanbing Bridge Monitoring / 桥梁监测处理系统

## Overview / 概述

This repository contains the MATLAB analysis workflow and the Python/packaged report builder used for bridge monitoring projects.
本仓库包含桥梁监测项目使用的 MATLAB 分析流程，以及 Python / 打包版自动报告生成程序。

## Main Entry Points / 主要入口

### MATLAB GUI

```matlab
start_gui
```

Use this GUI for analysis runs, threshold configuration, post-filter cleaning, zero-offset correction, and plot settings.
用于分析计算、阈值配置、滤波后二次清洗、零点修正和绘图参数配置。

### Report GUI

Prefer the packaged executable when available.
优先使用已打包的报告程序。

```text
reporting/dist/BridgeReportBuilder/BridgeReportBuilder.exe
```

Or run the Python GUI directly.
也可以直接运行 Python GUI。

```powershell
reporting/.venv/Scripts/python reporting/report_gui.py
```

Build a standardized report-builder release package.
生成标准化报告生成器发布包。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package_report_builder.ps1
```

The release package is written under `archive/` and includes `VERSION.txt`, templates, README files, `BridgeReportBuilder.exe`, and `_internal/`.
发布包输出到 `archive/`，包含 `VERSION.txt`、模板、README、`BridgeReportBuilder.exe` 和 `_internal/`。

## Repository Layout / 仓库结构

- `analysis/` MATLAB analysis modules / MATLAB 分析模块
- `pipeline/` shared loaders and helpers / 通用加载与辅助逻辑
- `config/` project configuration files / 项目配置文件
- `ui/` MATLAB GUI / MATLAB 图形界面
- `reporting/` report scripts and GUI / 报告脚本与 GUI
- `reports/` report templates / 报告模板
- `scripts/` deployment and utility scripts / 部署与辅助脚本

## Supported Modules / 当前已接入模块

Current MATLAB workflow supports the commonly used monitoring modules below.
当前 MATLAB 流程已接入以下常用监测模块。

- Temperature / 温度
- Humidity / 湿度
- Rainfall / 雨量
- Deflection / 挠度
- Bearing displacement / 支座位移
- Tilt / 倾角
- Acceleration / 加速度
- Cable acceleration / 索力加速度
- Strain / 应变
- Dynamic strain high-pass / 动应变分析（高通+含箱线图）
- Dynamic strain low-pass / 动应变分析（低通+含箱线图）
- Crack / 裂缝
- Wind / 风速风向
- Earthquake / 地震动
- GNSS / GNSS
- WIM / 称重

Jiulongjiang currently has dedicated support for rainfall and GNSS CSV analysis.
九龙江项目目前已专项接入雨量与 GNSS 的 CSV 分析流程。

## Data Layout / 数据目录约定

Templates stay under the program directory. Generated outputs should stay under the data root.
模板放在程序目录，生成结果放在数据根目录。

Recommended example.
推荐示例。

```text
E:/洪塘大桥数据/2026年1-3月
  lowfreq/
    data.xlsx
  WIM/
    HS_Data_202601.bcp
    HS_Data_202601.fmt
    HS_Data_202602.bcp
    HS_Data_202602.fmt
    HS_Data_202603.bcp
    HS_Data_202603.fmt
    results/
      hongtang/
        202601/
        202602/
        202603/
  stats/
  run_logs/
  自动报告/
  时程曲线_GNSS/
  时程曲线_倾斜/
  时程曲线_支座位移/
  箱线图_应变/

For Jiulongjiang, GNSS and rainfall outputs also follow the same rule: write figures and stats under the data root.
对于九龙江，GNSS 和雨量的输出也遵循同样规则：图表和统计结果直接写到数据根目录下。
```

## Config Files / 配置文件

Common files.
常用配置。

- `config/default_config.json`
- `config/hongtang_config.json`
- `config/jiulongjiang_config.json`

Machine-specific overrides may be stored as `config/hongtang_config_<COMPUTERNAME>.json`.
机器专用覆盖配置可保存为 `config/hongtang_config_<COMPUTERNAME>.json`。

Tracked production example.
当前已纳入版本库的生产机示例。

- `config/hongtang_config_DESKTOP_21RTG63.json`

Jiulongjiang GNSS and rainfall keys now use:
九龙江 GNSS 和雨量目前使用以下配置键：

- `points.gnss`
- `subfolders.gnss`
- `plot_styles.gnss`
- `points.rainfall`
- `subfolders.rainfall`
- `plot_styles.rainfall`

## Reporting / 报告生成

Monthly reports use the monthly template and a single result directory.
月报使用月报模板和单个结果目录。

Period reports use the period template, a date range, and WIM monthly results.
周期报使用周期报模板、起止日期以及 WIM 月结果。

Jiulongjiang monthly reports use a dedicated builder and logic path instead of the Hongtang monthly-report pipeline.
九龙江月报使用独立的生成脚本和专用逻辑，不复用洪塘月报第 4 章/结论页装配逻辑。

```powershell
python reporting/build_jlj_monthly_report.py --template <template.docx> --config config/jiulongjiang_config.json --result-root <data-root>
```

Default period-report template.
默认周期报模板。

- `reports/洪塘大桥健康监测2026年第一季季报-改4.docx`

For period reports, section `1.4 健康监测系统运行状况` only counts raw missing / no-file / no-record conditions.
对于周期报，`1.4 健康监测系统运行状况` 只统计原始缺失、无文件、无记录。

See `reporting/README.md` for report GUI details.
报告 GUI 细节见 `reporting/README.md`。

Current official templates are listed in `reports/README.md`; old drafts and generated reports should not be committed.
当前正式模板清单见 `reports/README.md`；历史草稿和自动生成报告不应提交。

MATLAB GUI release / MATLAB GUI 版本:

- `v1.6.5`: fixes Guanbing April crack filtering, deflection/tilt report image replacement, deflection original/filtered image naming, nested ZIP recovery, and plot gap-mode propagation for dynamic strain.
- `v1.6.5`：修复管柄 4 月裂缝过滤、挠度/倾角报告插图替换、挠度原始/滤波图命名、嵌套 ZIP 恢复，以及动应变绘图断点模式传递。
- `v1.6.4`: fixes the plot settings tab encoding/syntax issue introduced in v1.6.3.
- `v1.6.4`：修复 v1.6.3 引入的绘图参数页编码/语法问题。
- `v1.6.3`: plot outputs no longer append the run timestamp by default; files keep the data period and overwrite the same-period results. The plot settings page can re-enable timestamp suffixes.
- `v1.6.3`：绘图结果默认不再追加运行时间戳；文件名保留数据周期，同周期重算会覆盖旧结果。可在绘图参数页重新启用时间戳后缀。

The report GUI now separates Hongtang monthly, Hongtang period, and Jiulongjiang monthly report modes; use `检查模板/目录` before generating on production machines.
报告 GUI 已区分洪塘月报、洪塘周期报和九龙江月报；生产机生成前建议先点击 `检查模板/目录`。

Report GUI release / 报告 GUI 版本:

- `v1.6.3`: replaces Guanbing monthly deflection/tilt figures from result images and refreshes related statistics text.
- `v1.6.3`：管柄月报自动替换挠度/倾角结果图，并同步刷新相关统计文字。
- `v1.6.2`: writes missing-content txt/xlsx summaries next to generated reports.
- `v1.6.2`：在生成报告同目录输出缺失内容 txt/xlsx 清单。
- `v1.6.1`: writes txt/json template precheck reports and keeps the custom exe icon in packaged builds.
- `v1.6.1`：输出 txt/json 模板预检报告，并在打包 exe 中保留自定义图标。
- `v1.6.0`: separates Hongtang monthly, Hongtang period, and Jiulongjiang monthly modes; adds clearer report-type hints and stronger result-directory checks.
- `v1.6.0`：拆分洪塘月报、洪塘周期报、九龙江月报；增加报告类型说明和更明确的结果目录检查。

Template precheck and smoke test.
模板预检与冒烟测试。

```powershell
.\reporting\.venv\Scripts\python.exe -m unittest discover -s tests_py -v
python reporting/template_precheck.py --kind hongtang_period --template reports/洪塘大桥健康监测2026年第一季季报-改4.docx --output-dir tmp/report_precheck
python reporting/template_precheck.py --kind jlj_monthly --template reports/九龙江大桥健康监测2026年3月份月报_修订5.docx --output-dir tmp/report_precheck
python reporting/smoke_report_generation.py --kind all
python reporting/smoke_report_generation.py --kind all --generate
```

Generated artifacts should stay out of Git.
生成产物不应纳入版本库。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/clean_generated_artifacts.ps1
powershell -ExecutionPolicy Bypass -File scripts/clean_generated_artifacts.ps1 -Apply
```

## Runtime Notes / 运行说明

Parallel analysis is now disabled by default to avoid memory exhaustion on large datasets.
当前默认关闭并行分析，以避免大数据量场景下的内存溢出。

## WIM SQL Troubleshooting / WIM SQL 故障排查

Common WIM SQL failures are classified explicitly.
WIM SQL 常见故障现在会明确分类显示。

- `WIM:SQL:Instance`
  - Cannot connect to the SQL Server instance.
  - Check `wim_db.server`, `wim_db.service_name`, and whether the SQL Server service is running.
  - 无法连接 SQL Server 实例；检查 `wim_db.server`、`wim_db.service_name` 和 SQL Server 服务状态。

- `WIM:SQL:Permission`
  - The current Windows user does not have enough SQL Server or bulk import permissions.
  - Re-run `scripts/setup_wim_sql.ps1` or grant SQL permissions manually.
  - 当前 Windows 用户缺少 SQL Server 或 bulk import 权限；可重新运行 `scripts/setup_wim_sql.ps1` 或手工授权。

- `WIM:SQL:DatabaseMissing`
  - The configured database cannot be opened or does not exist.
  - Check `wim_db.database` and create `HighSpeed_PROC` first.
  - 目标数据库不存在或无法打开；检查 `wim_db.database` 并先创建 `HighSpeed_PROC`。

- `WIM:Input:MissingFmt`
  - The monthly `HS_Data_YYYYMM.fmt` file is missing.
  - For Hongtang, the default raw WIM directory is `<data-root>/WIM`.
  - Check `wim.input.zhichen.dir` and the month-specific input files.
  - 缺少当月 `HS_Data_YYYYMM.fmt`；洪塘默认原始称重目录为 `<数据根目录>/WIM`，请检查 `wim.input.zhichen.dir` 和对应月份文件。

- `WIM:Input:MissingBcp`
  - The monthly `HS_Data_YYYYMM.bcp` file is missing.
  - For Hongtang, the default raw WIM directory is `<data-root>/WIM`.
  - Check `wim.input.zhichen.dir` and the month-specific input files.
  - 缺少当月 `HS_Data_YYYYMM.bcp`；洪塘默认原始称重目录为 `<数据根目录>/WIM`，请检查 `wim.input.zhichen.dir` 和对应月份文件。
