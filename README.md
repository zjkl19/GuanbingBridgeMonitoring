# Guanbing Bridge Monitoring / 桥梁监测处理系统

## Overview / 概述

This repository contains the MATLAB analysis workflow and the Python/packaged report builder used for bridge monitoring projects.
本仓库包含桥梁监测项目使用的 MATLAB 分析流程，以及 Python / 打包版自动报告生成程序。

## Main Entry Points / 主要入口

### PySide6 Workbench (development branch)

The additive PySide6 workbench unifies project selection, local MATLAB job
launching, status/manifest review, an explicit plot-approval gate, and report
context handoff. It also includes the first migrated advanced editor for
explicit `alarm_bounds` values. The validated MATLAB analysis engine and the existing report
builders remain separate backend processes during migration.

PySide6 工作台以增量方式统一项目选择、本机 MATLAB 任务启动、状态/Manifest
审核、图件确认门禁和报告上下文传递。迁移期间，已经验证的 MATLAB 分析内核与
现有报告生成器仍作为独立后台保留。

开发版 EXE 构建与运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_workbench_exe.ps1
dist/BridgeMonitoringWorkbench/BridgeMonitoringWorkbench.exe
```

发布目录会同时包含 MATLAB 编译 Runner、配置/模板和通过
`--job-context` 冒烟测试的报告生成器。`release_manifest.json` 记录 EXE
哈希、发布清单自身以外的文件数/总大小及启动自测结果；`workbench_startup.png`、
`workbench_alarm_editor.png`、`workbench_cleaning_editor.png`、
`workbench_post_filter_editor.png`、`workbench_auto_threshold.png`、
`workbench_offset_editor.png`、`workbench_group_plot_editor.png`、
`workbench_plot_common_editor.png`、`workbench_spectrum_editor.png` 与
`workbench_report_task.png` 是构建时自动生成的界面证据。

“配置与预警值”页现已迁移显式 `alarm_bounds` 以及
`thresholds` / `zero_to_nan` / `outlier` 数据清洗字段。清洗编辑器支持默认和测点规则、
单边阈值、成对时间窗及历史 `1000/-1000` 全抑制哨兵；覆盖保存前执行源文件哈希校验并自动备份，
不会修改零点修正、滤波后二次清洗或绘图字段。

工作台现已增加独立“滤波后二次清洗”和“自动清洗建议”子页。后者仍调用
MATLAB `AutoThresholdProposalService`，由重新编译的同一
`BridgeAnalysisRunner.exe` 在独立进程生成建议；PySide6只负责参数、状态、人工复核和受保护写入。
建议不会自动落入配置，Runner 会在读取数据前校验请求固定的配置 SHA；只有勾选的
`range/window_range` 在二次确认、再次校验配置 SHA 和自动备份后写入。

“零点修正”页完整保留六桥现用的纯数值、`fixed`、首日/逐日/逐小时基线和
`segmented` 分段结构，并在写入前拒绝日期重叠。“组图配置”页直接管理
`groups` 与 `group_labels`，分开呈现应变统计组和时程组，支持测点筛选、排序及
历史二维数组无修改往返。两页均沿用源 SHA 漂移拒绝、自动备份和旧任务失效门禁。

“绘图公共参数”页覆盖六桥实际使用的全部 14 个 `plot_common` 字段，包括普通图点数、
缺口连接方式及高频原始图的 full/capped、line/dense_band 和线宽设置。取消“显式”会删除
该字段并回退 MATLAB 默认值；为避免产生与运行时不一致的配置，显式 `full` 不允许同时选择
`dense_band`。“频谱覆盖与找峰”页统一管理加速度/索力加速度频谱测点及默认、逐测点
`peak_orders`，保留采样率、阈值和未知字段；历史频率字段只在用户实际编辑后迁移。

“结果与图件审核”页会从绑定的分析 Manifest 枚举全部 `.plot.json`，逐序列核验 full、
未降采样、source=input、finite=plotted、日覆盖计数和不完整日期披露；缺少源级 provenance
或计数不闭环时不能勾选正式报告审核。“报告生成”页不再打开第二个 GUI，而是启动独立
报告子进程并显示预检、生成、QC、完成阶段。最终结果表展示 DOCX ZIP/主文档/媒体、可用
PDF 页数、报告 Manifest 缺失项与警告；配置、模板和分析 Manifest 的固定 SHA 仍会在子进程
读取前再次校验。

报告任务还会调用 LibreOffice 与 Poppler 将最终 DOCX 逐页渲染，生成页面 PNG、联系表和
`visual_qc.json`。自动门禁标出空白页及内容触碰页面边界；这些提示用于缩小人工复核范围，
联系表仍需人工确认。渲染输出使用短哈希目录，避免长中文报告名触发 Windows 路径上限。

报告子进程会独立重放完整门禁，而不只信任 UI 保存的“已审核”布尔值：固定配置、模板和
分析 Manifest 的 SHA256、桥梁/数据根/日期、所选模块覆盖、运行状态以及每个正式
`.plot.json` 的 full/source/input/finite/plotted 闭环都必须再次通过。缺少任何正式图
provenance 的旧 Manifest 不能用于嵌入式生产报告。可用
`scripts/validate_fresh_report_profiles.py` 审计五桥候选；`--generate-fallback` 只用于隔离的
生成器/版式回归，并会明确标为 `generator_only_fallback`，不能冒充通过正式门禁。

打包版右上角提供“检查更新”。正式版启动后每天最多自动查询一次 GitHub
Release；发现更高稳定版本时，可下载、双重 SHA256 校验、备份当前安装并在退出后
更新。现有项目配置不会被覆盖。发布资产命名和操作流程见
`docs/workbench_github_updates.md`。

```powershell
reporting/.venv/Scripts/python start_workbench.py
```

Headless smoke test / 无界面冒烟测试：

```powershell
reporting/.venv/Scripts/python start_workbench.py --smoke-test --smoke-output tmp/workbench_smoke.json
```

The migration design and current scope are documented in
`docs/pyside6_workbench_migration.md`. The legacy MATLAB GUI remains the
production entry until parity and production-cycle validation are complete.
迁移设计与当前范围见 `docs/pyside6_workbench_migration.md`；在功能对等和生产周期
验证完成前，旧 MATLAB GUI 仍是正式生产入口。

### MATLAB GUI

```matlab
start_gui
```

Use this GUI for analysis runs, threshold configuration, post-filter cleaning, zero-offset correction, and plot settings.
用于分析计算、阈值配置、滤波后二次清洗、零点修正和绘图参数配置。

GUI runs are launched asynchronously. In production, build and copy the compiled runner first; the GUI prefers `bin/BridgeAnalysisRunner/BridgeAnalysisRunner.exe` and falls back to `matlab.exe -batch` only in a full MATLAB development environment.
GUI 运行采用异步子进程。生产环境应先编译并随包复制独立 runner；GUI 会优先使用 `bin/BridgeAnalysisRunner/BridgeAnalysisRunner.exe`，只有完整 MATLAB 开发环境才回退到 `matlab.exe -batch`。

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_analysis_runner.ps1 -Clean
```

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
- `workbench/` unified PySide6 workbench and job contract / 统一 PySide6 工作台与任务契约
- `reporting/` report scripts and GUI / 报告脚本与 GUI
- `reports/` report templates / 报告模板
- `scripts/` deployment and utility scripts / 部署与辅助脚本

## Refactor Foundation / 重构基础

`bms` means Bridge Monitoring System. The package name is intentionally neutral and is not tied to Guanbing, Hongtang, Jiulongjiang, or the current repository name.
`bms` 表示 Bridge Monitoring System，包名刻意保持中性，不绑定管柄、洪塘、九龙江或当前仓库名称。

The MATLAB workflow now has an additive weak-MVC/OOP foundation. Existing analysis modules remain callable, while `run_all` delegates the run lifecycle to `bms.app.RunSession`. The GUI enters the pipeline through `bms_run_context`, which creates a `bms.core.AnalysisContext` and writes `analysis_manifest_*.json` under `<data-root>/run_logs`.
MATLAB 流程已增加增量式弱 MVC/OOP 基础。既有分析模块不重写；`run_all` 将运行生命周期交给 `bms.app.RunSession`。GUI 通过 `bms_run_context` 进入流程，创建 `bms.core.AnalysisContext`，并在 `<数据根目录>/run_logs` 写入 `analysis_manifest_*.json`。

The manifest is versioned with `schema_version=2`. It records enabled modules, each module's `ok/fail/skip` state, coarse `error_type`, messages, stats files, `run_log` path, elapsed time, missing expected stats files, offset-correction report path, artifact summary, data-index summary, and stats schema registry. This is the preferred machine-readable source for later report-generation checks.
运行清单带 `schema_version=2`。它会记录启用模块、各模块 `ok/fail/skip` 状态、粗粒度 `error_type`、错误信息、stats 文件、`run_log` 路径、耗时、缺失的预期统计文件、零点修正记录表路径、产物摘要、数据索引摘要和统计字段 schema。后续报告生成前检查应优先读取这个结构化文件。

Module metadata is now centralized in `bms.module.ModuleRegistry` / `bms.module.ModuleSpec`. `bms.app.StepDefinition`, `run_all`, the MATLAB GUI option mapping, expected stats files, and manifest preflight records all read from this registry. When adding a new module, register it first, then wire only the execution function and any report-specific logic.
模块元数据现在统一集中在 `bms.module.ModuleRegistry` / `bms.module.ModuleSpec`。`bms.app.StepDefinition`、`run_all`、MATLAB GUI 选项映射、预期 stats 文件和 manifest 预检记录都从该注册表读取。新增模块时，应先注册模块，再接执行函数和报告专项逻辑。

The application layer uses `bms.app.StepExecutor` / `bms.app.StepResult` to capture per-step timing, failure information, and error classification. `run_all` remains the compatible public entry point.
应用层通过 `bms.app.StepExecutor` / `bms.app.StepResult` 统一记录每个步骤的耗时、失败信息和错误分类。`run_all` 仍保持为兼容的公开入口。

Configuration saves from GUI tabs use `bms.core.ConfigStore.saveGuarded` to prevent accidental loss of unrelated protected fields such as `per_point.*.*.offset_correction`.
GUI 配置页保存时使用 `bms.core.ConfigStore.saveGuarded`，用于防止误删无关保护字段，例如 `per_point.*.*.offset_correction`。

New helper packages are intentionally small and side-effect-light: `bms.config.SchemaValidator` checks common config shape problems, `bms.data.*` resolves data roots and point aliases, `bms.plot.PlotService` normalizes plot options, and `bms.io.StatsWriter` centralizes stats-table writes.
新增辅助包刻意保持小而低副作用：`bms.config.SchemaValidator` 检查常见配置结构问题，`bms.data.*` 解析数据根目录和测点别名，`bms.plot.PlotService` 归一化绘图选项，`bms.io.StatsWriter` 集中处理统计表写入。

`bms.data.CleaningPipeline` centralizes the common data-cleaning operations used by time-series modules: offset correction, threshold filtering, zero-to-NaN conversion, and moving-window outlier removal. It also returns a cleaning log with removed counts. `load_timeseries_range` now delegates these common cleaning steps to this service, while legacy module-specific algorithms remain unchanged.
`bms.data.CleaningPipeline` 集中管理时程模块共用的数据清洗步骤：零点修正、阈值过滤、零值置空和滑动窗口异常值剔除，并返回清洗日志。`load_timeseries_range` 已将这些共用清洗步骤委托给该服务，既有模块专项算法不变。

`bms.data.TimeSeriesLoader` now provides reusable CSV series loading, numeric-column detection, closed-range clipping, and basic series summaries. New analysis code should prefer this helper instead of re-implementing time/value column detection.
`bms.data.TimeSeriesLoader` 现在提供可复用的 CSV 时程序列读取、数值列识别、闭区间裁剪和基础序列摘要。新增分析代码应优先使用该工具，避免重复实现时间列/数值列识别。

For large high-frequency periods, the time-series loader can automatically use
existing MAT caches after source CSV files have been archived. See
`docs/mat_only_timeseries_source.md` before deleting active CSV copies.
对于高频大数据周期，时程加载器可在原始 CSV 归档后自动使用已有 MAT 缓存。删除活动目录中的 CSV 前，先阅读
`docs/mat_only_timeseries_source.md`。

`bms.data.DataIndex` can build `data_index_*.json` and `data_index_summary_*.xlsx` under `<data-root>/run_logs` when `opts.buildDataIndex=true` or `config.data_index.enabled=true`. It maps enabled modules and configured points to actual source files, file counts, source metadata, and missing points. Use `scripts/build_data_index.m` when only a source-data inventory is needed. It is intentionally optional because indexing very large raw-data roots can add startup time.
`bms.data.DataIndex` 可在 `opts.buildDataIndex=true` 或 `config.data_index.enabled=true` 时，在 `<数据根目录>/run_logs` 生成 `data_index_*.json` 和 `data_index_summary_*.xlsx`。它把启用模块和配置测点映射到实际原始文件、文件数量、源文件元信息和缺失测点。只需要排查原始数据清单时，可单独调用 `scripts/build_data_index.m`。该功能默认保持可选，因为超大原始数据目录索引会增加启动耗时。

`bms.io.StatsSchema` centralizes report-facing stats fields, units and decimal precision; `bms.core.WarningEvaluator` centralizes range/upper-limit threshold judgement. New modules should use these services before adding report-specific formatting.
`bms.io.StatsSchema` 集中维护面向报告的统计字段、单位和小数位；`bms.core.WarningEvaluator` 集中处理区间阈值和上限阈值判断。新增模块在写报告专项格式前，应优先接入这些服务。

`bms.io.StatsInventory` can scan expected `stats/*.xlsx` outputs and write `stats_inventory_*.json` plus `stats_inventory_summary_*.xlsx` when `opts.buildStatsInventory=true` or `config.stats_inventory.enabled=true`. This provides a structured check for missing, empty, or unreadable stats files before report generation. Use `scripts/build_stats_inventory.m` when only a stats-output inventory is needed.
`bms.io.StatsInventory` 可在 `opts.buildStatsInventory=true` 或 `config.stats_inventory.enabled=true` 时扫描预期的 `stats/*.xlsx` 结果，并写出 `stats_inventory_*.json` 与 `stats_inventory_summary_*.xlsx`。它用于在报告生成前结构化检查统计表缺失、空表或无法读取等问题。只需要检查统计结果清单时，可单独调用 `scripts/build_stats_inventory.m`。

`bms.app.RunHealthReport` combines preflight warnings/errors, point coverage, data index, stats inventory, stale-artifact checks, and WIM input checks into `run_health_*.json` plus `run_health_summary_*.xlsx`. Enable it with `opts.buildRunHealthReport=true` or `config.run_health.enabled=true`. Enabling it also enables the data index and stats inventory for the same preflight run.
`bms.app.RunHealthReport` 将预检警告/错误、测点获取率、原始数据索引、统计结果清单、旧产物检查和 WIM 输入检查合并到 `run_health_*.json` 与 `run_health_summary_*.xlsx`。通过 `opts.buildRunHealthReport=true` 或 `config.run_health.enabled=true` 启用；启用后同一次预检会同时启用 data index 和 stats inventory。

Data-root conventions are isolated behind small adapters: `DatedFolderAdapter` handles `<root>/YYYY-MM-DD` and `<root>/YYYYMMDD`, `ZipDailyExportAdapter` handles `data_jlj_YYYY-MM-DD` / `data_sxh_YYYY-MM-DD` daily exports and ZIP files, and `PeriodFolderAdapter` handles period roots with `lowfreq` / `WIM`. `DataLayoutResolver` and preflight checks should call these adapters instead of hard-coding bridge-specific paths.
数据根目录约定已收口到小型 adapter：`DatedFolderAdapter` 处理 `<根目录>/YYYY-MM-DD` 和 `<根目录>/YYYYMMDD`，`ZipDailyExportAdapter` 处理 `data_jlj_YYYY-MM-DD` / `data_sxh_YYYY-MM-DD` 日导出目录和 ZIP，`PeriodFolderAdapter` 处理含 `lowfreq` / `WIM` 的周期目录。`DataLayoutResolver` 和预检逻辑应调用这些 adapter，不再散落硬编码各桥路径。

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
Dynamic strain boxplot figures remain in their figure folders; high-pass/low-pass boxplot stats are written to `stats/dynamic_strain_highpass_stats.xlsx` and `stats/dynamic_strain_lowpass_stats.xlsx`.
动应变箱线图图片仍写入对应图片目录；高通/低通箱线图统计结果统一写入 `stats/dynamic_strain_highpass_stats.xlsx` 和 `stats/dynamic_strain_lowpass_stats.xlsx`。
```

## Config Files / 配置文件

Common files.
常用配置。

- `config/default_config.json`
- `config/hongtang_config.json`
- `config/jiulongjiang_config.json`
- `config/zhishan_config.json`

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

Zhishan monthly reports use the edited `0609_1652` template. The builder preserves existing section structure and dynamic figure/table captions, then refreshes the main result tables and figures from `stats/` and the March result folders.
芝山月报使用已编辑的 `0609_1652` 模板。生成器保留原章节结构和动态图表编号，并从 `stats/` 及 3 月结果目录刷新主要结果表和图件。

```powershell
python reporting/build_zhishan_monthly_report.py --no-word-update
python reporting/smoke_report_generation.py --kind zhishan --generate --keep-output
python reporting/report_gui.py --self-test-zhishan --self-test-no-word-update
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

- `v1.7.39`: adds the full Hongtang typhoon high-frequency analysis workflow, Q2-template incremental/quick report paths, audited acceleration RMS conclusions, and final cross-application field/page locking.
- `v1.7.39`：新增洪塘台风高频完整数据分析流程、Q2 模板增量/快速报告路径、可审核的加速度 RMS 结论，以及跨办公软件的域与页码终稿锁定。
- `v1.7.38`: adds a guarded WPS Writer fallback, rejects field updates that produce broken references, and provides OOXML field/TOC staticization for stable production delivery.
- `v1.7.38`：新增带失败保护的 WPS Writer 回退；若域更新产生断链引用则自动拒绝，并提供 OOXML 字段与目录静态化，保证生产交付稳定。
- `v1.7.37`: keeps the MATLAB and report GUIs aligned with the Hongtang wind diagnostic memo and legacy period-template caption compatibility fix; wind analysis remains the validated v1.7.36 implementation.
- `v1.7.37`：同步洪塘风速专项排查简报与周期报旧模板题注兼容修复；风数据分析继续采用已验证的 v1.7.36 实现。
- `v1.7.36`: Wind-rose axes reserve title clearance above north and give radial percentage labels a readable background.
- `v1.7.36`：风玫瑰为北向标注与标题预留间距，并为百分比环标注增加可读底色。
- `v1.7.35`: Wind-rose radial percentage labels move into the north-east interior so they do not overlap the corrected east compass label.
- `v1.7.35`：风玫瑰百分比环标注移入东北象限内侧，避免与修正后的东向标注重叠。
- `v1.7.34`: Wind-rose compass labels now follow the meteorological convention: north is up and east is right.
- `v1.7.34`：风玫瑰方位标注改为气象约定：北向上、东向右。
- `v1.7.33`: Hongtang wind processing now reconstructs every calendar day from rolling D+D1 exports, rejects physically invalid negative wind speed, records source provenance for speed, direction, 10-minute and wind-rose plots, and reports bridge-deck W1 separately from tower-top W2 with a location-aware interpretation.
- `v1.7.33`：洪塘风数据按滚动导出 D+D1 重建完整自然日，剔除物理无效负风速，并为风速、风向、10min 和风玫瑰图记录源证明；报告分别陈述桥面 W1 与塔顶 W2，并加入基于测点位置的客观解释。
- `v1.7.32`: Zhishan reports now compare low-pass strain point ranges against configured alarm bounds and replace fixed "no abnormality" wording with the measured excursion, configured boundary, and a sensor/raw-data/site-review qualification when exceeded.
- `v1.7.32`：芝山报告会将低通应变测点范围与配置报警边界逐点比较；发生超限时，不再套用“未见异常”固定表述，而是写入实测值、配置边界及原始数据/传感器/现场复核要求。
- `v1.7.31`: adds an audited Zhishan report source-quality note that is written into both the data-coverage narrative and the monitoring-summary table, and pinned in the report build manifest. This supports explicit partial-day rolling-export disclosures without fabricating missing samples.
- `v1.7.31`：芝山报告新增可审计的源数据质量说明，同时写入数据覆盖段、监测结果汇总和报告构建 manifest，用于明确披露滚动导出造成的局部时段缺失，且不得伪造补齐。
- `v1.7.30`: keeps Zhishan SX-5 low-pass seasonal strain after March by removing its obsolete April-June ±100 με post-filter cleaning window. The March cap remains, other points are unchanged, and the configured SX-5 alarm range continues to be reported rather than used to erase valid samples.
- `v1.7.30`：取消芝山 SX-5 低通结果中过时的 4~6 月 ±100 με 清洗窗口，保留 3 月限制且不改变其它测点；SX-5 报警范围继续用于报告判定，不再用于删掉有效的季节慢变应变。
- `v1.7.29`: dynamic-strain high/low-pass analysis now defers absolute static-strain thresholds until after filtering. File aliases, offsets and other source cleaning remain active, while seasonal baseline drift can no longer erase otherwise finite dynamic-strain samples (notably Zhishan SX-5 in May-June).
- `v1.7.29`：动应变高/低通分析改为在滤波后执行动态阈值；文件映射、偏置及其它源数据清洗仍然保留，季节性基线漂移不再把有效动应变样本整月误删（典型为芝山 5~6 月 SX-5）。
- `v1.7.28`: fixes Zhishan CF-5 May-June baseline drift by retaining the validated April fixed offset and applying an hourly-median baseline in dated, non-overlapping offset segments; raw finite samples are no longer discarded merely because the rolling-export baseline moves within a day.
- `v1.7.28`：修复芝山 CF-5 在 5~6 月的基线漂移误删问题；4 月继续使用已验证的固定偏置，5~6 月在互不重叠的日期分段内采用逐小时中位数基线，避免滚动导出基线日内变化导致原始有限值被整段过滤。
- `v1.7.27`: aligns the MATLAB GUI with the Hongtang report image-token fix; analysis behavior remains the v1.7.26 rolling-export implementation.
- `v1.7.27`：同步洪塘报告图片测点精确匹配修复；数据分析行为继续沿用 v1.7.26 的滚动导出自然日重建实现。
- `v1.7.26`: fixes rolling-export calendar-day reconstruction for dynamic acceleration, including cross-month/quarter lookahead, explicit source completeness provenance, full baseline-style plotting, and safer high-frequency group behavior.
- `v1.7.26`：修复动态加速度滚动导出的自然日重建，支持跨月/跨季度读取下一导出目录，明确记录源完整性 provenance，恢复基线 full 绘图样式，并收紧高频组图行为。
- `v1.7.25`: keeps the MATLAB and report GUIs aligned with the hardened locked-media report release; analysis behavior remains the full-resolution `v1.7.24` implementation.
- `v1.7.25`：同步主分析 GUI 与报告生成器的媒体锁定安全加固版本；数据分析行为继续沿用 `v1.7.24` 的全量绘图实现。
- `v1.7.24`: adds an explicit `capped/full` raw dynamic sampling mode. Full mode plots every cleaned finite sample, forces sequential high-frequency processing with per-point release, supports full formal group plots, disables unsafe full-waveform EMF export, writes per-plot point-count provenance, and fixes the final-day boundary of structural group plots.
- `v1.7.24`：新增动态原始曲线 `capped/full` 采样模式。完整模式使用清洗后的全部有限样本，强制高频测点串行处理并逐点释放内存，支持正式组图全量绘制，禁用高风险的全波形 EMF 导出，逐图记录输入/绘制点数，并修复结构组图漏掉结束日期当天数据的问题。
- `v1.7.23`: tightens Zhishan April-June cleaning for bearing displacement, strain, dynamic strain, and structural acceleration, and switches high-frequency plot reduction to bucketed local-extrema sampling so capped monthly time-history plots keep a continuous envelope.
- `v1.7.23`：收紧芝山 4~6 月梁端位移、应变、动应变和结构加速度清洗规则，并将高频时程抽稀改为按时间桶保留局部极值，避免月度时程图因均匀抽点看起来像缺数据。
- `v1.7.22`: keeps the MATLAB GUI aligned with the Hongtang Q2 period-report template hardening release; analysis behavior is unchanged from `v1.7.21`.
- `v1.7.22`：同步洪塘 Q2 周期报模板与报告生成器加固版本；数据分析行为沿用 `v1.7.21`。
- `v1.7.21`: preserves critical extrema when plotting or saving downsampled time series across all measurement types, makes earthquake stats expose signed absolute peaks, and aligns earthquake plot markers/text with the same full-resolution peak used by reports.
- `v1.7.21`：所有测点类型的时程绘图和轻量 `.fig` 抽稀都会保留最小值、最大值和绝对峰值；地震动统计新增带符号绝对峰值，图上红点/文字标注与报告使用同一个全分辨率峰值。
- `v1.7.20`: fixes Hongtang Q2 period reports so table 1-2 is regenerated from the Q2 maintenance log, earthquake peak summaries map `EQ` + component stats rows to `EQ-X/Y/Z`, and bearing-displacement cleaning removes values outside each point's level-2 alarm bounds before rerun/reporting.
- `v1.7.20`：修复洪塘 Q2 周期报：表 1-2 改为按 Q2 维护日志生成，地震动统计表中 `EQ` + 方向分量正确映射到 `EQ-X/Y/Z`，支座位移重算前按各测点二级预警范围清洗超限值。
- `v1.7.19`: restores Hongtang Q2 SG-6/SL-8 strain thresholds after the recovered points showed usable data, makes the Hongtang low-frequency raw absolute-value guard sensor-specific so offset-corrected strain is not pre-filtered, switches Hongtang low-frequency cache to raw-only `__raw_v3.mat` files, keeps inverted thresholds available only as the legacy all-data suppression workaround, and converts static period-report figure/table captions to Word auto-number fields while preserving cross-reference bookmarks.
- `v1.7.19`：恢复洪塘 Q2 `SG-6`、`SL-8` 应变阈值，洪塘低频原始绝对值过滤改为按传感器类型生效，避免零点修正前误删应变数据；洪塘低频缓存改为只保存原始解析数据的 `__raw_v3.mat`；保留反向阈值作为历史坏点全量屏蔽兼容方式，并将周期报静态图表题注统一转为 Word 自动编号域且保留交叉引用书签。
- `v1.7.18`: adds the Hongtang Q2 report corrections for SG-6/Z11-2 offset correction, splits bearing-displacement raw/filtered output folders across the shared structural pipeline, and updates period-report WIM captions to Word auto-number fields with clearer overload-count wording.
- `v1.7.18`：补充洪塘 Q2 `SG-6`、`Z11-2` 零点修正，支座位移共用管线拆分原始/滤波输出目录，并将周期报 WIM 图表题改为 Word 自动编号域，同时优化超载车次表述。
- `v1.7.15`: adds automatic MAT-only time-series source support for large high-frequency datasets, including Hongtang legacy MAT-cache compatibility, safer point-name matching, data-index awareness, and regression tests for archived-CSV operation.
- `v1.7.15`：新增大数据时程 MAT-only 数据源自动识别，兼容洪塘旧 MAT 缓存，收紧测点文件名匹配，数据索引可识别 MAT 源，并补充 CSV 归档后的回归测试。
- `v1.7.14`: hardens Hongtang Q2 production processing: dated-folder loading for the Q2 layout, connected gap-mode propagation, day-reduced high-frequency/RMS handling for acceleration and cable acceleration, wind day aggregation, report-field update fallback through PowerShell Word COM, and Hongtang Q2 recovery documentation.
- `v1.7.14`：加固洪塘 Q2 生产处理链路：适配 Q2 日期目录读取，贯通 `gap_mode=connect`，加速度/索力加速度改为分日降采样与 RMS 聚合，风速风向改为分日聚合，报告字段更新增加 PowerShell Word COM 兜底，并沉淀洪塘 Q2 复跑说明。
- `v1.7.13`: adds machine-specific path profiles for local/remote data roots, exposes a hidden main-GUI smoke-test entry with stable handles, and adds main-window shortcuts for faster remote GUI validation.
- `v1.7.13`：新增本机/远程数据根目录路径 profile，主 GUI 支持隐藏窗口烟测入口并暴露稳定控件句柄，同时补充主窗口快捷键，便于远程环境快速验证 GUI。
- `v1.7.12`: keeps the MATLAB GUI version aligned with the report-generator release that commits the ShuiXianHua monthly period-label filename fix used by CLI and packaged exe self-tests.
- `v1.7.12`：同步主 GUI 版本号，配合报告生成器提交水仙花月报 CLI/打包 exe 自测使用的监测期标签与输出文件名修正。
- `v1.7.11`: fixes the report-builder packaging workflow so packaged exe folders include the bridge profile config files required by hidden self-tests and production default report modes.
- `v1.7.11`：修复报告生成器打包流程，打包后的 exe 目录会携带隐藏自测和生产默认报告模式所需的桥梁 profile 配置文件。
- `v1.7.10`: fixes Jiulongjiang monthly defaults so the 0508 accepted template and static-strain module are used by default, and keeps report generation tolerant of missing optional stats files while still writing a missing-data summary.
- `v1.7.10`：修正九龙江月报默认口径，默认使用已确认的 0508 模板并纳入静态应变模块；报告生成器在缺少可选统计表时不再直接中断，同时继续输出缺失数据清单。
- `v1.7.9`: fixes low-pass filtering across missing-data gaps by interpolating only for filter stability and restoring the original NaN mask, expands the default MATLAB test suite around cleaning, module registry, and Zhishan config checks, and adds safer Zhishan-from-Hongtang staging support for extracted CSV and ZIP sources.
- `v1.7.9`：修复低通滤波跨缺测段时的边界振铃问题，滤波前仅为稳定性临时插值、滤波后恢复原始 NaN 掩码；扩展默认 MATLAB 测试覆盖清洗流程、模块注册表和芝山配置检查；补充从洪塘混合导出中安全分离芝山数据的 CSV/ZIP 暂存工具。
- `v1.7.8`: adds expanded spectrum peak-order editing in the plot settings GUI, allowing per-module defaults and per-point overrides for each order's theoretical frequency and search band; the spectrum backend now accepts explicit `search_min_hz` / `search_max_hz` ranges.
- `v1.7.8`：绘图参数 GUI 新增展开式频谱找峰配置，可分别编辑模块默认值和单测点覆盖值，支持按阶次设置理论频率与搜索范围；频谱计算后端同步支持显式 `search_min_hz` / `search_max_hz`。
- `v1.7.6`: adds the Chongyangxi Bridge March 2025 processing profile refinements, fixes the acceleration group-plot folder name, separates 3.2 Hz peak-search frequency from the 2.83 Hz theoretical reference line, switches acceleration/RMS plots to `mm/s^2`, makes high-pass dynamic-strain time-series y-limits adaptive, and hardens GUI result-summary rendering.
- `v1.7.6`：完善崇阳溪大桥 2025 年 3 月处理配置，修正加速度组图目录名，区分 3.2 Hz 搜索频率与 2.83 Hz 理论参考线，将加速度/RMS 图统一为 `mm/s^2`，动应变高通时程图改为 y 轴自适应，并增强 GUI 结果汇总表对异常字段的兼容性。
- `v1.7.5`: adds the Zhishan Bridge March 2026 profile/config workflow, auto-cleaning proposal tooling, cable-acceleration display/review scripts, per-point cleaning/plot rules, and refreshed Zhishan strain, bearing-displacement, acceleration, cable-acceleration, and spectrum outputs.
- `v1.7.5`：新增芝山大桥 2026 年 3 月 profile/config 接入流程、自动清洗建议工具、索力加速度展示/复核脚本、按测点清洗与绘图规则，并刷新芝山应变、梁端纵向位移、加速度、索力加速度和频谱输出口径。
- `v1.7.4`: refactors config loading/editing around layered configs, adds a Shuixianhua layered-config pilot, clears config-lint warnings, and exposes analysis output contracts for report readiness checks.
- `v1.7.4`：围绕分层配置重构配置加载与 GUI 编辑链路，新增水仙花分层配置试点，清零配置 lint 提示，并输出分析结果契约供报告就绪检查使用。
- `v1.7.3`: refactors report/profile integration, reuses the shared dynamic-strain group plotting service, and keeps Jiulongjiang bearing-displacement outputs in profile-based readiness checks.
- `v1.7.3`：重构报告生成与桥梁 profile 的衔接，动应变组图复用统一时程绘图服务，并将九龙江支座位移纳入 profile 化结果就绪检查。
- `v1.7.2`: refines the Shuixianhua March data-processing workflow with updated deflection, bearing/expansion-joint displacement, strain, cable-acceleration, and acceleration-spectrum outputs; group plots now use the current thresholds and folder conventions needed by the report workflow.
- `v1.7.2`：完善水仙花 3 月数据处理流程，覆盖挠度、支座/伸缩缝位移、应变、索力加速度和加速度频谱等输出；组图统一使用当前预警值和报告生成所需的目录口径。
- `v1.7.0`: promotes the recent ShuiXianHua and data-processing work to a minor release: configurable acceleration-spectrum peak orders, standardized deflection single/group output folders, Shuixianhua deflection thresholds, and acceleration/RMS group plots with project threshold lines.
- `v1.7.0`：将近期水仙花与数据处理功能升级作为小版本发布：支持加速度频谱按配置识别阶次，统一挠度单图/组图输出目录，补充水仙花挠度阈值，并新增振动加速度/RMS 组图及项目预警线。
- `v1.6.11`: adds Shuixianhua sensor-ID mapping for the temperature/humidity combo sensor, keeps missing offline `WD-*` temperature points visible as data-availability issues, cleans stale scalar stats overwrites, and adjusts the GUI module display order.
- `v1.6.11`：新增水仙花温湿度一体传感器的测点编号映射；`WD-*` 温度测点因现场离线导致的缺失继续按数据可用性问题提示；修复标量统计表覆盖旧行残留，并调整 GUI 模块显示顺序。
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

- `v1.7.39`: adds the Hongtang typhoon full-data and quick-report workflows, Q2-template augmentation, audited RMS unit handling, and final caption/page-total locking.
- `v1.7.39`：新增洪塘台风完整数据/快速报告流程、Q2 模板增补、RMS 单位审核处理及题注/总页数终稿锁定。
- `v1.7.38`: can try WPS Writer when `Word.Application` is unavailable, but restores the original DOCX if WPS creates broken references; OOXML field/TOC staticization supports the final locked delivery path.
- `v1.7.38`：`Word.Application` 不可用时可尝试 WPS；若产生断链引用则恢复原 DOCX，并以 OOXML 字段/目录静态化完成最终锁定交付。
- `v1.7.37`: adds the Hongtang W1/W2 diagnostic memo builder and accepts the legacy deck-wind caption as a valid template anchor before replacing it with the location-aware caption.
- `v1.7.37`：新增洪塘 W1/W2 风速专项排查简报生成器，并允许旧版桥面风速题注作为模板锚点，再替换为区分桥面/塔顶的新题注。
- `v1.7.36`: reserves wind-rose title clearance and improves radial-label readability.
- `v1.7.36`：修正风玫瑰标题留白并提高百分比环标注可读性。
- `v1.7.35`: moves wind-rose radial percentage labels away from the corrected east compass label.
- `v1.7.35`：调整风玫瑰百分比环标注位置，避免与东向标注重叠。
- `v1.7.34`: corrects wind-rose compass labels to north-up/east-right meteorological orientation.
- `v1.7.34`：修正风玫瑰方位标注为气象学“北上东右”。
- `v1.7.33`: fixes Hongtang rolling-export wind coverage, validates wind domains and adds location-aware W1/W2 reporting with strict source provenance.
- `v1.7.33`：修复洪塘滚动导出风数据覆盖，增加风数据物理范围校验，并在严格源证明下按位置解释 W1/W2。
- `v1.7.32`: adds configuration-backed Zhishan low-pass strain alarm wording while preserving strict locked-media behavior.
- `v1.7.32`：新增基于配置边界的芝山低通应变报警表述，严格锁定媒体行为保持不变。
- `v1.7.31`: adds audited Zhishan source-quality-note support while preserving strict locked-media behavior.
- `v1.7.31`：新增芝山源数据质量说明的可审计生成支持，严格锁定媒体行为保持不变。
- `v1.7.30`: keeps the report GUI/package version aligned with the Zhishan SX-5 low-pass retention correction; report-generation behavior is unchanged.
- `v1.7.30`：同步芝山 SX-5 低通有效样本保留修复后的统一版本号；报告生成行为保持不变。
- `v1.7.29`: keeps the report GUI/package version aligned with the dynamic-strain source-retention correction; locked-media report behavior is unchanged.
- `v1.7.29`：同步动应变源数据保留修复后的统一版本号；锁定媒体报告行为保持不变。
- `v1.7.28`: keeps the report GUI/package version aligned with the Zhishan CF-5 processing correction; locked-media and exact point-token report behavior is unchanged from v1.7.27.
- `v1.7.28`：同步芝山 CF-5 数据处理修复后的统一版本号；锁定媒体和测点精确匹配逻辑沿用 v1.7.27。
- `v1.7.27`: rejects manifest prefix collisions during strict point-image lookup, preventing `CS1`/`CX1` report slots from selecting `CS12`/`CX12` figures.
- `v1.7.27`：报告按测点查图时拒绝 manifest 前缀碰撞，避免 `CS1`/`CX1` 槽位误选 `CS12`/`CX12` 图片。
- `v1.7.26`: adds an opt-in locked-media source-provenance gate so report bindings can reject legacy “full after truncation” plots while still accepting explicitly disclosed source gaps.
- `v1.7.26`：媒体锁定报告新增可选源 provenance 门禁，可拒绝历史“截断后 full”图，同时允许使用已明确披露真实源缺口的新图。
- `v1.7.25`: adds an opt-in `same_aspect_or_larger` policy for manifest-bound higher-resolution report figures while preserving exact dimensions by default, pins candidate dimensions in plan schema v2, rechecks candidate bytes against their SHA-256 immediately before writing, and keeps v1 plans readable as exact-only.
- `v1.7.25`：为清单绑定的高分辨率报告图片新增显式 `same_aspect_or_larger` 策略，默认仍要求像素尺寸完全一致；计划 schema 升至 v2 并固定候选图尺寸，写入前再次校验候选字节 SHA-256，同时将 v1 计划按 exact-only 兼容读取。
- `v1.7.24`: adds a strict locked-media DOCX workflow that replaces only explicitly approved `word/media/*` members, validates hashes and image dimensions, rejects shared slots, and proves that all non-media OOXML parts remain unchanged.
- `v1.7.24`：新增严格的 DOCX 媒体锁定流程，只替换显式批准的 `word/media/*` 成员，校验基线/候选哈希与图片尺寸，拒绝共享槽位，并验证所有非媒体 OOXML 内容完全不变。
- `v1.7.23`: keeps the report GUI aligned with the Zhishan Q2 tight-clean rerun; report generation behavior is unchanged from `v1.7.22`, and the regenerated reports should be rendered and checked with high-frequency key-image contact sheets.
- `v1.7.23`：同步芝山 Q2 收紧清洗与重算版本；报告生成逻辑沿用 `v1.7.22`，重生成后应渲染报告并用高频关键图联系表复核图片是否已替换且视觉连续。
- `v1.7.22`: adds the official Hongtang period-report auto template, derives quarterly report numbers, generalizes WIM anchors, falls back from incompatible WIM template tables, and removes stale template images before inserting fresh figures so checked reports can be reused as templates without duplicated figures.
- `v1.7.22`：新增正式洪塘周期报自动报告模板，自动推导季度报告编号，泛化 WIM 锚点，WIM 模板表格结构不兼容时自动回退为标准表格，并在插入新图前清理模板中的旧图，避免以已校核报告作模板时重复插图。
- `v1.7.12`: commits the ShuiXianHua monthly builder period-label parsing and output filename generalization so source, CLI, smoke tests, and packaged exe builds stay consistent.
- `v1.7.12`：提交水仙花月报生成器的监测期标签解析与输出文件名通用化修正，使源码、CLI、烟测和打包 exe 构建保持一致。
- `v1.7.11`: rebuilds the packaged report generator with copied bridge config files, restoring packaged ShuiXianHua/Zhishan self-tests and default config discovery in exe deployments.
- `v1.7.11`：重打包报告生成器时同步复制桥梁配置文件，恢复打包版水仙花/芝山自测和 exe 部署下的默认配置发现。
- `v1.7.10`: hardens the Jiulongjiang monthly report builder for production reruns by allowing missing optional stats sheets, aligning the default template with the accepted 0508 report, and adding regression coverage for the fallback.
- `v1.7.10`：增强九龙江月报生成器的生产补跑稳定性，缺少可选统计表时允许继续生成报告，默认模板对齐已确认的 0508 版本，并补充相应回归测试。
- `v1.7.9`: refreshes Zhishan monthly report filling for month labels, data-availability wording, offline temperature/humidity placeholders, and config/result-aligned summary text while preserving the existing template-driven layout.
- `v1.7.9`：完善芝山月报生成器的月份标题、数据可用性说明、温湿度离线占位和与配置/结果一致的汇总文字，继续保持基于模板的版式回填方式。
- `v1.7.8`: reads Zhishan structural-vibration theoretical/search-frequency wording from the active config, so report summaries stay aligned with per-point spectrum peak-order settings.
- `v1.7.8`：芝山结构振动理论频率和搜索频率说明改为从当前配置读取，使报告汇总文字与按测点频谱找峰配置保持一致。
- `v1.7.7`: upgrades the Zhishan monthly report generator to insert main-analysis output figures for AZ/CF PSD, cable acceleration, and cable-force time histories, preserving manual fallback assets; adds Zhishan packaged-exe smoke coverage.
- `v1.7.7`：升级芝山月报生成器，AZ/CF 频谱、索力加速度、索力时程图均优先使用主分析程序输出图件，保留人工兜底图件来源；补充芝山打包 exe 冒烟覆盖。
- `v1.7.6`: keeps the report GUI version aligned with the Chongyangxi March processing/runtime package release; report-builder behavior is unchanged from v1.7.5.
- `v1.7.6`：报告 GUI 版本与崇阳溪 3 月数据处理/运行时打包发布同步；报告生成器行为沿用 v1.7.5。
- `v1.7.5`: keeps the report GUI aligned with the Zhishan March data-processing release and documents the new Zhishan analysis/report asset workflow while preserving Shuixianhua report-builder fixes.
- `v1.7.5`：报告 GUI 版本与芝山 3 月数据处理发布同步，补充芝山分析/报告图件流程说明，并保留水仙花报告生成器修正。
- `v1.7.4`: reads the MATLAB analysis reporting contract in report build manifests, keeps missing-contract checks non-blocking for legacy outputs, and extracts reusable OOXML helpers for template table/text filling.
- `v1.7.4`：报告构建清单读取 MATLAB 分析结果契约，对旧结果目录缺少契约的情况保持非阻断提示，并抽取可复用的 OOXML 表格/文本回填工具。
- `v1.7.3`: refactors the Shuixianhua builder to update template tables by caption, moves result-readiness checks into a module/profile catalog, uses profile defaults in GUI and smoke tests, treats the Jiulongjiang patrol heading as optional, and adds a packaged-exe Shuixianhua self-test mode.
- `v1.7.3`：水仙花报告生成器改为按题注定位表格，结果就绪检查收口到模块/profile 目录，GUI 与冒烟测试统一读取 profile 默认值；九龙江巡查章节按模板可选处理，并新增打包 exe 水仙花自测入口。
- `v1.7.2`: fills Shuixianhua section 2.2 from the acquisition summary when available, and falls back to config/stats-derived coverage rows when that Excel is absent, so the monthly data-availability table is generated deterministically.
- `v1.7.2`：水仙花月报 2.2“本月监测数据情况”优先使用测点获取统计表，缺少该 Excel 时回退到配置和 stats 自动推导，确保数据获取情况表可确定性生成。
- `v1.7.1`: switches the Shuixianhua monthly report builder to fill the accepted template in place, preserves auto-numbered captions and existing layout, refreshes the deterministic stats tables/text from current processing outputs, and disables tracked changes in generated DOCX/PDF output.
- `v1.7.1`：水仙花月报生成器改为在已接受修订的模板上原位回填，保留自动编号题注和既有版式；按当前数据处理结果刷新可复现的统计表与文字，并关闭生成 DOCX/PDF 中的修订痕迹。
- `v1.7.0`: keeps the report GUI version aligned with the MATLAB GUI after the ShuiXianHua data-processing and plotting changes; report builders now look for the standardized deflection group-plot folder.
- `v1.7.0`：在水仙花数据处理与绘图功能升级后同步报告 GUI 版本；报告生成器同步使用标准化后的挠度组图目录。
- `v1.6.11`: adds the Shuixianhua monthly report mode, template assets, and generator path while keeping the report GUI version aligned with the MATLAB GUI release.
- `v1.6.11`：增加水仙花月报模式、模板资产和生成器入口，并保持报告 GUI 与 MATLAB GUI 版本一致。
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
