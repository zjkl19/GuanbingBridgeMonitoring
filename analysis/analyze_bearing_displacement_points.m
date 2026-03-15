function analyze_bearing_displacement_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_bearing_displacement_points
% Plot bearing displacement time series (raw + filtered) and export stats.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), error('start_date is required'); end
    if nargin < 3 || isempty(end_date), error('end_date is required'); end
    if nargin < 4 || isempty(excel_file), excel_file = 'bearing_displacement_stats.xlsx'; end
    if nargin < 6 || isempty(cfg), cfg = load_config(); end

    if nargin < 5 || isempty(subfolder)
        subfolder = '';
        if isfield(cfg, 'subfolders')
            if isfield(cfg.subfolders, 'bearing_displacement')
                subfolder = cfg.subfolders.bearing_displacement;
            elseif isfield(cfg.subfolders, 'deflection')
                subfolder = cfg.subfolders.deflection;
            end
        end
    end

    style = get_style(cfg, 'bearing_displacement');
    if isempty(fieldnames(style))
        style = get_style(cfg, 'deflection');
    end

    groups = get_groups(cfg, 'bearing_displacement', {});
    points = get_points(cfg, 'bearing_displacement', flatten_groups(groups));
    points = unique(points, 'stable');

    stats = cell(0, 7);
    row = 0;

    for i = 1:numel(points)
        pid = points{i};
        [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'bearing_displacement');
        if isempty(vals)
            warning('Bearing displacement point %s has no data, skip', pid);
            continue;
        end

        vals_f = moving_median_10min(times, vals);
        vals_f = apply_threshold_rules(vals_f, times, ...
            resolve_post_filter_thresholds(cfg, 'bearing_displacement', pid));

        row = row + 1;
        stats(row, :) = {
            pid, ...
            round(min(vals), 3), ...
            round(max(vals), 3), ...
            round(mean(vals, 'omitnan'), 3), ...
            round(min(vals_f), 3), ...
            round(max(vals_f), 3), ...
            round(mean(vals_f, 'omitnan'), 3)
        };

        warn_lines = resolve_warn_lines(style, cfg, pid);
        plot_bearing_curve({times}, {vals}, {pid}, root_dir, start_date, end_date, pid, style, 'Orig', warn_lines);
        plot_bearing_curve({times}, {vals_f}, {pid}, root_dir, start_date, end_date, pid, style, 'Filt', warn_lines);
    end

    if ~isempty(groups)
        for g = 1:numel(groups)
            pid_list = groups{g};
            if ~iscell(pid_list) || isempty(pid_list)
                continue;
            end

            orig_times = {};
            orig_vals = {};
            filt_times = {};
            filt_vals = {};
            labels = {};
            for i = 1:numel(pid_list)
                pid = pid_list{i};
                [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'bearing_displacement');
                if isempty(vals)
                    continue;
                end
                vals_f = moving_median_10min(times, vals);
                vals_f = apply_threshold_rules(vals_f, times, ...
                    resolve_post_filter_thresholds(cfg, 'bearing_displacement', pid));
                orig_times{end+1,1} = times; %#ok<AGROW>
                orig_vals{end+1,1} = vals; %#ok<AGROW>
                filt_times{end+1,1} = times; %#ok<AGROW>
                filt_vals{end+1,1} = vals_f; %#ok<AGROW>
                labels{end+1,1} = pid; %#ok<AGROW>
            end
            if isempty(labels)
                continue;
            end
            group_warn = resolve_warn_lines(style, cfg, '');
            plot_bearing_curve(orig_times, orig_vals, labels, root_dir, start_date, end_date, sprintf('G%d', g), style, 'Orig', group_warn);
            plot_bearing_curve(filt_times, filt_vals, labels, root_dir, start_date, end_date, sprintf('G%d', g), style, 'Filt', group_warn);
        end
    end

    T = cell2table(stats, 'VariableNames', ...
        {'PointID', 'OrigMin_mm', 'OrigMax_mm', 'OrigMean_mm', 'FiltMin_mm', 'FiltMax_mm', 'FiltMean_mm'});
    writetable(T, excel_file);
    fprintf('Bearing displacement stats saved to %s\n', excel_file);
end

function vals_f = moving_median_10min(times, vals)
    vals_f = vals;
    if isempty(vals) || isempty(times)
        return;
    end
    if numel(times) < 2
        vals_f = movmedian(vals, 201, 'omitnan');
        return;
    end
    dt = seconds(diff(times));
    fs = 1 / median(dt, 'omitnan');
    if ~isfinite(fs) || fs <= 0
        vals_f = movmedian(vals, 201, 'omitnan');
        return;
    end
    win_len = max(3, round(10 * 60 * fs));
    if mod(win_len, 2) == 0
        win_len = win_len + 1;
    end
    vals_f = movmedian(vals, win_len, 'omitnan');
end

function plot_bearing_curve(times_list, vals_list, pid_list, root_dir, start_date, end_date, name_tag, style, suffix, warn_lines)
    valid = ~cellfun(@isempty, vals_list);
    if ~any(valid)
        return;
    end

    fig = figure('Position', [100 100 1000 469]);
    hold on;
    N = numel(pid_list);

    colors_2 = normalize_colors(get_style_field(style, 'colors_2', [0 0 1; 0 0.7 0]));
    colors_3 = normalize_colors(get_style_field(style, 'colors_3', [0.5 0 0.7; 0 0 1; 0 0.7 0]));

    h = gobjects(N,1);
    for i = 1:N
        if isempty(vals_list{i})
            continue;
        end
        if N == 2 && i <= numel(colors_2)
            c = colors_2{i};
        elseif N == 3 && i <= numel(colors_3)
            c = colors_3{i};
        else
            cmap = lines(N);
            c = cmap(i,:);
        end
        h(i) = plot(times_list{i}, vals_list{i}, 'LineWidth', 1.0, 'Color', c);
    end

    good_lines = h(isgraphics(h));
    good_labels = pid_list(valid);
    if ~isempty(good_lines)
        lg = legend(good_lines, good_labels, 'Location', 'northeast', 'Box', 'off');
        lg.AutoUpdate = 'off';
    end

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
    ylabel(get_style_field(style, 'ylabel', 'Bearing displacement (mm)'));
    title(sprintf('%s %s %s', get_style_field(style, 'title_prefix', 'Bearing displacement'), char(string(name_tag)), suffix));

    warn_lines = normalize_warn_lines(warn_lines);
    for k = 1:numel(warn_lines)
        wl = warn_lines{k};
        if ~isstruct(wl) || ~isfield(wl, 'y') || ~isnumeric(wl.y) || ~isfinite(wl.y)
            continue;
        end
        yl = yline(wl.y, '--', get_warn_label(wl), 'LabelHorizontalAlignment', 'left');
        if isfield(wl, 'color') && isnumeric(wl.color) && numel(wl.color) == 3
            yl.Color = wl.color;
        end
    end

    ylim_auto = get_style_field(style, 'ylim_auto', false);
    if (islogical(ylim_auto) && ylim_auto) || (isnumeric(ylim_auto) && ylim_auto ~= 0)
        ylim auto;
    else
        ylim_default = get_style_field(style, 'ylim', []);
        pid = '';
        if numel(pid_list) == 1
            pid = pid_list{1};
        end
        ylim_override = get_ylim_for_pid(style, pid, ylim_default);
        if is_valid_ylim(ylim_override)
            ylim(ylim_override);
        else
            ylim auto;
        end
    end

    grid on;
    grid minor;

    out_dir = get_style_field(style, 'output_dir', '时程曲线_支座位移');
    out_dir = fullfile(root_dir, char(string(out_dir)));
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    ts = datestr(now, 'yyyymmdd_HHMMSS');
    fname = sanitize_filename(sprintf('BearingDisp_%s_%s_%s_%s', char(string(name_tag)), datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'), suffix));
    saveas(fig, fullfile(out_dir, [fname '_' ts '.jpg']));
    saveas(fig, fullfile(out_dir, [fname '_' ts '.emf']));
    savefig(fig, fullfile(out_dir, [fname '_' ts '.fig']), 'compact');
    close(fig);
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
    if ~isfield(cfg, 'per_point') || ~isfield(cfg.per_point, 'bearing_displacement')
        return;
    end
    safe_id = strrep(pid, '-', '_');
    if ~isfield(cfg.per_point.bearing_displacement, safe_id)
        return;
    end
    pt = cfg.per_point.bearing_displacement.(safe_id);
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
                ccell{end+1,1} = item; %#ok<AGROW>
            elseif isnumeric(item) && isscalar(item)
                ccell{end+1,1} = struct('y', item); %#ok<AGROW>
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

function groups = get_groups(cfg, key, fallback)
    groups = fallback;
    if isfield(cfg, 'groups') && isfield(cfg.groups, key)
        g = cfg.groups.(key);
        if iscell(g)
            groups = g;
        elseif isstruct(g)
            names = fieldnames(g);
            tmp = cell(numel(names), 1);
            for i = 1:numel(names)
                tmp{i} = normalize_points(g.(names{i}));
            end
            groups = tmp;
        end
    end
end

function pts = flatten_groups(groups)
    pts = {};
    if ~iscell(groups)
        return;
    end
    for i = 1:numel(groups)
        g = groups{i};
        if iscell(g)
            pts = [pts; g(:)]; %#ok<AGROW>
        end
    end
    pts = normalize_points(pts);
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
                    out{end+1,1} = item; %#ok<AGROW>
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

function tf = is_valid_ylim(v)
    tf = isnumeric(v) && isvector(v) && numel(v) == 2 && ...
        isfinite(v(1)) && (isfinite(v(2)) || isinf(v(2))) && (v(2) > v(1));
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

function out = sanitize_filename(name)
    out = regexprep(char(string(name)), '[\\/:*?"<>|]', '_');
end
