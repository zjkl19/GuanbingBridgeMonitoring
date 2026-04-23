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

- `reports/洪塘大桥健康监测周期报模板-自动报告.docx`

For period reports, section `1.4 健康监测系统运行状况` only counts raw missing / no-file / no-record conditions.
对于周期报，`1.4 健康监测系统运行状况` 只统计原始缺失、无文件、无记录。

See `reporting/README.md` for report GUI details.
报告 GUI 细节见 `reporting/README.md`。

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
