function analyze_eq_points(root_dir, start_date, end_date, subfolder, cfg)
% analyze_eq_points  Earthquake motion time-series with alarm lines.
%   Draws EQ-X/EQ-Y/EQ-Z time series with E1/E2 alarm lines and max label.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), start_date = input('开始日期 (yyyy-MM-dd): ', 's'); end
    if nargin < 3 || isempty(end_date),   end_date   = input('结束日期 (yyyy-MM-dd): ', 's'); end
    if nargin < 5 || isempty(cfg), cfg = load_config(); end
    if nargin < 4 || isempty(subfolder)
        if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, 'eq_raw')
            subfolder = cfg.subfolders.eq_raw;
        else
            subfolder = '波形';
        end
    end

    time_start = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
    fprintf('开始时间: %s', char(time_start));

    points = get_points(cfg, 'eq', {'EQ-X','EQ-Y','EQ-Z'});
    style = get_eq_style(cfg);
    out_root = fullfile(root_dir, style.output.root_dir);
    ensure_dir(out_root);

    for i = 1:numel(points)
        pid = points{i};
        [sensor_type, comp] = get_eq_component(pid);
        fprintf('处理测点 %s ...', pid);

        [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, sensor_type);
        if isempty(vals)
            warning('测点 %s 无数据，跳过', pid);
            continue;
        end

        params = get_eq_params(cfg, pid);
        plot_eq_timeseries(times, vals, pid, comp, params, style, out_root, start_date, end_date);
    end

    time_end = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
    fprintf('结束时间: %s', char(time_end));
    elapsed = seconds(time_end - time_start);
    fprintf('总用时: %.2f \u79d2', elapsed);
end

function [sensor_type, comp] = get_eq_component(pid)
    comp = 'X';
    sensor_type = 'eq_x';
    if contains(pid, '-Y')
        comp = 'Y'; sensor_type = 'eq_y';
    elseif contains(pid, '-Z')
        comp = 'Z'; sensor_type = 'eq_z';
    elseif contains(pid, '-X')
        comp = 'X'; sensor_type = 'eq_x';
    end
end

function plot_eq_timeseries(times, vals, pid, comp, params, style, out_root, start_date, end_date)
    fig = figure('Position', [100 100 1100 500]);
    plot(times, vals, 'LineWidth', 1.1, 'Color', style.main_color);
    xlabel('时间');
    ylabel(style.ylabel);
    title(sprintf('%s %s [%s-%s]', style.title_prefix, pid, start_date, end_date));
    grid on; grid minor; hold on;
    if ~isempty(style.ylim)
        ylim(style.ylim);
    end
    set_time_axis(times);

    % alarm lines (E1/E2)
    levels = params.alarm_levels(:)';
    levels = sort(levels(~isnan(levels)));
    labels = {'E1地震作用加速度峰值', 'E2地震作用加速度峰值'};
    colors = [1 0.85 0; 0.85 0.1 0.1]; % yellow, red
    for i = 1:min(numel(levels), numel(labels))
        lv = levels(i);
        if ~isfinite(lv), continue; end
        h = yline(lv, '--', sprintf('%s %.2f', labels{i}, lv), 'Color', colors(i,:));
        h.LabelHorizontalAlignment = 'left';
        h.LabelVerticalAlignment = 'bottom';
    end

    % max marker
    [vmax, idx] = max(vals, [], 'omitnan');
    if ~isempty(idx) && isfinite(vmax) && idx >= 1 && idx <= numel(times)
        tmax = times(idx);
        plot(tmax, vmax, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
        text(tmax, vmax, sprintf('最大值: %.3f', vmax), ...
            'VerticalAlignment','bottom', 'HorizontalAlignment','left', 'Color',[0.6 0 0]);
    end

    out_dir = fullfile(out_root, style.output.series_dir);
    ensure_dir(out_dir);
    base = sprintf('%s_%s_%s_%s', style.output.prefix, comp, start_date, end_date);
    save_plot(fig, out_dir, base);
end

function set_time_axis(times)
    if isempty(times)
        return;
    end
    ax = gca;
    xmin = min(times);
    xmax = max(times);
    if xmin == xmax
        xmin = xmin - minutes(1);
        xmax = xmax + minutes(1);
    end
    ax.XLim = [xmin xmax];
    ticks = datetime(linspace(posixtime(xmin), posixtime(xmax), 5), 'ConvertFrom', 'posixtime');
    ticks = unique(ticks, 'stable');
    if numel(ticks) >= 2
        ax.XTick = ticks;
    else
        ax.XTickMode = 'auto';
    end
    if days(xmax - xmin) >= 1
        xtickformat('yyyy-MM-dd');
    else
        xtickformat('MM-dd HH:mm');
    end
end

function save_plot(fig, out_dir, base_name)
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    saveas(fig, fullfile(out_dir, [base_name '_' ts '.jpg']));
    saveas(fig, fullfile(out_dir, [base_name '_' ts '.emf']));
    savefig(fig, fullfile(out_dir, [base_name '_' ts '.fig']), 'compact');
    close(fig);
end

function ensure_dir(p)
    if ~exist(p, 'dir')
        mkdir(p);
    end
end

function pts = get_points(cfg, key, fallback)
    pts = fallback;
    if isfield(cfg, 'points') && isfield(cfg.points, key)
        val = cfg.points.(key);
        if iscell(val) || isstring(val)
            pts = cellstr(val(:));
        end
    end
end

function style = get_eq_style(cfg)
    style = struct();
    style.output = struct( ...
        'root_dir', '地震动结果', ...
        'series_dir', '地震动时程', ...
        'prefix', 'EQ');
    style.ylabel = '地震动加速度 (m/s^2)';
    style.title_prefix = '地震动时程';
    style.ylim = [];
    style.main_color = [0 0.447 0.741];

    if isfield(cfg, 'plot_styles') && isfield(cfg.plot_styles, 'eq')
        ps = cfg.plot_styles.eq;
        if isfield(ps, 'output') && isstruct(ps.output)
            style.output = merge_struct(style.output, ps.output);
        end
        if isfield(ps, 'ylabel'), style.ylabel = ps.ylabel; end
        if isfield(ps, 'title_prefix'), style.title_prefix = ps.title_prefix; end
        if isfield(ps, 'ylim'), style.ylim = ps.ylim; end
        if isfield(ps, 'color'), style.main_color = ps.color; end
    end
end

function params = get_eq_params(cfg, pid)
    params = struct();
    params.alarm_levels = [1, 2];
    if isfield(cfg, 'eq_params') && isstruct(cfg.eq_params)
        ep = cfg.eq_params;
        if isfield(ep, 'alarm_levels') && ~isempty(ep.alarm_levels)
            params.alarm_levels = double(ep.alarm_levels(:))';
        end
    end

    if nargin < 2 || isempty(pid)
        return;
    end
    safe_id = strrep(pid, '-', '_');
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, 'eq') ...
            && isfield(cfg.per_point.eq, safe_id)
        pt = cfg.per_point.eq.(safe_id);
        if isfield(pt, 'alarm_levels') && ~isempty(pt.alarm_levels)
            params.alarm_levels = double(pt.alarm_levels(:))';
        end
    end
end

function out = merge_struct(base, override)
    out = base;
    fns = fieldnames(override);
    for i = 1:numel(fns)
        fn = fns{i};
        out.(fn) = override.(fn);
    end
end
