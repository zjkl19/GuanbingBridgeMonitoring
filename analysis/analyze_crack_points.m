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
        crack_stats = bms.analyzer.StructuralSeriesService.statsTriple(S.crack_vals, 3);

        row = row + 1;
        stats{row,1} = pid;
        stats{row,2} = crack_stats(1);
        stats{row,3} = crack_stats(2);
        stats{row,4} = crack_stats(3);
        if opt.temp_enabled
            temp_stats = bms.analyzer.StructuralSeriesService.statsTriple(S.temp_vals, 3);
            stats{row,5} = temp_stats(1);
            stats{row,6} = temp_stats(2);
            stats{row,7} = temp_stats(3);
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

    T = bms.analyzer.StructuralSeriesService.crackStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'crack');

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
                    get_named_ylim(style, pid, get_default_ylim(style)), cfg);
            end
            if opt.temp_enabled && ~isempty(S.temp_times)
                plot_single_curve(S.temp_times, S.temp_vals, pid, temp_ylabel, temp_title, temp_dir, start_date, end_date, [], cfg);
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
                    get_named_ylim(style, grp_name, get_default_ylim(style)), style, cfg);
            elseif ~opt.skip_group_if_missing
                warning('Crack group %s has no valid data.', grp_name);
            end

            if opt.temp_enabled
                if ~isempty(temp_labels)
                    plot_group_curve(temp_times, temp_vals, temp_labels, temp_ylabel, temp_title, temp_dir, grp_name, start_date, end_date, [], style, cfg);
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

function plot_single_curve(t, v, pid, ylabel_str, title_prefix, out_dir, start_date, end_date, ylim_range, cfg)
    if nargin < 10
        cfg = struct();
    end
    plot_group_curve({t}, {v}, {pid}, ylabel_str, title_prefix, out_dir, pid, start_date, end_date, ylim_range, struct(), cfg);
end

function plot_group_curve(times_cell, vals_cell, labels, ylabel_str, title_prefix, out_dir, group_name, start_date, end_date, ylim_range, style, cfg)
    if nargin < 12
        cfg = struct();
    end
    if isempty(labels)
        return;
    end

    [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(start_date, end_date);
    opts = struct();
    opts.style = style;
    opts.outputDir = out_dir;
    opts.baseName = sprintf('%s_%s_%s_%s_%s', title_prefix, group_name, datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS'));
    opts.titleText = sprintf('%s %s', title_prefix, group_name);
    opts.ylabel = ylabel_str;
    opts.ylimRange = ylim_range;
    opts.colorField = 'colors_4';
    opts.defaultColors = [0 0 0; 1 0 0; 0 0 1; 0 0.7 0];
    bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
        '', times_cell, vals_cell, labels, start_date, end_date, opts, cfg);
end

function out = sanitize_filename(name)
    out = bms.analyzer.StructuralPlotConfigService.sanitizeFilename(name);
end

function g = get_groups(cfg, key)
    g = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, key, []);
end

function tf = has_group_config(groups_cfg)
    tf = bms.analyzer.StructuralPlotConfigService.hasGroupConfig(groups_cfg);
end

function pts = flatten_group_points(groups_cfg)
    pts = bms.analyzer.StructuralPlotConfigService.flattenGroupPoints(groups_cfg);
end

function pts = get_points(cfg, key, fallback)
    pts = bms.analyzer.StructuralPlotConfigService.getPoints(cfg, key, fallback);
end

function pts = normalize_points(v)
    pts = bms.analyzer.StructuralPlotConfigService.normalizePoints(v);
end

function style = get_style(cfg, key)
    style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, key);
end

function val = get_style_field(style, field, default)
    val = bms.analyzer.StructuralPlotConfigService.getStyleField(style, field, default);
end

function ylim_val = get_named_ylim(style, grp_name, default_ylim)
    ylim_val = bms.analyzer.StructuralPlotConfigService.resolveNamedYLim(style, grp_name, default_ylim);
end

function ylim_val = get_default_ylim(style)
    ylim_val = bms.analyzer.StructuralPlotConfigService.defaultYLim(style);
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
    txt = bms.analyzer.StructuralPlotConfigService.toChar(v);
end
