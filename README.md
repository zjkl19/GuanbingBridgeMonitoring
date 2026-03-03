# Guanbing Bridge Monitoring

桥梁监测数据处理与报表生成工具（MATLAB）。

## 1. 快速启动

- GUI（一键）  
  在项目根目录 MATLAB 命令行运行：
  ```matlab
  start_gui
  ```

- GUI（手动）  
  ```matlab
  addpath(fullfile(pwd,'ui'));
  run_gui
  ```

- CLI  
  ```matlab
  run_all(root, start_date, end_date, opts, cfg)
  ```

## 2. 目录结构

- `analysis/`：各分析模块（温度、湿度、挠度、支座位移、倾角、加速度、频谱、索力、裂缝、风速风向、地震动、WIM 等）
- `pipeline/`：数据读取、适配器、清洗逻辑
- `config/`：配置文件与加载函数
- `ui/`：GUI 代码（入口 `run_gui.m`）
- `scripts/`：辅助脚本（含 WIM SQL 脚本、提示音等）
- `tests/`：单元测试
- `outputs/`：运行日志、图表、报表输出

## 3. 配置文件

- 默认配置：`config/default_config.json`
- 洪塘配置：`config/hongtang_config.json`
- 九龙江配置：`config/jiulongjiang_config.json`

建议按桥梁复制一份配置后再改，不要直接改默认配置。

## 4. run_all 模块开关（opts）

常用字段：

- 预处理：`precheck_zip_count`、`doUnzip`、`doRenameCsv`、`doRemoveHeader`、`doResample`
- 常规模块：`doTemp`、`doHumidity`、`doDeflect`、`doBearingDisplacement`、`doTilt`、`doAccel`、`doCrack`、`doStrain`
- 频谱/索力：`doAccelSpectrum`、`doCableAccel`、`doCableAccelSpectrum`
- 其他：`doWind`、`doEq`、`doWIM`、`doDynStrainBoxplot`

示例：

```matlab
addpath('config','pipeline','analysis','scripts');
cfg = load_config('config/hongtang_config.json');

opts = struct( ...
    'precheck_zip_count', false, ...
    'doUnzip', false, 'doRenameCsv', false, 'doRemoveHeader', false, 'doResample', false, ...
    'doTemp', false, 'doHumidity', false, ...
    'doDeflect', false, 'doBearingDisplacement', false, 'doTilt', false, ...
    'doAccel', false, 'doAccelSpectrum', false, ...
    'doCableAccel', false, 'doCableAccelSpectrum', false, ...
    'doCrack', false, 'doStrain', false, 'doDynStrainBoxplot', false, ...
    'doWind', false, 'doEq', false, 'doWIM', true, ...
    'doRenameCrk', false ...
);

run_all('D:\Data\Hongtang', '2026-01-01', '2026-01-31', opts, cfg);
```

## 5. WIM（动态称重）流程

入口：`analysis/analyze_wim_reports.m`  
支持两种管线：

- `wim.pipeline = "direct"`：直接读取源文件统计
- `wim.pipeline = "database"`：先入 SQL Server，再跑 SQL 报表

### 5.1 洪塘（智宸天驰 bcp/fmt）

主要配置（`config/hongtang_config.json`）：

- `wim.vendor = "zhichen"`
- `wim.input.zhichen.dir`：`bcp/fmt` 所在目录
- `wim.input.zhichen.bcp` / `fmt`：支持 `{yyyymm}` 模板
- `wim_db.*`：数据库连接与导入策略（`import_mode`: `truncate` / `skip_if_exists`）

程序输出：

- 多个报表 CSV（Daily/Lane/Speed/Gross/Hourly/Custom/TopN/Overload）
- 汇总 Excel：`WIM_Report_{bridge}_{yyyymm}.xlsx`
- 若启用 `wim_plot.enabled`，同时生成图和总结文本

### 5.2 SQL Server 服务说明

当 `wim.pipeline = "database"` 时，程序会尝试检查并启动 SQL Server 服务。  
默认服务名在配置里：`wim_db.service_name`（常见：`MSSQLSERVER` 或 `MSSQL$SQLEXPRESS`）。

手动查看服务（PowerShell）：

```powershell
Get-Service | Where-Object { $_.Name -like 'MSSQL*' } | Select-Object Name, Status
```

## 6. 提示音通知

配置 `notify`：

```json
"notify": {
  "enabled": true,
  "on_analysis_done": true,
  "on_task_done": true,
  "on_error": true,
  "mode": "beep"
}
```

实现脚本：`scripts/play_notify_sound.m`

## 7. 测试

- 推荐入口：
  ```matlab
  run_tests
  run_tests('smoke')
  run_tests('all')
  ```

- 也可直接：
  ```matlab
  runtests('tests/test_jlj_adapter.m');
  ```

## 8. 常见问题

- 结果全是 NaN：优先检查 `defaults/per_point` 阈值是否过严
- 九龙江数据读不到：检查 `data_adapter`、日期目录命名和 `points` 是否一致
- WIM 数据库模式失败：先确认 SQL Server 服务、`sqlcmd`、`wim_db.server`、`import_mode`

