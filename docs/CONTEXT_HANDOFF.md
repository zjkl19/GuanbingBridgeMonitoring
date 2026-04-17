# 项目上下文交接备忘

本文件用于解决长对话被压缩或近期内容不完整显示时的上下文恢复问题。以后如果对话历史不完整，先阅读本文件，再查看最近 git commit。

## 当前架构判断

- 现阶段维持单仓库结构更合适：MATLAB 负责数据分析与绘图，Python `reporting/` 负责自动报告生成。
- 暂不拆成两个独立项目，也不做 MATLAB 到 Python 的全量重构。
- 管柄、洪塘相对稳定，可作为标准化样板；九龙江仍在适配阶段，先稳定九龙江后再评估架构调整。
- 当前重点不是统一语言，而是稳定 MATLAB 输出与 Python 报告生成之间的文件接口。

## 近期洪塘报告生成状态

- 周期报默认模板已切到 `洪塘大桥健康监测2026年第一季季报-改4.docx`。
- `BridgeReportBuilder` 周期报默认类型为“周期报（含WIM）”。
- WIM 表格已改为从 `改4.docx` 中克隆人工调好的表格 XML，再填充数据，避免后续重复人工调表格格式。
- 典型 WIM 表格包括：
  - `表 4-1 2026年第一季度交通状况分月统计表`
  - 每月车流量统计表
  - 前 10 总重最重车辆参数表及续表
  - 前 10 最大轴重车辆参数表及续表
- `CS1/CX1` 图片匹配已修复，避免误匹配到 `CS12/CX12`。
- 应变报告图片目录字段已做缺省兼容，避免配置缺少 `group_output_dir` 时直接报错。

## 最近已推送的关键 commit

- `8943469 Update Hongtang period report generation`
  - 健康监测系统运行状况保留原段落，缺失情况表格插到原段落后。
  - WIM 超限统计支持 1.5/2.0 倍总重和轴重，0 值不再写出。
  - 地震动结果写入第 4 章 `4.8 地震动监测` 后。
- `e9b8307 Improve Hongtang WIM report table templating`
  - WIM 表格改为克隆模板表格 XML。
  - 修复 `CS1/CX1` 与 `CS12/CX12` 图片匹配串号。
  - 增加应变报告图片目录缺省兼容。

## 发布包状态

- `reporting/dist/BridgeReportBuilder/BridgeReportBuilder.exe` 已在本地重新打包。
- `reporting/dist/` 当前在 `.gitignore` 中，不纳入 git。
- 发布包内 `reports/` 已包含 `洪塘大桥健康监测2026年第一季季报-改4.docx`。

## 当前未跟踪本地文件

这些文件目前未纳入 git，处理前需要单独确认：

- `config/default_config_g.json`
- `output/`
- `reports/`
- `scripts/build_online_plan_xlsx.py`
- `tmp/`
- `tmp_doc_check.py`

## 后续建议

- 继续保留本文件作为长期上下文锚点。
- 每次完成较大改动并 commit 后，同步更新“最近已推送的关键 commit”和“当前状态”。
- 后续可以新增 `docs/analysis_reporting_contract.md`，专门定义 MATLAB 输出与 Python 报告生成之间的接口规范。
