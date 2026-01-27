function analyze_cable_acceleration_points(root_dir, start_date, end_date, excel_file, subfolder, auto_detect_fs, cfg)
% analyze_cable_acceleration_points 批量绘制索力加速度时程及统计
%   root_dir: 根目录
%   start_date,end_date: 'yyyy-MM-dd'
%   excel_file: 输出 Excel
%   subfolder: 数据子目录，默认配置里的 acceleration 子目录
%   auto_detect_fs: true 时根据时间戳估计采样率，否则 100 Hz
%   cfg: load_config() 结构

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(start_date),  start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),    end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file),  excel_file = 'cable_accel_stats.xlsx'; end
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'cable_accel')
            subfolder = cfg_tmp.subfolders.cable_accel;
        else
            subfolder = '索力加速度_重采样';
        end
    end
    if nargin<6 || isempty(auto_detect_fs)
        auto_detect_fs = false;
    end
    if nargin<7 || isempty(cfg)
        cfg = load_config();
    end

    time_start = datetime('now','Format','yyyy-MM-dd HH:mm:ss');
    fprintf('开始时间 %s\n', char(time_start));

    tpts = get_points(cfg, 'cable_accel', { ...
        'GB-VIB-G04-001-01','GB-VIB-G05-001-01','GB-VIB-G05-002-01','GB-VIB-G05-003-01', ...
        'GB-VIB-G06-001-01','GB-VIB-G06-002-01','GB-VIB-G06-003-01','GB-VIB-G07-001-01'});

    style = get_style(cfg, 'cable_accel');
    stats = cell(numel(tpts),6);

    for i = 1:numel(tpts)
        pid = tpts{i}; fprintf('处理测点 %s ...\n', pid);
        [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'cable_accel');
        if isempty(vals)
            warning('测点 %s 无数据，跳过', pid);
            continue;
        end
        if auto_detect_fs
            dts = seconds(diff(times));
            fs = 1 / median(dts);
            fprintf('自动检测采样率 %.2f Hz\n', fs);
        else
            fs = 100;
            fprintf('使用默认采样率: %d Hz\n', fs);
        end
        window_sec = 10 * 60;          % 10 分钟
        win_len    = round(window_sec * fs);

        mn = round(min(vals),3);
        mx = round(max(vals),3);
        av = round(mean(vals),3);
        if numel(vals) >= win_len
            rms_vals = sqrt(movmean(vals.^2, win_len, 'Endpoints','shrink'));
            [rms_max, idx] = max(rms_vals);
            rms_max = round(rms_max,3);
            rms_time = times(idx);
        else
            rms_max = NaN;
            rms_time = NaT;
        end
        stats(i,:) = {pid, mn, mx, av, rms_max,rms_time};
        plot_accel_curve(root_dir,pid, times, vals, mn, mx, style);
        plot_accel_rms_curve(root_dir, pid, times, vals, fs, start_date, end_date, style);
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
    style = struct('ylabel','索力加速度 (mm/s^2)', ...
                   'title_prefix','索力加速度时程', ...
                   'ylim', [], ...
                   'color_main',[0 0.447 0.741], ...
                   'color_rms',[0.8500 0.3250 0.0980], ...
                   'rms_ylabel','10 min RMS (mm/s^2)', ...
                   'rms_title_prefix','10 min RMS 时程', ...
                   'rms_ylim', []);
    if isfield(cfg,'plot_styles') && isfield(cfg.plot_styles,key)
        ps = cfg.plot_styles.(key);
        if isfield(ps,'ylabel'), style.ylabel = ps.ylabel; end
        if isfield(ps,'title_prefix'), style.title_prefix = ps.title_prefix; end
        if isfield(ps,'ylim'), style.ylim = ps.ylim; end
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
            if isfield(r,'color'), style.color_rms = r.color; end
        end
    end
end

function plot_accel_curve(root_dir,pid, times, vals, mn, mx, style)
% 绘制索力加速度时程曲线及标尺
fig = figure('Position',[100 100 1000 469]);
plot(times, vals, 'LineWidth',1, 'Color', style.color_main);
xlabel('时间');
ylabel(style.ylabel);
if ~isempty(style.ylim)
    ylim(style.ylim);
else
    ylim auto;
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
out = fullfile(root_dir,'时程曲线_索力加速度'); if ~exist(out,'dir'), mkdir(out); end
fname = [pid '_' datestr(times(1),'yyyymmdd') '_' datestr(times(end),'yyyymmdd')];
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
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
plot(times, rms_series, 'LineWidth', 1.2, 'Color', style.color_rms);
xlabel('时间'); ylabel(style.rms_ylabel);
if ~isempty(style.rms_ylim)
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
out = fullfile(root_dir,'时程曲线_索力加速度_RMS10min');
if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('CableCableCableCableCableAccelRMS10_%s_%s_%s', pid, datestr(min(times),'yyyymmdd'), datestr(max(times),'yyyymmdd'));
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end