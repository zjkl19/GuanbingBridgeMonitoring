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

        fs = estimate_fs(t_speed);
        params = get_wind_params(cfg, pid);

        [v10, t10_max, v10_max] = compute_speed_10min(t_speed, v_speed, fs, params.window_minutes);

        mn = round(min(v_speed, [], 'omitnan'), params.decimals);
        mx = round(max(v_speed, [], 'omitnan'), params.decimals);
        av = round(mean(v_speed, 'omitnan'), params.decimals);
        stats(i,:) = {pid, mn, mx, av, v10_max, t10_max};

        plot_speed_timeseries(t_speed, v_speed, pid, style, out_root, start_date, end_date);
        plot_direction_timeseries(t_dir, v_dir, pid, style, out_root, start_date, end_date);
        plot_speed_10min(t_speed, v10, pid, params, style, out_root, start_date, end_date);

        if ~isempty(v_dir)
            [rose_speed, rose_dir] = align_for_rose(t_speed, v_speed, t_dir, v_dir);
            plot_wind_rose(rose_dir, rose_speed, pid, params, style, out_root, start_date, end_date);
        end
    end

    T = cell2table(stats, 'VariableNames', {'PointID','MinSpeed','MaxSpeed','MeanSpeed','Mean10minMax','Mean10minTime'});
    writetable(T, fullfile(out_root, style.output.stats_file));
    fprintf('统计结果已保存至 %s\n', fullfile(out_root, style.output.stats_file));

    time_end = datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss');
    fprintf('结束时间: %s\n', char(time_end));
    elapsed = seconds(time_end - time_start);
    fprintf('总用时: %.2f 秒\n', elapsed);
end

function fs = estimate_fs(times)
    fs = 1;
    if numel(times) < 2
        return;
    end
    dts = seconds(diff(times));
    dts = dts(isfinite(dts) & dts > 0);
    if isempty(dts)
        return;
    end
    fs = 1 / median(dts);
    if ~isfinite(fs) || fs <= 0
        fs = 1;
    end
end

function [v10, t_max, v_max] = compute_speed_10min(times, vals, fs, window_minutes)
    if nargin < 4 || isempty(window_minutes)
        window_minutes = 10;
    end
    win_len = max(1, round(window_minutes * 60 * fs));
    valid_cnt = movsum(isfinite(vals), win_len, 'Endpoints', 'shrink');
    v10 = movmean(vals, win_len, 'omitnan', 'Endpoints', 'shrink');
    min_need = max(1, round(0.7 * win_len));
    v10(valid_cnt < min_need) = NaN;

    [v_max, idx_max] = max(v10, [], 'omitnan');
    t_max = NaT;
    if ~isempty(idx_max) && isfinite(v_max)
        t_max = times(idx_max);
    end
end

function [speed_aligned, dir_aligned] = align_for_rose(t_speed, v_speed, t_dir, v_dir)
    if isempty(v_speed) || isempty(v_dir)
        speed_aligned = [];
        dir_aligned = [];
        return;
    end
    x_dir = posixtime(t_dir);
    x_spd = posixtime(t_speed);
    if numel(unique(x_dir)) < 2
        speed_aligned = [];
        dir_aligned = [];
        return;
    end
    dir_interp = interp1(x_dir, v_dir, x_spd, 'nearest', NaN);
    mask = isfinite(v_speed) & isfinite(dir_interp);
    speed_aligned = v_speed(mask);
    dir_aligned = dir_interp(mask);
    dir_aligned = mod(dir_aligned, 360);
end

function plot_speed_timeseries(times, vals, pid, style, out_root, start_date, end_date)
    if isempty(vals)
        return;
    end
    fig = figure('Position', [100 100 1100 500]);
    plot(times, vals, 'LineWidth', 1.1, 'Color', style.speed.color);
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
    save_plot(fig, out_dir, sprintf('%s_speed_%s_%s', pid, start_date, end_date));
end

function plot_direction_timeseries(times, vals, pid, style, out_root, start_date, end_date)
    if isempty(vals)
        return;
    end
    fig = figure('Position', [100 100 1100 500]);
    plot(times, vals, 'LineWidth', 1.0, 'Color', style.direction.color);
    xlabel('时间');
    ylabel(style.direction.ylabel);
    title(sprintf('%s %s [%s-%s]', style.direction.title_prefix, pid, start_date, end_date));
    grid on; grid minor;
    ylim([0 360]);
    set_time_axis(times);

    out_dir = fullfile(out_root, style.output.direction_dir);
    ensure_dir(out_dir);
    save_plot(fig, out_dir, sprintf('%s_direction_%s_%s', pid, start_date, end_date));
end

function plot_speed_10min(times, v10, pid, params, style, out_root, start_date, end_date)
    if isempty(v10)
        return;
    end
    fig = figure('Position', [100 100 1100 500]);
    plot(times, v10, 'LineWidth', 1.2, 'Color', style.speed10.color);
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
    save_plot(fig, out_dir, sprintf('%s_speed10min_%s_%s', pid, start_date, end_date));
end

function plot_wind_rose(dir_deg, speed, pid, params, style, out_root, start_date, end_date)
    if isempty(dir_deg)
        return;
    end
    [rose_mat, sector_edges, speed_edges, total_count] = build_wind_rose_matrix(dir_deg, speed, params);
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

    speed_labels = speed_bin_labels(speed_edges);
    legend_handles = gobjects(numel(speed_labels),1);
    for k = 1:numel(speed_labels)
        legend_handles(k) = patch(ax, NaN, NaN, colors(k,:), 'EdgeColor','none');
    end
    legend(ax, legend_handles, speed_labels, 'Location','eastoutside');

    out_dir = fullfile(out_root, style.output.rose_dir);
    ensure_dir(out_dir);
    base_name = sprintf('%s_windrose_%s_%s', pid, start_date, end_date);
    save_plot(fig, out_dir, base_name);

    write_wind_summary(out_dir, base_name, pid, dir_deg, speed, sector_edges, speed_edges, rose_mat, total_count);
end

function ang = circular_mean_deg(dir_deg)
    if isempty(dir_deg)
        ang = NaN;
        return;
    end
    theta = deg2rad(dir_deg(:));
    s = mean(sin(theta), 'omitnan');
    c = mean(cos(theta), 'omitnan');
    if ~isfinite(s) || ~isfinite(c) || (abs(s) < eps && abs(c) < eps)
        ang = NaN;
        return;
    end
    ang = mod(rad2deg(atan2(s, c)), 360);
end


function [mat, sector_edges, speed_edges, total_count] = build_wind_rose_matrix(dir_deg, speed, params)
    dir_deg = mod(dir_deg(:), 360);
    speed = speed(:);
    mask = isfinite(dir_deg) & isfinite(speed);
    dir_deg = dir_deg(mask);
    speed = speed(mask);

    if isempty(dir_deg)
        mat = [];
        sector_edges = [];
        speed_edges = [];
        total_count = 0;
        return;
    end

    sector_deg = params.sector_deg;
    if isempty(sector_deg) || sector_deg <= 0
        sector_deg = 22.5;
    end
    sector_edges = 0:sector_deg:360;
    if sector_edges(end) < 360
        sector_edges = [sector_edges 360];
    end

    speed_edges = params.speed_bins(:)';
    if isempty(speed_edges)
        speed_edges = [0 2 4 6 8 10 15 20 25 30 35 40];
    end
    speed_edges = unique(speed_edges, 'stable');
    if speed_edges(1) > 0
        speed_edges = [0 speed_edges];
    end
    if speed_edges(end) < max(speed)
        speed_edges = [speed_edges inf];
    end

    sector_idx = discretize(dir_deg, sector_edges, 'IncludedEdge','right');
    sector_idx(sector_idx == 0) = 1;
    bin_idx = discretize(speed, speed_edges);

    n_sec = numel(sector_edges) - 1;
    n_bin = numel(speed_edges) - 1;
    mat = zeros(n_sec, n_bin);
    for i = 1:numel(sector_idx)
        si = sector_idx(i);
        bi = bin_idx(i);
        if ~isnan(si) && ~isnan(bi) && si >= 1 && si <= n_sec && bi >= 1 && bi <= n_bin
            mat(si, bi) = mat(si, bi) + 1;
        end
    end
    total_count = sum(mat, 'all');
    if total_count > 0
        mat = mat ./ total_count; % normalize to probability
    end
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

function labels = speed_bin_labels(edges)
    labels = cell(1, numel(edges)-1);
    for i = 1:numel(labels)
        a = edges(i);
        b = edges(i+1);
        if isinf(b)
            labels{i} = sprintf('>=%.0f m/s', a);
        else
            labels{i} = sprintf('%.0f-%.0f m/s', a, b);
        end
    end
end

function write_wind_summary(out_dir, base_name, pid, dir_deg, speed, sector_edges, speed_edges, mat, total_count)
    if total_count <= 0
        return;
    end
    mean_dir = circular_mean_deg(dir_deg);
    mean_speed = mean(speed, 'omitnan');
    max_speed = max(speed, [], 'omitnan');

    sector_totals = sum(mat, 2);
    [dom_val, dom_idx] = max(sector_totals);
    dom_range = sprintf('%.1f°-%.1f°', sector_edges(dom_idx), sector_edges(dom_idx+1));

    bin_totals = sum(mat, 1);
    [~, bin_idx] = max(bin_totals);
    speed_label = speed_bin_labels(speed_edges);
    main_bin = speed_label{bin_idx};

    fid = fopen(fullfile(out_dir, [base_name '_summary.txt']), 'w', 'n', 'UTF-8');
    if fid < 0
        return;
    end
    fprintf(fid, '风玫瑰简要结论（%s）\n', pid);
    fprintf(fid, '样本总数: %d\n', total_count);
    if isfinite(mean_dir)
        fprintf(fid, '平均风向: %.1f°\n', mean_dir);
    end
    fprintf(fid, '主导风向: %s，占比 %.1f%%\n', dom_range, dom_val * 100);
    fprintf(fid, '平均风速: %.2f m/s\n', mean_speed);
    fprintf(fid, '最大风速: %.2f m/s\n', max_speed);
    fprintf(fid, '主要风速等级: %s（依据：全样本风速分级占比最高）\n', main_bin);
    fclose(fid);
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
