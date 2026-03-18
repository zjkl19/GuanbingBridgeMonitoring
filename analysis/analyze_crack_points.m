function analyze_crack_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_crack_points Crack width analysis with optional crack-temperature branch.

    if nargin < 1 || isempty(root_dir),  root_dir = pwd; end
    if nargin < 2 || isempty(start_date), error('start_date is required'); end
    if nargin < 3 || isempty(end_date),   error('end_date is required'); end
    if nargin < 4 || isempty(excel_file), excel_file = 'crack_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
    if nargin < 5 || isempty(subfolder)
        cfg_tmp = load_config();
        if isfield(cfg_tmp,'subfolders') && isfield(cfg_tmp.subfolders,'crack')
            subfolder = cfg_tmp.subfolders.crack;
        else
            subfolder = '???';
        end
    end
    if nargin < 6 || isempty(cfg), cfg = load_config(); end

    style = get_style(cfg, 'crack');
    opt = get_crack_options(style);

    groups_cfg = get_groups(cfg, 'crack');
    if ~opt.group_plot
        groups_cfg = struct();
    elseif ~has_group_config(groups_cfg)
        if opt.skip_group_if_missing
            groups_cfg = struct();
        else
            groups_cfg = default_crack_groups();
        end
    end

    point_list = get_points(cfg, 'crack', {});
    if isempty(point_list)
        point_list = unique(flatten_group_points(groups_cfg), 'stable');
    end

    cache = containers.Map('KeyType','char','ValueType','any');
    stats = cell(numel(point_list), 7);
    row = 0;

    for i = 1:numel(point_list)
        pid = point_list{i};
        S = fetch_point_series(cache, root_dir, subfolder, start_date, end_date, cfg, pid, opt.temp_enabled);

        row = row + 1;
        stats{row,1} = pid;
        stats{row,2} = safe_stat(S.crack_vals, @min);
        stats{row,3} = safe_stat(S.crack_vals, @max);
        stats{row,4} = safe_stat(S.crack_vals, @mean);
        if opt.temp_enabled
            stats{row,5} = safe_stat(S.temp_vals, @min);
            stats{row,6} = safe_stat(S.temp_vals, @max);
            stats{row,7} = safe_stat(S.temp_vals, @mean);
        else
            stats{row,5} = NaN;
            stats{row,6} = NaN;
            stats{row,7} = NaN;
        end
    end

    if row == 0
        stats = cell(0,7);
    else
        stats = stats(1:row,:);
    end

    T = cell2table(stats, 'VariableNames', {'PointID','CrkMin','CrkMax','CrkMean','TmpMin','TmpMax','TmpMean'});
    writetable(T, excel_file);

    crack_ylabel = get_style_field(style, 'ylabel_crack', 'Crack Width (mm)');
    crack_title  = get_style_field(style, 'title_prefix_crack', 'Crack Width');
    temp_ylabel  = get_style_field(style, 'ylabel_temp', 'Crack Temp (degC)');
    temp_title   = get_style_field(style, 'title_prefix_temp', 'Crack Temp');

    crack_dir = fullfile(root_dir, sanitize_filename(get_style_field(style, 'output_dir_crack', '时程曲线_裂缝宽度')));
    temp_dir  = fullfile(root_dir, sanitize_filename(get_style_field(style, 'output_dir_temp', '时程曲线_裂缝温度')));

    % Per-point plots
    if opt.per_point_plot
        for i = 1:numel(point_list)
            pid = point_list{i};
            S = fetch_point_series(cache, root_dir, subfolder, start_date, end_date, cfg, pid, opt.temp_enabled);
            if ~isempty(S.crack_times)
                plot_single_curve(S.crack_times, S.crack_vals, pid, crack_ylabel, crack_title, crack_dir, start_date, end_date, ...
                    get_named_ylim(style, pid, get_default_ylim(style)));
            end
            if opt.temp_enabled && ~isempty(S.temp_times)
                plot_single_curve(S.temp_times, S.temp_vals, pid, temp_ylabel, temp_title, temp_dir, start_date, end_date, []);
            end
        end
    end

    % Group plots
    if opt.group_plot && has_group_config(groups_cfg)
        grp_names = fieldnames(groups_cfg);
        for gi = 1:numel(grp_names)
            grp_name = grp_names{gi};
            pid_list = normalize_points(groups_cfg.(grp_name));
            if isempty(pid_list)
                continue;
            end

            crack_times = {};
            crack_vals = {};
            crack_labels = {};
            temp_times = {};
            temp_vals = {};
            temp_labels = {};

            for i = 1:numel(pid_list)
                pid = pid_list{i};
                S = fetch_point_series(cache, root_dir, subfolder, start_date, end_date, cfg, pid, opt.temp_enabled);
                if ~isempty(S.crack_times)
                    crack_times{end+1,1} = S.crack_times; %#ok<AGROW>
                    crack_vals{end+1,1} = S.crack_vals; %#ok<AGROW>
                    crack_labels{end+1,1} = pid; %#ok<AGROW>
                end
                if opt.temp_enabled && ~isempty(S.temp_times)
                    temp_times{end+1,1} = S.temp_times; %#ok<AGROW>
                    temp_vals{end+1,1} = S.temp_vals; %#ok<AGROW>
                    temp_labels{end+1,1} = pid; %#ok<AGROW>
                end
            end

            if ~isempty(crack_labels)
                plot_group_curve(crack_times, crack_vals, crack_labels, crack_ylabel, crack_title, crack_dir, grp_name, start_date, end_date, ...
                    get_named_ylim(style, grp_name, get_default_ylim(style)), style);
            elseif ~opt.skip_group_if_missing
                warning('Crack group %s has no valid data.', grp_name);
            end

            if opt.temp_enabled
                if ~isempty(temp_labels)
                    plot_group_curve(temp_times, temp_vals, temp_labels, temp_ylabel, temp_title, temp_dir, grp_name, start_date, end_date, [], style);
                elseif ~opt.skip_group_if_missing
                    warning('Crack temp group %s has no valid data.', grp_name);
                end
            end
        end
    end

    fprintf('Crack stats saved to %s\n', excel_file);
end

function S = fetch_point_series(cache, root_dir, subfolder, start_date, end_date, cfg, pid, temp_enabled)
    if isKey(cache, pid)
        S = cache(pid);
        return;
    end

    [tc, vc] = load_timeseries_range(root_dir, subfolder, pid, start_date, end_date, cfg, 'crack');
    tt = [];
    vt = [];
    if temp_enabled
        [tt, vt] = load_timeseries_range(root_dir, subfolder, [pid '-t'], start_date, end_date, cfg, 'crack_temp');
    end

    S = struct('crack_times', tc, 'crack_vals', vc, 'temp_times', tt, 'temp_vals', vt);
    cache(pid) = S;
end

function plot_single_curve(t, v, pid, ylabel_str, title_prefix, out_dir, start_date, end_date, ylim_range)
    plot_group_curve({t}, {v}, {pid}, ylabel_str, title_prefix, out_dir, pid, start_date, end_date, ylim_range, struct());
end

function plot_group_curve(times_cell, vals_cell, labels, ylabel_str, title_prefix, out_dir, group_name, start_date, end_date, ylim_range, style)
    if isempty(labels)
        return;
    end
    if ~exist(out_dir,'dir')
        mkdir(out_dir);
    end

    fig = figure('Position',[100 100 1000 469]);
    hold on;

    n = numel(labels);
    colors = normalize_colors(get_style_field(style, 'colors_4', { ...
        [0 0 0], ...
        [1 0 0], ...
        [0 0 1], ...
        [0 0.7 0] ...
    }));

    h = gobjects(n,1);
    for i = 1:n
        if i <= numel(colors)
            h(i) = plot(times_cell{i}, vals_cell{i}, 'LineWidth', 1.0, 'Color', colors{i});
        else
            h(i) = plot(times_cell{i}, vals_cell{i}, 'LineWidth', 1.0);
        end
    end

    good = h(isgraphics(h));
    if ~isempty(good)
        legend(good, labels, 'Location','northeast', 'Box','off');
    end

    xlabel('Time');
    ylabel(ylabel_str);
    title(sprintf('%s %s', title_prefix, group_name));
    grid on;
    grid minor;

    dt0 = datetime(start_date, 'InputFormat', 'yyyy-MM-dd');
    dt1 = datetime(end_date,   'InputFormat', 'yyyy-MM-dd');
    if dt1 <= dt0
        dt1 = dt0 + days(1);
    end
    ticks = dt0 + (dt1 - dt0) * (0:4)/4;
    ax = gca;
    ax.XLim = [dt0 dt1];
    ax.XTick = ticks;
    xtickformat('yyyy-MM-dd');

    if is_valid_ylim(ylim_range)
        ylim(ylim_range);
    end

    ts = datestr(now, 'yyyymmdd_HHMMSS');
    base = sanitize_filename(sprintf('%s_%s_%s_%s', title_prefix, group_name, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd')));
    save_plot_bundle(fig, out_dir, [base '_' ts]);
end

function tf = is_valid_ylim(v)
    tf = isnumeric(v) && numel(v) == 2 && isvector(v) && ...
        isfinite(v(1)) && (isfinite(v(2)) || isinf(v(2))) && (v(2) > v(1));
end

function out = sanitize_filename(name)
    out = regexprep(char(string(name)), '[\\/:*?"<>|]', '_');
end

function v = safe_stat(x, fcn)
    if isempty(x)
        v = NaN;
        return;
    end
    x = x(isfinite(x));
    if isempty(x)
        v = NaN;
        return;
    end
    v = round(fcn(x), 3);
end

function g = get_groups(cfg, key)
    g = [];
    if isfield(cfg,'groups') && isfield(cfg.groups, key)
        g = cfg.groups.(key);
    end
end

function tf = has_group_config(groups_cfg)
    tf = isstruct(groups_cfg) && ~isempty(fieldnames(groups_cfg));
end

function pts = flatten_group_points(groups_cfg)
    pts = {};
    if ~has_group_config(groups_cfg)
        return;
    end
    gn = fieldnames(groups_cfg);
    for i = 1:numel(gn)
        pts = [pts; normalize_points(groups_cfg.(gn{i}))]; %#ok<AGROW>
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
        tmp = {};
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
                    tmp{end+1,1} = item; %#ok<AGROW>
                end
            end
        end
        pts = tmp;
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

function ylim_val = get_named_ylim(style, grp_name, default_ylim)
    ylim_val = default_ylim;
    if ~isstruct(style) || ~isfield(style,'ylims') || isempty(style.ylims) || isempty(grp_name)
        return;
    end
    ylims = style.ylims;
    safe_name = strrep(grp_name, '-', '_');
    if isstruct(ylims)
        if isfield(ylims, grp_name)
            ylim_val = ylims.(grp_name);
            return;
        end
        if isfield(ylims, safe_name)
            ylim_val = ylims.(safe_name);
            return;
        end
        if isfield(ylims, 'name') && isfield(ylims, 'ylim')
            for i = 1:numel(ylims)
                if strcmp(to_char(ylims(i).name), grp_name)
                    ylim_val = ylims(i).ylim;
                    return;
                end
            end
        end
    elseif iscell(ylims)
        for i = 1:numel(ylims)
            item = ylims{i};
            if isstruct(item) && isfield(item,'name') && isfield(item,'ylim') && strcmp(to_char(item.name), grp_name)
                ylim_val = item.ylim;
                return;
            end
        end
    end
end

function ylim_val = get_default_ylim(style)
    ylim_val = [];
    if ~isstruct(style)
        return;
    end
    ylim_auto = false;
    if isfield(style,'ylim_auto') && ~isempty(style.ylim_auto)
        ylim_auto = logical(style.ylim_auto);
    end
    if ~ylim_auto && isfield(style,'ylim')
        ylim_val = style.ylim;
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

function opt = get_crack_options(style)
    opt = struct( ...
        'per_point_plot', false, ...
        'group_plot', true, ...
        'temp_enabled', true, ...
        'skip_group_if_missing', true ...
    );

    if ~isstruct(style)
        return;
    end
    if isfield(style, 'per_point_plot') && ~isempty(style.per_point_plot)
        opt.per_point_plot = logical(style.per_point_plot);
    end
    if isfield(style, 'group_plot') && ~isempty(style.group_plot)
        opt.group_plot = logical(style.group_plot);
    end
    if isfield(style, 'temp_enabled') && ~isempty(style.temp_enabled)
        opt.temp_enabled = logical(style.temp_enabled);
    end
    if isfield(style, 'skip_group_if_missing') && ~isempty(style.skip_group_if_missing)
        opt.skip_group_if_missing = logical(style.skip_group_if_missing);
    end
end

function g = default_crack_groups()
    g = struct( ...
        'G05', {{'GB-CRK-G05-001-01','GB-CRK-G05-001-02','GB-CRK-G05-001-03','GB-CRK-G05-001-04'}}, ...
        'G06', {{'GB-CRK-G06-001-01','GB-CRK-G06-001-02','GB-CRK-G06-001-03','GB-CRK-G06-001-04'}} ...
    );
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
