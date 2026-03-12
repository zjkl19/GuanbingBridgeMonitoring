function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_tilt_points Plot tilt time series and export stats.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), error('start_date is required'); end
    if nargin < 3 || isempty(end_date), error('end_date is required'); end
    if nargin < 4 || isempty(excel_file), excel_file = 'tilt_stats.xlsx'; end
    if nargin < 6 || isempty(cfg), cfg = load_config(); end

    if nargin < 5 || isempty(subfolder)
        if isfield(cfg, 'subfolders') && isfield(cfg.subfolders, 'tilt')
            subfolder = cfg.subfolders.tilt;
        else
            subfolder = '波形_重采样';
        end
    end

    style = get_style(cfg, 'tilt');

    points_cfg = get_points(cfg, 'tilt', {});
    groups_cfg = get_groups(cfg, 'tilt');
    explicit_points = ~isempty(points_cfg);
    explicit_groups = has_groups(groups_cfg);

    % Preserve legacy behavior when no tilt points or groups are configured.
    if ~explicit_points && ~explicit_groups
        groups_cfg = legacy_tilt_groups();
        explicit_groups = true;
        points_cfg = flatten_groups(groups_cfg);
    end

    per_point_stats = cell(0, 4);
    if explicit_points || is_jiulongjiang(cfg)
        for i = 1:numel(points_cfg)
            pid = points_cfg{i};
            fprintf('Per-point tilt: %s ...\n', pid);
            [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'tilt');
            if isempty(vals)
                warning('Tilt point %s has no data, skip', pid);
                continue;
            end

            per_point_stats(end+1, :) = { ... %#ok<AGROW>
                pid, ...
                round(min(vals), 3), ...
                round(max(vals), 3), ...
                round(mean(vals, 'omitnan'), 3)};

            warn_lines = resolve_warn_lines(style, cfg, pid);
            data_one = struct('pid', pid, 'times', times, 'vals', vals);
            plot_tilt_curve(root_dir, data_one, start_date, end_date, pid, style, warn_lines);
        end
    end

    group_stats = {};
    group_names = {};
    if explicit_groups
        groups_map = normalize_group_map(groups_cfg);
        names = fieldnames(groups_map);
        for i = 1:numel(names)
            group_name = names{i};
            [stats, data_list] = process_group(root_dir, subfolder, groups_map.(group_name), start_date, end_date, cfg);
            if ~isempty(stats)
                group_names{end+1, 1} = group_name; %#ok<AGROW>
                group_stats{end+1, 1} = stats; %#ok<AGROW>
            end
            if has_plot_data(data_list)
                group_warn = resolve_warn_lines(style, cfg, '');
                plot_tilt_curve(root_dir, data_list, start_date, end_date, group_name, style, group_warn);
            end
        end
    end

    if ~isempty(per_point_stats)
        T = cell2table(per_point_stats, 'VariableNames', {'PointID', 'Min', 'Max', 'Mean'});
        writetable(T, excel_file, 'Sheet', 'Tilt');
    end
    for i = 1:numel(group_stats)
        T = cell2table(group_stats{i}, 'VariableNames', {'PointID', 'Min', 'Max', 'Mean'});
        writetable(T, excel_file, 'Sheet', make_sheet_name(group_names{i}));
    end

    fprintf('Tilt stats saved to %s\n', excel_file);
end

function [stats, data_list] = process_group(root_dir, subfolder, pids, start_date, end_date, cfg)
    stats = cell(0, 4);
    data_list = struct('pid', {}, 'times', {}, 'vals', {});
    for i = 1:numel(pids)
        pid = pids{i};
        fprintf('Extracting %s ...\n', pid);
        [times, vals] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'tilt');
        if isempty(vals)
            warning('Tilt point %s has no data, skip', pid);
            continue;
        end

        stats(end+1, :) = { ... %#ok<AGROW>
            pid, ...
            round(min(vals), 3), ...
            round(max(vals), 3), ...
            round(mean(vals, 'omitnan'), 3)};
        data_list(end+1, 1) = struct('pid', pid, 'times', times, 'vals', vals); %#ok<AGROW>
    end
end

function plot_tilt_curve(root_dir, data_list, start_date, end_date, suffix, style, warn_lines)
    if isempty(data_list) || ~has_plot_data(data_list)
        return;
    end

    fig = figure('Position', [100 100 1000 469]);
    hold on;

    dt0 = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    dt1 = datetime(end_date, 'InputFormat', 'yyyy-MM-dd');
    if dt1 <= dt0
        dt1 = dt0 + days(1);
    end

    colors_3 = normalize_colors(get_style_field(style, 'colors_3', [0 0 0; 1 0 0; 0 0 1]));
    h_lines = gobjects(numel(data_list), 1);
    for i = 1:numel(data_list)
        d = data_list(i);
        if isempty(d.vals)
            continue;
        end
        if numel(data_list) == 3 && i <= numel(colors_3)
            h_lines(i) = plot(d.times, d.vals, 'LineWidth', 1.0, 'Color', colors_3{i});
        else
            h_lines(i) = plot(d.times, d.vals, 'LineWidth', 1.0);
        end
    end

    valid = isgraphics(h_lines);
    if any(valid)
        labels = {data_list(valid).pid};
        lg = legend(h_lines(valid), labels, 'Location', 'northeast', 'Box', 'off');
        lg.AutoUpdate = 'off';
    end

    ticks = dt0 + (dt1 - dt0) * (0:4) / 4;
    ax = gca;
    ax.XLim = [dt0 dt1];
    ax.XTick = ticks;
    xtickformat('yyyy-MM-dd');

    xlabel('时间');
    ylabel(get_style_field(style, 'ylabel', '倾角 (°)'));
    title(sprintf('%s %s', get_style_field(style, 'title_prefix', '倾角时程'), char(string(suffix))));

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

    ylim_auto = get_style_field(style, 'ylim_auto', false);
    if (islogical(ylim_auto) && ylim_auto) || (isnumeric(ylim_auto) && ylim_auto ~= 0)
        ylim auto;
    else
        ylim_val = get_style_field(style, 'ylim', []);
        pid = '';
        if numel(data_list) == 1 && isfield(data_list, 'pid')
            pid = data_list(1).pid;
        end
        ylim_override = get_ylim_for_pid(style, pid, ylim_val);
        if is_valid_ylim(ylim_override)
            ylim(ylim_override);
        else
            ylim auto;
        end
    end

    grid on;
    grid minor;

    ts = datestr(now, 'yyyymmdd_HHMMSS');
    out_dir = char(string(get_style_field(style, 'output_dir', '时程曲线_倾角')));
    out_dir = fullfile(root_dir, out_dir);
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    fname = sanitize_filename(sprintf('Tilt_%s_%s_%s', char(string(suffix)), datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd')));
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
    if ~isfield(cfg, 'per_point') || ~isfield(cfg.per_point, 'tilt')
        return;
    end
    safe_id = strrep(pid, '-', '_');
    if ~isfield(cfg.per_point.tilt, safe_id)
        return;
    end
    pt = cfg.per_point.tilt.(safe_id);
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

function groups = legacy_tilt_groups()
    groups = struct( ...
        'X', {{'GB-DIS-P04-001-01-X', 'GB-DIS-P05-001-01-X', 'GB-DIS-P06-001-01-X'}}, ...
        'Y', {{'GB-DIS-P04-001-01-Y', 'GB-DIS-P05-001-01-Y', 'GB-DIS-P06-001-01-Y'}});
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

function pts = flatten_groups(groups_cfg)
    groups = normalize_group_map(groups_cfg);
    names = fieldnames(groups);
    pts = {};
    for i = 1:numel(names)
        pts = [pts; groups.(names{i})(:)]; %#ok<AGROW>
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

function tf = is_jiulongjiang(cfg)
    tf = isfield(cfg, 'vendor') && strcmpi(cfg.vendor, 'jiulongjiang');
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
        ccell = mat2cell(c, ones(size(c, 1), 1), size(c, 2));
    elseif iscell(c)
        ccell = c;
    else
        ccell = {};
    end
end

function tf = has_plot_data(data_list)
    tf = false;
    for i = 1:numel(data_list)
        if isfield(data_list(i), 'vals') && ~isempty(data_list(i).vals)
            tf = true;
            return;
        end
    end
end

function sheet = make_sheet_name(name)
    sheet = regexprep(char(string(name)), '[:\\/?*\[\]]', '_');
    if strlength(string(sheet)) > 31
        sheet = extractBefore(string(sheet), 32);
        sheet = char(sheet);
    end
    if ~startsWith(sheet, 'Tilt_', 'IgnoreCase', true)
        sheet = ['Tilt_' sheet];
    end
    if strlength(string(sheet)) > 31
        sheet = char(extractBefore(string(sheet), 32));
    end
end

function out = sanitize_filename(name)
    out = regexprep(char(string(name)), '[\\/:*?"<>|]', '_');
end
