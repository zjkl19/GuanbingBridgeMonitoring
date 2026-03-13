# Monthly Report Automation

当前首版已接入 3 个模块：

- 结构应变监测
- 主塔倾斜监测
- 支座变位监测

脚本会读取标准 `.docx` 模板，基于已有计算结果自动生成：

- 章节文字摘要
- 报告拼图
- 报告 `docx`
- 一份带图片查找明细的 `manifest.json`

## Environment

本地虚拟环境目录：

- `reporting/.venv`

安装或更新依赖：

```powershell
reporting/.venv/Scripts/python -m pip install -r reporting/requirements.txt
```

## Recommended usage

推荐把“月报结果根目录”直接指向月度结果目录，例如：

- `E:\洪塘数据\2025年12月`

程序会：

- 优先从 `result-root` 读取统计表
- 如果统计表不在 `result-root`，则回退到 `analysis-root`
- 从 `result-root` 下递归查找图片目录
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

## Output

默认输出内容：

- 报告清单：`自动报告\report_manifest_*.json`
- 生成的拼图：`自动报告\generated_assets\`
- 生成的报告：`自动报告\*.docx`

## Image lookup rules

当前图片查找规则：

- 结构应变
  - 目录名：`plot_styles.strain.boxplot_output_dir`
  - 文件前缀：`StrainBox_B_` ~ `StrainBox_L_`
- 主塔倾斜
  - 目录名：`plot_styles.tilt.output_dir`
  - 文件前缀：`Tilt_Q1-Z_`、`Tilt_Q1-H_`、`Tilt_Q2-Z_`、`Tilt_Q2-H_`
- 支座变位
  - 目录名：`plot_styles.bearing_displacement.output_dir`
  - 文件前缀：`BearingDisp_<PointID>_`

支持的图片格式：

- `.jpg`
- `.png`
- `.jpeg`

程序会在 `result-root` 下递归查找这些目录，并选择匹配前缀的最新图片。

## Recommended directory convention

建议继续保持原程序生成的月度目录树，不需要手工搬运图片，例如：

- `E:\洪塘数据\2025年12月\箱线图_应变`
- `E:\洪塘数据\2025年12月\时程曲线_倾斜`
- `E:\洪塘数据\2025年12月\时程曲线_支座位移`

这样月报脚本可以直接读取，不需要额外整理。

## Template strategy

当前阶段不依赖书签或内容控件。

脚本通过模板中现有的章节标题和图题文本定位内容。
如果后续模板改版频繁，建议再增加显式书签或占位符。
