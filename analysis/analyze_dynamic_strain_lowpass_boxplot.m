function analyze_dynamic_strain_lowpass_boxplot(root_dir, start_date, end_date, varargin)
%ANALYZE_DYNAMIC_STRAIN_LOWPASS_BOXPLOT  按配置批量生成动应变箱线图与时程图（低通滤波版）
%
%   analyze_dynamic_strain_lowpass_boxplot(root_dir, start_date, end_date, Name, Value, ...)
%
%   必选参数：
%     root_dir   : 数据根目录，包含形如 YYYY-MM-DD 的子目录
%     start_date : 起始日期字符串 'yyyy-MM-dd'
%     end_date   : 结束日期字符串 'yyyy-MM-dd'
%
%   可选 Name-Value：
%     'Cfg'        : 配置 struct 或 JSON 路径，默认 load_config()
%     'OutputDir'  : 箱线图输出目录，默认 <root>/动应变箱线图_低通滤波
%     'OutputDirTs': 时程图输出目录，默认 <root>/时程曲线_动应变_低通滤波
%
%   设计要点：
%     - 分组、样式、清洗参数均从配置读取（优先 defaults.dynamic_strain_lowpass /
%       groups.dynamic_strain_lowpass / plot_styles.dynamic_strain_lowpass）。
%     - 统一使用 load_timeseries_range 读取与清洗，再在本函数中可选
%       Lower/UpperBound 二次裁剪，并低通滤波、边缘裁剪。
%     - 若配置缺失则回落到内置默认并仅提示一次，保证不崩。

%% 解析参数
p = inputParser;
addRequired(p, 'root_dir',   @(s)ischar(s)||isstring(s));
addRequired(p, 'start_date', @(s)ischar(s)||isstring(s));
addRequired(p, 'end_date',   @(s)ischar(s)||isstring(s));
addParameter(p,'Cfg',         [], @(x)isstruct(x)||ischar(x)||isstring(x));
addParameter(p,'OutputDir',   '', @(s)ischar(s)||isstring(s));
addParameter(p,'OutputDirTs', '', @(s)ischar(s)||isstring(s));
addParameter(p,'Subfolder',   '', @(s)ischar(s)||isstring(s));
addParameter(p,'Fs',          [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
addParameter(p,'Fc',          [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
addParameter(p,'CutoffPeriodMinutes', [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
addParameter(p,'FilterOrder', [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
addParameter(p,'Whisker',     [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
addParameter(p,'ShowOutliers',[], @(x)islogical(x)||isnumeric(x));
addParameter(p,'YLimManual',  [], @(x)islogical(x)||isnumeric(x));
addParameter(p,'YLimRange',   [], @(x)isnumeric(x)&&numel(x)==2);
addParameter(p,'LowerBound',  [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
addParameter(p,'UpperBound',  [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
addParameter(p,'EdgeTrimSec', [], @(x)isnumeric(x)&&isscalar(x)||isempty(x));
parse(p, root_dir, start_date, end_date, varargin{:});
opt = p.Results;

root_dir = char(opt.root_dir);
dt0 = datetime(opt.start_date,'InputFormat','yyyy-MM-dd');
dt1 = datetime(opt.end_date,  'InputFormat','yyyy-MM-dd');
start_str = char(string(dt0,'yyyy-MM-dd'));
end_str   = char(string(dt1,'yyyy-MM-dd'));
tag = sprintf('%s-%s', char(string(dt0,'yyyyMMdd')), char(string(dt1,'yyyyMMdd')));
timestamp = char(string(datetime('now'),'yyyy-MM-dd_HH-mm-ss'));

%% 加载配置
if isempty(opt.Cfg)
    cfg = load_config();
elseif ischar(opt.Cfg) || isstring(opt.Cfg)
    cfg = load_config(opt.Cfg);
else
    cfg = opt.Cfg;
end

ds = get_dynamic_lowpass_cfg(cfg); % 动应变低通专用参数（含默认回退提示）
apply_plot_common_runtime(cfg);

% 允许外部参数覆盖配置（例如 run_all 传入）
% override_fields = {'Fs','Fc','CutoffPeriodMinutes','FilterOrder','Whisker','ShowOutliers','YLimManual','YLimRange','LowerBound','UpperBound','EdgeTrimSec'};
% for i = 1:numel(override_fields)
%     f = override_fields{i};
%     if ~isempty(opt.(f))
%         ds.(f) = opt.(f);
%     end
% end

% 子目录允许外部传入覆盖
if ~isempty(opt.Subfolder)
    subfolder = char(opt.Subfolder);
else
    subfolder = get_subfolder(cfg, 'strain', '特征值');
end

% 输出目录（若传入相对路径则自动挂到 root_dir 下）
outdir    = resolve_dir(root_dir, opt.OutputDir,  '动应变箱线图_低通滤波');
outdir_ts = resolve_dir(root_dir, opt.OutputDirTs,'时程曲线_动应变_低通滤波');
if ~exist(outdir,'dir'),    mkdir(outdir);    end
if ~exist(outdir_ts,'dir'), mkdir(outdir_ts); end

% 分组与样式
[groups, group_names, style] = get_groups_and_style(cfg);

fprintf('日期范围: %s ~ %s\n', start_str, end_str);
fprintf('数据目录: %s\\YYYY-MM-DD\\%s\n', root_dir, subfolder);

%% 处理各分组
for gi = 1:numel(groups)
    gname = group_names{gi};
    fprintf('\n== 处理分组 %s ==\n', gname);
    [dataMat, labels, tsList] = collect_group_data(root_dir, subfolder, start_str, end_str, groups{gi}, ds, cfg);
    make_boxplot_and_stats(dataMat, labels, gname, outdir, ds, tag, timestamp, dt0, dt1);
    ylim_group = get_ylim(style, gname, ds);
    plot_timeseries_group(tsList, labels, gname, outdir_ts, dt0, dt1, ds, ylim_group, tag, timestamp);
end

fprintf('\n全部完成。\n');

end

%% 内部函数
function [dataMat, labels, tsList] = collect_group_data(root_dir, subfolder, start_str, end_str, pid_list, ds_cfg, cfg)
    N = numel(pid_list);
    colData = cell(N,1);
    labels  = pid_list(:).';
    tsList  = struct('pid',cell(N,1),'times',[],'vals',[]);
    for ii = 1:N
        pid = pid_list{ii};
        fprintf('  -> 读取 %s ...\n', pid);
        [vals_all, times_all] = process_one_pid(root_dir, subfolder, start_str, end_str, pid, ds_cfg, cfg);
        colData{ii} = vals_all(:);
        tsList(ii).pid   = pid;
        tsList(ii).times = times_all(:);
        tsList(ii).vals  = vals_all(:);
        fprintf('    样本数(非NaN): %d\n', nnz(~isnan(vals_all)));
    end
    Lmax = max(cellfun(@numel, colData));
    dataMat = NaN(Lmax, N);
    for ii = 1:N
        v = colData{ii};
        dataMat(1:numel(v), ii) = v;
    end
end

function [vals_all, times_all] = process_one_pid(root_dir, subfolder, start_str, end_str, pid, ds_cfg, cfg)
    % 统一调用 load_timeseries_range 读取 + 通用清洗
    [times_all, vals_all] = load_timeseries_range( ...
        root_dir, subfolder, pid, start_str, end_str, cfg, 'strain');

    % 若仍为空直接返回
    if isempty(vals_all), return; end

    % 二次上下限裁剪（仅提示一次，避免与通用清洗重复但保留可调性）
    % if ~isempty(ds_cfg.LowerBound) || ~isempty(ds_cfg.UpperBound)
    %     warning_once('dynamic_strain_lowpass:bounds', ...
    %         '动应变再次应用 Lower/UpperBound（请确保与 load_timeseries_range 的阈值规则一致）。');
    %     if ~isempty(ds_cfg.LowerBound)
    %         vals_all(vals_all < ds_cfg.LowerBound) = NaN;
    %     end
    %     if ~isempty(ds_cfg.UpperBound)
    %         vals_all(vals_all > ds_cfg.UpperBound) = NaN;
    %     end
    % end

    fs_local = estimate_sample_rate(times_all, ds_cfg.Fs);
    [fc_local, cutoff_minutes] = resolve_lowpass_cutoff(ds_cfg, fs_local);
    filter_order = max(1, min(6, round(ds_cfg.FilterOrder)));

    v2 = vals_all;
    % 低通滤波：按有效连续段分别处理，避免跨缺测段产生虚假趋势。
    if ~isempty(fc_local) && fc_local > 0
        nyq = fs_local / 2;
        if nyq > 0 && fc_local < nyq
            v2 = lowpass_by_segments(times_all, v2, fs_local, fc_local, filter_order, ds_cfg);
            if ~isempty(cutoff_minutes)
                fprintf('    低通截止周期: %.3g min (fs=%.6g Hz)\n', cutoff_minutes, fs_local);
            end
        else
            warning_once('dynamic_strain_lowpass:fc', ...
                sprintf('低通截止频率 %.6g Hz 不小于 Nyquist %.6g Hz，跳过滤波。', fc_local, nyq));
        end
    end

    % 边缘裁剪
    trimN = round(ds_cfg.EdgeTrimSec * fs_local);
    if trimN>0 && numel(v2)>2*trimN
        v2        = v2(trimN+1:end-trimN);
        times_all = times_all(trimN+1:end-trimN);
    end

    vals_all = v2;
    % ===== 结果级异常兜底清理（最小侵入）=====
    % 目的：防止低通后仍出现非物理突起
    if ~isempty(ds_cfg.LowerBound)
        vals_all(vals_all < ds_cfg.LowerBound) = NaN;
    end
    if ~isempty(ds_cfg.UpperBound)
        vals_all(vals_all > ds_cfg.UpperBound) = NaN;
    end
    vals_all = apply_threshold_rules(vals_all, times_all, ...
        resolve_post_filter_thresholds(cfg, 'dynamic_strain_lowpass', pid));
    % ==========================================
end

function make_boxplot_and_stats(dataMat, labels, groupName, outdir, ds_cfg, tag, ts, dt0, dt1)
    f = figure('Position',[100 100 1100 520]);
    if ds_cfg.ShowOutliers
        boxplot(dataMat, 'Labels', labels, 'LabelOrientation','horizontal', 'Whisker', ds_cfg.Whisker);
    else
        boxplot(dataMat, 'Labels', labels, 'LabelOrientation','horizontal', 'Whisker', ds_cfg.Whisker, 'Symbol','');
    end
    xlabel('测点'); ylabel('应变 (με)');
    title(sprintf('动应变箱线图（低通滤波后）%s [%s]', groupName, tag));
    xtickangle(45); grid on; grid minor;
    if ds_cfg.YLimManual, ylim(ds_cfg.YLimRange); end

    base = sprintf('boxplot_%s_%s', groupName, tag);
    save_plot_bundle(f, outdir, [base '_' ts]);

    statsTbl = calc_stats_table(dataMat, labels);
    txtPath  = fullfile(outdir, sprintf('boxplot_stats_%s_%s.txt', groupName, tag));
    xlsxPath = fullfile(outdir, sprintf('boxplot_stats_%s.xlsx', tag));
    write_stats_txt(txtPath, statsTbl, dt0, dt1);
    writetable(statsTbl, xlsxPath, 'Sheet', groupName);
end

function plot_timeseries_group(tsList, labels, groupName, outdir_ts, dt0, dt1, ds_cfg, ylim_group, tag, ts)
    f = figure('Position',[100 100 1100 520]); hold on;
    colors_6 = {[0 0 0],[0 0 1],[0 0.7 0],[1 0.4 0.8],[1 0.6 0],[1 0 0]};

    n = numel(tsList);
    labels = labels(:);
    hLines = gobjects(n,1);
    hasLine = false(n,1);
    for i = 1:n
        t = tsList(i).times; v = tsList(i).vals;
        if isempty(t) || isempty(v), continue; end
        c = colors_6{ min(i, numel(colors_6)) };
        [times_plot, vals_plot] = prepare_plot_series(t, v);
        if isempty(times_plot) || isempty(vals_plot) || ~any(isfinite(vals_plot))
            continue;
        end
        h = plot(times_plot, vals_plot, 'LineWidth', 1.0, 'Color', c);
        if ~isempty(h)
            hLines(i) = h(1);
            hasLine(i) = true;
        end
    end

    xlabel('时间'); ylabel('应变 (με)');
    title(sprintf('动应变时程（低通滤波后）%s [%s]', groupName, tag));
    grid on; grid minor;

    all_t = vertcat(tsList.times);
    if ~isempty(all_t)
        xmin = min(all_t); xmax = max(all_t);
    else
        xmin = dt0; xmax = dt1;
    end
    if xmin == xmax, xmin = xmin - minutes(1); xmax = xmax + minutes(1); end
    ax = gca; ax.XLim = [xmin xmax];
    ticks = linspace(xmin, xmax, 5);
    ax.XTick = ticks;
    if days(xmax - xmin) >= 1, xtickformat('yyyy-MM-dd'); else, xtickformat('MM-dd HH:mm'); end

    if ~isempty(ylim_group)
        ylim(ylim_group);
    elseif ds_cfg.YLimManual
        ylim(ds_cfg.YLimRange);
    end

    if any(hasLine)
        legend(hLines(hasLine), labels(hasLine), 'Location','northeast','Box','off');
    end

    base = sprintf('dynstrain_lp_%s_%s', groupName, tag);
    save_plot_bundle(f, outdir_ts, [base '_' ts]);
end

function T = calc_stats_table(dataMat, labels)
    N = numel(labels);
    mins  = NaN(N,1); q1s = NaN(N,1); meds = NaN(N,1); q3s = NaN(N,1);
    maxs  = NaN(N,1); means=NaN(N,1); stds=NaN(N,1); cnts=NaN(N,1);
    for k = 1:N
        v = dataMat(:,k);
        v = v(~isnan(v) & isfinite(v));
        if isempty(v), continue; end
        mins(k)  = min(v);
        q1s(k)   = quantile(v,0.25);
        meds(k)  = quantile(v,0.50);
        q3s(k)   = quantile(v,0.75);
        maxs(k)  = max(v);
        means(k) = mean(v);
        stds(k)  = std(v);
        cnts(k)  = numel(v);
    end
    T = table(labels(:), mins, q1s, meds, q3s, maxs, means, stds, cnts, ...
        'VariableNames', {'PointID','Min','Q1','Median','Q3','Max','Mean','Std','Count'});
end

function write_stats_txt(path, T, dt0, dt1)
    fid = fopen(path,'wt');
    fprintf(fid, '动应变箱线图统计（低通滤波后） 日期范围: %s ~ %s\n', char(string(dt0,'yyyy-MM-dd')), char(string(dt1,'yyyy-MM-dd')));
    fprintf(fid, "字段: PointID, Min, Q1, Median, Q3, Max, Mean, Std, Count\n\n");
    for i = 1:height(T)
        fprintf(fid, '%s\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%.3f\t%d\n', ...
            T.PointID{i}, T.Min(i), T.Q1(i), T.Median(i), T.Q3(i), ...
            T.Max(i), T.Mean(i), T.Std(i), T.Count(i));
    end
    fclose(fid);
end

function ylim_val = get_ylim(style_cfg, groupName, ds_cfg)
    ylim_val = [];
    if isstruct(style_cfg) && isfield(style_cfg,'ylims') && isfield(style_cfg.ylims, groupName)
        ylim_val = style_cfg.ylims.(groupName);
    elseif ds_cfg.YLimManual
        ylim_val = ds_cfg.YLimRange;
    end
end

function [groups, names, style] = get_groups_and_style(cfg)
    groups = {}; names = {};
    if isfield(cfg,'groups') && isfield(cfg.groups,'dynamic_strain_lowpass')
        g = cfg.groups.dynamic_strain_lowpass;
    elseif isfield(cfg,'groups_dynamic_strain_lowpass')
        g = cfg.groups_dynamic_strain_lowpass;
    elseif isfield(cfg,'groups') && isfield(cfg.groups,'dynamic_strain')
        g = cfg.groups.dynamic_strain;
    elseif isfield(cfg,'groups_dynamic_strain')
        g = cfg.groups_dynamic_strain;
    else
        g = [];
    end

    if isstruct(g)
        names = fieldnames(g);
        for i = 1:numel(names)
            groups{i} = cellstr(g.(names{i})(:));
        end
    elseif iscell(g)
        groups = g;
        names = arrayfun(@(i)sprintf('Group%d',i),1:numel(g),'UniformOutput',false);
    end

    if isempty(groups)
        error(['未配置 dynamic_strain_lowpass 分组，且无法回退到 dynamic_strain。' ...
               '请配置 groups.dynamic_strain_lowpass 或 groups.dynamic_strain。']);
    end

    if isfield(cfg,'plot_styles') && isfield(cfg.plot_styles,'dynamic_strain_lowpass')
        style = cfg.plot_styles.dynamic_strain_lowpass;
    elseif isfield(cfg,'plot_styles_dynamic_strain_lowpass')
        style = cfg.plot_styles_dynamic_strain_lowpass;
    elseif isfield(cfg,'plot_styles') && isfield(cfg.plot_styles,'dynamic_strain')
        style = cfg.plot_styles.dynamic_strain;
    elseif isfield(cfg,'plot_styles_dynamic_strain')
        style = cfg.plot_styles_dynamic_strain;
    else
        style = struct();
    end
end

function sub = get_subfolder(cfg, key, fallback)
    sub = fallback;
    if isfield(cfg,'subfolders') && isfield(cfg.subfolders, key) && ~isempty(cfg.subfolders.(key))
        sub = cfg.subfolders.(key);
    end
end

function ds = get_dynamic_lowpass_cfg(cfg)
    ds = struct('FilterMode','auto', 'AutoPreset','temperature', ...
        'AutoCutoffPeriodMinutes',720, 'MinSamplesPerCutoff',20, ...
        'Fs',[], 'Fc',[], 'CutoffPeriodMinutes',[], 'FilterOrder',2, ...
        'Whisker',300, 'ShowOutliers',false, ...
        'YLimManual',false, 'YLimRange',[-150 150], ...
        'LowerBound',-150, 'UpperBound',150, 'EdgeTrimSec',5, ...
        'MaxGapSec',[]);
    if isfield(cfg,'defaults') && isfield(cfg.defaults,'dynamic_strain_lowpass')
        d = cfg.defaults.dynamic_strain_lowpass;
    elseif isfield(cfg,'defaults_dynamic_strain_lowpass')
        d = cfg.defaults_dynamic_strain_lowpass;
    else
        d = struct();
    end
    fn = fieldnames(ds);
    for i = 1:numel(fn)
        f = fn{i};
        if isfield(d,f) && ~isempty(d.(f))
            ds.(f) = d.(f);
        end
    end
end

function fs = estimate_sample_rate(times, fs_cfg)
    if ~isempty(fs_cfg) && isfinite(fs_cfg) && fs_cfg > 0
        fs = double(fs_cfg);
        return;
    end
    fs = 20;
    if numel(times) < 2
        warning_once('dynamic_strain_lowpass:fs', '无法从数据估计采样率，使用默认 20 Hz。');
        return;
    end
    dt = diff_seconds(times(:));
    dt = dt(isfinite(dt) & dt > 0);
    if isempty(dt)
        warning_once('dynamic_strain_lowpass:fs', '无法从数据估计采样率，使用默认 20 Hz。');
        return;
    end
    fs = 1 / median(dt);
end

function [fc, cutoff_minutes] = resolve_lowpass_cutoff(ds_cfg, fs)
    cutoff_minutes = [];
    if isfield(ds_cfg, 'Fc') && ~isempty(ds_cfg.Fc) && isfinite(ds_cfg.Fc) && ds_cfg.Fc > 0
        fc = double(ds_cfg.Fc);
        return;
    end
    if isfield(ds_cfg, 'CutoffPeriodMinutes') && ~isempty(ds_cfg.CutoffPeriodMinutes) && ...
            isfinite(ds_cfg.CutoffPeriodMinutes) && ds_cfg.CutoffPeriodMinutes > 0
        cutoff_minutes = double(ds_cfg.CutoffPeriodMinutes);
        fc = 1 / (cutoff_minutes * 60);
        return;
    end

    mode = lower(char(string(get_field_default(ds_cfg, 'FilterMode', 'auto'))));
    if strcmp(mode, 'auto')
        cutoff_minutes = auto_cutoff_period_minutes(ds_cfg, fs);
        fc = 1 / (cutoff_minutes * 60);
    else
        fc = [];
    end
end

function minutes_val = auto_cutoff_period_minutes(ds_cfg, fs)
    preset = lower(char(string(get_field_default(ds_cfg, 'AutoPreset', 'temperature'))));
    switch preset
        case {'temperature','temp','thermal','temperature_strain'}
            minutes_val = get_numeric_field_default(ds_cfg, 'AutoCutoffPeriodMinutes', 720);
        otherwise
            minutes_val = get_numeric_field_default(ds_cfg, 'AutoCutoffPeriodMinutes', 720);
    end

    if ~isfinite(minutes_val) || minutes_val <= 0
        minutes_val = 720;
    end
    min_samples = get_numeric_field_default(ds_cfg, 'MinSamplesPerCutoff', 20);
    if isfinite(fs) && fs > 0 && isfinite(min_samples) && min_samples > 0
        sample_minutes = 1 / fs / 60;
        minutes_val = max(minutes_val, min_samples * sample_minutes);
    end
end

function val = get_field_default(s, name, default_val)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        val = s.(name);
    else
        val = default_val;
    end
end

function val = get_numeric_field_default(s, name, default_val)
    val = default_val;
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name)) && ...
            isnumeric(s.(name)) && isscalar(s.(name)) && isfinite(s.(name))
        val = double(s.(name));
    end
end

function y = lowpass_by_segments(times, vals, fs, fc, order, ds_cfg)
    y = NaN(size(vals));
    vals = vals(:);
    times = times(:);
    n = min(numel(vals), numel(times));
    if n == 0
        return;
    end
    vals = vals(1:n);
    times = times(1:n);

    valid = isfinite(vals) & is_valid_time(times);
    idx = find(valid);
    if isempty(idx)
        return;
    end

    dt_all = diff_seconds(times(idx));
    dt_all = dt_all(isfinite(dt_all) & dt_all > 0);
    if isempty(dt_all)
        max_gap = 5 / fs;
    else
        max_gap = 5 * median(dt_all);
    end
    if isfield(ds_cfg, 'MaxGapSec') && ~isempty(ds_cfg.MaxGapSec) && ...
            isfinite(ds_cfg.MaxGapSec) && ds_cfg.MaxGapSec > 0
        max_gap = min(max_gap, double(ds_cfg.MaxGapSec));
    end

    [b,a] = butter(order, fc/(fs/2), 'low');
    min_len = 3 * max(numel(a), numel(b));
    gap_breaks = diff(idx) > 1 | diff_seconds(times(idx)) > max_gap;
    starts = [1; find(gap_breaks) + 1];
    stops = [find(gap_breaks); numel(idx)];
    for si = 1:numel(starts)
        seg = idx(starts(si):stops(si));
        if numel(seg) <= min_len
            y(seg) = vals(seg);
        else
            y(seg) = filtfilt(b, a, double(vals(seg)));
        end
    end
end

function tf = is_valid_time(times)
    if isdatetime(times)
        tf = ~isnat(times);
    else
        tf = isfinite(times);
    end
end

function dt = diff_seconds(times)
    if isdatetime(times) || isduration(times)
        dt = seconds(diff(times));
    else
        dt = diff(double(times));
    end
end


function apply_plot_common_runtime(cfg)
    try
        if isstruct(cfg) && isfield(cfg, 'plot_common') && isstruct(cfg.plot_common)
            plot_runtime_settings('set', cfg.plot_common);
        end
    catch
    end
end

function warning_once(id,msg)
    persistent fired;
    if isempty(fired), fired = containers.Map(); end
    if ~isKey(fired,id)
        warning(msg);
        fired(id) = true;
    end
end

function out = ifelse(cond, a, b)
    if cond, out = a; else, out = b; end
end

function p = resolve_dir(root_dir, user_path, default_name)
    if ~isempty(user_path)
        p = char(user_path);
        if ~is_absolute_path(p)
            p = fullfile(root_dir, p);
        end
    else
        p = fullfile(root_dir, default_name);
    end
end

function yes = is_absolute_path(p)
    % Windows drive root or UNC or Unix-style
    yes = ~isempty(regexp(p, '^[A-Za-z]:\\', 'once')) || startsWith(p, filesep) || startsWith(p, '\\');
end
