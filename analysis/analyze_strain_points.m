function analyze_strain_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_strain_points Plot static strain time series and grouped boxplots.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), error('start_date is required'); end
    if nargin < 3 || isempty(end_date), error('end_date is required'); end
    if nargin < 4 || isempty(excel_file), excel_file = 'strain_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin < 6 || isempty(cfg), cfg = load_config(); end

    if nargin < 5 || isempty(subfolder)
        if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, 'strain')
            subfolder = cfg.subfolders.strain;
        else
            subfolder = '特征值';
        end
    end

    style = get_style(cfg, 'strain');
    points_cfg = get_points(cfg, 'strain', {});
    groups_cfg = get_groups(cfg, 'strain');
    ts_groups_cfg = get_groups(cfg, 'strain_timeseries');
    explicit_points = ~isempty(points_cfg);
    explicit_groups = has_groups(groups_cfg);
    explicit_ts_groups = has_groups(ts_groups_cfg);

    if ~explicit_ts_groups && explicit_groups
        ts_groups_cfg = groups_cfg;
        explicit_ts_groups = true;
    end

    if ~explicit_points && ~explicit_groups && ~explicit_ts_groups
        groups_cfg = legacy_strain_groups();
        ts_groups_cfg = groups_cfg;
        explicit_groups = true;
        explicit_ts_groups = true;
    end

    stats_rows = cell(0, 4);
    if explicit_points
        for i = 1:numel(points_cfg)
            pid = points_cfg{i};
            fprintf('Per-point strain: %s ...\n', pid);
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'strain');
            if isempty(vals)
                warning('Strain point %s has no data, skip', pid);
                continue;
            end

            stats_rows(end+1, :) = { ... %#ok<AGROW>
                pid, ...
                round(min(vals), 3), ...
                round(max(vals), 3), ...
                round(mean(vals, 'omitnan'), 3)};

            warn_lines = resolve_warn_lines(style, cfg, pid);
            plot_point_curve(root_dir, times, vals, start_date, end_date, pid, style, warn_lines);
        end
    end

    if explicit_ts_groups
        ts_groups_map = normalize_group_map(ts_groups_cfg);
        names = fieldnames(ts_groups_map);
        for i = 1:numel(names)
            group_name = names{i};
            [data_list, group_stats] = collect_group_data(root_dir, subfolder, ts_groups_map.(group_name), start_date, end_date, cfg);
            if isempty(data_list)
                continue;
            end

            if ~explicit_points && ~explicit_groups
                stats_rows = [stats_rows; group_stats]; %#ok<AGROW>
            end
            plot_group_timeseries(root_dir, data_list, start_date, end_date, group_name, style);
        end
    end

    if explicit_groups
        groups_map = normalize_group_map(groups_cfg);
        names = fieldnames(groups_map);
        for i = 1:numel(names)
            group_name = names{i};
            [data_list, group_stats] = collect_group_data(root_dir, subfolder, groups_map.(group_name), start_date, end_date, cfg);
            if isempty(data_list)
                continue;
            end

            if ~explicit_points
                stats_rows = [stats_rows; group_stats]; %#ok<AGROW>
            end
            plot_group_boxplot(root_dir, data_list, start_date, end_date, group_name, style, cfg);
        end
    end

    T = cell2table(stats_rows, 'VariableNames', {'PointID', 'Min', 'Max', 'Mean'});
    writetable(T, excel_file);
    fprintf('Strain stats saved to %s\n', excel_file);
end

function [data_list, stats_rows] = collect_group_data(root_dir, subfolder, pids, start_date, end_date, cfg)
    data_list = struct('pid', {}, 'times', {}, 'vals', {});
    stats_rows = cell(0, 4);
    for i = 1:numel(pids)
        pid = pids{i};
        fprintf('Extracting %s ...\n', pid);
        [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'strain');
        if isempty(vals)
            warning('Strain point %s has no data, skip', pid);
            continue;
        end
        data_list(end+1, 1) = struct('pid', pid, 'times', times, 'vals', vals); %#ok<AGROW>
        stats_rows(end+1, :) = { ... %#ok<AGROW>
            pid, ...
            round(min(vals), 3), ...
            round(max(vals), 3), ...
            round(mean(vals, 'omitnan'), 3)};
    end
end

function plot_point_curve(root_dir, times, vals, start_date, end_date, pid, style, warn_lines)
    fig = figure('Position', [100 100 1000 469]);
    hold on;
    plot(times, vals, 'LineWidth', 1.0, 'Color', [0 0.447 0.741]);

    dt0 = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    dt1 = datetime(end_date, 'InputFormat', 'yyyy-MM-dd');
    if dt1 <= dt0
        dt1 = dt0 + days(1);
    end
    ticks = dt0 + (dt1 - dt0) * (0:4) / 4;
    ax = gca;
    ax.XLim = [dt0 dt1];
    ax.XTick = ticks;
    xtickformat('yyyy-MM-dd');

    xlabel('时间');
    ylabel(get_style_field(style, 'ylabel', '主梁应变 (με)'));
    title(sprintf('%s %s', get_style_field(style, 'title_prefix', '应变时程曲线'), char(string(pid))));

    show_warn_lines = get_style_field(style, 'show_warn_lines_point', true);
    if (islogical(show_warn_lines) && show_warn_lines) || (isnumeric(show_warn_lines) && show_warn_lines ~= 0)
        warn_lines = normalize_warn_lines(warn_lines);
        for k = 1:numel(warn_lines)
            wl = warn_lines{k};
            if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ~isscalar(wl.y) || ~isfinite(wl.y)
                continue;
            end
            yl = yline(wl.y, '--', get_warn_label(wl), 'LabelHorizontalAlignment', 'left');
            if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                yl.Color = wl.color;
            end
        end
    end

    ylim_auto = get_style_field(style, 'ylim_auto', false);
    if (islogical(ylim_auto) && ylim_auto) || (isnumeric(ylim_auto) && ylim_auto ~= 0)
        ylim auto;
    else
        ylim_default = get_style_field(style, 'ylim', []);
        ylim_override = get_ylim_for_pid(style, pid, ylim_default);
        if is_valid_ylim(ylim_override)
            ylim(ylim_override);
        else
            ylim auto;
        end
    end

    grid on;
    grid minor;

    ts = datestr(now, 'yyyymmdd_HHMMSS');
    out_dir = fullfile(root_dir, char(string(get_style_field(style, 'output_dir', '时程曲线_应变'))));
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    fname = sanitize_filename(sprintf('Strain_%s_%s_%s', char(string(pid)), datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd')));
    save_plot_bundle(fig, out_dir, [fname '_' ts]);
end

function plot_group_timeseries(root_dir, data_list, start_date, end_date, group_name, style)
    if isempty(data_list)
        return;
    end

    fig = figure('Position', [100 100 1000 469]);
    hold on;
    n_series = numel(data_list);
    if n_series > 12
        fprintf('[WARN] Strain group %s has %d curves; consider splitting it for readability.\n', ...
            char(string(group_name)), n_series);
    end
    colors = get_group_colors(style, n_series);

    h_lines = gobjects(n_series, 1);
    for i = 1:n_series
        c = colors(i, :);
        h_lines(i) = plot(data_list(i).times, data_list(i).vals, 'LineWidth', 1.0, 'Color', c);
    end
    labels = {data_list.pid};
    lg = legend(h_lines, labels, 'Location', 'northeast', 'Box', 'off');
    lg.AutoUpdate = 'off';

    dt0 = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    dt1 = datetime(end_date, 'InputFormat', 'yyyy-MM-dd');
    if dt1 <= dt0
        dt1 = dt0 + days(1);
    end
    ticks = dt0 + (dt1 - dt0) * (0:4) / 4;
    ax = gca;
    ax.XLim = [dt0 dt1];
    ax.XTick = ticks;
    xtickformat('yyyy-MM-dd');

    xlabel('时间');
    ylabel(get_style_field(style, 'ylabel', '主梁应变 (με)'));
    title(sprintf('%s %s', get_style_field(style, 'title_prefix', '应变时程曲线'), char(string(group_name))));

    group_ylim = get_group_ylim(style, group_name, []);
    if is_valid_ylim(group_ylim)
        ylim(group_ylim);
    else
        ylim auto;
    end

    grid on;
    grid minor;

    ts = datestr(now, 'yyyymmdd_HHMMSS');
    out_dir = fullfile(root_dir, char(string(get_style_field(style, 'group_output_dir', '时程曲线_应变_组图'))));
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    fname = sanitize_filename(sprintf('Strain_%s_%s_%s', char(string(group_name)), datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd')));
    save_plot_bundle(fig, out_dir, [fname '_' ts]);
end

function plot_group_boxplot(root_dir, data_list, start_date, end_date, group_name, style, cfg)
    if isempty(data_list)
        return;
    end

    labels = {data_list.pid};
    [data_mat, max_len] = build_boxplot_matrix(data_list); %#ok<ASGLU>

    fig = figure('Position', [100 100 1200 520]);
    show_outliers = get_style_field(style, 'show_boxplot_outliers', false);
    if (islogical(show_outliers) && show_outliers) || (isnumeric(show_outliers) && show_outliers ~= 0)
        boxplot(data_mat, 'Labels', labels, 'LabelOrientation', 'inline');
    else
        boxplot(data_mat, 'Labels', labels, 'LabelOrientation', 'inline', 'Symbol', '');
    end
    hold on;
    xtickangle(45);

    show_warn_lines = get_style_field(style, 'show_warn_lines_boxplot', true);
    if (islogical(show_warn_lines) && show_warn_lines) || (isnumeric(show_warn_lines) && show_warn_lines ~= 0)
        for i = 1:numel(data_list)
            warn_lines = resolve_warn_lines(style, cfg, data_list(i).pid);
            warn_lines = normalize_warn_lines(warn_lines);
            for k = 1:numel(warn_lines)
                wl = warn_lines{k};
                if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ~isscalar(wl.y) || ~isfinite(wl.y)
                    continue;
                end
                x0 = i - 0.28;
                x1 = i + 0.28;
                col = [0.5 0.5 0.5];
                if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
                    col = wl.color;
                end
                line([x0 x1], [wl.y wl.y], 'LineStyle', '--', 'LineWidth', 1.0, 'Color', col);
            end
        end
    end

    ylabel(get_style_field(style, 'ylabel', '主梁应变 (με)'));
    title(sprintf('%s %s', get_style_field(style, 'boxplot_title_prefix', '应变箱线图'), char(string(group_name))));

    group_ylim = get_group_ylim(style, group_name, []);
    if is_valid_ylim(group_ylim)
        ylim(group_ylim);
    else
        ylim auto;
    end

    grid on;
    grid minor;

    dt0 = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    dt1 = datetime(end_date, 'InputFormat', 'yyyy-MM-dd');
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    out_dir = fullfile(root_dir, char(string(get_style_field(style, 'boxplot_output_dir', '箱线图_应变'))));
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    fname = sanitize_filename(sprintf('StrainBox_%s_%s_%s', char(string(group_name)), datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd')));
    save_plot_bundle(fig, out_dir, [fname '_' ts]);
end

function [data_mat, max_len] = build_boxplot_matrix(data_list)
    max_len = 0;
    for i = 1:numel(data_list)
        max_len = max(max_len, numel(data_list(i).vals));
    end
    data_mat = NaN(max_len, numel(data_list));
    for i = 1:numel(data_list)
        v = data_list(i).vals(:);
        data_mat(1:numel(v), i) = v;
    end
end

function warn_lines = resolve_warn_lines(style, cfg, pid)
    warn_lines = {};
    global_warn = get_style_field(style, 'warn_lines', {});
    if ~isempty(global_warn)
        warn_lines = normalize_warn_lines(global_warn);
    end
    if isempty(pid)
        return;
    end
    if ~isfield(cfg, 'per_point') || ~isfield(cfg.per_point, 'strain')
        return;
    end
    safe_id = strrep(pid, '-', '_');
    if ~isfield(cfg.per_point.strain, safe_id)
        return;
    end
    pt = cfg.per_point.strain.(safe_id);
    if isfield(pt, 'warn_lines')
        if isempty(pt.warn_lines)
            warn_lines = {};
        else
            warn_lines = normalize_warn_lines(pt.warn_lines);
        end
    elseif isfield(pt, 'alarm_bounds') && ~isempty(pt.alarm_bounds)
        warn_lines = bounds_to_warn_lines(pt.alarm_bounds, style);
    end
end

function warn_lines = bounds_to_warn_lines(bounds, style)
    warn_lines = {};
    if isempty(bounds) || ~isstruct(bounds)
        return;
    end

    colors = get_style_field(style, 'alarm_colors', []);
    level2_color = [0.929 0.694 0.125];
    level3_color = [0.85 0.1 0.1];
    if isnumeric(colors) && size(colors, 2) == 3
        if size(colors, 1) >= 1
            level2_color = colors(1, :);
        end
        if size(colors, 1) >= 2
            level3_color = colors(2, :);
        end
    elseif iscell(colors)
        if numel(colors) >= 1 && isnumeric(colors{1}) && numel(colors{1}) == 3
            level2_color = reshape(colors{1}, 1, 3);
        end
        if numel(colors) >= 2 && isnumeric(colors{2}) && numel(colors{2}) == 3
            level3_color = reshape(colors{2}, 1, 3);
        end
    end

    warn_lines = [warn_lines; append_alarm_pair(bounds, 'level2', '二级', level2_color)]; %#ok<AGROW>
    warn_lines = [warn_lines; append_alarm_pair(bounds, 'level3', '三级', level3_color)]; %#ok<AGROW>
end

function lines = append_alarm_pair(bounds, field_name, prefix, color)
    lines = {};
    if ~isfield(bounds, field_name)
        return;
    end
    vals = bounds.(field_name);
    if ~isnumeric(vals) || numel(vals) ~= 2
        return;
    end
    vals = sort(vals(:));
    labels = {sprintf('%s下限', prefix), sprintf('%s上限', prefix)};
    for i = 1:2
        if ~isfinite(vals(i))
            continue;
        end
        lines{end+1, 1} = struct('y', vals(i), 'label', labels{i}, 'color', color); %#ok<AGROW>
    end
end

function ccell = normalize_warn_lines(v)
    ccell = {};
    if isempty(v)
        return;
    end
    if isstruct(v)
        ccell = num2cell(v);
        return;
    end
    if isnumeric(v)
        vv = v(:);
        ccell = cell(numel(vv), 1);
        for i = 1:numel(vv)
            ccell{i} = struct('y', vv(i));
        end
        return;
    end
    if iscell(v)
        for i = 1:numel(v)
            item = v{i};
            if isstruct(item)
                ccell{end+1, 1} = item; %#ok<AGROW>
            elseif isnumeric(item) && isscalar(item)
                ccell{end+1, 1} = struct('y', item); %#ok<AGROW>
            end
        end
    end
end

function lbl = get_warn_label(wl)
    lbl = '';
    if isfield(wl, 'label') && (ischar(wl.label) || isstring(wl.label))
        lbl = char(string(wl.label));
    end
end

function groups = get_groups(cfg, key)
    groups = [];
    if isfield(cfg, 'groups') && isfield(cfg.groups, key)
        groups = cfg.groups.(key);
    end
end

function groups = normalize_group_map(groups_cfg)
    groups = struct();
    if isempty(groups_cfg)
        return;
    end
    if isstruct(groups_cfg)
        names = fieldnames(groups_cfg);
        for i = 1:numel(names)
            groups.(names{i}) = normalize_points(groups_cfg.(names{i}));
        end
        return;
    end
    if iscell(groups_cfg)
        for i = 1:numel(groups_cfg)
            groups.(sprintf('G%d', i)) = normalize_points(groups_cfg{i});
        end
    end
end

function tf = has_groups(groups_cfg)
    tf = false;
    if isstruct(groups_cfg)
        names = fieldnames(groups_cfg);
        for i = 1:numel(names)
            if ~isempty(normalize_points(groups_cfg.(names{i})))
                tf = true;
                return;
            end
        end
    elseif iscell(groups_cfg)
        tf = any(~cellfun(@isempty, groups_cfg));
    end
end

function groups = legacy_strain_groups()
    groups = struct( ...
        'G05', {{'GB-RSG-G05-001-01', 'GB-RSG-G05-001-02', 'GB-RSG-G05-001-03', 'GB-RSG-G05-001-04', 'GB-RSG-G05-001-05', 'GB-RSG-G05-001-06'}}, ...
        'G06', {{'GB-RSG-G06-001-01', 'GB-RSG-G06-001-02', 'GB-RSG-G06-001-03', 'GB-RSG-G06-001-04', 'GB-RSG-G06-001-05', 'GB-RSG-G06-001-06'}});
end

function pts = get_points(cfg, key, fallback)
    pts = normalize_points(fallback);
    if isfield(cfg, 'points') && isfield(cfg.points, key)
        raw = cfg.points.(key);
        if isempty(raw)
            pts = {};
            return;
        end
        pts = normalize_points(raw);
    end
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
        out = {};
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
                    out{end+1, 1} = item; %#ok<AGROW>
                end
            end
        end
        if ~isempty(out)
            out = unique(out, 'stable');
        end
        pts = out;
    end
end

function style = get_style(cfg, key)
    style = struct();
    if isfield(cfg, 'plot_styles') && isfield(cfg.plot_styles, key) && isstruct(cfg.plot_styles.(key))
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

function y = get_ylim_for_pid(style, pid, default)
    y = default;
    if isempty(pid) || ~isstruct(style) || ~isfield(style, 'ylims')
        return;
    end
    ylims = style.ylims;
    if isa(ylims, 'containers.Map')
        if isKey(ylims, pid)
            y = ylims(pid);
        end
        return;
    end
    if isstruct(ylims)
        if isfield(ylims, pid)
            y = ylims.(pid);
            return;
        end
        if isfield(ylims, 'name') && isfield(ylims, 'ylim')
            for i = 1:numel(ylims)
                if strcmp(ylims(i).name, pid)
                    y = ylims(i).ylim;
                    return;
                end
            end
        end
    elseif iscell(ylims)
        for i = 1:numel(ylims)
            item = ylims{i};
            if isstruct(item) && isfield(item, 'name') && isfield(item, 'ylim') && strcmp(item.name, pid)
                y = item.ylim;
                return;
            end
        end
    end
end

function y = get_group_ylim(style, group_name, default)
    y = default;
    if ~isstruct(style) || ~isfield(style, 'ylims')
        return;
    end
    ylims = style.ylims;
    if isstruct(ylims) && isfield(ylims, group_name)
        y = ylims.(group_name);
        return;
    end
    if isstruct(ylims) && isfield(ylims, 'name') && isfield(ylims, 'ylim')
        for i = 1:numel(ylims)
            if strcmp(to_char(ylims(i).name), group_name)
                y = ylims(i).ylim;
                return;
            end
        end
    elseif iscell(ylims)
        for i = 1:numel(ylims)
            item = ylims{i};
            if isstruct(item) && isfield(item, 'name') && isfield(item, 'ylim') && strcmp(to_char(item.name), group_name)
                y = item.ylim;
                return;
            end
        end
    end
end

function tf = is_valid_ylim(v)
    tf = isnumeric(v) && isvector(v) && numel(v) == 2 && ...
        isfinite(v(1)) && (isfinite(v(2)) || isinf(v(2))) && (v(2) > v(1));
end

function ccell = normalize_colors(c)
    if isnumeric(c)
        ccell = mat2cell(c, ones(size(c, 1), 1), size(c, 2));
    elseif iscell(c)
        ccell = c;
    else
        ccell = {};
    end
end

function out = sanitize_filename(name)
    out = regexprep(char(string(name)), '[\\/:*?"<>|]', '_');
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

function colors = get_group_colors(style, n_series)
    default_colors = [
        0.0000 0.4470 0.7410
        0.8500 0.3250 0.0980
        0.9290 0.6940 0.1250
        0.4940 0.1840 0.5560
        0.4660 0.6740 0.1880
        0.3010 0.7450 0.9330
    ];
    colors = [];
    custom = normalize_colors(get_style_field(style, 'colors_6', default_colors));
    if ~isempty(custom)
        colors = NaN(numel(custom), 3);
        valid = true(numel(custom), 1);
        for i = 1:numel(custom)
            ci = custom{i};
            if isnumeric(ci) && numel(ci) == 3
                colors(i, :) = reshape(ci, 1, 3);
            else
                valid(i) = false;
            end
        end
        colors = colors(valid, :);
    end
    if size(colors, 1) < n_series
        colors = generate_distinct_colors(n_series);
    else
        colors = colors(1:n_series, :);
    end
end

function colors = generate_distinct_colors(n_series)
    if exist('turbo', 'builtin') == 5 || exist('turbo', 'file') == 2
        colors = turbo(n_series);
        return;
    end

    idx = (0:n_series-1)';
    hues = mod(idx * 0.61803398875, 1.0);
    sat = 0.65 + 0.20 * mod(idx * 0.31, 1.0);
    val = 0.78 + 0.18 * mod(idx * 0.47, 1.0);
    colors = hsv2rgb([hues, sat, val]);
end
