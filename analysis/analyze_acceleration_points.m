function analyze_acceleration_points(root_dir, start_date, end_date, excel_file, subfolder, auto_detect_fs, cfg)
% analyze_acceleration_points 批量绘制加速度时程及统计
%   root_dir: 根目录
%   start_date,end_date: 'yyyy-MM-dd'
%   excel_file: 输出 Excel
%   subfolder: 数据子目录，默认配置里的 acceleration 子目录
%   auto_detect_fs: true 时根据时间戳估计采样率，否则 100 Hz
%   cfg: load_config() 结构

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(start_date),  start_date = input('开始日期 (yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),    end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file),  excel_file = 'accel_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'acceleration')
            subfolder = cfg_tmp.subfolders.acceleration;
        else
            subfolder = '波形_重采样';
        end
    end
    if nargin<6 || isempty(auto_detect_fs)
        auto_detect_fs = false;
    end
    if nargin<7 || isempty(cfg)
        cfg = load_config();
    end

    time_start = datetime('now','Format','yyyy-MM-dd HH:mm:ss');
    fprintf('开始时间: %s\n', char(time_start));

    tpts = get_points(cfg, 'acceleration', { ...
        'GB-VIB-G04-001-01','GB-VIB-G05-001-01','GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
        'GB-VIB-G06-001-01','GB-VIB-G06-002-01','GB-VIB-G06-003-01','GB-VIB-G07-001-01'});

    style = get_style(cfg, 'acceleration');
    stats = cell(numel(tpts),6);
    parallel_plan = get_parallel_plan(cfg, numel(tpts), 'acceleration');
    if parallel_plan.enabled
        fprintf('加速度分析检测到并行配置，但为避免整段波形累积导致内存不足，改为逐测点顺序处理。\n');
    end

    for i = 1:numel(tpts)
        rec = collect_accel_record(root_dir, subfolder, tpts{i}, start_date, end_date, cfg, auto_detect_fs);
        pid = rec.pid;
        fprintf('处理测点 %s ...\n', pid);
        if ~rec.has_data
            warning('测点 %s 无数据，跳过', pid);
            continue;
        end
        if auto_detect_fs
            fprintf('自动检测采样率 %.2f Hz\n', rec.fs);
        else
            fprintf('使用默认采样率 %d Hz\n', round(rec.fs));
        end
        stats(i,:) = {pid, rec.mn, rec.mx, rec.av, rec.rms_max, rec.rms_time};
        plot_accel_curve(root_dir, pid, rec.times, rec.vals, rec.mn, rec.mx, style);
        plot_accel_rms_curve(root_dir, pid, rec.times, rec.vals, rec.fs, start_date, end_date, style);
        rec = [];
    end

    T = cell2table(stats, 'VariableNames',{'PointID','Min','Max','Mean','RMS10minMax','RMSStartTime'});
    writetable(T, excel_file);
    fprintf('统计结果已保存至 %s\n', excel_file);

    time_end = datetime('now','Format','yyyy-MM-dd HH:mm:ss');
    fprintf('结束时间: %s\n', char(time_end));
    elapsed = seconds(time_end - time_start);
    fprintf('总用时 %.2f 秒\n', elapsed);
end

function pts = get_points(cfg, key, fallback)
    pts = fallback;
    if isfield(cfg,'points') && isfield(cfg.points, key)
        val = cfg.points.(key);
        if iscellstr(val) || (iscell(val) && all(cellfun(@ischar,val)))
            pts = val;
        end
    end
end

function style = get_style(cfg, key)
    style = struct('ylabel','主梁竖向振动加速度 (m/s^2)', ...
                   'title_prefix','加速度时程', ...
                   'ylim_auto', false, ...
                   'ylim', [], ...
                   'ylims', [], ...
                   'color_main',[0 0.447 0.741], ...
                   'color_rms',[0.8500 0.3250 0.0980], ...
                   'rms_ylabel','10 min RMS (m/s^2)', ...
                   'rms_title_prefix','10 min RMS 时程', ...
                   'rms_ylim', [], ...
                   'rms_ylims', []);
    if isfield(cfg,'plot_styles') && isfield(cfg.plot_styles,key)
        ps = cfg.plot_styles.(key);
        if isfield(ps,'ylabel'), style.ylabel = ps.ylabel; end
        if isfield(ps,'title_prefix'), style.title_prefix = ps.title_prefix; end
        if isfield(ps,'ylim_auto'), style.ylim_auto = ps.ylim_auto; end
        if isfield(ps,'ylim'), style.ylim = ps.ylim; end
        if isfield(ps,'ylims'), style.ylims = ps.ylims; end
        if isfield(ps,'colors') && numel(ps.colors)>=1
            c = ps.colors;
            if isnumeric(c) && size(c,2)==3
                style.color_main = c(1,:);
                if size(c,1)>=2, style.color_rms = c(2,:); end
            end
        end
        if isfield(ps,'rms')
            r = ps.rms;
            if isfield(r,'ylabel'), style.rms_ylabel = r.ylabel; end
            if isfield(r,'title_prefix'), style.rms_title_prefix = r.title_prefix; end
            if isfield(r,'ylim'), style.rms_ylim = r.ylim; end
            if isfield(r,'ylims'), style.rms_ylims = r.ylims; end
            if isfield(r,'color'), style.color_rms = r.color; end
        end
        if isfield(ps,'rms_ylims'), style.rms_ylims = ps.rms_ylims; end
    end
end

function plot_accel_curve(root_dir,pid, times, vals, mn, mx, style)
% 绘制加速度时程曲线及标注
fig = figure('Position',[100 100 1000 469]);
[times_plot, vals_plot] = prepare_plot_series(times, vals);
plot(times_plot, vals_plot, 'LineWidth',1, 'Color', style.color_main);
xlabel('时间');
ylabel(style.ylabel);
if is_truthy(style.ylim_auto)
    ylim auto;
elseif ~isempty(style.ylim)
    yl = resolve_point_ylim(style.ylims, pid, style.ylim);
    if is_valid_ylim(yl)
        ylim(yl);
    else
        ylim(style.ylim);
    end
else
    yl = resolve_point_ylim(style.ylims, pid, []);
    if is_valid_ylim(yl)
        ylim(yl);
    else
        ylim auto;
    end
end
hold on;
h1 = yline(mx, '--r'); h1.Label = sprintf('最大值 %.3f', mx);
h1.LabelHorizontalAlignment = 'left';
h2 = yline(mn, '--r'); h2.Label = sprintf('最小值 %.3f', mn);
h2.LabelHorizontalAlignment = 'left';
dn0 = datenum(times(1)); dn1 = datenum(times(end));
numDiv = 4;
ticks = datetime(linspace(dn0, dn1, numDiv+1), 'ConvertFrom','datenum');
ax = gca; ax.XLim = ticks([1 end]); ax.XTick = ticks; xtickformat('yyyy-MM-dd');
grid on; grid minor;
title([style.title_prefix ' ' pid]);
ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(root_dir,'时程曲线_加速度'); if ~exist(out,'dir'), mkdir(out); end
fname = [pid '_' datestr(times(1),'yyyymmdd') '_' datestr(times(end),'yyyymmdd')];
save_plot_bundle(fig, out, [fname '_' ts]);
end

function plot_accel_rms_curve(root_dir, pid, times, vals, fs, start_date, end_date, style)
% 10 min RMS 全时程曲线（含峰值标注）
if isempty(vals) || numel(times) ~= numel(vals)
    return;
end

win_len = max(1, round(600 * fs));  % 10 min
valid_cnt = movsum(~isnan(vals) & isfinite(vals), win_len, 'Endpoints','shrink');
rms_series = sqrt(movmean(vals.^2, win_len, 'omitnan', 'Endpoints','shrink'));
min_need = max(1, round(0.7 * win_len));
rms_series(valid_cnt < min_need) = NaN;

[rms_max, idx_max] = max(rms_series, [], 'omitnan');
t_max = NaT;
if ~isempty(idx_max) && ~isnan(rms_max)
    t_max = times(idx_max);
end

fig = figure('Position',[100 100 1000 469]);
[times_plot, rms_plot] = prepare_plot_series(times, rms_series);
plot(times_plot, rms_plot, 'LineWidth', 1.2, 'Color', style.color_rms);
xlabel('时间'); ylabel(style.rms_ylabel);
yl_rms = resolve_point_ylim(style.rms_ylims, pid, style.rms_ylim);
if is_valid_ylim(yl_rms)
    ylim(yl_rms);
elseif ~isempty(style.rms_ylim)
    ylim(style.rms_ylim);
else
    ylim auto;
end

title(sprintf('%s %s', style.rms_title_prefix, pid));
grid on; grid minor; hold on;

if ~isnan(rms_max)
    h1 = yline(rms_max, '--r');
    h1.Label = sprintf('最大值 %.3f', rms_max);
    h1.LabelHorizontalAlignment = 'left';
    if ~isnat(t_max)
        plot(t_max, rms_max, 'ro', 'MarkerFaceColor','r');
    end
end

ax = gca;
xmin = min(times); xmax = max(times);
if xmin == xmax
    xmin = xmin - minutes(1);
    xmax = xmax + minutes(1);
end
ax.XLim = [xmin xmax];
ticks = datetime(linspace(datenum(xmin), datenum(xmax), 5), 'ConvertFrom','datenum');
ticks = unique(ticks,'stable');
if numel(ticks) >= 2 && all(diff(ticks) > duration(0,0,0))
    ax.XTick = ticks;
else
    ax.XTickMode = 'auto';
end
if days(xmax - xmin) >= 1
    xtickformat('yyyy-MM-dd');
else
    xtickformat('MM-dd HH:mm');
end

ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(root_dir,'时程曲线_加速度_RMS10min');
if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('AccelRMS10_%s_%s_%s', pid, datestr(min(times),'yyyymmdd'), datestr(max(times),'yyyymmdd'));
save_plot_bundle(fig, out, [fname '_' ts]);
end

function yl = resolve_point_ylim(ylims, pid, default_ylim)
yl = default_ylim;
if isempty(ylims) || isempty(pid)
    return;
end
safe_pid = strrep(pid, '-', '_');

if isstruct(ylims)
    if isfield(ylims, pid)
        yl = ylims.(pid);
        return;
    end
    if isfield(ylims, safe_pid)
        yl = ylims.(safe_pid);
        return;
    end
    if isfield(ylims, 'name') && isfield(ylims, 'ylim')
        for i = 1:numel(ylims)
            nm = string(ylims(i).name);
            if strcmp(nm, string(pid)) || strcmp(nm, string(safe_pid))
                yl = ylims(i).ylim;
                return;
            end
        end
    end
end

if iscell(ylims)
    for i = 1:numel(ylims)
        item = ylims{i};
        if isstruct(item) && isfield(item,'name') && isfield(item,'ylim')
            nm = string(item.name);
            if strcmp(nm, string(pid)) || strcmp(nm, string(safe_pid))
                yl = item.ylim;
                return;
            end
        end
    end
end
end

function ok = is_valid_ylim(v)
ok = isnumeric(v) && numel(v)==2 && all(isfinite(v)) && v(2) > v(1);
end

function tf = is_truthy(v)
tf = (islogical(v) && isscalar(v) && v) || ...
    (isnumeric(v) && isscalar(v) && ~isnan(v) && v ~= 0);
end

function rec = init_accel_record()
rec = struct('pid', '', 'times', [], 'vals', [], 'fs', NaN, ...
    'mn', NaN, 'mx', NaN, 'av', NaN, 'rms_max', NaN, ...
    'rms_time', NaT, 'has_data', false);
end

function rec = collect_accel_record(root_dir, subfolder, pid, start_date, end_date, cfg, auto_detect_fs)
rec = init_accel_record();
rec.pid = pid;
[times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'acceleration');
if isempty(vals)
    return;
end

if auto_detect_fs
    dts = seconds(diff(times));
    fs = 1 / median(dts);
else
    fs = 100;
end

window_sec = 10 * 60;
win_len = round(window_sec * fs);

rec.times = times;
rec.vals = vals;
rec.fs = fs;
rec.mn = round(min(vals), 3);
rec.mx = round(max(vals), 3);
rec.av = round(mean(vals), 3);
rec.rms_max = NaN;
rec.rms_time = NaT;
rec.has_data = true;

if numel(vals) >= win_len
    rms_vals = sqrt(movmean(vals.^2, win_len, 'Endpoints', 'shrink'));
    [rms_max, idx] = max(rms_vals);
    rec.rms_max = round(rms_max, 3);
    rec.rms_time = times(idx);
end
end

