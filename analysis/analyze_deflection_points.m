function analyze_deflection_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_deflection_points
% 批量绘制主梁挠度时程（原始+中值滤波）并统计。
%
% 输入:
%   root_dir   根目录，如 'F:/桥梁监测数据/'
%   start_date, end_date  'yyyy-MM-dd'
%   excel_file 输出统计 Excel
%   subfolder  数据子目录，默认配置里的 deflection 子目录
%   cfg        load_config() 返回的配置结构

    if nargin<1||isempty(root_dir),    root_dir = pwd; end
    if nargin<2||isempty(start_date),  start_date = input('开始日期(yyyy-MM-dd): ','s'); end
    if nargin<3||isempty(end_date),    end_date   = input('结束日期 (yyyy-MM-dd): ','s'); end
    if nargin<4||isempty(excel_file),  excel_file = 'deflection_stats.xlsx'; end
    if nargin<5||isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'deflection')
            subfolder = cfg_tmp.subfolders.deflection;
        else
            subfolder = '特征值_重采样';
        end
    end
    if nargin<6||isempty(cfg),         cfg = load_config(); end

    groups = get_groups(cfg, 'deflection', { ...
        {'GB-DIS-G05-001-01Y','GB-DIS-G05-001-02Y'}, ...
        {'GB-DIS-G05-002-01Y','GB-DIS-G05-002-02Y','GB-DIS-G05-002-03Y'}, ...
        {'GB-DIS-G05-003-01Y','GB-DIS-G05-003-02Y'}, ...
        {'GB-DIS-G06-001-01Y','GB-DIS-G06-001-02Y'}, ...
        {'GB-DIS-G06-002-01Y','GB-DIS-G06-002-02Y','GB-DIS-G06-002-03Y'}, ...
        {'GB-DIS-G06-003-01Y','GB-DIS-G06-003-02Y'} ...
        });
    style = get_style(cfg, 'deflection');

    stats = {};
    row = 1;
    for g = 1:numel(groups)
        pid_list = groups{g};
        fprintf('处理组 %d: %s\n', g, strjoin(pid_list, ', '));
        N = numel(pid_list);
        orig_times = cell(N,1); orig_vals = cell(N,1);
        filt_times = cell(N,1); filt_vals = cell(N,1);

        for i = 1:N
            pid = pid_list{i};
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'deflection');
            if isempty(vals)
                warning('测点 %s 无数据，跳过', pid);
                continue;
            end

            % 中值滤波窗口（约 10 min）
            if numel(times) >= 2
                dts = seconds(diff(times));
                fs = 1/median(dts);
                window_sec = 10*60;
                win_len = round(window_sec * fs);
                if mod(win_len,2)==0, win_len = win_len + 1; end
            else
                win_len = 201;
            end
            vals_f = movmedian(vals, win_len, 'omitnan');

            orig_times{i} = times;  orig_vals{i} = vals;
            filt_times{i} = times;  filt_vals{i} = vals_f;
            stats(row, :) = {
                pid, ...
                round(min(vals),1), round(max(vals),1), round(mean(vals,  'omitnan'), 1), ...
                round(min(vals_f),1), round(max(vals_f),1), round(mean(vals_f,  'omitnan'), 1)};
            row = row + 1;
        end

        % 绘制原始&滤波曲线
        plot_deflection_curve(orig_times, orig_vals, pid_list, root_dir, start_date, end_date, g, style, '原始');
        plot_deflection_curve(filt_times, filt_vals, pid_list, root_dir, start_date, end_date, g, style, '滤波');
    end

    % 写入 Excel
    T = cell2table(stats, 'VariableNames', ...
        {'PointID','OrigMin_mm','OrigMax_mm','OrigMean_mm','FiltMin_mm','FiltMax_mm','FiltMean_mm'});
    writetable(T, excel_file);
    fprintf('挠度统计已保存至 %s\n', excel_file);
end

function plot_deflection_curve(times_list, vals_list, pid_list, root_dir, start_date, end_date, group_idx, style, suffix)
fig = figure('Position',[100 100 1000 469]); hold on;
dt0 = datetime(start_date,'InputFormat','yyyy-MM-dd'); dt1 = datetime(end_date,'InputFormat','yyyy-MM-dd');
N = numel(pid_list);

colors_2 = normalize_colors(get_style_field(style,'colors_2', {[0 0 1], [0 0.7 0]}));
colors_3 = normalize_colors(get_style_field(style,'colors_3', {[0.5 0 0.7], [0 0 1], [0 0.7 0]}));

for i = 1:N
    if N == 2
        c = colors_2{i};
    elseif N == 3
        c = colors_3{i};
    else
        cmap = lines(N);
        c = cmap(i,:);
    end
    if isempty(vals_list{i}), continue; end
    plot(times_list{i}, vals_list{i}, 'LineWidth', 1.0, 'Color', c);
end

lg = legend(pid_list,'Location','northeast','Box','off');
lg.AutoUpdate = 'off';

% X 轴
numDiv = 4;
ticks = dt0 + (dt1 - dt0) * (0:numDiv) / numDiv;
ax = gca; ax.XLim = [dt0 dt1]; ax.XTick = ticks; xtickformat('yyyy-MM-dd');
xlabel('时间'); ylabel(get_style_field(style,'ylabel','挠度 (mm)'));
prefix = get_style_field(style,'title_prefix','挠度时程');
if nargin < 9 || isempty(suffix)
    suffix = '';
else
    suffix = [' ' suffix];
end
title(sprintf('%s 组%d%s', prefix, group_idx, suffix));

% 预警线
warn_lines = get_style_field(style,'warn_lines', {});
if isstruct(warn_lines) && ~iscell(warn_lines)
    warn_lines = num2cell(warn_lines);
end
if iscell(warn_lines)
    for k = 1:numel(warn_lines)
        wl = warn_lines{k};
        if isstruct(wl) && isfield(wl,'y')
            yl = yline(wl.y, '--', get_label(wl), 'LabelHorizontalAlignment','left');
            if isfield(wl,'color'), yl.Color = wl.color; end
        end
    end
end

% Y 轴范围
ylim_val = get_style_field(style,'ylim', []);
if ~isempty(ylim_val)
    ylim(ylim_val);
else
    ylim auto;
end
grid on; grid minor;

% 保存
ts = datestr(now,'yyyymmdd_HHMMSS');
out = fullfile(root_dir, '时程曲线_挠度'); if ~exist(out,'dir'), mkdir(out); end
fname = sprintf('Defl_G%d_%s_%s', group_idx, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'));
saveas(fig, fullfile(out, [fname '_' ts '.jpg']));
saveas(fig, fullfile(out, [fname '_' ts '.emf']));
savefig(fig, fullfile(out, [fname '_' ts '.fig']), 'compact');
close(fig);
end

% helpers
function groups = get_groups(cfg, key, fallback)
    groups = fallback;
    if isfield(cfg, 'groups') && isfield(cfg.groups, key)
        g = cfg.groups.(key);
        if iscell(g)
            groups = g;
        end
    end
end

function style = get_style(cfg, key)
    style = struct();
    if isfield(cfg,'plot_styles') && isfield(cfg.plot_styles, key)
        style = cfg.plot_styles.(key);
    end
end

function val = get_style_field(style, field, default)
    if isstruct(style) && isfield(style, field)
        val = style.(field);
    else
        val = default;
    end
end

function lbl = get_label(wl)
    if isfield(wl,'label')
        lbl = wl.label;
    else
        lbl = '';
    end
end

function ccell = normalize_colors(c)
    if isnumeric(c)
        ccell = mat2cell(c, ones(size(c,1),1), size(c,2));
    elseif iscell(c)
        ccell = c;
    else
        ccell = {};
    end
end
