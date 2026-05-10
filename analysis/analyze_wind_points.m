function analyze_wind_points(root_dir, start_date, end_date, subfolder, cfg)
% analyze_wind_points  Wind speed/direction analysis with 10-min mean and wind rose.
%   This module loads wind speed and wind direction for each configured point,
%   plots time series, plots 10-minute mean wind speed with alarm lines,
%   and produces a wind-rose style polar histogram for the selected date range.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), start_date = input('开始日期 (yyyy-MM-dd): ', 's'); end
    if nargin < 3 || isempty(end_date),   end_date   = input('结束日期 (yyyy-MM-dd): ', 's'); end
    if nargin < 5 || isempty(cfg), cfg = load_config(); end
    if nargin < 4 || isempty(subfolder)
        if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, 'wind_raw')
            subfolder = cfg.subfolders.wind_raw;
        else
            subfolder = '波形';
        end
    end

    time_start = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
    fprintf('开始时间: %s\n', char(time_start));

    points = get_points(cfg, 'wind', {'W1','W2'});
    style = get_wind_style(cfg);
    stats = cell(numel(points), 6);
    stats_file = resolve_data_output_path(root_dir, get_wind_stats_file(cfg), 'stats');

    out_root = fullfile(root_dir, style.output.root_dir);
    ensure_dir(out_root);

    for i = 1:numel(points)
        pid = points{i};
        fprintf('处理测点 %s ...\n', pid);

        [t_speed, v_speed] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'wind_speed');
        [t_dir, v_dir]     = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'wind_direction');

        if isempty(v_speed)
            warning('测点 %s 风速无数据，跳过', pid);
            continue;
        end

        fs = bms.analyzer.DynamicSeriesService.sampleRate(t_speed, true, 1);
        params = get_wind_params(cfg, pid);

        [v10, v10_max, t10_max] = bms.analyzer.DynamicSeriesService.movingMeanSeries( ...
            t_speed, v_speed, fs, params.window_minutes, 0.7);

        speed_stats = bms.analyzer.StructuralSeriesService.statsTriple(v_speed, params.decimals);
        stats(i,:) = {pid, speed_stats(1), speed_stats(2), speed_stats(3), v10_max, t10_max};

        plot_speed_timeseries(t_speed, v_speed, pid, style, out_root, start_date, end_date, cfg);
        plot_direction_timeseries(t_dir, v_dir, pid, style, out_root, start_date, end_date, cfg);
        plot_speed_10min(t_speed, v10, pid, params, style, out_root, start_date, end_date, cfg);

        if ~isempty(v_dir)
            [rose_speed, rose_dir] = bms.analyzer.WindRoseService.alignForRose(t_speed, v_speed, t_dir, v_dir);
            plot_wind_rose(rose_dir, rose_speed, pid, params, style, out_root, start_date, end_date, cfg);
        end
    end

    T = bms.analyzer.DynamicSeriesService.windStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(T, stats_file, 'wind');
    fprintf('Wind stats saved to %s\n', stats_file);

    time_end = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
    fprintf('结束时间: %s\n', char(time_end));
    elapsed = seconds(time_end - time_start);
    fprintf('总用时: %.2f 秒\n', elapsed);
end


function stats_file = get_wind_stats_file(cfg)
    stats_file = 'wind_stats.xlsx';
    if isfield(cfg, 'plot_styles') && isfield(cfg.plot_styles, 'wind') ...
            && isstruct(cfg.plot_styles.wind) ...
            && isfield(cfg.plot_styles.wind, 'output') ...
            && isstruct(cfg.plot_styles.wind.output) ...
            && isfield(cfg.plot_styles.wind.output, 'stats_file') ...
            && ~isempty(cfg.plot_styles.wind.output.stats_file)
        stats_file = cfg.plot_styles.wind.output.stats_file;
    end
end
function plot_speed_timeseries(times, vals, pid, style, out_root, start_date, end_date, cfg)
    if nargin < 8
        cfg = struct();
    end
    if isempty(vals)
        return;
    end
    fig = figure('Position', [100 100 1100 500]);
    [times_plot, vals_plot] = prepare_plot_series(times, vals);
    plot(times_plot, vals_plot, 'LineWidth', 1.1, 'Color', style.speed.color);
    xlabel('时间');
    ylabel(style.speed.ylabel);
    title(sprintf('%s %s [%s-%s]', style.speed.title_prefix, pid, start_date, end_date));
    grid on; grid minor;
    if ~isempty(style.speed.ylim)
        ylim(style.speed.ylim);
    end
    set_time_axis(times);

    out_dir = fullfile(out_root, style.output.speed_dir);
    ensure_dir(out_dir);
    save_plot(fig, out_dir, sprintf('%s_speed_%s_%s', pid, start_date, end_date), cfg);
end

function plot_direction_timeseries(times, vals, pid, style, out_root, start_date, end_date, cfg)
    if nargin < 8
        cfg = struct();
    end
    if isempty(vals)
        return;
    end
    fig = figure('Position', [100 100 1100 500]);
    [times_plot, vals_plot] = prepare_plot_series(times, vals);
    plot(times_plot, vals_plot, 'LineWidth', 1.0, 'Color', style.direction.color);
    xlabel('时间');
    ylabel(style.direction.ylabel);
    title(sprintf('%s %s [%s-%s]', style.direction.title_prefix, pid, start_date, end_date));
    grid on; grid minor;
    ylim([0 360]);
    set_time_axis(times);

    out_dir = fullfile(out_root, style.output.direction_dir);
    ensure_dir(out_dir);
    save_plot(fig, out_dir, sprintf('%s_direction_%s_%s', pid, start_date, end_date), cfg);
end

function plot_speed_10min(times, v10, pid, params, style, out_root, start_date, end_date, cfg)
    if nargin < 9
        cfg = struct();
    end
    if isempty(v10)
        return;
    end
    fig = figure('Position', [100 100 1100 500]);
    [times_plot, v10_plot] = prepare_plot_series(times, v10);
    plot(times_plot, v10_plot, 'LineWidth', 1.2, 'Color', style.speed10.color);
    xlabel('时间');
    ylabel(style.speed10.ylabel);
    title(sprintf('%s %s [%s-%s]', style.speed10.title_prefix, pid, start_date, end_date));
    grid on; grid minor; hold on;
    if ~isempty(style.speed10.ylim)
        ylim(style.speed10.ylim);
    end
    set_time_axis(times);

    levels = params.alarm_levels(:)';
    if isempty(levels)
        levels = [];
    end
    levels = sort(levels(~isnan(levels)));
    labels = {'一级','二级','三级'};
    colors = [0 0.447 0.741; 1 0.85 0; 0.85 0.1 0.1]; % blue, yellow, red
    for i = 1:min(numel(levels), numel(labels))
        lv = levels(i);
        h = yline(lv, '--', labels{i}, 'Color', colors(i,:));
        h.LabelHorizontalAlignment = 'left';
        h.LabelVerticalAlignment = 'bottom';
    end

    out_dir = fullfile(out_root, style.output.speed10_dir);
    ensure_dir(out_dir);
    save_plot(fig, out_dir, sprintf('%s_speed10min_%s_%s', pid, start_date, end_date), cfg);
end

function plot_wind_rose(dir_deg, speed, pid, params, style, out_root, start_date, end_date, cfg)
    if nargin < 9
        cfg = struct();
    end
    if isempty(dir_deg)
        return;
    end
    [rose_mat, sector_edges, speed_edges, total_count] = bms.analyzer.WindRoseService.buildMatrix(dir_deg, speed, params);
    if total_count == 0
        return;
    end

    fig = figure('Position', [100 100 720 640]);
    ax = axes(fig);
    axis(ax, 'equal'); axis(ax, 'off'); hold(ax, 'on');
    title(ax, sprintf('%s %s [%s-%s]', style.rose.title_prefix, pid, start_date, end_date));

    colors = get_rose_colors(style, size(rose_mat,2));
    draw_wind_rose(ax, rose_mat, sector_edges, colors);
    draw_polar_grid(ax, max(sum(rose_mat, 2)));
    draw_direction_labels(ax, max(sum(rose_mat, 2)) * 1.08);

    speed_labels = bms.analyzer.WindRoseService.speedBinLabels(speed_edges);
    legend_handles = gobjects(numel(speed_labels),1);
    for k = 1:numel(speed_labels)
        legend_handles(k) = patch(ax, NaN, NaN, colors(k,:), 'EdgeColor','none');
    end
    legend(ax, legend_handles, speed_labels, 'Location','eastoutside');

    out_dir = fullfile(out_root, style.output.rose_dir);
    ensure_dir(out_dir);
    base_name = sprintf('%s_windrose_%s_%s', pid, start_date, end_date);
    save_plot(fig, out_dir, base_name, cfg);

    bms.analyzer.WindRoseService.writeSummary(out_dir, base_name, pid, dir_deg, speed, sector_edges, speed_edges, rose_mat, total_count);
end

function colors = get_rose_colors(style, nbin)
    if nbin <= 0
        colors = zeros(0, 3);
        return;
    end
    colors = [];
    if isfield(style, 'rose') && isstruct(style.rose) && isfield(style.rose, 'colors')
        colors = style.rose.colors;
    end
    if isempty(colors) || size(colors, 2) ~= 3
        colors = parula(max(nbin, 3));
    end
    if size(colors, 1) < nbin
        colors = repmat(colors(end,:), nbin, 1);
    end
    colors = colors(1:nbin, :);
    if size(colors, 1) < nbin
        colors = repmat(colors(end,:), nbin, 1);
    end
    colors = colors(1:nbin, :);
end

function draw_wind_rose(ax, mat, sector_edges, colors)
    if isempty(mat)
        return;
    end
    n_sec = size(mat, 1);
    n_bin = size(mat, 2);
    ang_edges = deg2rad(sector_edges);
    for si = 1:n_sec
        theta1 = ang_edges(si);
        theta2 = ang_edges(si+1);
        r0 = 0;
        for bi = 1:n_bin
            r1 = r0 + mat(si, bi);
            if r1 > r0
                draw_annular_sector(ax, theta1, theta2, r0, r1, colors(bi, :));
            end
            r0 = r1;
        end
    end
end

function draw_annular_sector(ax, theta1, theta2, r0, r1, color)
    n = 30;
    t = linspace(theta1, theta2, n);
    [x1, y1] = pol2cart(t, r1 * ones(1, n));
    [x0, y0] = pol2cart(fliplr(t), r0 * ones(1, n));
    x = [x1 x0];
    y = [y1 y0];
    patch(ax, x, y, color, 'EdgeColor', 'none', 'FaceAlpha', 0.9);
end

function draw_polar_grid(ax, rmax)
    if rmax <= 0
        rmax = 1;
    end
    steps = 4;
    for i = 1:steps
        r = rmax * i / steps;
        t = linspace(0, 2*pi, 120);
        [x, y] = pol2cart(t, r * ones(size(t)));
        plot(ax, x, y, 'Color', [0.8 0.8 0.8], 'LineStyle', ':');
        text(ax, r, 0, sprintf('%.0f%%', r * 100), 'FontSize', 9, 'Color', [0.4 0.4 0.4]);
    end
    for ang = 0:45:315
        t = deg2rad(ang);
        [x, y] = pol2cart([t t], [0 rmax]);
        plot(ax, x, y, 'Color', [0.85 0.85 0.85]);
    end
end

function draw_direction_labels(ax, r)
    labels = {'N','NE','E','SE','S','SW','W','NW'};
    angles = 0:45:315;
    for i = 1:numel(angles)
        t = deg2rad(angles(i));
        [x, y] = pol2cart(t, r);
        text(ax, x, y, labels{i}, 'HorizontalAlignment','center', 'VerticalAlignment','middle', 'FontWeight','bold');
    end
end

function set_time_axis(times)
    bms.plot.PlotService.setTimeAxis(times);
end

function save_plot(fig, out_dir, base_name, cfg)
    if nargin < 4
        cfg = struct();
    end
    bms.plot.PlotService.saveModuleBundleWithTimestamp(fig, out_dir, base_name, cfg);
end

function ensure_dir(p)
    bms.core.PathResolver.ensureDir(p);
end

function pts = get_points(cfg, key, fallback)
    pts = bms.data.PointResolver.fromConfig(cfg, key, fallback);
end

function style = get_wind_style(cfg)
    style = struct();
    style.output = struct( ...
        'root_dir', '风速风向结果', ...
        'speed_dir', '风速时程', ...
        'direction_dir', '风向时程', ...
        'speed10_dir', '风速10min', ...
        'rose_dir', '风玫瑰', ...
        'stats_file', 'wind_stats.xlsx');
    style.speed = struct('ylabel', '风速 (m/s)', 'title_prefix', '风速时程', ...
                         'ylim', [], 'color', [0 0.447 0.741]);
    style.direction = struct('ylabel', '风向 (°)', 'title_prefix', '风向时程', ...
                             'ylim', [0 360], 'color', [0.15 0.5 0.15]);
    style.speed10 = struct('ylabel', '10 min 均值风速 (m/s)', 'title_prefix', '风速10min均值', ...
                           'ylim', [], 'color', [0.8500 0.3250 0.0980], ...
                           'alarm_color', [0.8 0.1 0.1]);
    style.rose = struct('title_prefix', '风玫瑰', 'color', [0.2 0.4 0.8], 'colors', []);

    if isfield(cfg, 'plot_styles') && isfield(cfg.plot_styles, 'wind')
        ps = cfg.plot_styles.wind;
        if isfield(ps, 'output') && isstruct(ps.output)
            style.output = merge_struct(style.output, ps.output);
        end
        if isfield(ps, 'speed') && isstruct(ps.speed)
            style.speed = merge_struct(style.speed, ps.speed);
        end
        if isfield(ps, 'direction') && isstruct(ps.direction)
            style.direction = merge_struct(style.direction, ps.direction);
        end
        if isfield(ps, 'speed10') && isstruct(ps.speed10)
            style.speed10 = merge_struct(style.speed10, ps.speed10);
        end
        if isfield(ps, 'rose') && isstruct(ps.rose)
            style.rose = merge_struct(style.rose, ps.rose);
        end
    end
end

function params = get_wind_params(cfg, pid)
    params = struct();
    params.alarm_levels = [25, 29.92, 37.4];
    params.window_minutes = 10;
    params.decimals = 2;
    params.speed_bins = [0 2 4 6 8 10 15 20 25 30 35 40];
    params.sector_deg = 22.5;

    if isfield(cfg, 'wind_params') && isstruct(cfg.wind_params)
        wp = cfg.wind_params;
        if isfield(wp, 'alarm_levels') && ~isempty(wp.alarm_levels)
            params.alarm_levels = double(wp.alarm_levels(:))';
        end
        if isfield(wp, 'window_minutes') && ~isempty(wp.window_minutes)
            params.window_minutes = double(wp.window_minutes);
        end
        if isfield(wp, 'decimals') && ~isempty(wp.decimals)
            params.decimals = double(wp.decimals);
        end
        if isfield(wp, 'speed_bins') && ~isempty(wp.speed_bins)
            params.speed_bins = double(wp.speed_bins(:))';
        end
        if isfield(wp, 'sector_deg') && ~isempty(wp.sector_deg)
            params.sector_deg = double(wp.sector_deg);
        end
    end

    if nargin < 2 || isempty(pid)
        return;
    end
    safe_id = strrep(pid, '-', '_');
    if isfield(cfg, 'per_point') && isfield(cfg.per_point, 'wind') ...
            && isfield(cfg.per_point.wind, safe_id)
        pt = cfg.per_point.wind.(safe_id);
        if isfield(pt, 'alarm_levels') && ~isempty(pt.alarm_levels)
            params.alarm_levels = double(pt.alarm_levels(:))';
        end
        if isfield(pt, 'window_minutes') && ~isempty(pt.window_minutes)
            params.window_minutes = double(pt.window_minutes);
        end
        if isfield(pt, 'decimals') && ~isempty(pt.decimals)
            params.decimals = double(pt.decimals);
        end
        if isfield(pt, 'speed_bins') && ~isempty(pt.speed_bins)
            params.speed_bins = double(pt.speed_bins(:))';
        end
        if isfield(pt, 'sector_deg') && ~isempty(pt.sector_deg)
            params.sector_deg = double(pt.sector_deg);
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
