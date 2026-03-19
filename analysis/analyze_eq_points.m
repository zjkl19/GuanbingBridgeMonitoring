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
    records = repmat(init_eq_record(), numel(points), 1);
    parallel_plan = get_parallel_plan(cfg, numel(points), 'eq');

    if parallel_plan.enabled
        fprintf('地震动分析使用并行数据收集 (%d workers)\n', parallel_plan.worker_count);
        parfor i = 1:numel(points)
            records(i) = collect_eq_record(root_dir, subfolder, points{i}, start_date, end_date, cfg);
        end
    else
        for i = 1:numel(points)
            records(i) = collect_eq_record(root_dir, subfolder, points{i}, start_date, end_date, cfg);
        end
    end

    for i = 1:numel(points)
        rec = records(i);
        fprintf('处理测点 %s ...', rec.pid);
        if ~rec.has_data
            warning('测点 %s 无数据，跳过', rec.pid);
            continue;
        end
        if parallel_plan.enabled
            record_parallel_offset_correction(cfg, rec.sensor_type, rec.pid, rec.times, rec.vals);
        end
        plot_eq_timeseries(rec.times, rec.vals, rec.pid, rec.comp, rec.params, style, out_root, start_date, end_date);
    end

    time_end = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
    fprintf('结束时间: %s', char(time_end));
    elapsed = seconds(time_end - time_start);
    fprintf('总用时: %.2f sec', elapsed);
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
    if is_truthy(style.ylim_auto)
        ylim auto;
    else
        yl = resolve_named_ylim(style.ylims, pid, style.ylim);
        if is_valid_ylim(yl)
            ylim(yl);
        elseif ~isempty(style.ylim)
            ylim(style.ylim);
        end
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
    save_plot_bundle(fig, out_dir, [base_name '_' ts]);
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
        if isfield(ps, 'ylim_auto'), style.ylim_auto = ps.ylim_auto; end
        if isfield(ps, 'ylim'), style.ylim = ps.ylim; end
        if isfield(ps, 'ylims'), style.ylims = ps.ylims; end
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

function yl = resolve_named_ylim(ylims, name, default_ylim)
    yl = default_ylim;
    if isempty(ylims) || isempty(name)
        return;
    end
    safe_name = strrep(name, '-', '_');
    if isstruct(ylims)
        if isfield(ylims, name)
            yl = ylims.(name);
            return;
        end
        if isfield(ylims, safe_name)
            yl = ylims.(safe_name);
            return;
        end
        if isfield(ylims, 'name') && isfield(ylims, 'ylim')
            for i = 1:numel(ylims)
                if strcmp(to_char(ylims(i).name), name)
                    yl = ylims(i).ylim;
                    return;
                end
            end
        end
    elseif iscell(ylims)
        for i = 1:numel(ylims)
            item = ylims{i};
            if isstruct(item) && isfield(item, 'name') && isfield(item, 'ylim') && strcmp(to_char(item.name), name)
                yl = item.ylim;
                return;
            end
        end
    end
end

function ok = is_valid_ylim(v)
    ok = isnumeric(v) && numel(v) == 2 && all(isfinite(v)) && v(2) > v(1);
end

function tf = is_truthy(v)
    tf = (islogical(v) && isscalar(v) && v) || ...
        (isnumeric(v) && isscalar(v) && ~isnan(v) && v ~= 0);
end

function txt = to_char(v)
    if isstring(v)
        txt = char(v);
    elseif ischar(v)
        txt = v;
    else
        txt = char(string(v));
    end
end

function rec = init_eq_record()
rec = struct('pid', '', 'sensor_type', '', 'comp', '', ...
    'times', [], 'vals', [], 'params', struct(), 'has_data', false);
end

function rec = collect_eq_record(root_dir, subfolder, pid, start_date, end_date, cfg)
rec = init_eq_record();
rec.pid = pid;
[rec.sensor_type, rec.comp] = get_eq_component(pid);
[times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, rec.sensor_type);
rec.params = get_eq_params(cfg, pid);
if isempty(vals)
    return;
end
rec.times = times;
rec.vals = vals;
rec.has_data = true;
end
