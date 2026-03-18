# Reporting Logic / 报告业务逻辑

## Purpose / 目的

This note explains how the report generator locates and replaces content in Word templates.
本文说明报告程序如何在 Word 模板中定位并替换内容。

## General Rule / 总体规则

The generator does not rebuild the whole document. It looks for existing section titles, figure captions, and table anchors, then fills the matched locations.
程序不会重建整份文档。它会查找现有的章节标题、图题和表格锚点，然后在匹配位置填入内容。

## Module Mapping / 模块映射

- `结构应变 / Strain`
  - Replaces the strain summary and inserts strain time-series and boxplot figures.
  - 替换应变摘要，插入应变时程图和箱线图。
- `主塔倾斜 / Tower Tilt`
  - Replaces the tilt summary and inserts tilt figures.
  - 替换倾斜摘要，插入倾角图。
- `支座变位 / Bearing Displacement`
  - Replaces the bearing summary and inserts bearing time-series figures.
  - 替换支座摘要，插入支座时程图。
- `吊索索力 / Cable Force`
  - Replaces the cable force summary, fills the cable force table, and inserts cable force figures.
  - 替换索力摘要，填充索力表，插入索力图。
- `主梁、主塔振动 / Vibration`
  - Replaces the vibration summary and inserts acceleration, RMS, and frequency figures.
  - 替换振动摘要，插入加速度、RMS 和频率图。
- `风向风速 / Wind`
  - Replaces the wind summary, fills the wind statistics table, and inserts wind figures.
  - 替换风摘要，填充风统计表，插入风速和风玫瑰图。
- `地震动 / Earthquake`
  - Replaces the earthquake summary and inserts EQ-X, EQ-Y, and EQ-Z figures.
  - 替换地震动摘要，插入 EQ-X、EQ-Y、EQ-Z 图。
- `WIM / 称重系统`
  - Period reports insert WIM month by month.
  - Each month includes summary text, traffic table, top-10 gross weight table, top-10 axle weight table, and six traffic figures.
  - 周期报中 WIM 按月插入。每个月包含摘要、车流量统计表、前 10 总重表、前 10 轴重表及六张交通图。
- `1.4 健康监测系统运行状况 / System Health Status`
  - Only raw missing/no-file/no-record conditions are counted.
  - This section is accurate only when the selected result root also contains the raw source data required by the missing-data scan.
  - 只统计原始缺失/无文件/无记录。
  - 只有当所选结果根目录同时包含原始数据时，这一节才是准确的。

## Config Keys Used Directly / 直接读取的配置项

The report generator reads these config sections directly.
报告程序会直接读取以下配置项。

- `plot_styles.*.output_dir`
- `plot_styles.*.group_output_dir`
- `plot_styles.*.boxplot_output_dir`
- `reporting.*`
- `wim.*`
- `wim_db.*`

## Important Constraint / 重要约束

If section titles, figure captions, or table titles in the template change, the anchor-matching logic may need to be updated as well.
如果模板中的章节标题、图题或表题发生变化，锚点匹配逻辑也需要同步调整。
