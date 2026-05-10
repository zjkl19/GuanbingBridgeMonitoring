function analyze_tilt_points(root_dir, start_date, end_date, excel_file, subfolder, cfg)
% analyze_tilt_points Plot tilt time series and export stats.

    if nargin < 1 || isempty(root_dir), root_dir = pwd; end
    if nargin < 2 || isempty(start_date), error('start_date is required'); end
    if nargin < 3 || isempty(end_date), error('end_date is required'); end
    if nargin < 4 || isempty(excel_file), excel_file = 'tilt_stats.xlsx'; end
    excel_file = resolve_data_output_path(root_dir, excel_file, 'stats');
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
            data_one = bms.analyzer.StructuralSeriesService.loadPoint( ...
                root_dir, subfolder, pid, start_date, end_date, cfg, 'tilt');
            if isempty(data_one.vals)
                warning('Tilt point %s has no data, skip', pid);
                continue;
            end

            per_point_stats(end+1, :) = bms.analyzer.StructuralSeriesService.basicStatsRow( ...
                pid, data_one.vals, 3); %#ok<AGROW>

            warn_lines = resolve_warn_lines(style, cfg, pid);
            plot_tilt_curve(root_dir, data_one, start_date, end_date, pid, style, warn_lines, cfg);
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
                plot_tilt_curve(root_dir, data_list, start_date, end_date, group_name, style, group_warn, cfg);
            end
        end
    end

    if ~isempty(per_point_stats)
        T = bms.analyzer.StructuralSeriesService.basicStatsTable(per_point_stats);
        bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'tilt', 'Sheet', 'Tilt');
    end
    for i = 1:numel(group_stats)
        T = bms.analyzer.StructuralSeriesService.basicStatsTable(group_stats{i});
        bms.io.StatsWriter.writeModuleTableChecked(T, excel_file, 'tilt', 'Sheet', make_sheet_name(group_names{i}));
    end

    fprintf('Tilt stats saved to %s\n', excel_file);
end

function [stats, data_list] = process_group(root_dir, subfolder, pids, start_date, end_date, cfg)
    [data_list, stats] = bms.analyzer.StructuralSeriesService.collectPoints( ...
        root_dir, subfolder, pids, start_date, end_date, cfg, 'tilt', 3, 'Tilt point');
end

function plot_tilt_curve(root_dir, data_list, start_date, end_date, suffix, style, warn_lines, cfg)
    if nargin < 8
        cfg = struct();
    end
    if isempty(data_list) || ~has_plot_data(data_list)
        return;
    end

    [dt0, dt1] = bms.analyzer.StructuralTimeSeriesPlotService.dateRange(start_date, end_date);
    pid = '';
    if numel(data_list) == 1 && isfield(data_list, 'pid')
        pid = data_list(1).pid;
    end

    opts = struct();
    opts.style = style;
    opts.ylabel = get_style_field(style, 'ylabel', '倾角 (°)');
    opts.titleText = sprintf('%s %s', get_style_field(style, 'title_prefix', '倾角时程'), char(string(suffix)));
    opts.outputDir = get_style_field(style, 'output_dir', '时程曲线_倾角');
    opts.baseName = sprintf('Tilt_%s_%s_%s_%s', char(string(suffix)), datestr(dt0, 'yyyymmdd'), datestr(dt1, 'yyyymmdd'), datestr(now, 'yyyymmdd_HHMMSS'));
    opts.warnLines = warn_lines;
    opts.ylimRange = bms.analyzer.StructuralTimeSeriesPlotService.resolveStyleYLim(style, pid);
    if numel(data_list) == 3
        opts.colorField = 'colors_3';
        opts.defaultColors = [0 0 0; 1 0 0; 0 0 1];
    end
    bms.analyzer.StructuralTimeSeriesPlotService.plotDataList(root_dir, data_list, start_date, end_date, opts, cfg);
end

function warn_lines = resolve_warn_lines(style, cfg, pid)
    warn_lines = bms.analyzer.StructuralTimeSeriesPlotService.resolveWarnLines(style, cfg, 'tilt', pid);
end

function groups = get_groups(cfg, key)
    groups = bms.analyzer.StructuralPlotConfigService.getGroups(cfg, key, []);
end

function groups = normalize_group_map(groups_cfg)
    groups = bms.analyzer.StructuralPlotConfigService.normalizeGroupMap(groups_cfg);
end

function tf = has_groups(groups_cfg)
    tf = bms.analyzer.StructuralPlotConfigService.hasGroups(groups_cfg);
end

function groups = legacy_tilt_groups()
    groups = struct( ...
        'X', {{'GB-DIS-P04-001-01-X', 'GB-DIS-P05-001-01-X', 'GB-DIS-P06-001-01-X'}}, ...
        'Y', {{'GB-DIS-P04-001-01-Y', 'GB-DIS-P05-001-01-Y', 'GB-DIS-P06-001-01-Y'}});
end

function pts = get_points(cfg, key, fallback)
    pts = bms.analyzer.StructuralPlotConfigService.getPoints(cfg, key, fallback);
end

function pts = flatten_groups(groups)
    pts = bms.analyzer.StructuralPlotConfigService.flattenGroups(groups);
end

function tf = is_jiulongjiang(cfg)
    tf = bms.analyzer.StructuralPlotConfigService.isJiulongjiang(cfg);
end

function style = get_style(cfg, key)
    style = bms.analyzer.StructuralPlotConfigService.getStyle(cfg, key);
end

function val = get_style_field(style, field, default)
    val = bms.analyzer.StructuralPlotConfigService.getStyleField(style, field, default);
end

function tf = has_plot_data(data_list)
    tf = bms.analyzer.StructuralPlotConfigService.hasPlotData(data_list);
end

function sheet = make_sheet_name(name)
    sheet = bms.analyzer.StructuralPlotConfigService.sheetName(name, 'Tilt_');
end
