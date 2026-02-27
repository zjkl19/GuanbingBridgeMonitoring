function run_all(root, start_date, end_date, opts, cfg)
% run_all  统一入口，串联预处理与各分析模块，支持软停止。
global RUN_STOP_FLAG;
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

log_records = {};
start_ts = datetime('now');

% Config warnings
if isfield(cfg,'warnings') && ~isempty(cfg.warnings)
    for i = 1:numel(cfg.warnings)
        warning('Config: %s', cfg.warnings{i});
        log_records{end+1} = struct('label','config', 'status','warn', 'message', cfg.warnings{i}); %#ok<AGROW>
    end
end

% Subfolder shortcuts (with fallback)
sub = struct();
sub.temperature  = get_subfolder(cfg, 'temperature',  '特征值');
sub.humidity     = get_subfolder(cfg, 'humidity',     '特征值');
sub.deflection   = get_subfolder(cfg, 'deflection',   '特征值_重采样');
sub.tilt         = get_subfolder(cfg, 'tilt',         '波形_重采样');
sub.accel        = get_subfolder(cfg, 'acceleration', '波形_重采样');
sub.accel_raw    = get_subfolder(cfg, 'acceleration_raw', '波形');
sub.cable_accel  = get_subfolder(cfg, 'cable_accel', '索力加速度_重采样');
sub.cable_accel_raw = get_subfolder(cfg, 'cable_accel_raw', '索力加速度');
sub.crack        = get_subfolder(cfg, 'crack',        '特征值');
sub.strain       = get_subfolder(cfg, 'strain',       '特征值');
sub.wind_raw     = get_subfolder(cfg, 'wind_raw',     '波形');
sub.eq_raw       = get_subfolder(cfg, 'eq_raw',       '波形');

results = {};
RUN_STOP_FLAG = false;

if opts.precheck_zip_count && ~should_stop()
    results{end+1} = run_step('预检查压缩包数量', @() precheck_zip_count(root, start_date, end_date)); %#ok<AGROW>
end

if opts.doUnzip && ~should_stop()
    results{end+1} = run_step('批量解压', @() batch_unzip_data_parallel(root, start_date, end_date, true)); %#ok<AGROW>
end

if opts.doRenameCsv && ~should_stop()
    results{end+1} = run_step('批量重命名CSV', @() batch_rename_csv(root, start_date, end_date, true)); %#ok<AGROW>
end

if opts.doRemoveHeader && ~should_stop()
    results{end+1} = run_step('批量去除表头', @() batch_remove_header(root, start_date, end_date, true)); %#ok<AGROW>
end

if opts.doResample && ~should_stop()
    results{end+1} = run_step('批量重采样', @() batch_resample_data_parallel(...
        root, start_date, end_date, 100, true, 'batch_resample_data_parallel_config.csv')); %#ok<AGROW>
end

if opts.doTemp && ~should_stop()
    temp_fallback = {'GB-RTS-G05-001-01','GB-RTS-G05-001-02','GB-RTS-G05-001-03'};
    pts = get_sensor_points(cfg, 'temperature', temp_fallback);
    if isempty(pts)
        results{end+1} = struct('label','temperature','status','skip','message','No temperature points configured');
    else
        results{end+1} = run_step('温度分析', @() analyze_temperature_points(root, pts, start_date, end_date, 'temp_stats.xlsx', sub.temperature, cfg));
    end
end

if opts.doHumidity && ~should_stop()
    hum_fallback = {'GB-RHS-G05-001-01','GB-RHS-G05-001-02','GB-RHS-G05-001-03'};
    pts = get_sensor_points(cfg, 'humidity', hum_fallback);
    if isempty(pts)
        results{end+1} = struct('label','humidity','status','skip','message','No humidity points configured');
    else
        results{end+1} = run_step('湿度分析', @() analyze_humidity_points(root, pts, start_date, end_date, 'humidity_stats.xlsx', sub.humidity, cfg));
    end
end

if isfield(opts,'doWind') && opts.doWind && ~should_stop()
    results{end+1} = run_step('风速风向分析', @() analyze_wind_points(root, start_date, end_date, sub.wind_raw, cfg));
end

if isfield(opts,'doEq') && opts.doEq && ~should_stop()
    results{end+1} = run_step('地震动分析', @() analyze_eq_points(root, start_date, end_date, sub.eq_raw, cfg));
end

if isfield(opts,'doWIM') && opts.doWIM && ~should_stop()
    results{end+1} = run_step('WIM', @() analyze_wim_reports(root, start_date, end_date, cfg));
end

if opts.doDeflect && ~should_stop()
    results{end+1} = run_step('挠度分析', @() analyze_deflection_points(root, start_date, end_date, ...
        'deflection_stats.xlsx', sub.deflection, cfg));
end

if opts.doTilt && ~should_stop()
    results{end+1} = run_step('倾角分析', @() analyze_tilt_points(root, start_date, end_date, 'tilt_stats.xlsx', sub.tilt, cfg));
end
if opts.doAccel && ~should_stop()
    results{end+1} = run_step('加速度分析', @() analyze_acceleration_points(root, start_date, end_date, ...
        'accel_stats.xlsx', sub.accel, true, cfg));
end

if isfield(opts,'doCableAccel') && opts.doCableAccel && ~should_stop()
    results{end+1} = run_step('索力加速度分析', @() analyze_cable_acceleration_points(root, start_date, end_date, ...
        'cable_accel_stats.xlsx', sub.cable_accel, true, cfg));
end

% -------- Acceleration spectrum analysis --------
if opts.doAccelSpectrum && ~should_stop()
    default_spec_pts = { ...
        'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
        'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
        'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
        'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
    accel_pts = get_points(cfg, 'accel_spectrum', get_points(cfg, 'acceleration', default_spec_pts));
    [spec_freqs, spec_tol] = get_accel_spec_params(cfg);
    results{end+1} = run_step('加速度频谱', @() analyze_accel_spectrum_points( ...
        root, start_date, end_date, accel_pts, ...
        'accel_spec_stats.xlsx', sub.accel_raw, ...   % use raw waveform
        spec_freqs, spec_tol, false, cfg));
end

if isfield(opts,'doCableAccelSpectrum') && opts.doCableAccelSpectrum && ~should_stop()
    default_spec_pts = { ...
        'GB-VIB-G04-001-01','GB-VIB-G05-001-01', ...
        'GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
        'GB-VIB-G06-001-01','GB-VIB-G06-002-01', ...
        'GB-VIB-G06-003-01','GB-VIB-G07-001-01'};
    cable_pts = get_points(cfg, 'cable_accel_spectrum', ...
        get_points(cfg, 'cable_accel', get_points(cfg, 'cable_force', default_spec_pts)));
    [spec_freqs, spec_tol] = get_cable_spec_params(cfg);
    results{end+1} = run_step('索力加速度频谱', @() analyze_cable_accel_spectrum_points( ...
        root, start_date, end_date, cable_pts, ...
        'cable_accel_spec_stats.xlsx', sub.cable_accel_raw, ...
        spec_freqs, spec_tol, false, cfg));
end

if opts.doRenameCrk && ~should_stop()
    batch_rename_crk_T_to_t(root, start_date, end_date, true);
end
if opts.doCrack && ~should_stop()
    results{end+1} = run_step('裂缝分析', @() analyze_crack_points(root, start_date, end_date, 'crack_stats.xlsx', sub.crack, cfg));
end
if opts.doStrain && ~should_stop()
    results{end+1} = run_step('应变分析', @() analyze_strain_points(root, start_date, end_date, 'strain_stats.xlsx', sub.strain, cfg));
end

if isfield(opts,'doDynStrainBoxplot') && opts.doDynStrainBoxplot && ~should_stop()
    results{end+1} = run_step('动应变箱线图', @() analyze_dynamic_strain_boxplot( ...
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
        'UpperBound',   30, ...
        'EdgeTrimSec',   5 ...                       % trim edges after filtfilt (seconds)
        ));
end

% Restore warning
warning(ws);
elapsed = toc;
fprintf('总耗时: %.2f 秒\n', elapsed);
all_logs = [log_records, results];
print_summary(all_logs);
write_log(all_logs, start_ts, elapsed);
end

function sub = get_subfolder(cfg, key, fallback)
    sub = fallback;
    if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, key)
        sub = cfg.subfolders.(key);
    end
end

function pts = get_points(cfg, key, fallback)
    pts = normalize_points(fallback);
    if isfield(cfg, 'points') && isfield(cfg.points, key)
        raw = cfg.points.(key);
        if isempty(raw)
            pts = {};
            return;
        end
        if iscell(raw) || isstring(raw) || ischar(raw)
            pts = normalize_points(raw);
        end
    end
end

function pts = get_sensor_points(cfg, key, fallback)
    pts = get_points(cfg, key, fallback);
    if strcmpi(key, 'temperature') || strcmpi(key, 'humidity')
        shared = get_points(cfg, 'temp_humidity', {});
        pts = merge_point_lists(pts, shared);
    end
end

function pts = merge_point_lists(a, b)
    pts = [normalize_points(a); normalize_points(b)];
    if isempty(pts)
        return;
    end
    pts = unique(pts, 'stable');
end

function pts = normalize_points(v)
    pts = {};
    if isstring(v)
        pts = cellstr(v(:));
    elseif ischar(v)
        vv = strtrim(v);
        if ~isempty(vv)
            pts = {vv};
        end
    elseif iscell(v)
        tmp = {};
        for i = 1:numel(v)
            item = v{i};
            if isstring(item)
                if isscalar(item)
                    item = char(item);
                else
                    continue;
                end
            end
            if ischar(item)
                item = strtrim(item);
                if ~isempty(item)
                    tmp{end+1,1} = item; %#ok<AGROW>
                end
            end
        end
        pts = tmp;
    end
end

function [freqs, tol] = get_accel_spec_params(cfg)
    freqs = [1.150 1.480 2.310];
    tol   = 0.15;
    if isfield(cfg,'accel_spectrum_params') && isstruct(cfg.accel_spectrum_params)
        ps = cfg.accel_spectrum_params;
        if isfield(ps,'target_freqs') && ~isempty(ps.target_freqs), freqs = ps.target_freqs; end
        if isfield(ps,'tolerance')   && ~isempty(ps.tolerance),    tol   = ps.tolerance;   end
    end
end

function [freqs, tol] = get_cable_spec_params(cfg)
    freqs = [1.150 1.480 2.310];
    tol   = 0.15;
    if isfield(cfg,'cable_accel_spectrum_params') && isstruct(cfg.cable_accel_spectrum_params)
        ps = cfg.cable_accel_spectrum_params;
        if isfield(ps,'target_freqs') && ~isempty(ps.target_freqs), freqs = ps.target_freqs; end
        if isfield(ps,'tolerance')   && ~isempty(ps.tolerance),    tol   = ps.tolerance;   end
    end
end


function result = run_step(label, fcn)
    try
        if should_stop()
            result = struct('label',label,'status','skip','message','用户请求停止');
            return;
        end
        fcn();
        result = struct('label',label,'status','ok','message','');
    catch ME
        warning('%s 失败: %s', label, ME.message);
        result = struct('label',label,'status','fail','message',ME.message);
    end
end

function print_summary(logs)
    if isempty(logs), return; end
    fprintf('--- 运行汇总 ---\n');
    for i = 1:numel(logs)
        if isempty(logs{i}), continue; end
        fprintf('[%s] %s', upper(logs{i}.status), logs{i}.label);
        if ~isempty(logs{i}.message)
            fprintf(' - %s', logs{i}.message);
        end
        fprintf('\n');
    end
    fprintf('----------------\n');
end

function write_log(logs, start_ts, elapsed)
    if isempty(logs), return; end
    logdir = fullfile(pwd,'outputs','run_logs');
    if ~exist(logdir,'dir'), mkdir(logdir); end
    ts = datestr(start_ts,'yyyymmdd_HHMMSS');
    logfile = fullfile(logdir, ['run_log_' ts '.txt']);
    fid = fopen(logfile,'wt');
    if fid<0, warning('无法写入日志文件 %s', logfile); return; end
    fprintf(fid, 'Start: %s\n', datestr(start_ts,'yyyy-MM-dd HH:mm:ss'));
    fprintf(fid, 'Elapsed: %.2f sec\n', elapsed);
    fprintf(fid, "Summary:\n");
    for i = 1:numel(logs)
        if isempty(logs{i}), continue; end
        fprintf(fid, '[%s] %s', upper(logs{i}.status), logs{i}.label);
        if ~isempty(logs{i}.message)
            fprintf(fid, ' - %s', logs{i}.message);
        end
        fprintf(fid, '\n');
    end
    fclose(fid);
    fprintf('日志已写入 %s\n', logfile);
end

function tf = should_stop()
    tf = false;
    try
        global RUN_STOP_FLAG;
        tf = ~isempty(RUN_STOP_FLAG) && RUN_STOP_FLAG;
    catch
        tf = false;
    end
end
