# Reporting

报告生成支持两类入口：

- 月报
- 周期报（含 WIM）

当前口径已经统一到**数据目录**。模板仍放程序目录 `reports/`，其他统计表、图片、报告产物都放在数据目录。

## 1. 环境

安装依赖：

```powershell
reporting/.venv/Scripts/python -m pip install -r reporting/requirements.txt
```

如果直接使用打包好的 GUI，可跳过这一步。

## 2. 数据目录约定

建议的数据目录结构：

```text
E:\洪塘大桥数据\2026年1-3月\
  lowfreq\
    data.xlsx
  WIM\
    HS_Data_202601.bcp
    HS_Data_202601.fmt
    HS_Data_202602.bcp
    HS_Data_202602.fmt
    HS_Data_202603.bcp
    HS_Data_202603.fmt
    results\
      hongtang\
        202601\
        202602\
        202603\
  stats\
    strain_stats.xlsx
    tilt_stats.xlsx
    bearing_displacement_stats.xlsx
    wind_stats.xlsx
    ...
  自动报告\
  时程曲线_倾斜\
  时程曲线_支座位移\
  箱线图_应变\
  ...
```

说明：

- 模板继续放程序目录 `reports/`
- 统计表统一放数据目录 `stats/`
- 报告默认输出到数据目录 `自动报告/`
- WIM 月结果统一放数据目录 `WIM/results/hongtang/<yyyymm>/`

## 3. 月报命令行

```powershell
reporting/.venv/Scripts/python reporting/build_monthly_report.py `
  --template "reports\洪塘大桥健康监测2025年12月份月报 - 新模板2.docx" `
  --config "config\hongtang_config.json" `
  --result-root "E:\洪塘大桥数据\2026年1-3月" `
  --analysis-root "."
```

默认输出：

- `E:\洪塘大桥数据\2026年1-3月\自动报告`

## 4. 周期报（含 WIM）命令行

```powershell
reporting/.venv/Scripts/python reporting/build_period_report.py `
  --template "reports\洪塘大桥健康监测2025年12月份月报 - 新模板2.docx" `
  --config "config\hongtang_config.json" `
  --result-root "E:\洪塘大桥数据\2026年1-3月" `
  --wim-root "E:\洪塘大桥数据\2026年1-3月\WIM\results\hongtang" `
  --period-label "2026年1-3月" `
  --monitoring-range "2026.01.01~2026.03.16" `
  --report-date "2026年03月17日" `
  --start-date "2026-01-01" `
  --end-date "2026-03-16"
```

说明：

- 非 WIM 模块默认直接从 `result-root` 读取统计表和图片
- WIM 默认从 `wim-root` 读取已处理好的月结果
- 周期报第一版假设分析结果已经提前算好，报告程序不负责重算

## 5. GUI

启动：

```powershell
reporting/.venv/Scripts/python reporting/report_gui.py
```

GUI 当前行为：

- 默认结果目录：`E:\洪塘大桥数据\2026年1-3月`
- 默认输出目录：`<结果目录>\自动报告`
- 默认 WIM 结果目录：`<结果目录>\WIM\results\hongtang`
- 如果存在机器专用配置：
  - `config\hongtang_config_<COMPUTERNAME>.json`
  - GUI 会优先选它

报告类型：

- `月报`
- `周期报（含WIM）`

## 6. 打包 GUI

```powershell
powershell -ExecutionPolicy Bypass -File reporting/build_gui_exe.ps1
```

输出：

- `reporting/dist/MonthlyReportBuilder/MonthlyReportBuilder.exe`

## 7. 配置说明

`config/hongtang_config.json` 中 `reporting` 配置当前支持：

- `enabled`
- `order`
- `girder_order` / `tower_order`
- `force_order`
- `include`
- `exclude`

机器专用配置建议单独放：

- `config/hongtang_config_<COMPUTERNAME>.json`

这样可以保留生产机路径、SQL Server 实例等环境差异，同时继续跟随主线业务配置更新。
