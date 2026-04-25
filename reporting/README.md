# Reporting / 报告生成

## Scope / 范围

The report builder supports both monthly reports and period reports.
报告生成程序同时支持月报和周期报。

- `月报 / Monthly Report`
- `周期报（含 WIM） / Period Report (with WIM)`

## Packaged GUI / 打包 GUI

The packaged directory should contain at least the following files.
打包目录至少应包含以下文件。

```text
BridgeReportBuilder/
  BridgeReportBuilder.exe
  _internal/
  reports/
    洪塘大桥健康监测月报模板.docx
    洪塘大桥健康监测2026年第一季季报-改4.docx
    九龙江大桥健康监测2026年3月份月报_修订5.docx
  README.md
  REPORTING_LOGIC.md
```

Keep `BridgeReportBuilder.exe` and `_internal/` together.
`BridgeReportBuilder.exe` 和 `_internal/` 必须一起保留。

## Data Root / 数据根目录

Templates stay under `reports/`. Runtime outputs stay under the data root.
模板放在 `reports/`，运行产物放在数据根目录。

Recommended layout.
推荐目录如下。

```text
E:/洪塘大桥数据/2026年1-3月/
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
    strain_stats.xlsx
    tilt_stats.xlsx
    bearing_displacement_stats.xlsx
    wind_stats.xlsx
  run_logs/
  自动报告/
```

## GUI Fields / GUI 字段说明

- `报告类型 / Report Type`
  - `月报` 或 `周期报（含 WIM）`
- `模板文件 / Template`
  - Monthly default: `洪塘大桥健康监测月报模板.docx`
  - Period default: `洪塘大桥健康监测2026年第一季季报-改4.docx`
  - The current automatic period-report layout assumes this default template.
  - 当前自动周期报布局默认按这份模板适配。
- `配置文件 / Config`
  - Prefer machine-specific override when present.
  - 存在机器专用配置时优先使用。
- `数据/结果根目录 / Data and Result Root`
  - Contains plots, `stats/`, `run_logs/`, and `自动报告/`.
  - 用于存放图片、`stats/`、`run_logs/` 和 `自动报告/`。
  - For period reports, section `1.4 健康监测系统运行状况` is only accurate when this root also contains the raw source data needed for missing-data checks.
  - 对周期报，`1.4 健康监测系统运行状况` 只有在该目录同时包含原始数据时才准确。
- `程序根目录（高级） / Program Root (Advanced)`
  - Compatibility fallback for code and template lookup.
  - 用于代码、模板的兼容查找，通常保持程序所在目录即可。
- `WIM 结果目录 / WIM Result Root`
  - Usually `<数据/结果根目录>/WIM/results/hongtang`.
  - 通常是 `<数据/结果根目录>/WIM/results/hongtang`。
- `输出目录 / Output Directory`
  - Usually `<数据/结果根目录>/自动报告`.
  - 通常是 `<数据/结果根目录>/自动报告`。

## Config Keys Used Directly / 直接影响报告生成的配置项

The report generator reads these config sections directly.
报告程序会直接读取以下配置项。

- `plot_styles.*.output_dir`
- `plot_styles.*.boxplot_output_dir`
- `plot_styles.*.group_output_dir`
- `reporting.*`
- `wim.*`
- `wim_db.*`

Thresholds, zero-offset corrections, and alarm bounds affect reports indirectly through regenerated analysis outputs.
阈值、零点修正和预警值通过分析结果间接影响报告。

## Monthly Report / 月报

Use a single result directory for one monitoring period.
月报使用单个监测周期的结果目录。

## Period Report / 周期报

Use the period template, result root, WIM monthly results, and a date range.
周期报需要周期模板、结果根目录、WIM 月结果和起止日期。

Important note for period reports:
周期报的重要说明：

- Non-WIM sections are assembled from the result root.
- WIM is still inserted month by month from `WIM/results/hongtang/<yyyymm>/`.
- `1.4 健康监测系统运行状况` checks raw missing/no-file/no-record conditions. If the result root contains only derived outputs but not raw data, this section will report many missing items.

- 非 WIM 章节从结果根目录读取。
- WIM 仍按月从 `WIM/results/hongtang/<yyyymm>/` 插入。
- `1.4 健康监测系统运行状况` 统计的是原始缺失/无文件/无记录。如果结果根目录只有处理结果而没有原始数据，该节会显示大量缺失。
- GUI 中的 `监测时间` 是报告显示文字，可人工调整，例如 `2026年01月01日~2026年03月31日`；`开始日期` 和 `结束日期` 用于推导 WIM 月份范围。

CLI debugging example:
CLI 调试示例：

```powershell
python reporting\build_period_report.py `
  --template reports\洪塘大桥健康监测2026年第一季季报-改4.docx `
  --config config\hongtang_config.json `
  --result-root "E:\洪塘大桥数据\2026年1-3月" `
  --wim-root "E:\洪塘大桥数据\2026年1-3月\WIM\results\hongtang" `
  --monitoring-range "2026年01月01日~2026年03月31日" `
  --start-date 2026-01-01 `
  --end-date 2026-03-31 `
  --debug-section cable_force
```

`--debug-section` can print `cable_force`, `vibration`, `wim`, or `health_status` from the generated manifest.
`--debug-section` 可输出生成清单中的 `cable_force`、`vibration`、`wim` 或 `health_status`，便于核查图片路径、统计值和缺失项。

The GUI performs a preflight check before generating a period report and warns when:
生成周期报前，GUI 会做输入校验，并在以下情况给出警告：

- `lowfreq/data.xlsx` is missing
- no raw `YYYY-MM-DD` directories are found under the selected data root
- `stats/` is missing
- WIM monthly result folders are missing for some months

- 缺少 `lowfreq/data.xlsx`
- 所选数据根目录下没有 `YYYY-MM-DD` 形式的原始数据目录
- 缺少 `stats/`
- 部分月份缺少 WIM 月结果目录


## Report GUI Workflow / 报告 GUI 使用步骤

Version `v1.6.1` separates report modes explicitly and writes template precheck reports.
版本 `v1.6.1` 已明确拆分报告类型，并会输出模板预检报告。

1. Select report type first: `洪塘月报`, `洪塘周期报（含WIM）`, or `九龙江月报`.
2. Confirm the auto-switched template, config, and data/result root.
3. Click `检查模板/目录` before generation.
4. If the check has no blocking error, click `生成报告`.
5. Review `<输出目录>/precheck/` when the GUI reports template anchors or result folders are missing.

1. 先选择报告类型：`洪塘月报`、`洪塘周期报（含WIM）` 或 `九龙江月报`。
2. 确认程序自动切换后的模板、配置和数据/结果根目录。
3. 生产机生成前先点击 `检查模板/目录`。
4. 没有阻断错误后再点击 `生成报告`。
5. 如果提示模板锚点或结果目录缺失，到 `<输出目录>/precheck/` 查看 txt/json 预检报告。

Report mode notes.
报告类型说明。

- `洪塘月报`: legacy Hongtang monthly-report pipeline for one calculated month.
- `洪塘周期报（含WIM）`: Hongtang period/quarter report, including WIM monthly insertion and section 1.4 raw-missing checks.
- `九龙江月报`: independent Jiulongjiang monthly-report pipeline for main bridge and ramp-bridge sections.

- `洪塘月报`：旧洪塘月报流程，适用于单月已计算结果。
- `洪塘周期报（含WIM）`：洪塘周期/季报流程，包含 WIM 按月插入和 1.4 原始数据缺失统计。
- `九龙江月报`：九龙江独立月报流程，按主桥和匝道桥章节生成。

## Output Locations / 输出位置

- Report document / 报告文档: `<result-root>/自动报告/`
- Precheck reports / 模板预检报告: `<result-root>/自动报告/precheck/`
- Stats workbooks / 统计表: `<result-root>/stats/`
- Run logs / 运行日志: `<result-root>/run_logs/`
- WIM monthly results / WIM 月结果: `<result-root>/WIM/results/hongtang/<yyyymm>/`

## Template Precheck / 模板预检

The precheck verifies key headings, table captions, figure-caption anchors, and auto-number fields before generation.
预检会在生成前检查关键标题、表题、图题插入锚点和自动编号域。

GUI checks write both text and JSON reports under `<输出目录>/precheck/`.
GUI 检查会在 `<输出目录>/precheck/` 同时写入 txt 和 json 报告。

CLI examples.
CLI 示例。

```powershell
python reporting\template_precheck.py `
  --kind hongtang_period `
  --template reports\洪塘大桥健康监测2026年第一季季报-改4.docx `
  --output-dir tmp\report_precheck

python reporting\smoke_report_generation.py --kind all
```

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

