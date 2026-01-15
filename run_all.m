function run_all(root, start_date, end_date, opts, cfg)
tic;
% Disable ModifiedAndSavedVarnames warning
ws = warning('off','MATLAB:table:ModifiedAndSavedVarnames');

% Paths
here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fullfile(here,'pipeline'));
addpath(fullfile(here,'config'));
addpath(fullfile(here,'analysis'));
addpath(fullfile(here,'scripts'));

% Config
if nargin < 5 || isempty(cfg)
    cfg = load_config();
end

% Subfolder shortcuts (with fallback)
sub = struct();
sub.temperature  = get_subfolder(cfg, 'temperature',  '特征值');
sub.humidity     = get_subfolder(cfg, 'humidity',     '特征值');
sub.deflection   = get_subfolder(cfg, 'deflection',   '特征值_重采样');
sub.tilt         = get_subfolder(cfg, 'tilt',         '波形_重采样');
sub.accel        = get_subfolder(cfg, 'acceleration', '波形_重采样');
sub.accel_raw    = get_subfolder(cfg, 'acceleration_raw', '波形');
sub.crack        = get_subfolder(cfg, 'crack',        '特征值');
sub.strain       = get_subfolder(cfg, 'strain',       '特征值');

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
    run_step('温度分析', @() analyze_temperature_points(root, pts, start_date, end_date, 'temp_stats.xlsx', sub.temperature, cfg));
end

if opts.doHumidity
    pts = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
    run_step('湿度分析', @() analyze_humidity_points(root, pts, start_date, end_date, 'humidity_stats.xlsx', sub.humidity, cfg));
end

if opts.doDeflect
    run_step('挠度分析', @() analyze_deflection_points(root, start_date, end_date, ...
        'deflection_stats.xlsx', sub.deflection, cfg));
end

if opts.doTilt
    run_step('倾角分析', @() analyze_tilt_points(root, start_date, end_date, 'tilt_stats.xlsx', sub.tilt, cfg));
end
if opts.doAccel
    run_step('加速度分析', @() analyze_acceleration_points(root, start_date, end_date, ...
        'accel_stats.xlsx', sub.accel, true, cfg));
end

% -------- Acceleration spectrum analysis --------
if opts.doAccelSpectrum
    accel_pts = { ...
        'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
        'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
        'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
        'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};   % same as time-domain analysis
    run_step('加速度频谱', @() analyze_accel_spectrum_points( ...
        root, start_date, end_date, accel_pts, ...
        'accel_spec_stats.xlsx', sub.accel_raw, ...   % use raw waveform
        [1.150 1.480 2.310], 0.15, false, cfg));
end

if opts.doRenameCrk
    batch_rename_crk_T_to_t(root, start_date, end_date, true);
end
if opts.doCrack
    run_step('裂缝分析', @() analyze_crack_points(root, start_date, end_date, 'crack_stats.xlsx', sub.crack, cfg));
end
if opts.doStrain
    run_step('应变分析', @() analyze_strain_points(root, start_date, end_date, 'strain_stats.xlsx', sub.strain, cfg));
end

if isfield(opts,'doDynStrainBoxplot') && opts.doDynStrainBoxplot
    run_step('动应变箱线图', @() analyze_dynamic_strain_boxplot( ...
        root, start_date, end_date, ...
        'Subfolder',   sub.strain, ...                 % folder: root>\YYYY-MM-DD\特征值\*.csv
        'OutputDir',   '箱线图结果_高通滤波', ...     % output root
        'Fs',          20, ...                       % sample rate: 20 Hz
        'Fc',          0.1, ...                      % high-pass cutoff: 0.1 Hz
        'Whisker',     300, ...                      % boxplot whisker control
        'ShowOutliers', false, ...                   % show outliers
        'YLimManual',  true, ...
        'YLimRange',   [-30 30], ...                 % y-axis range
        'LowerBound',  -150, ...                     % remove outliers threshold (NaN)
        'UpperBound',   150, ...
        'EdgeTrimSec',   5 ...                       % trim edges after filtfilt (seconds)
        ));
end

% Restore warning
warning(ws);
fprintf('总耗时: %.2f 秒\n', toc);
end

function sub = get_subfolder(cfg, key, fallback)
    sub = fallback;
    if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, key)
        sub = cfg.subfolders.(key);
    end
end

function run_step(label, fcn)
    try
        fcn();
    catch ME
        warning('%s 失败: %s', label, ME.message);
    end
end
