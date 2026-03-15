# Monthly Report Automation

当前版本已接入以下模块：

- 结构应变监测
- 主塔倾斜监测
- 支座变位监测
- 吊索索力监测
- 主梁、主塔振动监测
- 风向风速监测
- 地震动监测

脚本读取标准 `.docx` 模板，并基于现有计算结果自动生成：

- 章节文字摘要
- 按图逐张插入的报告图片
- 报告 `docx`
- 图片查找明细 `manifest.json`

## Environment

本地虚拟环境目录：

- `reporting/.venv`

安装或更新依赖：

```powershell
reporting/.venv/Scripts/python -m pip install -r reporting/requirements.txt
```

## Recommended usage

推荐把 `--result-root` 直接指向月度结果根目录，例如：

- `E:\洪塘数据\2025年12月`

脚本会：

- 优先从 `result-root` 读取统计表
- 若统计表不在 `result-root`，则回退到 `analysis-root`
- 从 `result-root` 递归查找图片目录
- 默认把报告输出到 `result-root\自动报告`

示例：

```powershell
reporting/.venv/Scripts/python reporting/build_monthly_report.py `
  --template "reports/洪塘大桥健康监测2025年12月份月报 - 新模板2 - 副本.docx" `
  --config "config/hongtang_config.json" `
  --result-root "E:\洪塘数据\2025年12月" `
  --analysis-root "."
```

如需自定义输出目录：

```powershell
reporting/.venv/Scripts/python reporting/build_monthly_report.py `
  --template "reports/洪塘大桥健康监测2025年12月份月报 - 新模板2 - 副本.docx" `
  --config "config/hongtang_config.json" `
  --result-root "E:\洪塘数据\2025年12月" `
  --analysis-root "." `
  --output-dir "E:\洪塘数据\2025年12月\自动报告"
```

## GUI

已提供最小可用 PySide6 GUI：

- `reporting/report_gui.py`

直接运行：

```powershell
reporting/.venv/Scripts/python reporting/report_gui.py
```

GUI 首版支持：

- 选择模板文件
- 选择配置文件
- 选择月结果目录
- 选择分析根目录
- 选择输出目录
- 生成报告
- 查看日志
- 打开输出目录

## Build EXE

客户机无 Python 环境时，可先在开发机打包为 Windows `exe`：

```powershell
powershell -ExecutionPolicy Bypass -File reporting/build_gui_exe.ps1
```

默认生成位置：

- `reporting/dist/MonthlyReportBuilder/MonthlyReportBuilder.exe`

## Output

默认输出内容：

- 报告清单：`自动报告\report_manifest_*.json`
- 生成的报告：`自动报告\*.docx`

## Reporting config

`config/hongtang_config.json` 中可选 `reporting` 配置块，用于控制报告各模块的开关和顺序。

当前支持：

- `enabled`
- `order`
- `girder_order`
- `tower_order`
- `force_order`
- `include`
- `exclude`

示例：

```json
"reporting": {
  "cable_force": {
    "enabled": true,
    "order": ["CS4", "CX4", "CS5", "CX5"],
    "force_order": ["CS4", "CX4", "CS5", "CX5"],
    "include": [],
    "exclude": []
  }
}
```

规则：

- 未配置时，脚本使用内置默认顺序
- 配置 `order` / `girder_order` / `tower_order` / `force_order` 时，按配置顺序插图
- `exclude` 中的点位或分组会被跳过
- 如需临时屏蔽异常图，优先通过 `exclude` 处理，不建议手工移动结果文件

## Image lookup rules

当前查图规则：

- 结构应变
  - 目录：`plot_styles.strain.boxplot_output_dir`
  - 前缀：`StrainBox_B_` ~ `StrainBox_L_`
- 主塔倾斜
  - 目录：`plot_styles.tilt.output_dir`
  - 前缀：`Tilt_Q1-Z_`、`Tilt_Q1-H_`、`Tilt_Q2-Z_`、`Tilt_Q2-H_`
- 支座变位
  - 目录：`plot_styles.bearing_displacement.output_dir`
  - 前缀：`BearingDisp_<PointID>_`
- 吊索索力
  - 目录：`时程曲线_索力加速度`、`时程曲线_索力加速度_RMS10min`、`索力时程图`
- 主梁、主塔振动
  - 目录：`时程曲线_加速度`、`时程曲线_加速度_RMS10min`、`频谱峰值曲线_加速度`
- 风向风速
  - 目录：`风速风向结果\风速10min`、`风速风向结果\风玫瑰`
- 地震动
  - 目录：`地震动结果\地震动时程`

支持图片格式：

- `.jpg`
- `.png`
- `.jpeg`

## Recommended directory convention

建议保持原程序生成的月度目录树，不需要手工搬运图片。例如：

- `E:\洪塘数据\2025年12月\箱线图_应变`
- `E:\洪塘数据\2025年12月\时程曲线_倾斜`
- `E:\洪塘数据\2025年12月\时程曲线_支座位移`
- `E:\洪塘数据\2025年12月\索力时程图`
- `E:\洪塘数据\2025年12月\风速风向结果`

这样月报脚本可以直接读取整个月目录。

## Template strategy

当前阶段不依赖书签或内容控件。
脚本通过模板中的现有章节标题、图题和表头文本定位内容。
如果后续模板改版频繁，再考虑增加显式书签或占位符。
