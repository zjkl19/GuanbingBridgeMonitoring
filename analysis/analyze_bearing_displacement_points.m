function analyze_bearing_displacement_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_bearing_displacement_points
% Plot bearing displacement time series (raw + filtered) and export stats.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), error('start_date is required'); end
    if nargin < 3 || isempty(end_date), error('end_date is required'); end
    if nargin < 4 || isempty(excel_file), excel_file = 'bearing_displacement_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
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

        vals_f = bms.analyzer.StructuralSeriesService.movingMedian10Min(times, vals);
        vals_f = apply_threshold_rules(vals_f, times, ...
            resolve_post_filter_thresholds(cfg, 'bearing_displacement', pid));

        row = row + 1;
        stats(row, :) = bms.analyzer.StructuralSeriesService.filteredStatsRow( ...
            pid, vals, vals_f, 3);

        warn_lines = resolve_warn_lines(style, cfg, pid);
        plot_bearing_curve({times}, {vals}, {pid}, root_dir, start_date, end_date, pid, style, 'Orig', warn_lines, cfg);
        plot_bearing_curve({times}, {vals_f}, {pid}, root_dir, start_date, end_date, pid, style, 'Filt', warn_lines, cfg);
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
                vals_f = bms.analyzer.StructuralSeriesService.movingMedian10Min(times, vals);
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
            plot_bearing_curve(orig_times, orig_vals, labels, root_dir, start_date, end_date, sprintf('G%d', g), style, 'Orig', group_warn, cfg);
            plot_bearing_curve(filt_times, filt_vals, labels, root_dir, start_date, end_date, sprintf('G%d', g), style, 'Filt', group_warn, cfg);
        end
    end

    T = bms.analyzer.StructuralSeriesService.filteredStatsTable(stats);
    bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'bearing_displacement');
    fprintf('Bearing displacement stats saved to %s\n', excel_file);
end

function plot_bearing_curve(times_list, vals_list, pid_list, root_dir, start_date, end_date, name_tag, style, suffix, warn_lines, cfg)
    if nargin < 11
        cfg = struct();
    end
    valid = ~cellfun(@isempty, vals_list);
    if ~any(valid)
        return;
    end

    N = numel(pid_list);
    [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(start_date, end_date);
    pid = '';
    if N == 1
        pid = pid_list{1};
    end

    opts = struct();
    opts.style = style;
    opts.ylabel = get_style_field(style, 'ylabel', 'Bearing displacement (mm)');
    opts.titleText = sprintf('%s %s %s', get_style_field(style, 'title_prefix', 'Bearing displacement'), char(string(name_tag)), suffix);
    opts.outputDir = get_style_field(style, 'output_dir', '时程曲线_支座位移');
    opts.baseName = sprintf('BearingDisp_%s_%s_%s_%s_%s', char(string(name_tag)), datestr(dt0,'yyyymmdd'), datestr(dt1,'yyyymmdd'), suffix, datestr(now, 'yyyymmdd_HHMMSS'));
    opts.warnLines = warn_lines;
    opts.ylimRange = bms.analyzer.StructuralTimeSeriesPlotService.resolveStyleYLim(style, pid);
    if N == 2
        opts.colorField = 'colors_2';
        opts.defaultColors = [0 0 1; 0 0.7 0];
    elseif N == 3
        opts.colorField = 'colors_3';
        opts.defaultColors = [0.5 0 0.7; 0 0 1; 0 0.7 0];
    end

    bms.analyzer.StructuralTimeSeriesPlotService.plotCells( ...
        root_dir, times_list, vals_list, pid_list, start_date, end_date, opts, cfg);
end

function warn_lines = resolve_warn_lines(style, cfg, pid)
    warn_lines = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines(style, cfg, 'bearing_displacement', pid);
end

function pts = get_points(cfg, key, fallback)
    pts = bms.data.PointResolver.fromConfig(cfg, key, fallback);
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
    pts = bms.data.PointResolver.flattenGroups(groups);
end

function pts = normalize_points(v)
    pts = bms.data.PointResolver.normalize(v);
end

function style = get_style(cfg, key)
    style = bms.config.ConfigReader.getPlotStyle(cfg, key);
end

function val = get_style_field(style, field, default)
    val = bms.config.ConfigReader.getField(style, field, default);
end
