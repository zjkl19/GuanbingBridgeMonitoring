# 使用说明（Guanbing 项目）

## 快速开始
1) 运行环境：MATLAB R2024a（Signal Processing / Statistics Toolbox 可选，用于分析与绘图）。
2) 配置文件：`config/default_config.json`（可复制一份自定义）。
3) 命令行入口：`run_all(root, start_date, end_date, opts, cfg)`，或使用 GUI `addpath(fullfile(pwd,'ui')); run_gui`。
4) 输出：分析结果/日志等默认写入 `outputs/`。

## 目录结构
- `config/`：`default_config.json`（主配置）、`load_config.m`（加载与校验）。
- `pipeline/`：数据读取、清洗与适配层，核心 `load_timeseries_range.m`。
- `analysis/`：各类分析脚本（温度、湿度、挠度、倾角、加速度、频谱、裂缝、应变、动应变箱线图等）。
- `ui/`：GUI 启动脚本 `run_gui.m`。
- `tests/`：单元测试（目前有 `test_load_timeseries_range.m`）。
- `outputs/`：运行日志、图表等输出；`outputs/ui_last_preset.json` 会自动保存上次 GUI 参数。

## 配置说明（换桥、换传感器时主要修改）
`config/default_config.json` 关键字段：
- `vendor`：厂商标识（现支持 `donghua`，可扩展）。加载器会按此选择文件查找/读取策略。
- `defaults.header_marker`：CSV 中标记数据开始的行（东华默认 `[绝对时间]`）。不同厂商表头行可在此调整。
- `subfolders`：各传感器在 `root/YYYY-MM-DD/` 下的子目录名（如 `特征值`、`波形_重采样`、`波形`）。路径不对会导致找不到文件。
- `file_patterns`：按传感器类型的文件名匹配模式。`default` 支持占位 `{point}`；若某测点文件名特殊可在 `per_point` 单独配置。
  - 例：`"crack": { "default": ["{point}_*.csv"] }`
  - 若裂缝温度文件名不同，可添加 `"crack_temp"` 或在 `per_point` 写死。
- `points`：各模块的测点列表（示例：`acceleration`、`accel_spectrum`）。换桥时可在此直接改测点，无需改代码。若缺失则代码回退到内置列表。
- `defaults.<sensor>`：每类传感器的清洗默认值：
  - `thresholds`：数组，每项可含 `min`/`max`（数值），可选时间窗 `t_range_start`/`t_range_end`（`yyyy-MM-dd HH:mm:ss`）。命中则超出阈值置 NaN。
  - `zero_to_nan`：布尔，是否把 0 视为缺失。
  - `outlier`：`window_sec` + `threshold_factor`，使用 `isoutlier(movmedian)` 过滤。
- `per_point.<sensor>.<point_id>`：指定测点的清洗规则，字段同上，覆盖 defaults。
- `groups`：分组绘图的点列表（挠度/应变等）；换桥时按新测点调整。
- `plot_styles`：绘图样式
  - 颜色：如 `colors_2`/`colors_3`/`colors_6` 为 RGB 列表。
  - 预警线：`warn_lines` 列表，包含 `y`、`label`、`color`。
  - 轴范围：`ylim` 或分组 `ylims`（如应变 G05/G06 不同范围）。

修改流程（换一座桥的建议步骤）：
1) 复制 `config/default_config.json` 为新文件（如 `config/bridge_X.json`），在 GUI 或命令行指定该路径。
2) 更新 `subfolders` 以匹配新数据目录结构。
3) 更新 `file_patterns`：
   - 先设置通用 `default` 模式，如 `{point}_*.csv`。
   - 若个别测点文件名不一致，补充到 `per_point`。
4) 调整 `defaults.<sensor>` 阈值/清洗规则；如需区分测点，再在 `per_point` 填写。
5) 更新 `groups` 与 `plot_styles` 以适配新测点和预警线。
6) 如更换厂商且文件格式/表头有差异，可先将 `vendor` 标记为新名字，后续按“厂商适配层”扩展。

## 厂商适配层（扩展点）
`pipeline/load_timeseries_range.m` 通过 `get_vendor_loader` 调用对应 loader。默认 loader：
- `find_file(...)`：按 `file_patterns` 或名称包含 `point_id` 查找文件。
- `read_file(...)`：按 header_marker 跳过表头，读取时间+数值两列，支持缓存；读取时会自动尝试多种编码/时间格式（UTF-16LE、UTF-8，带/不带毫秒；失败则 textscan 回退），兼容旧设备 CSV。

如新增厂商：
1) 在 `get_vendor_loader` 增加 `case 'newvendor'`。
2) 编写类似 `make_donghua_loader` 的函数，处理新厂商的文件名、表头、时间格式等。
3) 如时间格式不同，调整 `readtable` 的 `Format` 或自定义解析。

## GUI 使用
1) `addpath(fullfile(pwd,'ui')); run_gui`
2) 填写：数据根目录、开始/结束日期、模块勾选、预处理勾选、日志目录、配置文件。
3) 可用“全选/全不选”快速切换所有预处理与模块。
4) 运行时自动保存参数到 `outputs/ui_last_preset.json`，下次启动自动加载；也可手动保存/加载预设。
5) 日志实时显示，结果摘要写入 `outputs/run_logs`。

## 命令行使用示例
```matlab
addpath('config'); addpath('pipeline'); addpath('analysis'); addpath('scripts');
cfg = load_config('config/default_config.json');
opts = struct( ...
    'precheck_zip_count', false, 'doUnzip', false, 'doRenameCsv', false, ...
    'doRemoveHeader', false, 'doResample', false, ...
    'doTemp', false, 'doHumidity', false, 'doDeflect', true, ...
    'doTilt', false, 'doAccel', false, 'doAccelSpectrum', false, ...
    'doRenameCrk', false, 'doCrack', false, 'doStrain', false, 'doDynStrainBoxplot', false);
run_all('F:\数据根', '2025-08-01', '2025-08-02', opts, cfg);
```

## 缓存与清理
- 单文件缓存存放在每日日志目录下的 `cache/xxx.mat`；如调整解析格式，可删除对应 `cache` 目录或改动文件时间戳。
- 运行日志：`outputs/run_logs`。
- GUI 最近参数：`outputs/ui_last_preset.json`（可删除以重置）。

## 单元测试
- 运行：`matlab -batch "addpath('pipeline');addpath('config');addpath('tests');runtests('tests/test_load_timeseries_range.m')"`
- 测试数据为临时生成，不依赖真实数据。

## 常见调整清单（换桥时逐项检查）
- [ ] `vendor`
- [ ] `defaults.header_marker`
- [ ] `subfolders` 路径名称
- [ ] `file_patterns`（default + per_point）
- [ ] 各传感器 `defaults` 清洗规则
- [ ] `per_point` 特殊阈值
- [ ] 分组 `groups` 与绘图样式 `plot_styles`
- [ ] GUI/命令行选择的配置文件路径

## 如何告知程序“哪些测点属于哪种传感器类型”
- 传感器类型由分析脚本决定：每个分析函数会传入测点列表并指定 `sensor_type`（如 `acceleration`、`crack`、`strain`）。配置文件只负责“文件在哪、怎么清洗”，不负责“哪些点属于哪类传感器”。
- 更换桥梁时，需要在对应分析脚本里更新测点列表：
  - 温度：`analysis/analyze_temperature_points.m`
  - 湿度：`analysis/analyze_humidity_points.m`
  - 挠度：`analysis/analyze_deflection_points.m`
  - 倾角：`analysis/analyze_tilt_points.m`
  - 加速度：`analysis/analyze_acceleration_points.m`（时间域），`analysis/analyze_accel_spectrum_points.m`（频谱）
  - 裂缝：`analysis/analyze_crack_points.m`
  - 应变：`analysis/analyze_strain_points.m`
  - 动应变箱线图：`analysis/analyze_dynamic_strain_boxplot.m`
- 如果新增一种传感器类型：新增相应分析脚本，调用 `load_timeseries_range` 时传入新的 `sensor_type`，同时在配置文件中为该类型补充 `subfolders`、`file_patterns`、`defaults`/`per_point` 等字段。

## 参考
- 核心入口：`run_all.m`
- 数据加载：`pipeline/load_timeseries_range.m`
- 配置加载：`config/load_config.m`
- GUI：`ui/run_gui.m`

