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
    洪塘大桥健康监测周期报模板.docx
    洪塘大桥健康监测周期报模板0318.docx
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
  - Period default: `洪塘大桥健康监测周期报模板.docx`
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

## Output Locations / 输出位置

- Report document / 报告文档: `<result-root>/自动报告/`
- Stats workbooks / 统计表: `<result-root>/stats/`
- Run logs / 运行日志: `<result-root>/run_logs/`
- WIM monthly results / WIM 月结果: `<result-root>/WIM/results/hongtang/<yyyymm>/`
