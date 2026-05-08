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
- `+bms/+core/` lightweight OOP core: context, paths, config guard, module registry / 轻量 OOP 核心：运行上下文、路径、配置保护和模块注册
- `+bms/+app/` application layer: run session, step plan, result objects, error classifier, manifest writer / 应用层：运行会话、步骤计划、结果对象、错误分类和清单写入
- `+bms/+module/` canonical module registry and module metadata / 统一模块注册表与模块元数据
- `+bms/+config/` config validation and patch helpers / 配置校验与补丁辅助
- `+bms/+data/` data layout, point and date-range helpers / 数据目录、测点和日期范围辅助
- `+bms/+plot/` plotting option helpers / 绘图选项辅助
- `+bms/+io/` stats output helpers / 统计输出辅助
- `config/` project configuration files / 项目配置文件
- `ui/` MATLAB GUI / MATLAB 图形界面
- `reporting/` report scripts and GUI / 报告脚本与 GUI
- `reports/` report templates / 报告模板
- `scripts/` deployment and utility scripts / 部署与辅助脚本

## Refactor Foundation / 重构基础

`bms` means Bridge Monitoring System. The package name is intentionally neutral and is not tied to Guanbing, Hongtang, Jiulongjiang, or the current repository name.
`bms` 表示 Bridge Monitoring System，包名刻意保持中性，不绑定管柄、洪塘、九龙江或当前仓库名称。

The MATLAB workflow now has an additive weak-MVC/OOP foundation. Existing analysis modules remain callable, while `run_all` delegates the run lifecycle to `bms.app.RunSession`. The GUI enters the pipeline through `bms_run_context`, which creates a `bms.core.AnalysisContext` and writes `analysis_manifest_*.json` under `<data-root>/run_logs`.
MATLAB 流程已增加增量式弱 MVC/OOP 基础。既有分析模块不重写；`run_all` 将运行生命周期交给 `bms.app.RunSession`。GUI 通过 `bms_run_context` 进入流程，创建 `bms.core.AnalysisContext`，并在 `<数据根目录>/run_logs` 写入 `analysis_manifest_*.json`。

The manifest is versioned with `schema_version=1`. It records enabled modules, each module's `ok/fail/skip` state, coarse `error_type`, messages, stats files, `run_log` path, elapsed time, missing expected stats files, and the offset-correction report path. This is the preferred machine-readable source for later report-generation checks.
运行清单带 `schema_version=1`。它会记录启用模块、各模块 `ok/fail/skip` 状态、粗粒度 `error_type`、错误信息、stats 文件、`run_log` 路径、耗时、缺失的预期统计文件和零点修正记录表路径。后续报告生成前检查应优先读取这个结构化文件。

Module metadata is now centralized in `bms.module.ModuleRegistry` / `bms.module.ModuleSpec`. `bms.app.StepDefinition`, `run_all`, the MATLAB GUI option mapping, expected stats files, and manifest preflight records all read from this registry. When adding a new module, register it first, then wire only the execution function and any report-specific logic.
模块元数据现在统一集中在 `bms.module.ModuleRegistry` / `bms.module.ModuleSpec`。`bms.app.StepDefinition`、`run_all`、MATLAB GUI 选项映射、预期 stats 文件和 manifest 预检记录都从该注册表读取。新增模块时，应先注册模块，再接执行函数和报告专项逻辑。

The application layer uses `bms.app.StepExecutor` / `bms.app.StepResult` to capture per-step timing, failure information, and error classification. `run_all` remains the compatible public entry point.
应用层通过 `bms.app.StepExecutor` / `bms.app.StepResult` 统一记录每个步骤的耗时、失败信息和错误分类。`run_all` 仍保持为兼容的公开入口。

Configuration saves from GUI tabs use `bms.core.ConfigStore.saveGuarded` to prevent accidental loss of unrelated protected fields such as `per_point.*.*.offset_correction`.
GUI 配置页保存时使用 `bms.core.ConfigStore.saveGuarded`，用于防止误删无关保护字段，例如 `per_point.*.*.offset_correction`。

New helper packages are intentionally small and side-effect-light: `bms.config.SchemaValidator` checks common config shape problems, `bms.data.*` resolves data roots and point aliases, `bms.plot.PlotService` normalizes plot options, and `bms.io.StatsWriter` centralizes stats-table writes.
新增辅助包刻意保持小而低副作用：`bms.config.SchemaValidator` 检查常见配置结构问题，`bms.data.*` 解析数据根目录和测点别名，`bms.plot.PlotService` 归一化绘图选项，`bms.io.StatsWriter` 集中处理统计表写入。

Low-risk analyzers now have an OOP adapter layer under `bms.analyzer`. Temperature, humidity, rainfall, deflection, and crack still call the legacy numerical functions internally, but return a normalized `AnalyzerResult`; `StepExecutor` converts this into `StepResult` for manifests and future GUI result panels. This is intentionally an adapter-first migration, not a rewrite of the computation algorithms.
低风险分析模块已增加 `bms.analyzer` 适配层。温度、湿度、雨量、挠度和裂缝内部仍调用既有数值函数，但会返回统一的 `AnalyzerResult`；`StepExecutor` 再转换为 `StepResult`，供运行清单和后续 GUI 结果面板使用。这是“先适配、再逐步重构”的迁移方式，不是重写计算算法。

Most regular modules now enter through `AnalyzerFactory` as thin adapters, including tilt, bearing displacement, GNSS, wind, earthquake, acceleration, cable acceleration, spectra, strain, dynamic strain, and WIM. High-risk numerical modules still execute the legacy functions internally.
大多数常规模块现已通过 `AnalyzerFactory` 薄适配器进入，包括倾角、支座位移、GNSS、风、地震动、加速度、索力加速度、频谱、应变、动应变和 WIM。高风险数值模块内部仍执行原有函数。

`analysis_manifest_*.json` now uses `schema_version=2`. In addition to module status, it records `module_status_counts`, `module_artifacts`, and `artifact_count`. Report builders can use these paths before falling back to directory searches.
`analysis_manifest_*.json` 现使用 `schema_version=2`。除模块状态外，还记录 `module_status_counts`、`module_artifacts` 和 `artifact_count`。报告生成器可优先使用这些路径，再回退到目录搜索。


GUI 运行结果表中的诊断字段说明：
- `产物`：本次运行记录到的图片、统计表等输出文件数量。
- `预检提示`：运行或报告生成前发现的配置、目录、模板或结果提示；不一定代表失败，但需要关注。
- `疑似旧结果`：统计表或图片可能旧于输入数据/统计表，存在误引用旧结果风险。
- `统计表旧于输入数据`：stats 文件修改时间早于对应原始数据目录。
- `图片旧于统计表`：图片修改时间早于 stats 文件，报告可能引用了旧图。
- `缺失统计表`：预期的 stats 文件不存在，对应报告章节可能无法自动填充。

GUI result diagnostics:
- `Artifacts`: number of generated files recorded by the run manifest, such as figures and stats files.
- `Preflight warnings`: configuration, folder, template, or result-readiness warnings found before running or building a report.
- `Possible stale results`: stats or figures may be older than their source data or stats file.
- `Stats older than input`: the stats file is older than the source data folder.
- `Figure older than stats`: the figure file is older than the stats file and may be stale.
- `Missing stats`: an expected stats file is not available.

When adding another analyzer, prefer this sequence: register the module in `ModuleRegistry`, create a thin analyzer adapter, add it to `AnalyzerFactory`, then add tests before replacing any legacy implementation.
新增分析模块时，建议顺序为：先在 `ModuleRegistry` 注册模块，再创建薄适配器，接入 `AnalyzerFactory`，补充测试后再考虑替换旧实现。

Lightweight external-data baseline checks can be run without rerunning heavy production analyses.
可用以下轻量检查确认历史回归数据目录和关键统计文件是否仍可用，不会重跑耗时生产分析。

```matlab
check_regression_baseline
```

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

- `v1.6.9`: refines the Jiulongjiang monthly summary page so monitoring operation status, data acquisition, and analysis conclusions are generated in the correct order with fewer internal table separators.
- `v1.6.9`：调整九龙江月报结论页，按“监测系统运行情况、本月监测数据情况、监测数据分析结果”顺序生成，并减少监测结果内部横线分隔。
- `v1.6.8`: improves Jiulongjiang monthly report output, especially patrol-report insertion, month-based date replacement, WPS-friendly blank-area cleanup, and page breaks before patrol photo attachments.
- `v1.6.8`：完善九龙江月报输出，重点优化人工巡查报告插入、按报告月份替换日期、清理 WPS 下易显示的空白区域，并在巡检表与附件照片之间分页。
- `v1.6.7`: adds cached-result report regression tooling and shared report artifact/table helpers for more stable production report checks.
- `v1.6.7`：增加既有结果报告回归脚本，并抽取报告产物查找、表格写入公共工具，提升生产报告检查稳定性。
- `v1.6.6`: completes cached-result regression checks for Guanbing March and Hongtang Q1 data; keeps report generation tolerant of missing local result figures.
- `v1.6.6`：完成管柄 3 月、洪塘一季度既有结果回归检查；报告生成在本地结果图缺失时保留模板内容并输出缺失清单。
- `v1.6.5`: fixes Guanbing April crack filtering, deflection/tilt report image replacement, deflection original/filtered image naming, nested ZIP recovery, and plot gap-mode propagation for dynamic strain.
- `v1.6.5`：修复管柄 4 月裂缝过滤、挠度/倾角报告插图替换、挠度原始/滤波图命名、嵌套 ZIP 恢复，以及动应变绘图断点模式传递。
- `v1.6.4`: fixes the plot settings tab encoding/syntax issue introduced in v1.6.3.
- `v1.6.4`：修复 v1.6.3 引入的绘图参数页编码/语法问题。
- `v1.6.3`: plot outputs no longer append the run timestamp by default; files keep the data period and overwrite the same-period results. The plot settings page can re-enable timestamp suffixes.
- `v1.6.3`：绘图结果默认不再追加运行时间戳；文件名保留数据周期，同周期重算会覆盖旧结果。可在绘图参数页重新启用时间戳后缀。

The report GUI now separates Hongtang monthly, Hongtang period, and Jiulongjiang monthly report modes; use `检查模板/目录` before generating on production machines.
报告 GUI 已区分洪塘月报、洪塘周期报和九龙江月报；生产机生成前建议先点击 `检查模板/目录`。

Report GUI release / 报告 GUI 版本:

- `v1.6.9`: keeps Jiulongjiang patrol reports as replaceable references and updates the generated summary table structure without hard-coding current patrol dates or layouts.
- `v1.6.9`：继续将九龙江巡查报告作为可替换参考源处理，并更新结论页监测结果表结构，不写死当前巡查日期和版式。
- `v1.6.8`: uses the Jiulongjiang 0506 template by default and treats the patrol report as a replaceable reference source; future patrol dates and layout changes can be handled by replacing the reference document.
- `v1.6.8`：九龙江月报默认使用 0506 模板，并将巡查报告作为可替换参考源；后续巡查日期和格式变化可通过替换参考文档处理。
- `v1.6.5`: adds Guanbing template precheck, Guanbing result-readiness warnings, and cached report regression support.
- `v1.6.5`：增加管柄模板预检、管柄结果就绪提示，以及既有结果报告回归支持。
- `v1.6.4`: restores shared report helpers for Guanbing monthly and Hongtang period generation, and avoids inserting unsupported EMF images through python-docx.
- `v1.6.4`：恢复管柄月报、洪塘周期报共用生成辅助函数，并避免通过 python-docx 插入不支持的 EMF 图片。
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
python reporting/template_precheck.py --kind guanbing_monthly --template reports/G104线管柄大桥监测月报模板-自动报告.docx --output-dir tmp/report_precheck
python reporting/smoke_report_generation.py --kind all
python reporting/smoke_report_generation.py --kind all --generate
powershell -ExecutionPolicy Bypass -File scripts/run_cached_report_regression.ps1 -KeepOutput
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
