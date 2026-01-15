function run_all(root, start_date, end_date, opts)
tic;
% 关闭读取表格时那条“ModifiedAndSavedVarnames”警告
ws = warning('off','MATLAB:table:ModifiedAndSavedVarnames');

if opts.precheck_zip_count
    precheck_zip_count(root, start_date, end_date);
end

if opts.doUnzip
    batch_unzip_data_parallel(root, start_date, end_date, true);
end

if opts.doRenameCsv
    batch_rename_csv(root, start_date, end_date, true);
end

if opts.doRemoveHeader
    batch_remove_header(root, start_date, end_date, true);
end

if opts.doResample
    batch_resample_data_parallel(...
        root, start_date, end_date, 100, true, 'batch_resample_data_parallel_config.csv');
end

if opts.doTemp
    pts = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
    analyze_temperature_points(root, pts, start_date, end_date, 'temp_stats.xlsx', '特征值');
end

if opts.doHumidity
    pts = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
    analyze_humidity_points(root, pts, start_date, end_date, 'humidity_stats.xlsx', '特征值');
end

if opts.doDeflect
    analyze_deflection_points(root, start_date, end_date, ...
        'deflection_stats.xlsx', '特征值_重采样');
end

if opts.doTilt
    analyze_tilt_points(root, start_date, end_date, 'tilt_stats.xlsx', '波形_重采样');
end
if opts.doAccel
    analyze_acceleration_points(root, start_date, end_date, ...
        'accel_stats.xlsx', '波形_重采样', true);
end

% -------- 加速度谱分析 --------
if opts.doAccelSpectrum
    accel_pts = { ...
        'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
        'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
        'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
        'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};   % 与时域分析保持一致
    analyze_accel_spectrum_points( ...
        root, start_date, end_date, accel_pts, ...
        'accel_spec_stats.xlsx', '波形', ...        % ← 注意：重采样前“波形”原始 1 kHz 文件
        [1.150 1.480 2.310], 0.15, false);
end

if opts.doRenameCrk
    batch_rename_crk_T_to_t(root, start_date, end_date, true);
end
if opts.doCrack
    analyze_crack_points(root, start_date, end_date, 'crack_stats.xlsx', '特征值');
end
if opts.doStrain
    analyze_strain_points(root, start_date, end_date, 'strain_stats.xlsx', '特征值');
end

if isfield(opts,'doDynStrainBoxplot') && opts.doDynStrainBoxplot
    % 动应变高通滤波 + 跨日箱线图（G05/G06 各一张）
    % 参数可按需调整；以下为推荐默认
    try
        analyze_dynamic_strain_boxplot( ...
            root, start_date, end_date, ...
            'Subfolder',   '特征值', ...                 % 目录：<root>\YYYY-MM-DD\特征值\*.csv
            'OutputDir',   '箱线图结果_高通滤波', ...     % 输出根目录
            'Fs',          20, ...                       % 采样频率：20 Hz
            'Fc',          0.1, ...                      % 高通截止：0.1 Hz
            'Whisker',     300, ...                      % 箱线图胡须/离群控制
            'ShowOutliers', false, ...                   % 是否展示离群点
            'YLimManual',  true, ...
            'YLimRange',   [-30 30], ...                 % y 轴范围
            'LowerBound',  -150, ...                     % 去异常阈值（置 NaN）
            'UpperBound',   150, ...
            'EdgeTrimSec',   5 ...                       % filtfilt 后首尾修剪秒数
            );
    catch ME
        warning('动应变箱线图模块运行失败：%s', ME.message);
    end
end

% 恢复警告
warning(ws);
fprintf('总耗时: %.2f 秒\n', toc);
end
