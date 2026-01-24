# Guanbing 项目使用说明

## 快速启动
- GUI 一键：在项目根目录的 MATLAB 命令行运行 `start_gui`（自动添加 ui 路径）。
- GUI 手动：`addpath(fullfile(pwd,'ui')); run_gui`。若提示 `uilabel` 未识别，可先执行 `addpath(fullfile(matlabroot,'toolbox','matlab','uicomponents','uicomponents'));`。
- CLI：`run_all(root, start_date, end_date, opts, cfg)`。

## 目录结构（简述）
- `config/`：配置文件与加载脚本。
- `pipeline/`：数据读取与清洗。
- `analysis/`：各类分析模块。
- `ui/`：GUI（入口 `run_gui.m`，一键脚本 `start_gui.m`）。
- `tests/`：单元测试与测试配置。
- `outputs/`：运行日志、图表等输出。

## 配置与数据
默认配置位于 `config/default_config.json`；测试配置位于 `tests/config/test_config.json`。根据实际数据结构调整 `subfolders`、`file_patterns` 等键值。

## 单元测试
在项目根目录运行：
```matlab
addpath('pipeline','config','analysis','tests');
runtests;                        % 全部
% 或者：runtests('tests/test_simulated_data.m');
```

## 常用命令示例
```matlab
addpath('config','pipeline','analysis','scripts');
cfg = load_config('config/default_config.json');
opts = struct('precheck_zip_count', false, 'doUnzip', false, 'doRenameCsv', false, ...
    'doRemoveHeader', false, 'doResample', false, ...
    'doTemp', false, 'doHumidity', false, 'doDeflect', true, ...
    'doTilt', false, 'doAccel', false, 'doAccelSpectrum', false, ...
    'doRenameCrk', false, 'doCrack', false, 'doStrain', false, 'doDynStrainBoxplot', false);
run_all('F:\数据根目录', '2025-08-01', '2025-08-02', opts, cfg);
```

